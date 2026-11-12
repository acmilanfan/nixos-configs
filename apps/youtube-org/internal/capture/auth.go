package capture

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"time"

	"golang.org/x/oauth2"
	"golang.org/x/oauth2/google"
	"google.golang.org/api/youtube/v3"
)

var authNeeded = errors.New("credentials unavailable or invalid; run youtube-org auth in a terminal")

func oauthConfig(dir string) (*oauth2.Config, error) {
	b, err := os.ReadFile(filepath.Join(dir, "client_secret.json"))
	if err != nil {
		return nil, authNeeded
	}
	cfg, err := google.ConfigFromJSON(b, youtube.YoutubeReadonlyScope)
	if err != nil {
		return nil, authNeeded
	}
	cfg.RedirectURL = "http://127.0.0.1:8888/Callback"
	return cfg, nil
}

func authorizedClient(ctx context.Context, dir string) (*http.Client, error) {
	cfg, err := oauthConfig(dir)
	if err != nil {
		return nil, err
	}
	b, err := os.ReadFile(filepath.Join(dir, "token.json"))
	if err != nil {
		return nil, authNeeded
	}
	var token oauth2.Token
	if json.Unmarshal(b, &token) != nil || (token.AccessToken == "" && token.RefreshToken == "") {
		return nil, authNeeded
	}
	base := &http.Client{Timeout: 30 * time.Second}
	ctx = context.WithValue(ctx, oauth2.HTTPClient, base)
	client := cfg.Client(ctx, &token)
	client.Timeout = 30 * time.Second
	return client, nil
}

func Authenticate(ctx context.Context, dir string) error {
	ctx, cancel := context.WithTimeout(ctx, 120*time.Second)
	defer cancel()
	cfg, err := oauthConfig(dir)
	if err != nil {
		return err
	}
	stateBytes := make([]byte, 32)
	if _, err := rand.Read(stateBytes); err != nil {
		return errors.New("cannot create authorization state")
	}
	state := hex.EncodeToString(stateBytes)
	listener, err := net.Listen("tcp", "127.0.0.1:8888")
	if err != nil {
		return errors.New("cannot listen on authorization callback port 8888")
	}
	code, err := receiveAuthorization(ctx, listener, cfg.AuthCodeURL(state, oauth2.AccessTypeOffline), state, func(raw string) error { return exec.CommandContext(ctx, "/usr/bin/open", raw).Run() })
	if err != nil {
		return err
	}
	ctx = context.WithValue(ctx, oauth2.HTTPClient, &http.Client{Timeout: 30 * time.Second})
	token, err := cfg.Exchange(ctx, code)
	if err != nil {
		return errors.New("authorization exchange failed; run youtube-org auth again")
	}
	if err := saveToken(filepath.Join(dir, "token.json"), token); err != nil {
		return fmt.Errorf("cannot save private authorization token: %w", err)
	}
	return nil
}

func receiveAuthorization(ctx context.Context, listener net.Listener, authURL, state string, opener func(string) error) (string, error) {
	codes := make(chan string, 1)
	oauthErrors := make(chan error, 1)
	mux := http.NewServeMux()
	mux.HandleFunc("/Callback", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Cache-Control", "no-store")
		if r.Method != http.MethodGet || r.URL.Query().Get("state") != state {
			http.Error(w, "Invalid authorization request", http.StatusBadRequest)
			return
		}
		if r.URL.Query().Get("error") != "" {
			http.Error(w, "Authorization declined", http.StatusBadRequest)
			select {
			case oauthErrors <- errors.New("authorization declined"):
			default:
			}
			return
		}
		code := r.URL.Query().Get("code")
		if code == "" {
			http.Error(w, "Missing authorization code", http.StatusBadRequest)
			return
		}
		fmt.Fprintln(w, "Authorization received. You may close this window.")
		select {
		case codes <- code:
		default:
		}
	})
	server := &http.Server{Handler: mux, ReadHeaderTimeout: 5 * time.Second}
	done := make(chan error, 1)
	go func() { done <- server.Serve(listener) }()
	defer func() {
		shutdown, cancel := context.WithTimeout(context.Background(), time.Second)
		defer cancel()
		server.Shutdown(shutdown)
		server.Close()
	}()
	if err := opener(authURL); err != nil {
		return "", errors.New("could not open the authorization browser")
	}
	select {
	case code := <-codes:
		return code, nil
	case err := <-oauthErrors:
		return "", err
	case <-ctx.Done():
		return "", errors.New("authorization timed out or cancelled")
	case <-done:
		return "", errors.New("authorization callback server stopped")
	}
}

func saveToken(path string, token *oauth2.Token) error {
	data, err := json.Marshal(token)
	if err != nil {
		return errors.New("cannot encode authorization token")
	}
	old, mode, exists, err := readRegular(path)
	if err != nil {
		return err
	}
	if exists && mode != 0600 {
		return errors.New("token permissions must be 0600; fix permissions before authorizing")
	}
	return atomicReplace(path, append(data, '\n'), 0600, old, exists)
}
