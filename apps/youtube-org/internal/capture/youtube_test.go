package capture

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"google.golang.org/api/option"
	"google.golang.org/api/youtube/v3"
)

func TestYouTubeBatchesAndMetadata(t *testing.T) {
	var requests atomic.Int32
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		requests.Add(1)
		ids := strings.Split(r.URL.Query().Get("id"), ",")
		if len(ids) > 50 {
			t.Error("oversized batch")
		}
		var items []map[string]any
		for _, id := range ids {
			if id == "missing0000" {
				continue
			}
			duration := "PT9M59S"
			if id == "invalid0000" {
				duration = "bad"
			}
			items = append(items, map[string]any{"id": id, "snippet": map[string]string{"title": "A video", "channelTitle": "A channel", "publishedAt": "2020-01-02T03:04:05Z"}, "contentDetails": map[string]string{"duration": duration}})
		}
		json.NewEncoder(w).Encode(map[string]any{"items": items})
	}))
	defer server.Close()
	api, err := youtube.NewService(context.Background(), option.WithEndpoint(server.URL+"/"), option.WithHTTPClient(server.Client()))
	if err != nil {
		t.Fatal(err)
	}
	ids := []string{"missing0000", "invalid0000"}
	for i := 0; i < 49; i++ {
		ids = append(ids, fmt.Sprintf("video%06d", i))
	}
	videos, failures, err := fetchVideos(context.Background(), api, ids)
	if err != nil || requests.Load() != 2 || len(videos) != 49 || len(failures) != 2 || failures["missing0000"] != ErrUnavailable {
		t.Fatalf("videos=%d failures=%v requests=%d err=%v", len(videos), failures, requests.Load(), err)
	}
}

func TestYouTubeRequestCancellation(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { <-r.Context().Done() }))
	defer server.Close()
	api, _ := youtube.NewService(context.Background(), option.WithEndpoint(server.URL+"/"), option.WithHTTPClient(server.Client()))
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Millisecond)
	defer cancel()
	if _, _, err := fetchVideos(ctx, api, []string{testID}); err == nil {
		t.Fatal("ignored cancellation")
	}
}

func TestYouTubeParseDuration(t *testing.T) {
	for raw, want := range map[string]int64{"PT4M13S": 253, "PT1H2M3S": 3723, "PT59S": 59, "PT100H": 360000} {
		got, err := parseDuration(raw)
		if err != nil || got != want {
			t.Fatalf("%s: %d %v", raw, got, err)
		}
	}
	for _, raw := range []string{"PT", "PT0S", "PT1Sgarbage", "P1DT1H", "PT999999999999999999999999H", "1M"} {
		if _, err := parseDuration(raw); err == nil {
			t.Fatalf("accepted %s", raw)
		}
	}
}
