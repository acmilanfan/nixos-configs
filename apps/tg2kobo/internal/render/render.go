package render

import (
	"fmt"
	"html"
	"sort"
	"strings"
	"time"
	"unicode/utf16"
)

type Kind string

const (
	KindBold      Kind = "bold"
	KindItalic    Kind = "italic"
	KindUnderline Kind = "underline"
	KindStrike    Kind = "strikethrough"
	KindCode      Kind = "code"
	KindPre       Kind = "pre"
	KindSpoiler   Kind = "spoiler"
	KindLink      Kind = "textlink"
	KindURL       Kind = "url"
)

// Entity mirrors Telegram's message entities. Offset and Length are in
// UTF-16 code units, exactly as the Telegram API delivers them.
type Entity struct {
	Kind   Kind
	Offset int
	Length int
	URL    string // only for KindLink
}

func (e Entity) end() int { return e.Offset + e.Length }

type tag struct {
	open  string
	close string
}

var tags = map[Kind]tag{
	KindBold:      {"<strong>", "</strong>"},
	KindItalic:    {"<em>", "</em>"},
	KindUnderline: {"<u>", "</u>"},
	KindStrike:    {"<s>", "</s>"},
	KindCode:      {"<code>", "</code>"},
	KindPre:       {"<pre>", "</pre>"},
	KindSpoiler:   {`<span class="spoiler">`, "</span>"},
}

// ToHTML renders plain text plus Telegram entities into HTML,
// escaping everything that is not wrapped by an entity.
func ToHTML(text string, ents []Entity) (string, error) {
	units := utf16.Encode([]rune(text))
	for _, e := range ents {
		if e.Offset < 0 || e.Length < 0 || e.end() > len(units) {
			return "", fmt.Errorf("entity %v out of range (text has %d UTF-16 units)", e, len(units))
		}
	}
	sorted := make([]Entity, len(ents))
	copy(sorted, ents)
	for i := range sorted {
		// A bare-URL entity is just a link whose href is its own text.
		if sorted[i].Kind == KindURL {
			sorted[i].Kind = KindLink
			sorted[i].URL = string(utf16.Decode(units[sorted[i].Offset:sorted[i].end()]))
		}
	}
	sort.SliceStable(sorted, func(i, j int) bool {
		if sorted[i].Offset != sorted[j].Offset {
			return sorted[i].Offset < sorted[j].Offset
		}
		return sorted[i].Length > sorted[j].Length
	})
	return apply(units, sorted), nil
}

func apply(units []uint16, ents []Entity) string {
	var b strings.Builder
	pos := 0
	i := 0
	for i < len(ents) {
		e := ents[i]
		if e.Offset > pos {
			b.WriteString(html.EscapeString(string(utf16.Decode(units[pos:e.Offset]))))
		}
		var children []Entity
		j := i + 1
		for ; j < len(ents) && ents[j].end() <= e.end(); j++ {
			c := ents[j]
			c.Offset -= e.Offset
			children = append(children, c)
		}
		b.WriteString(openTag(e))
		b.WriteString(apply(units[e.Offset:e.end()], children))
		b.WriteString(closeTag(e))
		pos = e.end()
		i = j
	}
	if pos < len(units) {
		b.WriteString(html.EscapeString(string(utf16.Decode(units[pos:]))))
	}
	return b.String()
}

func openTag(e Entity) string {
	switch e.Kind {
	case KindLink:
		return fmt.Sprintf(`<a href="%s">`, html.EscapeString(e.URL))
	default:
		return tags[e.Kind].open
	}
}

func closeTag(e Entity) string {
	switch e.Kind {
	case KindLink:
		return "</a>"
	default:
		return tags[e.Kind].close
	}
}

type Message struct {
	ID       int
	Date     time.Time
	FromName string
	Text     string // raw text; used for titles and filenames
	BodyHTML string // rendered HTML; used for chapter bodies
}

const mediaPlaceholder = `<p class="placeholder">[media]</p>`

func MessageXHTML(m Message) string {
	var b strings.Builder
	b.WriteString("<div class=\"msg\">\n")
	fmt.Fprintf(&b, "<p class=\"meta\">%s</p>\n", metaLine(m))
	body := m.BodyHTML
	if body == "" {
		body = mediaPlaceholder
	}
	fmt.Fprintf(&b, "<div class=\"body\">%s</div>\n", body)
	b.WriteString("</div>")
	return b.String()
}

func metaLine(m Message) string {
	stamp := m.Date.Format("2006-01-02 15:04")
	if m.FromName == "" {
		return stamp
	}
	return stamp + " · " + html.EscapeString(m.FromName)
}
