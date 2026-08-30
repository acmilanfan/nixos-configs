package book

import (
	"strings"
	"testing"
	"time"

	"tg2kobo/internal/render"
)

func dateAt(day int, hour, min int) time.Time {
	return time.Date(2026, 8, day, hour, min, 0, 0, time.UTC)
}

func TestPerMessageOneBookEach(t *testing.T) {
	msgs := []render.Message{
		{ID: 1, Date: dateAt(24, 14, 3), Text: "first"},
		{ID: 2, Date: dateAt(25, 9, 0), Text: "second"},
	}
	books := PerMessage(msgs)
	if len(books) != 2 {
		t.Fatalf("books = %d, want 2", len(books))
	}
	for i, b := range books {
		if len(b.Chapters) != 1 {
			t.Fatalf("book %d has %d chapters, want 1", i, len(b.Chapters))
		}
		if !strings.Contains(b.Chapters[0].Body, `<div class="msg">`) {
			t.Fatalf("book %d chapter missing message div:\n%s", i, b.Chapters[0].Body)
		}
	}
	if books[0].Title != "first" || books[1].Title != "second" {
		t.Fatalf("titles = %q, %q", books[0].Title, books[1].Title)
	}
}

func TestTitleForFirstLineOnly(t *testing.T) {
	m := render.Message{Date: dateAt(24, 14, 3), Text: "headline\n\nbody line"}
	if got := TitleFor(m); got != "headline" {
		t.Fatalf("TitleFor = %q", got)
	}
}

func TestTitleForTruncatesTo60Runes(t *testing.T) {
	m := render.Message{Date: dateAt(24, 14, 3), Text: strings.Repeat("ж", 80)}
	got := TitleFor(m)
	if got != strings.Repeat("ж", 60) {
		t.Fatalf("TitleFor len = %d, want 60 runes", len([]rune(got)))
	}
}

func TestTitleForFromNamePrefix(t *testing.T) {
	m := render.Message{Date: dateAt(24, 14, 3), FromName: "Varlamov", Text: "news"}
	if got := TitleFor(m); got != "Varlamov: news" {
		t.Fatalf("TitleFor = %q", got)
	}
}

func TestTitleForMediaFallback(t *testing.T) {
	m := render.Message{Date: dateAt(24, 14, 3)}
	want := "Media 2026-08-24 14:03"
	if got := TitleFor(m); got != want {
		t.Fatalf("TitleFor = %q, want %q", got, want)
	}
}

func TestSlugSanitizes(t *testing.T) {
	got := Slug("Hello / world:  a  b?", 40)
	want := "Hello-world-a-b"
	if got != want {
		t.Fatalf("Slug = %q, want %q", got, want)
	}
}

func TestSlugKeepsUnicodeAndDots(t *testing.T) {
	got := Slug("Что-то.new 2026", 40)
	if got != "Что-то.new-2026" {
		t.Fatalf("Slug = %q", got)
	}
}

func TestSlugTruncatesAndTrims(t *testing.T) {
	got := Slug(strings.Repeat("a", 60)+"---", 40)
	if got != strings.Repeat("a", 40) {
		t.Fatalf("Slug = %d chars", len(got))
	}
}

func TestFilenameFor(t *testing.T) {
	m := render.Message{Date: dateAt(24, 14, 3), Text: "My / fancy link"}
	want := "2026-08-24-1403-My-fancy-link.epub"
	if got := FilenameFor(m); got != want {
		t.Fatalf("FilenameFor = %q, want %q", got, want)
	}
}

func TestFilenameForMedia(t *testing.T) {
	m := render.Message{Date: dateAt(24, 14, 3)}
	want := "2026-08-24-1403-media.epub"
	if got := FilenameFor(m); got != want {
		t.Fatalf("FilenameFor = %q, want %q", got, want)
	}
}
