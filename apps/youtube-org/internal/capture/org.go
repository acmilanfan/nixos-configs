package capture

import (
	"bufio"
	"errors"
	"fmt"
	"io"
	"strings"
	"time"
	"unicode"
)

func singleLine(s string) string {
	return strings.Join(strings.Fields(strings.Map(func(r rune) rune {
		if unicode.IsControl(r) || unicode.IsSpace(r) {
			return ' '
		}
		return r
	}, s)), " ")
}

func RenderEntry(v Video, created time.Time) (string, error) {
	ref, err := NormalizeURL(v.URL)
	if err != nil || ref.ID != v.ID || v.Duration <= 0 || v.Published.IsZero() || created.IsZero() || singleLine(v.Title) == "" || singleLine(v.Channel) == "" {
		return "", errors.New("incomplete video metadata or inconsistent video identity")
	}
	return fmt.Sprintf("** TODO %s - %s\n:PROPERTIES:\n:Link: [[%s]]\n:VIDEO_ID: %s\n:Duration: %d\n:Created: %s\n:Published: %s\n:END:\n", singleLine(v.Title), singleLine(v.Channel), ref.URL, ref.ID, v.Duration, created.Format(time.RFC3339), v.Published.Format(time.RFC3339)), nil
}

func indexOrg(r io.Reader, ids map[string]bool) error {
	scanner := bufio.NewScanner(r)
	scanner.Buffer(make([]byte, 4096), 4<<20)
	var id, linkID string
	drawer := false
	flush := func() error {
		if id != "" && linkID != "" && id != linkID {
			return errors.New("VIDEO_ID and Link disagree")
		}
		if id != "" {
			ids[id] = true
		}
		if linkID != "" {
			ids[linkID] = true
		}
		id, linkID = "", ""
		return nil
	}
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if strings.HasPrefix(line, "*") && strings.Contains(line, " ") {
			if err := flush(); err != nil {
				return err
			}
			drawer = false
		}
		if strings.EqualFold(line, ":PROPERTIES:") {
			drawer = true
			continue
		}
		if strings.EqualFold(line, ":END:") {
			drawer = false
			continue
		}
		if !drawer || !strings.HasPrefix(line, ":") {
			continue
		}
		parts := strings.SplitN(line[1:], ":", 2)
		if len(parts) != 2 {
			continue
		}
		value := strings.TrimSpace(parts[1])
		switch strings.ToLower(parts[0]) {
		case "video_id":
			if !videoIDPattern.MatchString(value) || (id != "" && id != value) {
				return errors.New("invalid VIDEO_ID property")
			}
			id = value
		case "link":
			if !strings.HasPrefix(value, "[[") {
				return errors.New("invalid video Link property")
			}
			end := strings.Index(value[2:], "]")
			if end < 0 {
				return errors.New("invalid video Link property")
			}
			ref, err := NormalizeURL(value[2 : 2+end])
			if err != nil {
				return fmt.Errorf("invalid video Link: %w", err)
			}
			if linkID != "" && ref.ID != linkID {
				return errors.New("conflicting Link properties")
			}
			linkID = ref.ID
		}
	}
	if err := scanner.Err(); err != nil {
		return err
	}
	return flush()
}
