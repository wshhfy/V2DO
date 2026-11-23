package main

/*
#include <stdlib.h>
*/
import "C"

import (
	"context"
	"crypto/tls"
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"os"
	"strings"
	"sync"
	"time"
)

type request struct {
	URL     string            `json:"url"`
	Method  string            `json:"method"`
	Headers map[string]string `json:"headers"`
	Body    string            `json:"body"`
}
type response struct {
	Status   int      `json:"status"`
	Body     string   `json:"body"`
	Location string   `json:"location"`
	Cookies  []string `json:"cookies"`
	Error    string   `json:"error"`
	ECH      bool     `json:"ech"`
}
type answer struct {
	Type int    `json:"type"`
	Data string `json:"data"`
}
type dnsResponse struct {
	Status int      `json:"Status"`
	Answer []answer `json:"Answer"`
}
type config struct {
	ech       []byte
	ips       []string
	expiry    time.Time
	preferred string
}

var mu sync.Mutex
var cache = map[string]*config{}
var dnsLocks = map[string]*sync.Mutex{"www.v2ex.com": {}, "linux.do": {}}
var once sync.Once
var roots *x509.CertPool
var rootErr error

func systemRoots() (*x509.CertPool, error) {
	once.Do(func() {
		roots = x509.NewCertPool()
		count := 0
		for _, dir := range []string{"/apex/com.android.conscrypt/cacerts", "/system/etc/security/cacerts"} {
			entries, err := os.ReadDir(dir)
			if err != nil {
				continue
			}
			for _, entry := range entries {
				if entry.IsDir() {
					continue
				}
				data, err := os.ReadFile(dir + "/" + entry.Name())
				if err == nil && roots.AppendCertsFromPEM(data) {
					count++
				}
			}
		}
		if count == 0 {
			rootErr = errors.New("system trust store unavailable")
		}
	})
	return roots, rootErr
}

var cfRanges = []string{"173.245.48.0/20", "103.21.244.0/22", "103.22.200.0/22", "103.31.4.0/22", "141.101.64.0/18", "108.162.192.0/18", "190.93.240.0/20", "188.114.96.0/20", "197.234.240.0/22", "198.41.128.0/17", "162.158.0.0/15", "104.16.0.0/13", "104.24.0.0/14", "172.64.0.0/13", "131.0.72.0/22"}

func isCloudflare(ip net.IP) bool {
	for _, cidr := range cfRanges {
		_, block, e := net.ParseCIDR(cidr)
		if e == nil && block.Contains(ip) {
			return true
		}
	}
	return false
}

func lookupOne(ctx context.Context, base, host, kind string, pool *x509.CertPool) ([]answer, error) {
	u, err := url.Parse(base)
	if err != nil {
		return nil, err
	}
	q := u.Query()
	q.Set("name", host)
	q.Set("type", kind)
	u.RawQuery = q.Encode()
	transport := &http.Transport{TLSClientConfig: &tls.Config{RootCAs: pool, MinVersion: tls.VersionTLS12}, Proxy: http.ProxyFromEnvironment}
	client := &http.Client{Timeout: 12 * time.Second, Transport: transport}
	defer transport.CloseIdleConnections()
	req, err := http.NewRequestWithContext(ctx, "GET", u.String(), nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Accept", "application/dns-json")
	res, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer res.Body.Close()
	if res.StatusCode != 200 {
		return nil, errors.New("secure DNS unavailable")
	}
	var data dnsResponse
	if err = json.NewDecoder(io.LimitReader(res.Body, 128*1024)).Decode(&data); err != nil || data.Status != 0 {
		return nil, errors.New("secure DNS response invalid")
	}
	for _, a := range data.Answer {
		if kind == "HTTPS" && a.Type == 65 && strings.Contains(a.Data, "ech=") {
			return data.Answer, nil
		}
		if kind == "A" && a.Type == 1 {
			ip := net.ParseIP(a.Data)
			if ip != nil && ip.To4() != nil && isCloudflare(ip) {
				return data.Answer, nil
			}
		}
	}
	return nil, errors.New("secure DNS returned no usable records")
}
func lookup(host, kind string, pool *x509.CertPool) ([]answer, error) {
	providers := []string{"https://dns.google/resolve", "https://cloudflare-dns.com/dns-query", "https://dns.alidns.com/resolve"}
	ctx, cancel := context.WithTimeout(context.Background(), 14*time.Second)
	defer cancel()
	type dnsResult struct {
		answers []answer
		err     error
	}
	results := make(chan dnsResult, len(providers))
	for _, provider := range providers {
		go func(p string) { a, e := lookupOne(ctx, p, host, kind, pool); results <- dnsResult{a, e} }(provider)
	}
	var last error
	for range providers {
		select {
		case r := <-results:
			if r.err == nil {
				return r.answers, nil
			}
			last = r.err
		case <-ctx.Done():
			return nil, ctx.Err()
		}
	}
	return nil, last
}

func getConfig(host string, pool *x509.CertPool) (*config, error) {
	dnsLocks[host].Lock()
	defer dnsLocks[host].Unlock()
	mu.Lock()
	item := cache[host]
	if item != nil && time.Now().Before(item.expiry) {
		out := *item
		mu.Unlock()
		return &out, nil
	}
	mu.Unlock()
	https, err := lookup(host, "HTTPS", pool)
	if err != nil {
		return nil, fmt.Errorf("HTTPS DNS: %w", err)
	}
	var ech []byte
	for _, r := range https {
		if r.Type != 65 {
			continue
		}
		for _, part := range strings.Fields(r.Data) {
			if strings.HasPrefix(part, "ech=") {
				ech, err = base64.StdEncoding.DecodeString(strings.Trim(strings.TrimPrefix(part, "ech="), "\""))
				if err == nil && len(ech) > 0 {
					break
				}
			}
		}
		if len(ech) > 0 {
			break
		}
	}
	if len(ech) == 0 {
		return nil, errors.New("ECH configuration unavailable")
	}
	a, err := lookup(host, "A", pool)
	if err != nil {
		return nil, fmt.Errorf("A DNS: %w", err)
	}
	var ips []string
	for _, r := range a {
		ip := net.ParseIP(r.Data)
		if r.Type == 1 && ip != nil && ip.To4() != nil && isCloudflare(ip) {
			ips = append(ips, ip.String())
			if len(ips) == 4 {
				break
			}
		}
	}
	if len(ips) == 0 {
		return nil, errors.New("no public addresses")
	}
	item = &config{ech: ech, ips: ips, expiry: time.Now().Add(5 * time.Minute)}
	mu.Lock()
	cache[host] = item
	out := *item
	mu.Unlock()
	return &out, nil
}

func connect(ctx context.Context, host, ip string, cfg *config, pool *x509.CertPool) (*tls.Conn, error) {
	dialer := &net.Dialer{Timeout: 8 * time.Second}
	raw, err := dialer.DialContext(ctx, "tcp", net.JoinHostPort(ip, "443"))
	if err != nil {
		return nil, err
	}
	conn := tls.Client(raw, &tls.Config{ServerName: host, RootCAs: pool, MinVersion: tls.VersionTLS13, EncryptedClientHelloConfigList: cfg.ech})
	if err = conn.HandshakeContext(ctx); err != nil {
		raw.Close()
		return nil, err
	}
	if !conn.ConnectionState().ECHAccepted {
		conn.Close()
		return nil, errors.New("ECH not accepted")
	}
	return conn, nil
}

func dialECH(ctx context.Context, host string) (net.Conn, error) {
	pool, err := systemRoots()
	if err != nil {
		return nil, err
	}
	cfg, err := getConfig(host, pool)
	if err != nil {
		return nil, err
	}
	if cfg.preferred != "" {
		c, e := connect(ctx, host, cfg.preferred, cfg, pool)
		if e == nil {
			return c, nil
		}
	}
	type result struct {
		conn *tls.Conn
		ip   string
		err  error
	}
	results := make(chan result, len(cfg.ips))
	raceCtx, cancel := context.WithCancel(ctx)
	defer cancel()
	for _, ip := range cfg.ips {
		go func(ip string) {
			c, e := connect(raceCtx, host, ip, cfg, pool)
			select {
			case results <- result{c, ip, e}:
			case <-raceCtx.Done():
				if c != nil {
					c.Close()
				}
			}
		}(ip)
	}
	var lastErr error
	for range cfg.ips {
		r := <-results
		if r.err == nil {
			mu.Lock()
			if current := cache[host]; current != nil {
				current.preferred = r.ip
			}
			mu.Unlock()
			cancel()
			go func() {
				for range len(cfg.ips) - 1 {
					select {
					case other := <-results:
						if other.conn != nil {
							other.conn.Close()
						}
					case <-time.After(9 * time.Second):
						return
					}
				}
			}()
			return r.conn, nil
		}
		lastErr = r.err
	}
	mu.Lock()
	delete(cache, host)
	mu.Unlock()
	return nil, fmt.Errorf("all ECH connections failed: %w", lastErr)
}

func perform(in request) response {
	fail := func() response {
		return response{Error: "ECH 连接失败，请检查网络或关闭 ECH 测试开关"}
	}
	target, err := url.Parse(in.URL)
	if err != nil || target.Scheme != "https" || (target.Host != "www.v2ex.com" && target.Host != "linux.do") || target.User != nil {
		return fail()
	}
	if in.Method != "GET" && in.Method != "POST" && in.Method != "PUT" && in.Method != "DELETE" {
		return fail()
	}
	body, err := base64.StdEncoding.DecodeString(in.Body)
	if err != nil || len(body) > 26*1024*1024 {
		return fail()
	}
	req, err := http.NewRequest(in.Method, target.String(), strings.NewReader(string(body)))
	if err != nil {
		return fail()
	}
	allowed := map[string]bool{"accept": true, "content-type": true, "x-csrf-token": true, "x-requested-with": true, "referer": true, "origin": true, "user-agent": true, "cookie": true}
	for key, value := range in.Headers {
		if allowed[strings.ToLower(key)] {
			req.Header.Set(key, value)
		}
	}
	transport := &http.Transport{DisableKeepAlives: true, DisableCompression: true, ForceAttemptHTTP2: false, DialTLSContext: func(ctx context.Context, network, addr string) (net.Conn, error) { return dialECH(ctx, target.Host) }}
	defer transport.CloseIdleConnections()
	timeout := 30 * time.Second
	if in.Method != "GET" {
		timeout = 130 * time.Second
	}
	client := &http.Client{Transport: transport, Timeout: timeout, CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }}
	res, err := client.Do(req)
	if err != nil {
		return fail()
	}
	defer res.Body.Close()
	bytes, err := io.ReadAll(io.LimitReader(res.Body, 48*1024*1024+1))
	if err != nil || len(bytes) > 48*1024*1024 {
		return fail()
	}
	return response{Status: res.StatusCode, Body: base64.StdEncoding.EncodeToString(bytes), Location: res.Header.Get("Location"), Cookies: res.Header.Values("Set-Cookie"), ECH: true}
}

//export PerformRequest
func PerformRequest(input *C.char) *C.char {
	var in request
	if input == nil || json.Unmarshal([]byte(C.GoString(input)), &in) != nil {
		return C.CString(`{"error":"无效请求"}`)
	}
	out := perform(in)
	data, err := json.Marshal(out)
	if err != nil {
		return C.CString(`{"error":"无法处理响应"}`)
	}
	return C.CString(string(data))
}
func main() { fmt.Sprint("") }
