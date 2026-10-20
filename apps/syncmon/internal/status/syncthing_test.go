package status

import (
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestGetStatusHTTPErrors(t *testing.T) {
	tests := []struct {
		name    string
		code    int
		state   State
		details string
	}{
		{"wrong api key", http.StatusForbidden, StateError, "Auth failed (403)"},
		{"unauthorized", http.StatusUnauthorized, StateError, "Auth failed (401)"},
		{"server error", http.StatusInternalServerError, StateError, "HTTP 500"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				http.Error(w, "nope", tt.code)
			}))
			defer srv.Close()

			c := &SyncthingClient{URL: srv.URL, APIKey: "bad"}
			got, _ := c.GetStatus()
			if got.State != tt.state || got.Details != tt.details {
				t.Errorf("GetStatus() = %v/%q; want %v/%q", got.State, got.Details, tt.state, tt.details)
			}
		})
	}
}

func TestGetStatusUnreachable(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {}))
	url := srv.URL
	srv.Close()

	c := &SyncthingClient{URL: url}
	got, _ := c.GetStatus()
	if got.State != StateInactive {
		t.Errorf("GetStatus() state = %v; want %v", got.State, StateInactive)
	}
}

func TestGetStatusConnected(t *testing.T) {
	mux := http.NewServeMux()
	mux.HandleFunc("/rest/system/config", func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("X-API-Key") != "key" {
			http.Error(w, "forbidden", http.StatusForbidden)
			return
		}
		_, _ = w.Write([]byte(`{"devices":[{"deviceID":"ME","name":"me"},{"deviceID":"D1","name":"phone"}],
			"folders":[{"id":"f 1","devices":[{"deviceID":"D1"}]}]}`))
	})
	mux.HandleFunc("/rest/system/connections", func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write([]byte(`{"connections":{"D1":{"connected":true}}}`))
	})
	mux.HandleFunc("/rest/system/status", func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write([]byte(`{"myID":"ME"}`))
	})
	mux.HandleFunc("/rest/db/completion", func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Query().Get("folder") != "f 1" {
			http.Error(w, "bad folder", http.StatusBadRequest)
			return
		}
		_, _ = w.Write([]byte(`{"completion":100}`))
	})
	srv := httptest.NewServer(mux)
	defer srv.Close()

	c := &SyncthingClient{URL: srv.URL, APIKey: "key"}
	got, _ := c.GetStatus()
	if got.State != StateIdle || got.Details != "Connected" {
		t.Fatalf("GetStatus() = %v/%q; want idle/Connected", got.State, got.Details)
	}
	if len(got.Devices) != 1 || got.Devices[0].Details != "Synced" {
		t.Errorf("devices = %+v; want one Synced device", got.Devices)
	}
}

func TestTruncate(t *testing.T) {
	tests := []struct {
		in, suffix string
		max        int
		want       string
	}{
		{"short", "..", 12, "short"},
		{"exactly12chr", "..", 12, "exactly12chr"},
		{"a-long-device-name", "..", 12, "a-long-dev.."},
		{"Ärger-Gerät-Größe", "..", 12, "Ärger-Gerä.."},
		{"日本語のデバイス名です", "...", 5, "日本..."},
		{"abc", "...", 2, "..."},
	}
	for _, tt := range tests {
		got := Truncate(tt.in, tt.max, tt.suffix)
		if got != tt.want {
			t.Errorf("Truncate(%q, %d, %q) = %q; want %q", tt.in, tt.max, tt.suffix, got, tt.want)
		}
	}
}
