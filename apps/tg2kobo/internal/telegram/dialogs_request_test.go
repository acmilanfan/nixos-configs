package telegram

import (
	"context"
	"fmt"
	"strings"
	"testing"

	"github.com/gotd/td/telegram/query/dialogs"
	"github.com/gotd/td/tg"
)

// fakeDialogs serves n dialogs (channels "chan-<i>", plus one basic
// group titled groupTitle at index groupAt) in pages of at most
// dialogsBatch, newest first, the way messages.getDialogs does.
type fakeDialogs struct {
	n          int
	groupAt    int
	groupTitle string
	reqs       []dialogs.Request
}

func (f *fakeDialogs) peerAt(i int) tg.PeerClass {
	if i == f.groupAt {
		return &tg.PeerChat{ChatID: int64(i + 1)}
	}
	return &tg.PeerChannel{ChannelID: int64(i + 1)}
}

func (f *fakeDialogs) Query(_ context.Context, req dialogs.Request) (tg.MessagesDialogsClass, error) {
	f.reqs = append(f.reqs, req)
	start := 0
	if req.OffsetID != 0 {
		start = req.OffsetID - 1000 + 1 // top message of dialog i is 1000+i
	}
	limit := req.Limit
	if limit > dialogsBatch {
		limit = dialogsBatch
	}
	res := &tg.MessagesDialogsSlice{Count: f.n}
	for i := start; i < f.n && i < start+limit; i++ {
		p := f.peerAt(i)
		res.Dialogs = append(res.Dialogs, &tg.Dialog{Peer: p, TopMessage: 1000 + i})
		res.Messages = append(res.Messages, &tg.Message{ID: 1000 + i, PeerID: p, Date: 2000000000 - i})
		if i == f.groupAt {
			res.Chats = append(res.Chats, &tg.Chat{ID: int64(i + 1), Title: f.groupTitle})
		} else {
			res.Chats = append(res.Chats, &tg.Channel{ID: int64(i + 1), AccessHash: int64(7 * (i + 1)), Title: fmt.Sprintf("chan-%d", i)})
		}
	}
	return res, nil
}

func iterOver(f *fakeDialogs) *dialogs.Iterator {
	return dialogs.NewIterator(f, dialogsBatch)
}

// Telegram rejects messages.getDialogs when offset_peer is missing
// (gotd cannot encode a nil union field — real-world error:
// "field offset_peer is nil"). Every request must carry a peer.
func TestFindInboxRequestsCarryOffsetPeer(t *testing.T) {
	f := &fakeDialogs{n: 150, groupAt: -1}
	if _, err := findInbox(context.Background(), iterOver(f), "missing"); err == nil {
		t.Fatal("findInbox() = nil error for a missing title")
	}
	if len(f.reqs) == 0 {
		t.Fatal("no dialogs requested")
	}
	for i, r := range f.reqs {
		if r.OffsetPeer == nil {
			t.Fatalf("request %d: OffsetPeer is nil; Telegram will refuse to encode it", i)
		}
		if r.Limit > dialogsBatch {
			t.Fatalf("request %d: Limit = %d, server caps at %d", i, r.Limit, dialogsBatch)
		}
	}
}

// The inbox may sit far below the most recent page of dialogs.
func TestFindInboxPagesBeyondFirstBatch(t *testing.T) {
	f := &fakeDialogs{n: 250, groupAt: 230, groupTitle: "kobo INBOX"}
	got, err := findInbox(context.Background(), iterOver(f), "Kobo Inbox")
	if err != nil {
		t.Fatalf("findInbox() = %v", err)
	}
	if p, ok := got.(*tg.InputPeerChat); !ok || p.ChatID != 231 {
		t.Fatalf("findInbox() = %#v, want InputPeerChat{231}", got)
	}
	if len(f.reqs) != 3 {
		t.Fatalf("requests = %d, want 3 pages", len(f.reqs))
	}
}

func TestFindInboxChannelKeepsAccessHash(t *testing.T) {
	f := &fakeDialogs{n: 5, groupAt: -1}
	got, err := findInbox(context.Background(), iterOver(f), "CHAN-3")
	if err != nil {
		t.Fatalf("findInbox() = %v", err)
	}
	p, ok := got.(*tg.InputPeerChannel)
	if !ok || p.ChannelID != 4 || p.AccessHash != 28 {
		t.Fatalf("findInbox() = %#v, want InputPeerChannel{4, hash 28}", got)
	}
}

func TestFindInboxNotFoundErrorIsBounded(t *testing.T) {
	f := &fakeDialogs{n: 120, groupAt: -1}
	_, err := findInbox(context.Background(), iterOver(f), "nope")
	if err == nil {
		t.Fatal("findInbox() = nil error")
	}
	msg := err.Error()
	if !strings.Contains(msg, "among 120 chats/channels") {
		t.Fatalf("error lacks dialog count: %s", msg)
	}
	if strings.Contains(msg, fmt.Sprintf("chan-%d", maxSeenTitles)) {
		t.Fatalf("error lists more than %d titles: %s", maxSeenTitles, msg)
	}
}
