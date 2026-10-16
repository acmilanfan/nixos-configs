package telegram

import (
	"bytes"
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/gotd/td/session"
	"github.com/gotd/td/tg"
)

// fakeHistory mimics messages.getHistory over a channel holding message
// IDs 1..last: newest first, at most historyBatch per page, honouring
// OffsetID (exclusive upper bound) and MinID (exclusive lower bound).
type fakeHistory struct {
	last    int
	service map[int]bool // IDs that are service messages
	reqs    []*tg.MessagesGetHistoryRequest
}

func (f *fakeHistory) MessagesGetHistory(_ context.Context, req *tg.MessagesGetHistoryRequest) (tg.MessagesMessagesClass, error) {
	f.reqs = append(f.reqs, req)
	limit := req.Limit
	if limit > historyBatch {
		limit = historyBatch
	}
	top := f.last
	if req.OffsetID != 0 {
		top = req.OffsetID - 1
	}
	res := &tg.MessagesChannelMessages{Count: f.last}
	for id := top; id > req.MinID && len(res.Messages) < limit; id-- {
		if f.service[id] {
			res.Messages = append(res.Messages, &tg.MessageService{ID: id})
			continue
		}
		res.Messages = append(res.Messages, &tg.Message{ID: id, Message: "m"})
	}
	return res, nil
}

func ids(class []tg.MessageClass) []int {
	out := make([]int, len(class))
	for i, mc := range class {
		out[i] = mc.GetID()
	}
	return out
}

func TestFetchHistoryPagesThroughEverythingOldestFirst(t *testing.T) {
	f := &fakeHistory{last: 357, service: map[int]bool{150: true}}
	got, err := fetchHistory(context.Background(), f, &tg.InputPeerEmpty{}, 42)
	if err != nil {
		t.Fatalf("fetchHistory() = %v", err)
	}
	gotIDs := ids(got)
	if len(gotIDs) != 357-42 {
		t.Fatalf("got %d messages, want %d", len(gotIDs), 357-42)
	}
	for i, id := range gotIDs {
		if want := 43 + i; id != want {
			t.Fatalf("message %d has ID %d, want %d (oldest first, no gaps)", i, id, want)
		}
	}
	for i, r := range f.reqs {
		if r.Limit > historyBatch {
			t.Fatalf("request %d: Limit = %d, server caps at %d", i, r.Limit, historyBatch)
		}
		if r.MinID != 42 {
			t.Fatalf("request %d: MinID = %d, want 42", i, r.MinID)
		}
	}
	// 315 messages / 100 per page = 4 pages, no extra empty round trip.
	if len(f.reqs) != 4 {
		t.Fatalf("requests = %d, want 4", len(f.reqs))
	}
}

func TestFetchHistoryNothingNew(t *testing.T) {
	f := &fakeHistory{last: 10}
	got, err := fetchHistory(context.Background(), f, &tg.InputPeerEmpty{}, 10)
	if err != nil {
		t.Fatalf("fetchHistory() = %v", err)
	}
	if len(got) != 0 || len(f.reqs) != 1 {
		t.Fatalf("got %v after %d requests, want nothing after 1", ids(got), len(f.reqs))
	}
}

// stuckHistory keeps returning the same page regardless of OffsetID.
type stuckHistory struct{ calls int }

func (s *stuckHistory) MessagesGetHistory(context.Context, *tg.MessagesGetHistoryRequest) (tg.MessagesMessagesClass, error) {
	s.calls++
	return &tg.MessagesMessagesSlice{Messages: []tg.MessageClass{&tg.Message{ID: 9}, &tg.Message{ID: 8}}}, nil
}

func TestFetchHistoryStopsWithoutProgress(t *testing.T) {
	s := &stuckHistory{}
	got, err := fetchHistory(context.Background(), s, &tg.InputPeerEmpty{}, 0)
	if err != nil {
		t.Fatalf("fetchHistory() = %v", err)
	}
	if s.calls > 2 {
		t.Fatalf("calls = %d; a non-advancing server must not loop", s.calls)
	}
	if want := []int{8, 9}; len(got) != 2 || got[0].GetID() != want[0] || got[1].GetID() != want[1] {
		t.Fatalf("got %v, want %v", ids(got), want)
	}
}

// One message with an out-of-range entity must not block the export
// (state would never advance past it): it is exported as plain text.
func TestConvertMessagesBadEntityFallsBackToPlainText(t *testing.T) {
	class := []tg.MessageClass{
		&tg.Message{ID: 1, Message: "ok <b>", Entities: []tg.MessageEntityClass{&tg.MessageEntityBold{Offset: 0, Length: 2}}},
		&tg.Message{ID: 2, Message: "a & b", Entities: []tg.MessageEntityClass{&tg.MessageEntityBold{Offset: 3, Length: 50}}},
		&tg.MessageService{ID: 3},
		&tg.Message{ID: 4, Message: "after"},
	}
	var warn bytes.Buffer
	got := convertMessages(class, &warn)
	if len(got) != 3 {
		t.Fatalf("got %d messages, want 3", len(got))
	}
	if got[0].BodyHTML != "<strong>ok</strong> &lt;b&gt;" {
		t.Fatalf("msg 1 BodyHTML = %q", got[0].BodyHTML)
	}
	if got[1].ID != 2 || got[1].BodyHTML != "a &amp; b" {
		t.Fatalf("msg 2 = %+v, want plain-text body", got[1])
	}
	if got[2].ID != 4 {
		t.Fatalf("msg after the bad one: ID = %d, want 4", got[2].ID)
	}
	if !strings.Contains(warn.String(), "message 2") {
		t.Fatalf("no warning for message 2: %q", warn.String())
	}
}

func TestAtomicFileStorageRoundTrip(t *testing.T) {
	ctx := context.Background()
	dir := t.TempDir()
	s := &atomicFileStorage{path: filepath.Join(dir, "session.json")}
	if _, err := s.LoadSession(ctx); err != session.ErrNotFound {
		t.Fatalf("LoadSession(missing) = %v, want ErrNotFound", err)
	}
	for _, data := range []string{`{"v":1}`, `{"v":2}`} {
		if err := s.StoreSession(ctx, []byte(data)); err != nil {
			t.Fatalf("StoreSession() = %v", err)
		}
		got, err := s.LoadSession(ctx)
		if err != nil || string(got) != data {
			t.Fatalf("LoadSession() = %q, %v; want %q", got, err, data)
		}
	}
	st, err := os.Stat(s.path)
	if err != nil {
		t.Fatal(err)
	}
	if perm := st.Mode().Perm(); perm != 0o600 {
		t.Fatalf("session perms = %o, want 600", perm)
	}
	entries, err := os.ReadDir(dir)
	if err != nil {
		t.Fatal(err)
	}
	if len(entries) != 1 {
		t.Fatalf("leftover temp files: %v", entries)
	}
}
