package main

import (
	"bufio"
	"crypto/subtle"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"time"

	"golang.org/x/sys/windows"
	"golang.org/x/sys/windows/svc"
)

func runService() error { return svc.Run(serviceName, &handler{}) }

type handler struct{}

func (*handler) Execute(_ []string, req <-chan svc.ChangeRequest, status chan<- svc.Status) (bool, uint32) {
	status <- svc.Status{State: svc.StartPending}
	c := &core{}
	srv, err := c.serve()
	if err != nil {
		return false, 1
	}
	if c.loadState().Autostart {
		if err := c.start(); err != nil {
			c.logf("autostart failed: %v", err)
		}
	}
	status <- svc.Status{State: svc.Running, Accepts: svc.AcceptStop | svc.AcceptShutdown}
	for r := range req {
		switch r.Cmd {
		case svc.Interrogate:
			status <- r.CurrentStatus
		case svc.Stop, svc.Shutdown:
			status <- svc.Status{State: svc.StopPending}
			_ = srv.Close()
			c.stop()
			return false, 0
		}
	}
	return false, 0
}

type state struct {
	Autostart bool `json:"autostart"`
}

type logLine struct {
	Seq  int    `json:"seq"`
	Text string `json:"text"`
}

// core owns the one sing-box child process and its log ring.
type core struct {
	mu      sync.Mutex
	cmd     *exec.Cmd
	done    chan struct{}
	since   time.Time
	lastErr string
	logs    []logLine
	seq     int
}

func configPath() string { return filepath.Join(dataDir(), "config.json") }
func statePath() string  { return filepath.Join(dataDir(), "state.json") }

func (c *core) loadState() state {
	var s state
	if b, err := os.ReadFile(statePath()); err == nil {
		_ = json.Unmarshal(b, &s)
	}
	return s
}

func (c *core) logf(format string, args ...any) {
	c.push("ERROR [singfox-service] " + strings.TrimSpace(fmt.Sprintf(format, args...)))
}

func (c *core) push(text string) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.seq++
	c.logs = append(c.logs, logLine{c.seq, text})
	if len(c.logs) > 3000 {
		c.logs = c.logs[len(c.logs)-2000:]
	}
}

// sanitize drops the options that would let a config write files as SYSTEM
// outside the service's own data directory.
func sanitize(raw []byte) ([]byte, error) {
	var cfg map[string]any
	if err := json.Unmarshal(raw, &cfg); err != nil {
		return nil, err
	}
	if log, ok := cfg["log"].(map[string]any); ok {
		delete(log, "output")
	}
	if exp, ok := cfg["experimental"].(map[string]any); ok {
		if cache, ok := exp["cache_file"].(map[string]any); ok {
			cache["path"] = filepath.Join(dataDir(), "cache.db")
		}
		if api, ok := exp["clash_api"].(map[string]any); ok {
			delete(api, "external_ui")
			delete(api, "external_ui_download_url")
		}
	}
	return json.MarshalIndent(cfg, "", "  ")
}

func (c *core) start() error {
	c.mu.Lock()
	if c.cmd != nil {
		c.mu.Unlock()
		return errors.New("core is already running")
	}
	c.mu.Unlock()
	check := exec.Command(corePath(), "check", "-c", configPath(), "-D", dataDir(), "--disable-color")
	check.SysProcAttr = &windows.SysProcAttr{HideWindow: true}
	if out, err := check.CombinedOutput(); err != nil {
		lines := strings.Split(strings.TrimSpace(string(out)), "\n")
		return errors.New(lines[len(lines)-1])
	}
	cmd := exec.Command(corePath(), "run", "-c", configPath(), "-D", dataDir(), "--disable-color")
	cmd.Dir = dataDir()
	cmd.SysProcAttr = &windows.SysProcAttr{HideWindow: true}
	stdout, _ := cmd.StdoutPipe()
	stderr, _ := cmd.StderrPipe()
	if err := cmd.Start(); err != nil {
		return err
	}
	done := make(chan struct{})
	c.mu.Lock()
	c.cmd, c.done, c.since, c.lastErr = cmd, done, time.Now(), ""
	c.mu.Unlock()
	var wg sync.WaitGroup
	for _, r := range []io.Reader{stdout, stderr} {
		wg.Add(1)
		go func(r io.Reader) {
			defer wg.Done()
			sc := bufio.NewScanner(r)
			sc.Buffer(make([]byte, 64*1024), 1024*1024)
			for sc.Scan() {
				c.push(sc.Text())
			}
		}(r)
	}
	go func() {
		wg.Wait()
		err := cmd.Wait()
		c.mu.Lock()
		if c.cmd == cmd {
			c.cmd = nil
			if err != nil {
				c.lastErr = err.Error()
			}
		}
		c.mu.Unlock()
		close(done)
	}()
	return nil
}

func (c *core) stop() {
	c.mu.Lock()
	cmd, done := c.cmd, c.done
	c.cmd = nil
	c.mu.Unlock()
	if cmd == nil {
		return
	}
	_ = cmd.Process.Kill()
	select {
	case <-done:
	case <-time.After(5 * time.Second):
	}
}

func (c *core) serve() (*http.Server, error) {
	token, err := os.ReadFile(tokenPath())
	if err != nil {
		return nil, err
	}
	want := strings.TrimSpace(string(token))
	mux := http.NewServeMux()
	reply := func(w http.ResponseWriter, v any) {
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(v)
	}
	fail := func(w http.ResponseWriter, code int, err error) {
		w.WriteHeader(code)
		reply(w, map[string]any{"error": err.Error()})
	}
	mux.HandleFunc("GET /status", func(w http.ResponseWriter, _ *http.Request) {
		c.mu.Lock()
		defer c.mu.Unlock()
		res := map[string]any{"running": c.cmd != nil, "error": c.lastErr, "autostart": c.loadState().Autostart, "seq": c.seq}
		if c.cmd != nil {
			res["pid"] = c.cmd.Process.Pid
			res["since"] = c.since.Unix()
		}
		reply(w, res)
	})
	mux.HandleFunc("POST /start", func(w http.ResponseWriter, r *http.Request) {
		raw, err := io.ReadAll(io.LimitReader(r.Body, 32<<20))
		if err != nil {
			fail(w, 400, err)
			return
		}
		cfg, err := sanitize(raw)
		if err != nil {
			fail(w, 400, err)
			return
		}
		c.stop()
		if err := os.WriteFile(configPath(), cfg, 0o600); err != nil {
			fail(w, 500, err)
			return
		}
		if err := c.start(); err != nil {
			fail(w, 422, err)
			return
		}
		reply(w, map[string]any{"ok": true})
	})
	mux.HandleFunc("POST /stop", func(w http.ResponseWriter, _ *http.Request) {
		c.stop()
		reply(w, map[string]any{"ok": true})
	})
	mux.HandleFunc("GET /logs", func(w http.ResponseWriter, r *http.Request) {
		after, _ := strconv.Atoi(r.URL.Query().Get("after"))
		c.mu.Lock()
		out := []logLine{}
		for _, l := range c.logs {
			if l.Seq > after {
				out = append(out, l)
			}
		}
		c.mu.Unlock()
		reply(w, out)
	})
	mux.HandleFunc("POST /autostart", func(w http.ResponseWriter, r *http.Request) {
		var s state
		if err := json.NewDecoder(io.LimitReader(r.Body, 4096)).Decode(&s); err != nil {
			fail(w, 400, err)
			return
		}
		b, _ := json.Marshal(s)
		if err := os.WriteFile(statePath(), b, 0o600); err != nil {
			fail(w, 500, err)
			return
		}
		reply(w, map[string]any{"ok": true})
	})
	auth := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		got := strings.TrimPrefix(r.Header.Get("Authorization"), "Bearer ")
		if subtle.ConstantTimeCompare([]byte(got), []byte(want)) != 1 {
			w.WriteHeader(http.StatusUnauthorized)
			return
		}
		mux.ServeHTTP(w, r)
	})
	ln, err := net.Listen("tcp", listenAddr)
	if err != nil {
		return nil, err
	}
	srv := &http.Server{Handler: auth, ReadHeaderTimeout: 10 * time.Second}
	go func() { _ = srv.Serve(ln) }()
	return srv, nil
}
