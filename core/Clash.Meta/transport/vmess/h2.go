package vmess

import (
	"context"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"strings"

	N "github.com/metacubex/mihomo/common/net"

	"github.com/metacubex/randv2"
	"golang.org/x/net/http2"
)

type h2Conn struct {
	net.Conn
	*http2.ClientConn
	pwriter *io.PipeWriter
	res     *http.Response
	cfg     *H2Config
}

type H2Config struct {
	Hosts        []string
	Path         string
	Method       string
	Headers      http.Header
	NoGRPCHeader bool
	XPaddingSize int
	ExpectStatus int
}

func (hc *h2Conn) establishConn() error {
	preader, pwriter := io.Pipe()

	host := "www.example.com"
	if len(hc.cfg.Hosts) > 0 {
		host = hc.cfg.Hosts[randv2.IntN(len(hc.cfg.Hosts))]
	}

	path := hc.cfg.Path
	if path == "" {
		path = "/"
	}

	pathURL, err := url.Parse(path)
	if err != nil {
		return err
	}

	if pathURL.Path == "" {
		pathURL.Path = "/"
	} else if !strings.HasPrefix(pathURL.Path, "/") {
		pathURL.Path = "/" + pathURL.Path
	}

	method := strings.ToUpper(strings.TrimSpace(hc.cfg.Method))
	if method == "" {
		method = http.MethodPut
	}

	headers := http.Header{}
	if hc.cfg.Headers != nil {
		headers = hc.cfg.Headers.Clone()
	}
	headers.Del("Host")
	headers.Del("Connection")
	headers.Del("Keep-Alive")
	headers.Del("Proxy-Connection")
	headers.Del("Transfer-Encoding")
	headers.Del("Upgrade")
	headers.Del("Trailer")
	headers.Del("Proxy-Authenticate")
	headers.Del("Proxy-Authorization")
	if te := strings.TrimSpace(headers.Get("Te")); te != "" && !strings.EqualFold(te, "trailers") {
		headers.Del("Te")
	}

	if headers.Get("Accept-Encoding") == "" {
		headers.Set("Accept-Encoding", "identity")
	}

	if method == http.MethodPost {
		if !hc.cfg.NoGRPCHeader && headers.Get("Content-Type") == "" {
			headers.Set("Content-Type", "application/grpc")
		}
		if headers.Get("Referer") == "" {
			xPaddingSize := hc.cfg.XPaddingSize
			if xPaddingSize <= 0 {
				xPaddingSize = 100 + randv2.IntN(901)
			}
			refererURL := url.URL{
				Scheme:   "https",
				Host:     host,
				Path:     pathURL.Path,
				RawQuery: "x_padding=" + strings.Repeat("X", xPaddingSize),
			}
			headers.Set("Referer", refererURL.String())
		}
	}
	// TODO: connect use VMess Host instead of H2 Host
	req := http.Request{
		Method: method,
		Host:   host,
		URL: &url.URL{
			Scheme:   "https",
			Host:     host,
			Path:     pathURL.Path,
			RawQuery: pathURL.RawQuery,
		},
		Proto:      "HTTP/2",
		ProtoMajor: 2,
		ProtoMinor: 0,
		Body:       preader,
		Header:     headers,
	}

	// it will be close at :  `func (hc *h2Conn) Close() error`
	res, err := hc.ClientConn.RoundTrip(&req)
	if err != nil {
		return err
	}

	if hc.cfg.ExpectStatus > 0 && res.StatusCode != hc.cfg.ExpectStatus {
		defer res.Body.Close()
		_, _ = io.Copy(io.Discard, res.Body)
		return fmt.Errorf("unexpected status: %s", res.Status)
	}

	hc.pwriter = pwriter
	hc.res = res

	return nil
}

// Read implements net.Conn.Read()
func (hc *h2Conn) Read(b []byte) (int, error) {
	if hc.res != nil && !hc.res.Close {
		n, err := hc.res.Body.Read(b)
		return n, err
	}

	if err := hc.establishConn(); err != nil {
		return 0, err
	}
	return hc.res.Body.Read(b)
}

// Write implements io.Writer.
func (hc *h2Conn) Write(b []byte) (int, error) {
	if hc.pwriter != nil {
		return hc.pwriter.Write(b)
	}

	if err := hc.establishConn(); err != nil {
		return 0, err
	}
	return hc.pwriter.Write(b)
}

func (hc *h2Conn) Close() error {
	if hc.pwriter != nil {
		if err := hc.pwriter.Close(); err != nil {
			return err
		}
	}
	ctx := context.Background()
	if hc.res != nil {
		ctx = hc.res.Request.Context()
	}
	if err := hc.ClientConn.Shutdown(ctx); err != nil {
		return err
	}
	return hc.Conn.Close()
}

func StreamH2Conn(ctx context.Context, conn net.Conn, cfg *H2Config) (_ net.Conn, err error) {
	if ctx.Done() != nil {
		done := N.SetupContextForConn(ctx, conn)
		defer done(&err)
	}

	transport := &http2.Transport{}

	cconn, err := transport.NewClientConn(conn)
	if err != nil {
		return nil, err
	}

	return &h2Conn{
		Conn:       conn,
		ClientConn: cconn,
		cfg:        cfg,
	}, nil
}
