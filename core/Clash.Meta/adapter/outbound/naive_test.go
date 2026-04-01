package outbound

import (
	"context"
	"encoding/base64"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strconv"
	"testing"
	"time"

	C "github.com/metacubex/mihomo/constant"
)

func TestNaiveDialContext(t *testing.T) {
	const (
		proxyUser = "demo-user"
		proxyPass = "demo-pass"
	)

	wantAuth := "Basic " + base64.StdEncoding.EncodeToString([]byte(proxyUser+":"+proxyPass))
	server := httptest.NewUnstartedServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodConnect {
			t.Errorf("unexpected method: %s", r.Method)
			w.WriteHeader(http.StatusMethodNotAllowed)
			return
		}
		if r.ProtoMajor != 2 {
			t.Errorf("unexpected proto major: %d", r.ProtoMajor)
		}
		if got := r.Header.Get("Proxy-Authorization"); got != wantAuth {
			t.Errorf("unexpected auth header: %q", got)
			w.WriteHeader(http.StatusProxyAuthRequired)
			return
		}
		if got := r.Host; got != "example.com:443" {
			t.Errorf("unexpected CONNECT authority: %s", got)
		}

		flusher, ok := w.(http.Flusher)
		if !ok {
			t.Fatal("response writer does not support flush")
		}

		w.WriteHeader(http.StatusOK)
		flusher.Flush()

		buf := make([]byte, 1024)
		for {
			n, err := r.Body.Read(buf)
			if n > 0 {
				if _, writeErr := w.Write(buf[:n]); writeErr != nil {
					return
				}
				flusher.Flush()
			}
			if err != nil {
				return
			}
		}
	}))
	server.EnableHTTP2 = true
	server.StartTLS()
	defer server.Close()

	serverURL, err := url.Parse(server.URL)
	if err != nil {
		t.Fatalf("parse server URL failed: %v", err)
	}
	port, err := strconv.Atoi(serverURL.Port())
	if err != nil {
		t.Fatalf("parse server port failed: %v", err)
	}

	proxy, err := NewNaive(NaiveOption{
		Name:              "naive-test",
		Server:            serverURL.Hostname(),
		Port:              port,
		UserName:          proxyUser,
		Password:          proxyPass,
		SNI:               serverURL.Hostname(),
		SkipCertVerify:    true,
		ClientFingerprint: "chrome",
	})
	if err != nil {
		t.Fatalf("NewNaive failed: %v", err)
	}
	defer proxy.Close()

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	metadata := &C.Metadata{
		NetWork: C.TCP,
		Host:    "example.com",
		DstPort: 443,
	}

	conn, err := proxy.DialContext(ctx, metadata)
	if err != nil {
		t.Fatalf("DialContext failed: %v", err)
	}
	defer conn.Close()

	payload := []byte("hello naive")
	if err := conn.SetDeadline(time.Now().Add(2 * time.Second)); err != nil {
		t.Fatalf("SetDeadline failed: %v", err)
	}
	if _, err := conn.Write(payload); err != nil {
		t.Fatalf("Write failed: %v", err)
	}

	received := make([]byte, len(payload))
	if _, err := io.ReadFull(conn, received); err != nil {
		t.Fatalf("ReadFull failed: %v", err)
	}

	if string(received) != string(payload) {
		t.Fatalf("unexpected echoed payload: got %q want %q", string(received), string(payload))
	}
}
