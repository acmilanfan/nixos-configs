package render

import (
	"strings"
	"testing"
	"time"
)

func TestPlainEscapesHTML(t *testing.T) {
	got, err := ToHTML("a < b & c", nil)
	if err != nil {
		t.Fatalf("ToHTML() err = %v", err)
	}
	want := "a &lt; b &amp; c"
	if got != want {
		t.Fatalf("ToHTML = %q, want %q", got, want)
	}
}

func TestBoldEntity(t *testing.T) {
	got, err := ToHTML("hello world", []Entity{{Kind: KindBold, Offset: 6, Length: 5}})
	if err != nil {
		t.Fatalf("err = %v", err)
	}
	want := "hello <strong>world</strong>"
	if got != want {
		t.Fatalf("got %q, want %q", got, want)
	}
}

func TestSequentialEntities(t *testing.T) {
	got, err := ToHTML("one two", []Entity{
		{Kind: KindBold, Offset: 0, Length: 3},
		{Kind: KindItalic, Offset: 4, Length: 3},
	})
	if err != nil {
		t.Fatalf("err = %v", err)
	}
	want := "<strong>one</strong> <em>two</em>"
	if got != want {
		t.Fatalf("got %q, want %q", got, want)
	}
}

// Telegram offsets/lengths are UTF-16 code units: an astral-plane char
// like 👍 counts as TWO units even though it is one rune.
func TestUTF16OffsetsWithEmoji(t *testing.T) {
	got, err := ToHTML("👍 hi there", []Entity{{Kind: KindBold, Offset: 3, Length: 2}})
	if err != nil {
		t.Fatalf("err = %v", err)
	}
	want := "👍 <strong>hi</strong> there"
	if got != want {
		t.Fatalf("got %q, want %q", got, want)
	}
}

func TestNestedEntities(t *testing.T) {
	got, err := ToHTML("see this page now", []Entity{
		{Kind: KindLink, Offset: 4, Length: 9, URL: "https://example.com/a&b"},
		{Kind: KindBold, Offset: 6, Length: 4},
	})
	if err != nil {
		t.Fatalf("err = %v", err)
	}
	want := `see <a href="https://example.com/a&amp;b">th<strong>is p</strong>age</a> now`
	if got != want {
		t.Fatalf("got %q, want %q", got, want)
	}
}

func TestCodeAndPreAndSpoiler(t *testing.T) {
	got, err := ToHTML("x y z", []Entity{
		{Kind: KindCode, Offset: 0, Length: 1},
		{Kind: KindPre, Offset: 2, Length: 1},
		{Kind: KindSpoiler, Offset: 4, Length: 1},
	})
	if err != nil {
		t.Fatalf("err = %v", err)
	}
	want := "<code>x</code> <pre>y</pre> <span class=\"spoiler\">z</span>"
	if got != want {
		t.Fatalf("got %q, want %q", got, want)
	}
}

func TestURLEntityBecomesAnchor(t *testing.T) {
	got, err := ToHTML("visit https://example.com ok", []Entity{
		{Kind: KindURL, Offset: 6, Length: 19},
	})
	if err != nil {
		t.Fatalf("err = %v", err)
	}
	want := `visit <a href="https://example.com">https://example.com</a> ok`
	if got != want {
		t.Fatalf("got %q, want %q", got, want)
	}
}

func sampleMessage(body string) Message {
	date := time.Date(2026, 8, 24, 14, 3, 0, 0, time.UTC)
	return Message{ID: 7, Date: date, FromName: "Alice", BodyHTML: body}
}

func TestMessageXHTMLFull(t *testing.T) {
	m := sampleMessage("hello")
	got := MessageXHTML(m)
	for _, want := range []string{
		`<div class="msg">`,
		`<p class="meta">2026-08-24 14:03 · Alice</p>`,
		`<div class="body">hello</div>`,
	} {
		if !strings.Contains(got, want) {
			t.Fatalf("missing %q in:\n%s", want, got)
		}
	}
}

func TestMessageXHTMLEmptyBodyPlaceholder(t *testing.T) {
	got := MessageXHTML(sampleMessage(""))
	if !strings.Contains(got, `<p class="placeholder">[media]</p>`) {
		t.Fatalf("missing placeholder in:\n%s", got)
	}
}

func TestMessageXHTMLNoFromOmitsSeparator(t *testing.T) {
	m := sampleMessage("hi")
	m.FromName = ""
	got := MessageXHTML(m)
	if strings.Contains(got, "·") && !strings.Contains(got, `<p class="meta">2026-08-24 14:03</p>`) {
		t.Fatalf("unexpected meta formatting:\n%s", got)
	}
}
