package outbound

import (
	"context"
	"crypto/tls"
	"encoding/base64"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/http/httptrace"
	"net/url"
	"strconv"
	"strings"
	"sync"
	"time"

	convertC "github.com/metacubex/mihomo/common/convert"
	"github.com/metacubex/mihomo/component/ca"
	"github.com/metacubex/mihomo/component/dialer"
	"github.com/metacubex/mihomo/component/proxydialer"
	C "github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/transport/gun"
)

type Naive struct {
	*Base
	option    *NaiveOption
	transport *gun.TransportWrap
}

type NaiveOption struct {
	BasicOption
	Name                  string            `proxy:"name"`
	Server                string            `proxy:"server"`
	Port                  int               `proxy:"port"`
	UserName              string            `proxy:"username,omitempty"`
	Password              string            `proxy:"password,omitempty"`
	SNI                   string            `proxy:"sni,omitempty"`
	ServerName            string            `proxy:"servername,omitempty"`
	Network               string            `proxy:"network,omitempty"`
	SkipCertVerify        bool              `proxy:"skip-cert-verify,omitempty"`
	Fingerprint           string            `proxy:"fingerprint,omitempty"`
	ClientFingerprint     string            `proxy:"client-fingerprint,omitempty"`
	Headers               map[string]string `proxy:"headers,omitempty"`
	ExtraHeaders          map[string]string `proxy:"extra-headers,omitempty"`
	InsecureConcurrency   int               `proxy:"insecure-concurrency,omitempty"`
	UDPOverTCP            bool              `proxy:"udp-over-tcp,omitempty"`
	QUIC                  bool              `proxy:"quic,omitempty"`
	QUICCongestionControl string            `proxy:"quic-congestion-control,omitempty"`
}

type naiveConn struct {
	reader     io.ReadCloser
	writer     *io.PipeWriter
	cancel     context.CancelFunc
	closer     io.Closer
	localAddr  net.Addr
	remoteAddr net.Addr

	deadlineMu sync.Mutex
	deadline   *time.Timer

	closeOnce sync.Once
	closeErr  error
}

func (n *Naive) DialContext(ctx context.Context, metadata *C.Metadata) (_ C.Conn, err error) {
	conn, err := n.dialWithTransport(ctx, n.transport, nil, metadata)
	if err != nil {
		return nil, err
	}

	return NewConn(conn, n), nil
}

func (n *Naive) DialContextWithDialer(ctx context.Context, cDialer C.Dialer, metadata *C.Metadata) (_ C.Conn, err error) {
	transport, err := newNaiveTransport(n.Base, n.option, cDialer)
	if err != nil {
		return nil, err
	}

	conn, err := n.dialWithTransport(ctx, transport, transport, metadata)
	if err != nil {
		_ = transport.Close()
		return nil, err
	}

	return NewConn(conn, n), nil
}

func (n *Naive) SupportWithDialer() C.NetWork {
	return C.TCP
}

func (n *Naive) ProxyInfo() C.ProxyInfo {
	info := n.Base.ProxyInfo()
	info.DialerProxy = n.option.DialerProxy
	return info
}

func (n *Naive) Close() error {
	if n.transport == nil {
		return nil
	}
	return n.transport.Close()
}

func (n *Naive) dialWithTransport(ctx context.Context, transport *gun.TransportWrap, closer io.Closer, metadata *C.Metadata) (net.Conn, error) {
	targetAddr := metadata.RemoteAddress()
	if targetAddr == "" {
		return nil, fmt.Errorf("invalid target address")
	}

	headers := n.buildHeaders()
	if n.option.UserName != "" || n.option.Password != "" {
		auth := n.option.UserName + ":" + n.option.Password
		headers.Set("Proxy-Authorization", "Basic "+base64.StdEncoding.EncodeToString([]byte(auth)))
	}

	proxyAddr := n.Addr()
	requestCtx, cancel := context.WithCancel(ctx)
	reader, writer := io.Pipe()

	connAddresses := gunTransportAddr{}
	trace := &httptrace.ClientTrace{
		GotConn: func(info httptrace.GotConnInfo) {
			connAddresses.localAddr = info.Conn.LocalAddr()
			connAddresses.remoteAddr = info.Conn.RemoteAddr()
		},
	}

	request := (&http.Request{
		Method: http.MethodConnect,
		Host:   targetAddr,
		URL: &url.URL{
			Scheme: "https",
			Host:   proxyAddr,
		},
		Proto:      "HTTP/2",
		ProtoMajor: 2,
		ProtoMinor: 0,
		Header:     headers,
		Body:       reader,
	}).WithContext(httptrace.WithClientTrace(requestCtx, trace))

	response, err := transport.RoundTrip(request)
	if err != nil {
		_ = writer.Close()
		cancel()
		if closer != nil {
			_ = closer.Close()
		}
		return nil, err
	}

	if response.StatusCode != http.StatusOK {
		defer response.Body.Close()
		_, _ = io.Copy(io.Discard, response.Body)
		_ = writer.Close()
		cancel()
		if closer != nil {
			_ = closer.Close()
		}
		return nil, mapNaiveResponseError(response.StatusCode, response.Status)
	}

	return &naiveConn{
		reader:     response.Body,
		writer:     writer,
		cancel:     cancel,
		closer:     closer,
		localAddr:  connAddresses.localAddr,
		remoteAddr: connAddresses.remoteAddr,
	}, nil
}

func (n *Naive) buildHeaders() http.Header {
	headers := http.Header{}

	for key, value := range n.option.ExtraHeaders {
		if strings.TrimSpace(key) == "" || strings.TrimSpace(value) == "" {
			continue
		}
		headers.Set(key, value)
	}

	for key, value := range n.option.Headers {
		if strings.TrimSpace(key) == "" || strings.TrimSpace(value) == "" {
			continue
		}
		headers.Set(key, value)
	}

	convertC.SetUserAgent(headers)
	return headers
}

func (c *naiveConn) Read(b []byte) (int, error) {
	return c.reader.Read(b)
}

func (c *naiveConn) Write(b []byte) (int, error) {
	return c.writer.Write(b)
}

func (c *naiveConn) Close() error {
	c.closeOnce.Do(func() {
		var errs []error
		if c.writer != nil {
			if err := c.writer.Close(); err != nil {
				errs = append(errs, err)
			}
		}
		if c.reader != nil {
			if err := c.reader.Close(); err != nil {
				errs = append(errs, err)
			}
		}
		if c.cancel != nil {
			c.cancel()
		}
		if c.closer != nil {
			if err := c.closer.Close(); err != nil {
				errs = append(errs, err)
			}
		}
		c.closeErr = errors.Join(errs...)
	})
	return c.closeErr
}

func (c *naiveConn) LocalAddr() net.Addr {
	return c.localAddr
}

func (c *naiveConn) RemoteAddr() net.Addr {
	return c.remoteAddr
}

func (c *naiveConn) SetDeadline(t time.Time) error {
	c.deadlineMu.Lock()
	defer c.deadlineMu.Unlock()

	if t.IsZero() {
		if c.deadline != nil {
			c.deadline.Stop()
			c.deadline = nil
		}
		return nil
	}

	d := time.Until(t)
	if c.deadline != nil {
		c.deadline.Reset(d)
		return nil
	}

	c.deadline = time.AfterFunc(d, func() {
		_ = c.Close()
	})
	return nil
}

func (c *naiveConn) SetReadDeadline(t time.Time) error {
	return c.SetDeadline(t)
}

func (c *naiveConn) SetWriteDeadline(t time.Time) error {
	return c.SetDeadline(t)
}

func NewNaive(option NaiveOption) (*Naive, error) {
	network := strings.ToLower(strings.TrimSpace(option.Network))
	switch network {
	case "", "https", "h2", "http2":
	case "quic", "h3", "http3":
		return nil, fmt.Errorf("naive quic is not supported")
	default:
		return nil, fmt.Errorf("unsupported naive network: %s", option.Network)
	}

	if option.QUIC || strings.TrimSpace(option.QUICCongestionControl) != "" {
		return nil, fmt.Errorf("naive quic is not supported")
	}

	if option.UDPOverTCP {
		return nil, fmt.Errorf("naive udp-over-tcp is not supported")
	}

	base := &Base{
		name:   option.Name,
		addr:   net.JoinHostPort(option.Server, strconv.Itoa(option.Port)),
		tp:     C.Naive,
		tfo:    option.TFO,
		mpTcp:  option.MPTCP,
		iface:  option.Interface,
		rmark:  option.RoutingMark,
		prefer: C.NewDNSPrefer(option.IPVersion),
	}

	transport, err := newNaiveTransport(base, &option, nil)
	if err != nil {
		return nil, err
	}

	return &Naive{
		Base:      base,
		option:    &option,
		transport: transport,
	}, nil
}

func newNaiveTransport(base *Base, option *NaiveOption, cDialer C.Dialer) (*gun.TransportWrap, error) {
	serverName := firstNonEmptyString(option.SNI, option.ServerName, option.Server)
	tlsConfig, err := ca.GetSpecifiedFingerprintTLSConfig(&tls.Config{
		ServerName:         serverName,
		InsecureSkipVerify: option.SkipCertVerify,
	}, option.Fingerprint)
	if err != nil {
		return nil, err
	}

	if cDialer == nil {
		cDialer = dialer.NewDialer(base.DialOptions()...)
	}

	if len(option.DialerProxy) > 0 {
		cDialer, err = proxydialer.NewByName(option.DialerProxy, cDialer)
		if err != nil {
			return nil, err
		}
	}

	dialFn := func(ctx context.Context, network, addr string) (net.Conn, error) {
		return cDialer.DialContext(ctx, network, addr)
	}

	return gun.NewHTTP2Client(dialFn, tlsConfig, option.ClientFingerprint, nil, nil), nil
}

func mapNaiveResponseError(statusCode int, status string) error {
	switch {
	case statusCode == http.StatusProxyAuthRequired:
		return errors.New("HTTP need auth")
	case statusCode == http.StatusMethodNotAllowed:
		return errors.New("CONNECT method not allowed by proxy")
	case statusCode >= http.StatusInternalServerError:
		return errors.New(status)
	default:
		return fmt.Errorf("can not connect remote err code: %d", statusCode)
	}
}

type gunTransportAddr struct {
	localAddr  net.Addr
	remoteAddr net.Addr
}
