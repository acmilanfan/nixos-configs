package capture

import (
	"encoding/csv"
	"errors"
	"fmt"
	"io"
	"net/url"
	"regexp"
	"strings"
	"unicode"
)

var videoIDPattern = regexp.MustCompile(`^[A-Za-z0-9_-]{11}$`)

func NormalizeURL(raw string) (VideoRef, error) {
	bad := func() (VideoRef, error) { return VideoRef{}, errors.New("expected a YouTube video URL") }
	if strings.IndexFunc(raw, unicode.IsControl) >= 0 || len(raw) > 8192 {
		return bad()
	}
	u, err := url.Parse(strings.TrimSpace(raw))
	if err != nil || u.User != nil || u.Port() != "" || (u.Scheme != "https" && u.Scheme != "http") || u.Opaque != "" {
		return bad()
	}
	q, err := url.ParseQuery(u.RawQuery)
	if err != nil {
		return bad()
	}
	var id string
	switch strings.ToLower(u.Host) {
	case "youtu.be", "www.youtu.be":
		id = strings.TrimPrefix(u.Path, "/")
	case "youtube.com", "www.youtube.com", "m.youtube.com":
		if u.Path == "/watch" {
			if len(q["v"]) != 1 {
				return bad()
			}
			id = q.Get("v")
		} else {
			parts := strings.Split(strings.TrimPrefix(u.Path, "/"), "/")
			if len(parts) != 2 || (parts[0] != "shorts" && parts[0] != "live") {
				return bad()
			}
			id = parts[1]
		}
	default:
		return bad()
	}
	if !videoIDPattern.MatchString(id) {
		return bad()
	}
	return VideoRef{ID: id, URL: "https://www.youtube.com/watch?v=" + id}, nil
}

func ReadLegacyStash(r io.Reader) ([]string, error) {
	reader := csv.NewReader(r)
	reader.FieldsPerRecord = -1
	var urls []string
	for line := 1; ; line++ {
		row, err := reader.Read()
		if err == io.EOF {
			return urls, nil
		}
		if err != nil {
			return nil, fmt.Errorf("stash row %d: %w", line, err)
		}
		var raw string
		switch len(row) {
		case 1:
			raw = row[0]
		case 3:
			raw = row[2]
		default:
			return nil, fmt.Errorf("stash row %d: expected URL or rating,focus,URL", line)
		}
		if raw = strings.TrimSpace(raw); raw != "" {
			urls = append(urls, raw)
		}
	}
}
