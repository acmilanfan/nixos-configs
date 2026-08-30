package book

import (
	"strings"

	"tg2kobo/internal/epub"
	"tg2kobo/internal/render"
)

// ChapterFor wraps a single message as one EPUB chapter.
func ChapterFor(m render.Message) epub.Chapter {
	return epub.Chapter{
		Title: m.Date.Format("2006-01-02 15:04"),
		Body:  render.MessageXHTML(m) + "\n",
	}
}

// PerMessage returns one single-chapter EPUB per message.
func PerMessage(msgs []render.Message) []epub.Book {
	books := make([]epub.Book, 0, len(msgs))
	for _, m := range msgs {
		books = append(books, epub.Book{
			Title:    TitleFor(m),
			Author:   "tg2kobo",
			Chapters: []epub.Chapter{ChapterFor(m)},
		})
	}
	return books
}

// TitleFor builds the human-facing book title: the message's first
// line, prefixed by the original sender for forwards, with a
// date-based fallback for media-only messages.
func TitleFor(m render.Message) string {
	first := m.Text
	if i := strings.IndexByte(first, '\n'); i >= 0 {
		first = first[:i]
	}
	first = strings.TrimSpace(first)
	if first == "" {
		return "Media " + m.Date.Format("2006-01-02 15:04")
	}
	runes := []rune(first)
	if len(runes) > 60 {
		first = string(runes[:60])
	}
	if m.FromName != "" {
		return m.FromName + ": " + first
	}
	return first
}

// FilenameFor builds a date-prefixed, filesystem-safe EPUB filename.
func FilenameFor(m render.Message) string {
	slug := Slug(m.Text, 40)
	if slug == "" {
		slug = "media"
	}
	return m.Date.Format("2006-01-02-1504") + "-" + slug + ".epub"
}

// Slug reduces text to a safe filename component: letters and digits
// (any script) plus '.', '-', '_', whitespace collapsed to '-'.
func Slug(text string, max int) string {
	var b strings.Builder
	for _, r := range text {
		switch {
		case r == ' ' || r == '\t' || r == '\n' || r == '\r':
			b.WriteByte('-')
		case r >= 'a' && r <= 'z', r >= 'A' && r <= 'Z', r >= '0' && r <= '9',
			r == '-', r == '_', r == '.',
			r >= 0x80: // keep non-ASCII scripts (e.g. Cyrillic) as-is
			b.WriteRune(r)
		}
	}
	out := b.String()
	for strings.Contains(out, "--") {
		out = strings.ReplaceAll(out, "--", "-")
	}
	out = strings.Trim(out, "-.")
	runes := []rune(out)
	if len(runes) > max {
		out = string(runes[:max])
	}
	return strings.Trim(out, "-.")
}
