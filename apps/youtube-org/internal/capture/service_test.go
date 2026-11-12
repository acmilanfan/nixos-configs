package capture

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

type fetchFunc func(context.Context, []string) (map[string]Video, map[string]error, error)

func (f fetchFunc) Fetch(ctx context.Context, ids []string) (map[string]Video, map[string]error, error) {
	return f(ctx, ids)
}
func serviceFixture(t *testing.T) *Service {
	t.Helper()
	return &Service{Store: &Store{Dir: filepath.Join(t.TempDir(), "collection")}, Now: func() time.Time { return time.Date(2026, 11, 11, 12, 0, 0, 0, time.UTC) }, Fetcher: fetchFunc(func(ctx context.Context, ids []string) (map[string]Video, map[string]error, error) {
		return map[string]Video{testID: fixtureVideo()}, nil, nil
	})}
}
func TestServiceExistingSkipsFetch(t *testing.T) {
	s := serviceFixture(t)
	s.Store.Commit(context.Background(), s.Now(), []Video{fixtureVideo()}, false)
	s.Fetcher = fetchFunc(func(context.Context, []string) (map[string]Video, map[string]error, error) {
		t.Fatal("existing video fetched")
		return nil, nil, nil
	})
	r, err := s.Save(context.Background(), []string{testURL, testURL}, false)
	if err != nil || r.Existing != 1 || r.Saved != 0 || r.Failed != 0 {
		t.Fatalf("%#v %v", r, err)
	}
}
func TestServicePartialBatch(t *testing.T) {
	s := serviceFixture(t)
	s.Fetcher = fetchFunc(func(_ context.Context, ids []string) (map[string]Video, map[string]error, error) {
		if len(ids) != 2 {
			t.Fatalf("batch contains duplicates: %v", ids)
		}
		return map[string]Video{testID: fixtureVideo()}, map[string]error{"abcdefghijk": ErrUnavailable}, nil
	})
	r, err := s.Save(context.Background(), []string{testURL, testURL, "https://youtu.be/abcdefghijk", "https://evil.org"}, false)
	if err != nil || r.Saved != 1 || r.Failed != 2 || r.Existing != 0 {
		t.Fatalf("%#v %v", r, err)
	}
	if !strings.Contains(read(t, r.Path), ":VIDEO_ID: "+testID) || r.Items[1].Status != "unavailable" || r.Items[2].Status != "invalid" {
		t.Fatalf("%#v", r)
	}
}
func TestServiceConcurrentRecheck(t *testing.T) {
	s := serviceFixture(t)
	s.Fetcher = fetchFunc(func(ctx context.Context, _ []string) (map[string]Video, map[string]error, error) {
		if _, err := s.Store.Commit(ctx, s.Now(), []Video{fixtureVideo()}, false); err != nil {
			t.Fatal(err)
		}
		return map[string]Video{testID: fixtureVideo()}, nil, nil
	})
	r, err := s.Save(context.Background(), []string{testURL}, false)
	if err != nil || r.Saved != 0 || r.Existing != 1 {
		t.Fatalf("%#v %v", r, err)
	}
}
func TestServiceMonthBoundary(t *testing.T) {
	s := serviceFixture(t)
	calls := 0
	s.Now = func() time.Time {
		calls++
		if calls == 1 {
			return time.Date(2026, 11, 30, 23, 59, 59, 0, time.FixedZone("local", 3600))
		}
		return time.Date(2026, 12, 1, 0, 0, 1, 0, time.FixedZone("local", 3600))
	}
	r, err := s.Save(context.Background(), []string{testURL}, false)
	if err != nil || filepath.Base(r.Path) != "2026-11.org" || !strings.Contains(read(t, r.Path), ":Created: 2026-11-30T23:59:59+01:00") || calls != 1 {
		t.Fatalf("%#v %v calls=%d", r, err, calls)
	}
}
func TestServiceDryRunAndCancellation(t *testing.T) {
	for _, mode := range []string{"dry", "api-error", "cancel", "invalid-metadata"} {
		t.Run(mode, func(t *testing.T) {
			s := serviceFixture(t)
			ctx, cancel := context.WithCancel(context.Background())
			defer cancel()
			s.Fetcher = fetchFunc(func(context.Context, []string) (map[string]Video, map[string]error, error) {
				if mode == "api-error" {
					return nil, nil, errors.New("offline")
				}
				if mode == "cancel" {
					cancel()
				}
				v := fixtureVideo()
				if mode == "invalid-metadata" {
					v.Duration = 0
				}
				return map[string]Video{testID: v}, nil, nil
			})
			r, err := s.Save(ctx, []string{testURL}, mode == "dry")
			if mode == "dry" {
				if err != nil || !r.DryRun || r.Saved != 0 || r.Items[0].Status != "would_save" {
					t.Fatalf("%#v %v", r, err)
				}
			} else if r.Saved != 0 || (err == nil && r.Failed == 0) {
				t.Fatalf("%#v %v", r, err)
			}
			if _, statErr := os.Stat(s.Store.Dir); !os.IsNotExist(statErr) {
				t.Fatal("failed/dry save mutated collection")
			}
		})
	}
}
