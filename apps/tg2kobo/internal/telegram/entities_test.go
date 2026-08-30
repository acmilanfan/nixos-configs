package telegram

import (
	"testing"

	"github.com/gotd/td/tg"

	"tg2kobo/internal/render"
)

func TestConvertEntitiesMapsKinds(t *testing.T) {
	in := []tg.MessageEntityClass{
		&tg.MessageEntityBold{Offset: 0, Length: 1},
		&tg.MessageEntityItalic{Offset: 2, Length: 3},
		&tg.MessageEntityUnderline{Offset: 4, Length: 5},
		&tg.MessageEntityStrike{Offset: 6, Length: 7},
		&tg.MessageEntityCode{Offset: 8, Length: 9},
		&tg.MessageEntityPre{Offset: 10, Length: 11},
		&tg.MessageEntitySpoiler{Offset: 12, Length: 13},
		&tg.MessageEntityTextURL{Offset: 14, Length: 15, URL: "https://t.io/x"},
		&tg.MessageEntityURL{Offset: 16, Length: 17},
		// intentionally unsupported kinds must be dropped:
		&tg.MessageEntityMention{Offset: 18, Length: 19},
		&tg.MessageEntityHashtag{Offset: 20, Length: 21},
		&tg.MessageEntityEmail{Offset: 22, Length: 23},
	}
	got := ConvertEntities(in)
	want := []render.Entity{
		{Kind: render.KindBold, Offset: 0, Length: 1},
		{Kind: render.KindItalic, Offset: 2, Length: 3},
		{Kind: render.KindUnderline, Offset: 4, Length: 5},
		{Kind: render.KindStrike, Offset: 6, Length: 7},
		{Kind: render.KindCode, Offset: 8, Length: 9},
		{Kind: render.KindPre, Offset: 10, Length: 11},
		{Kind: render.KindSpoiler, Offset: 12, Length: 13},
		{Kind: render.KindLink, Offset: 14, Length: 15, URL: "https://t.io/x"},
		{Kind: render.KindURL, Offset: 16, Length: 17},
	}
	if len(got) != len(want) {
		t.Fatalf("len = %d, want %d; got %v", len(got), len(want), got)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("got[%d] = %v, want %v", i, got[i], want[i])
		}
	}
}

func TestConvertEntitiesEmptyAndNil(t *testing.T) {
	if got := ConvertEntities(nil); got != nil {
		t.Fatalf("nil → %v, want nil", got)
	}
	if got := ConvertEntities([]tg.MessageEntityClass{}); len(got) != 0 {
		t.Fatalf("empty → %v", got)
	}
}
