package telegram

import (
	"github.com/gotd/td/tg"

	"tg2kobo/internal/render"
)

// ConvertEntities maps gotd message entities onto renderer entities.
// Unsupported kinds (mention, hashtag, …) are dropped: their text
// already renders fine as plain text.
func ConvertEntities(in []tg.MessageEntityClass) []render.Entity {
	if in == nil {
		return nil
	}
	out := make([]render.Entity, 0, len(in))
	for _, e := range in {
		switch v := e.(type) {
		case *tg.MessageEntityBold:
			out = append(out, render.Entity{Kind: render.KindBold, Offset: int(v.Offset), Length: int(v.Length)})
		case *tg.MessageEntityItalic:
			out = append(out, render.Entity{Kind: render.KindItalic, Offset: int(v.Offset), Length: int(v.Length)})
		case *tg.MessageEntityUnderline:
			out = append(out, render.Entity{Kind: render.KindUnderline, Offset: int(v.Offset), Length: int(v.Length)})
		case *tg.MessageEntityStrike:
			out = append(out, render.Entity{Kind: render.KindStrike, Offset: int(v.Offset), Length: int(v.Length)})
		case *tg.MessageEntityCode:
			out = append(out, render.Entity{Kind: render.KindCode, Offset: int(v.Offset), Length: int(v.Length)})
		case *tg.MessageEntityPre:
			out = append(out, render.Entity{Kind: render.KindPre, Offset: int(v.Offset), Length: int(v.Length)})
		case *tg.MessageEntitySpoiler:
			out = append(out, render.Entity{Kind: render.KindSpoiler, Offset: int(v.Offset), Length: int(v.Length)})
		case *tg.MessageEntityTextURL:
			out = append(out, render.Entity{Kind: render.KindLink, Offset: int(v.Offset), Length: int(v.Length), URL: v.URL})
		case *tg.MessageEntityURL:
			out = append(out, render.Entity{Kind: render.KindURL, Offset: int(v.Offset), Length: int(v.Length)})
		}
	}
	return out
}
