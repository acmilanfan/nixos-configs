package telegram

import (
	"testing"
	"time"

	"github.com/gotd/td/tg"
)

func TestConvertMessageNonForwarded(t *testing.T) {
	m := &tg.Message{
		ID:      5,
		Date:    1755948000,
		Message: "plain & <simple>",
	}
	got, err := convertMessage(m)
	if err != nil {
		t.Fatalf("convertMessage() = %v", err)
	}
	if got.ID != 5 {
		t.Fatalf("ID = %d", got.ID)
	}
	if got.FromName != "" {
		t.Fatalf("FromName = %q, want empty", got.FromName)
	}
	if want := time.Unix(1755948000, 0).Local(); !got.Date.Equal(want) {
		t.Fatalf("Date = %v, want %v", got.Date, want)
	}
	if got.Text != "plain & <simple>" {
		t.Fatalf("Text = %q", got.Text)
	}
	if got.BodyHTML != "plain &amp; &lt;simple&gt;" {
		t.Fatalf("BodyHTML = %q", got.BodyHTML)
	}
}

func TestConvertMessageForwardUsesOriginalDateAndName(t *testing.T) {
	const orig = 1700000000 // original message date
	const fwd = 1755948000  // date it landed in the inbox channel
	m := &tg.Message{
		ID:      6,
		Date:    fwd,
		Message: "check this out",
		FwdFrom: tg.MessageFwdHeader{
			FromName: "Alice",
			Date:     orig,
		},
	}
	got, err := convertMessage(m)
	if err != nil {
		t.Fatalf("convertMessage() = %v", err)
	}
	if want := time.Unix(orig, 0).Local(); !got.Date.Equal(want) {
		t.Fatalf("Date = %v, want original %v", got.Date, want)
	}
	if got.FromName != "Alice" {
		t.Fatalf("FromName = %q, want Alice", got.FromName)
	}
}

func TestConvertMessageForwardWithoutHeaderDateFallsBack(t *testing.T) {
	const fwd = 1755948000
	m := &tg.Message{
		ID:      7,
		Date:    fwd,
		Message: "no orig date",
		FwdFrom: tg.MessageFwdHeader{FromName: "Bob"},
	}
	got, err := convertMessage(m)
	if err != nil {
		t.Fatalf("convertMessage() = %v", err)
	}
	if want := time.Unix(fwd, 0).Local(); !got.Date.Equal(want) {
		t.Fatalf("Date = %v, want channel %v", got.Date, want)
	}
	if got.FromName != "Bob" {
		t.Fatalf("FromName = %q, want Bob", got.FromName)
	}
}

func TestConvertMessageEntities(t *testing.T) {
	m := &tg.Message{
		ID:      8,
		Date:    1755948000,
		Message: "bold text",
		Entities: []tg.MessageEntityClass{
			&tg.MessageEntityBold{Offset: 0, Length: 4},
		},
	}
	got, err := convertMessage(m)
	if err != nil {
		t.Fatalf("convertMessage() = %v", err)
	}
	if got.BodyHTML != "<strong>bold</strong> text" {
		t.Fatalf("BodyHTML = %q", got.BodyHTML)
	}
}
