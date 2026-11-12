package capture

import (
	"context"
	"encoding/json"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"golang.org/x/oauth2"
)

func TestAuthMissingCredentialsNonInteractive(t *testing.T) {
	f, err := NewFetcher(context.Background(), t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	_, _, err = f.Fetch(context.Background(), []string{testID})
	if err == nil || !strings.Contains(err.Error(), "youtube-org auth") {
		t.Fatalf("%v", err)
	}
}

func TestAuthCallbackStateAndCleanup(t *testing.T) {
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	address := listener.Addr().String()
	ctx, cancel := context.WithTimeout(context.Background(), time.Second)
	defer cancel()
	code, err := receiveAuthorization(ctx, listener, "http://example.invalid/auth", "expected-state", func(string) error {
		go func() {
			for _, query := range []string{"state=wrong&code=secret-code", "state=expected-state&code=accepted-code"} {
				resp, e := http.Get("http://" + address + "/Callback?" + query)
				if e != nil {
					t.Error(e)
					return
				}
				resp.Body.Close()
				if strings.Contains(query, "wrong") && resp.StatusCode != http.StatusBadRequest {
					t.Error("accepted incorrect state")
				}
			}
		}()
		return nil
	})
	if err != nil || code != "accepted-code" {
		t.Fatalf("%q %v", code, err)
	}
	if conn, e := net.DialTimeout("tcp", address, 20*time.Millisecond); e == nil {
		conn.Close()
		t.Fatal("authorization listener left open")
	}
}

func TestAuthTimeoutAndPrivateToken(t *testing.T) {
	l, _ := net.Listen("tcp", "127.0.0.1:0")
	ctx, cancel := context.WithTimeout(context.Background(), 25*time.Millisecond)
	defer cancel()
	if _, err := receiveAuthorization(ctx, l, "http://example.invalid/auth", "state", func(string) error { return nil }); err == nil {
		t.Fatal("ignored timeout")
	}
	dir := t.TempDir()
	token := &oauth2.Token{AccessToken: "fixture-private-token"}
	if err := saveToken(filepath.Join(dir, "token.json"), token); err != nil {
		t.Fatal(err)
	}
	info, _ := os.Stat(filepath.Join(dir, "token.json"))
	if info.Mode().Perm() != 0600 {
		t.Fatal("token not private")
	}
	var got oauth2.Token
	if err := json.Unmarshal([]byte(read(t, filepath.Join(dir, "token.json"))), &got); err != nil || got.AccessToken != token.AccessToken {
		t.Fatal("token not preserved")
	}
}

func TestAuthRefreshErrorRedacted(t *testing.T) {
	dir := t.TempDir()
	put(t, filepath.Join(dir, "client_secret.json"), `{"installed":{"client_id":"fixture-id","client_secret":"fixture-secret","auth_uri":"https://example.invalid/auth","token_uri":"http://127.0.0.1:1/token"}}`)
	put(t, filepath.Join(dir, "token.json"), `{"access_token":"fixture-access","refresh_token":"fixture-refresh","expiry":"2000-01-01T00:00:00Z"}`)
	f, _ := NewFetcher(context.Background(), dir)
	ctx, cancel := context.WithTimeout(context.Background(), 100*time.Millisecond)
	defer cancel()
	_, _, err := f.Fetch(ctx, []string{testID})
	if err == nil {
		t.Fatal("refresh unexpectedly succeeded")
	}
	for _, secret := range []string{"fixture-secret", "fixture-access", "fixture-refresh"} {
		if strings.Contains(err.Error(), secret) {
			t.Fatal("credential leaked")
		}
	}
}
