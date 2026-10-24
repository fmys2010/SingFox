package main

import (
	"crypto/rand"
	"encoding/hex"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"time"

	"golang.org/x/sys/windows"
	"golang.org/x/sys/windows/svc"
	"golang.org/x/sys/windows/svc/mgr"
)

func installDir() string { return filepath.Join(os.Getenv("ProgramFiles"), "SingFox Service") }
func dataDir() string    { return filepath.Join(os.Getenv("ProgramData"), "SingFox") }
func tokenPath() string  { return filepath.Join(dataDir(), "service.token") }
func corePath() string   { return filepath.Join(installDir(), "sing-box.exe") }

func install(args []string) error {
	fs := flag.NewFlagSet("install", flag.ContinueOnError)
	userSID := fs.String("user-sid", "", "SID of the user allowed to control the service")
	core := fs.String("core", "", "path of the sing-box.exe to install")
	if err := fs.Parse(args); err != nil {
		return err
	}
	if *userSID == "" || *core == "" {
		return errors.New("--user-sid and --core are required")
	}
	if _, err := windows.StringToSid(*userSID); err != nil {
		return fmt.Errorf("bad --user-sid: %w", err)
	}

	m, err := mgr.Connect()
	if err != nil {
		return fmt.Errorf("connect to service manager (run elevated): %w", err)
	}
	defer m.Disconnect()

	// Reinstalling replaces the binaries, so stop a running copy first.
	if s, err := m.OpenService(serviceName); err == nil {
		stopAndWait(s)
		s.Close()
	}

	self, err := os.Executable()
	if err != nil {
		return err
	}
	if err := os.MkdirAll(installDir(), 0o755); err != nil {
		return err
	}
	exe := filepath.Join(installDir(), "singfox-service.exe")
	if !samePath(self, exe) {
		if err := copyFile(self, exe); err != nil {
			return err
		}
	}
	if err := copyFile(*core, corePath()); err != nil {
		return err
	}

	if err := os.MkdirAll(dataDir(), 0o755); err != nil {
		return err
	}
	// Only SYSTEM and Administrators get full control of the data directory;
	// the installing user may read it (for the token) but not write it.
	if out, err := exec.Command("icacls", dataDir(), "/inheritance:r",
		"/grant:r", "*S-1-5-18:(OI)(CI)F", "*S-1-5-32-544:(OI)(CI)F", "*"+*userSID+":(OI)(CI)RX").CombinedOutput(); err != nil {
		return fmt.Errorf("icacls: %v: %s", err, out)
	}
	token := make([]byte, 24)
	if _, err := rand.Read(token); err != nil {
		return err
	}
	if err := os.WriteFile(tokenPath(), []byte(hex.EncodeToString(token)), 0o600); err != nil {
		return err
	}

	s, err := m.OpenService(serviceName)
	if err != nil {
		s, err = m.CreateService(serviceName, exe, mgr.Config{
			DisplayName: displayName,
			Description: "Runs the sing-box core for SingFox so TUN works without elevation.",
			StartType:   mgr.StartAutomatic,
		}, "run")
		if err != nil {
			return fmt.Errorf("create service: %w", err)
		}
	}
	defer s.Close()
	_ = s.SetRecoveryActions([]mgr.RecoveryAction{
		{Type: mgr.ServiceRestart, Delay: 5 * time.Second},
		{Type: mgr.ServiceRestart, Delay: 30 * time.Second},
	}, 86400)
	if err := s.Start(); err != nil {
		return fmt.Errorf("start service: %w", err)
	}
	return nil
}

func uninstall() error {
	m, err := mgr.Connect()
	if err != nil {
		return fmt.Errorf("connect to service manager (run elevated): %w", err)
	}
	defer m.Disconnect()
	if s, err := m.OpenService(serviceName); err == nil {
		stopAndWait(s)
		err = s.Delete()
		s.Close()
		if err != nil {
			return fmt.Errorf("delete service: %w", err)
		}
	}
	_ = os.RemoveAll(dataDir())
	// The running executable may be the installed one; leave it if locked.
	_ = os.Remove(corePath())
	return nil
}

func stopAndWait(s *mgr.Service) {
	st, err := s.Query()
	if err != nil || st.State == svc.Stopped {
		return
	}
	_, _ = s.Control(svc.Stop)
	for i := 0; i < 50; i++ {
		if st, err := s.Query(); err != nil || st.State == svc.Stopped {
			return
		}
		time.Sleep(200 * time.Millisecond)
	}
}

func samePath(a, b string) bool {
	ca, _ := filepath.Abs(a)
	cb, _ := filepath.Abs(b)
	return ca == cb
}

func copyFile(from, to string) error {
	in, err := os.Open(from)
	if err != nil {
		return err
	}
	defer in.Close()
	out, err := os.Create(to)
	if err != nil {
		return err
	}
	if _, err := io.Copy(out, in); err != nil {
		out.Close()
		return err
	}
	return out.Close()
}
