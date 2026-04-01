package encryption

import (
	"bytes"
	"crypto/aes"
	"crypto/cipher"
	"errors"
	"fmt"
	"io"
	"net"
	"strconv"
	"strings"
	"time"

	"github.com/metacubex/mihomo/common/pool"
	"github.com/metacubex/randv2"
	"lukechampine.com/blake3"

	"golang.org/x/crypto/chacha20poly1305"
)

type CommonConn struct {
	net.Conn
	UseAES      bool
	Client      *ClientInstance
	UnitedKey   []byte
	PreWrite    []byte
	AEAD        *AEAD
	PeerAEAD    *AEAD
	PeerPadding []byte
	rawInput    bytes.Buffer
	input       bytes.Reader
}

func NewCommonConn(conn net.Conn, useAES bool) *CommonConn {
	return &CommonConn{Conn: conn, UseAES: useAES}
}

func (c *CommonConn) Write(b []byte) (int, error) {
	if len(b) == 0 {
		return 0, nil
	}
	outBytes := pool.Get(5 + 8192 + 16)
	defer pool.Put(outBytes)
	for n := 0; n < len(b); {
		chunk := b[n:]
		if len(chunk) > 8192 {
			chunk = chunk[:8192]
		}
		n += len(chunk)
		headerAndData := outBytes[:5+len(chunk)+16]
		EncodeHeader(headerAndData, len(chunk)+16)
		max := bytes.Equal(c.AEAD.Nonce[:], MaxNonce)
		c.AEAD.Seal(headerAndData[:5], nil, chunk, headerAndData[:5])
		if max {
			c.AEAD = NewAEAD(headerAndData, c.UnitedKey, c.UseAES)
		}
		if c.PreWrite != nil {
			headerAndData = append(c.PreWrite, headerAndData...)
			c.PreWrite = nil
		}
		if _, err := c.Conn.Write(headerAndData); err != nil {
			return 0, err
		}
	}
	return len(b), nil
}

func (c *CommonConn) Read(b []byte) (int, error) {
	if len(b) == 0 {
		return 0, nil
	}
	if c.PeerAEAD == nil {
		serverRandom := make([]byte, 16)
		if _, err := io.ReadFull(c.Conn, serverRandom); err != nil {
			return 0, err
		}
		c.PeerAEAD = NewAEAD(serverRandom, c.UnitedKey, c.UseAES)
		if xorConn, ok := c.Conn.(*XorConn); ok {
			xorConn.PeerCTR = NewCTR(c.UnitedKey, serverRandom)
		}
	}
	if c.PeerPadding != nil {
		if _, err := io.ReadFull(c.Conn, c.PeerPadding); err != nil {
			return 0, err
		}
		if _, err := c.PeerAEAD.Open(c.PeerPadding[:0], nil, c.PeerPadding, nil); err != nil {
			return 0, err
		}
		c.PeerPadding = nil
	}
	if c.input.Len() > 0 {
		return c.input.Read(b)
	}
	peerHeader := [5]byte{}
	if _, err := io.ReadFull(c.Conn, peerHeader[:]); err != nil {
		return 0, err
	}
	l, err := DecodeHeader(peerHeader[:])
	if err != nil {
		if c.Client != nil && errors.Is(err, ErrInvalidHeader) {
			c.Client.RWLock.Lock()
			if bytes.HasPrefix(c.UnitedKey, c.Client.PfsKey) {
				c.Client.Expire = time.Now()
			}
			c.Client.RWLock.Unlock()
			return 0, errors.New("new handshake needed")
		}
		return 0, err
	}
	c.Client = nil
	if c.rawInput.Cap() < l {
		c.rawInput.Grow(l)
	}
	peerData := c.rawInput.Bytes()[:l]
	if _, err := io.ReadFull(c.Conn, peerData); err != nil {
		return 0, err
	}
	dst := peerData[:l-16]
	if len(dst) <= len(b) {
		dst = b[:len(dst)]
	}
	var newAEAD *AEAD
	if bytes.Equal(c.PeerAEAD.Nonce[:], MaxNonce) {
		newAEAD = NewAEAD(append(peerHeader[:], peerData...), c.UnitedKey, c.UseAES)
	}
	_, err = c.PeerAEAD.Open(dst[:0], nil, peerData, peerHeader[:])
	if newAEAD != nil {
		c.PeerAEAD = newAEAD
	}
	if err != nil {
		return 0, err
	}
	if len(dst) > len(b) {
		c.input.Reset(dst[copy(b, dst):])
		dst = b
	}
	return len(dst), nil
}

type AEAD struct {
	cipher.AEAD
	Nonce [12]byte
}

func deriveKey(ctx, key []byte) []byte {
	derived := make([]byte, 32)
	blake3.DeriveKey(derived, string(ctx), key)
	return derived
}

func NewAEAD(ctx, key []byte, useAES bool) *AEAD {
	k := deriveKey(ctx, key)
	var aead cipher.AEAD
	if useAES {
		block, _ := aes.NewCipher(k)
		aead, _ = cipher.NewGCM(block)
	} else {
		aead, _ = chacha20poly1305.New(k)
	}
	return &AEAD{AEAD: aead}
}

func (a *AEAD) Seal(dst, nonce, plaintext, additionalData []byte) []byte {
	if nonce == nil {
		nonce = IncreaseNonce(a.Nonce[:])
	}
	return a.AEAD.Seal(dst, nonce, plaintext, additionalData)
}

func (a *AEAD) Open(dst, nonce, ciphertext, additionalData []byte) ([]byte, error) {
	if nonce == nil {
		nonce = IncreaseNonce(a.Nonce[:])
	}
	return a.AEAD.Open(dst, nonce, ciphertext, additionalData)
}

func IncreaseNonce(nonce []byte) []byte {
	for i := 0; i < 12; i++ {
		nonce[11-i]++
		if nonce[11-i] != 0 {
			break
		}
	}
	return nonce
}

var MaxNonce = bytes.Repeat([]byte{255}, 12)

func EncodeLength(l int) []byte {
	return []byte{byte(l >> 8), byte(l)}
}

func DecodeLength(b []byte) int {
	return int(b[0])<<8 | int(b[1])
}

func EncodeHeader(h []byte, l int) {
	h[0] = 23
	h[1] = 3
	h[2] = 3
	h[3] = byte(l >> 8)
	h[4] = byte(l)
}

var ErrInvalidHeader = errors.New("invalid header")

func DecodeHeader(h []byte) (l int, err error) {
	l = int(h[3])<<8 | int(h[4])
	if h[0] != 23 || h[1] != 3 || h[2] != 3 {
		l = 0
	}
	if l < 17 || l > 17000 {
		err = fmt.Errorf("%w: %v", ErrInvalidHeader, h[:5])
	}
	return
}

func ParsePadding(padding string, paddingLens, paddingGaps *[][3]int) (err error) {
	if padding == "" {
		return
	}
	maxLen := 0
	for i, s := range strings.Split(padding, ".") {
		x := strings.Split(s, "-")
		if len(x) < 3 || x[0] == "" || x[1] == "" || x[2] == "" {
			return errors.New("invalid padding lenth/gap parameter: " + s)
		}
		y := [3]int{}
		if y[0], err = strconv.Atoi(x[0]); err != nil {
			return
		}
		if y[1], err = strconv.Atoi(x[1]); err != nil {
			return
		}
		if y[2], err = strconv.Atoi(x[2]); err != nil {
			return
		}
		if i == 0 && (y[0] < 100 || y[1] < 35 || y[2] < 35) {
			return errors.New("first padding length must not be smaller than 35")
		}
		if i%2 == 0 {
			*paddingLens = append(*paddingLens, y)
			if y[1] > y[2] {
				maxLen += y[1]
			} else {
				maxLen += y[2]
			}
		} else {
			*paddingGaps = append(*paddingGaps, y)
		}
	}
	if maxLen > 18+65535 {
		return errors.New("total padding length must not be larger than 65553")
	}
	return
}

func CreatPadding(paddingLens, paddingGaps [][3]int) (length int, lens []int, gaps []time.Duration) {
	if len(paddingLens) == 0 {
		paddingLens = [][3]int{{100, 111, 1111}, {50, 0, 3333}}
		paddingGaps = [][3]int{{75, 0, 111}}
	}
	for _, y := range paddingLens {
		l := 0
		if y[0] >= int(randBetween(0, 100)) {
			l = int(randBetween(int64(y[1]), int64(y[2])))
		}
		lens = append(lens, l)
		length += l
	}
	for _, y := range paddingGaps {
		g := 0
		if y[0] >= int(randBetween(0, 100)) {
			g = int(randBetween(int64(y[1]), int64(y[2])))
		}
		gaps = append(gaps, time.Duration(g)*time.Millisecond)
	}
	return
}

func randBetween(from int64, to int64) int64 {
	if from == to {
		return from
	}
	if to < from {
		from, to = to, from
	}
	return from + randv2.Int64N(to-from)
}
