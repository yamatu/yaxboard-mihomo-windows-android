package encryption

import (
	"crypto/aes"
	"crypto/cipher"
	"net"
)

type XorConn struct {
	net.Conn
	WriteCTR  cipher.Stream
	PeerCTR   cipher.Stream
	writeSkip int
	readSkip  int
}

func NewCTR(key, iv []byte) cipher.Stream {
	block, _ := aes.NewCipher(key[:32])
	return cipher.NewCTR(block, iv[:16])
}

func NewXorConn(conn net.Conn, writeCTR, peerCTR cipher.Stream, writeSkip, readSkip int) *XorConn {
	return &XorConn{
		Conn:      conn,
		WriteCTR:  writeCTR,
		PeerCTR:   peerCTR,
		writeSkip: writeSkip,
		readSkip:  readSkip,
	}
}

func (c *XorConn) Write(b []byte) (int, error) {
	if c.WriteCTR == nil || len(b) == 0 {
		return c.Conn.Write(b)
	}
	buf := make([]byte, len(b))
	copy(buf, b)
	if c.writeSkip > 0 {
		skip := c.writeSkip
		if skip > len(buf) {
			skip = len(buf)
		}
		c.writeSkip -= skip
		if skip < len(buf) {
			c.WriteCTR.XORKeyStream(buf[skip:], buf[skip:])
		}
	} else {
		c.WriteCTR.XORKeyStream(buf, buf)
	}
	return c.Conn.Write(buf)
}

func (c *XorConn) Read(b []byte) (int, error) {
	n, err := c.Conn.Read(b)
	if c.PeerCTR == nil || n <= 0 {
		return n, err
	}
	if c.readSkip > 0 {
		skip := c.readSkip
		if skip > n {
			skip = n
		}
		c.readSkip -= skip
		if skip < n {
			c.PeerCTR.XORKeyStream(b[skip:n], b[skip:n])
		}
	} else {
		c.PeerCTR.XORKeyStream(b[:n], b[:n])
	}
	return n, err
}
