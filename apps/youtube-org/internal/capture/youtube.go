package capture

import (
	"context"
	"errors"
	"math"
	"regexp"
	"strconv"
	"strings"
	"time"

	"google.golang.org/api/option"
	"google.golang.org/api/youtube/v3"
)

type youtubeFetcher struct{ credentialsDir string }

// Deliberately lazy: duplicate-only saves must not need credentials or network.
func NewFetcher(_ context.Context, credentialsDir string) (Fetcher, error) {
	return &youtubeFetcher{credentialsDir: credentialsDir}, nil
}

func (f *youtubeFetcher) Fetch(ctx context.Context, ids []string) (map[string]Video, map[string]error, error) {
	client, err := authorizedClient(ctx, f.credentialsDir)
	if err != nil {
		return nil, nil, err
	}
	api, err := youtube.NewService(ctx, option.WithHTTPClient(client))
	if err != nil {
		return nil, nil, errors.New("cannot initialize YouTube client")
	}
	return fetchVideos(ctx, api, ids)
}

func fetchVideos(ctx context.Context, api *youtube.Service, ids []string) (map[string]Video, map[string]error, error) {
	videos := map[string]Video{}
	failures := map[string]error{}
	for start := 0; start < len(ids); start += 50 {
		end := start + 50
		if end > len(ids) {
			end = len(ids)
		}
		batch := ids[start:end]
		requestCtx, cancel := context.WithTimeout(ctx, 30*time.Second)
		response, err := api.Videos.List([]string{"snippet", "contentDetails"}).Id(strings.Join(batch, ",")).Context(requestCtx).Do()
		cancel()
		if err != nil {
			return nil, nil, errors.New("YouTube request failed; check connection and credentials (youtube-org auth)")
		}
		for _, id := range batch {
			failures[id] = ErrUnavailable
		}
		for _, item := range response.Items {
			if item == nil {
				continue
			}
			if _, expected := failures[item.Id]; !expected {
				continue
			}
			if item.Snippet == nil || item.ContentDetails == nil {
				failures[item.Id] = errors.New("incomplete YouTube metadata")
				continue
			}
			published, err := time.Parse(time.RFC3339, item.Snippet.PublishedAt)
			if err != nil {
				failures[item.Id] = errors.New("invalid publication timestamp")
				continue
			}
			duration, err := parseDuration(item.ContentDetails.Duration)
			if err != nil {
				failures[item.Id] = err
				continue
			}
			v := Video{VideoRef: VideoRef{ID: item.Id, URL: "https://www.youtube.com/watch?v=" + item.Id}, Title: item.Snippet.Title, Channel: item.Snippet.ChannelTitle, Duration: duration, Published: published}
			if _, err := RenderEntry(v, time.Now()); err != nil {
				failures[item.Id] = err
				continue
			}
			videos[item.Id] = v
			delete(failures, item.Id)
		}
	}
	return videos, failures, nil
}

var durationPattern = regexp.MustCompile(`^PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?$`)

func parseDuration(raw string) (int64, error) {
	bad := errors.New("invalid or zero YouTube duration")
	m := durationPattern.FindStringSubmatch(raw)
	if m == nil {
		return 0, bad
	}
	var total int64
	for i, multiplier := range []int64{3600, 60, 1} {
		if m[i+1] == "" {
			continue
		}
		n, err := strconv.ParseInt(m[i+1], 10, 64)
		if err != nil || n > (math.MaxInt64-total)/multiplier {
			return 0, bad
		}
		total += n * multiplier
	}
	if total == 0 {
		return 0, bad
	}
	return total, nil
}
