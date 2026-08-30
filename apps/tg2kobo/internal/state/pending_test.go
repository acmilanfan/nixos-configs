package state

import (
	"path/filepath"
	"testing"
)

func TestPendingRoundtrip(t *testing.T) {
	path := filepath.Join(t.TempDir(), "state.json")
	want := State{LastMessageID: 10, Pending: []string{"/tmp/a.epub", "/Volumes/KOBOeReader/b.epub"}}
	if err := want.Save(path); err != nil {
		t.Fatalf("Save() = %v", err)
	}
	got, err := Load(path)
	if err != nil {
		t.Fatalf("Load() = %v", err)
	}
	if len(got.Pending) != 2 || got.Pending[1] != "/Volumes/KOBOeReader/b.epub" {
		t.Fatalf("pending roundtrip failed: %v", got.Pending)
	}
}

func TestLoadMissingHasNoPending(t *testing.T) {
	s, _ := Load(filepath.Join(t.TempDir(), "x.json"))
	if s.Pending != nil {
		t.Fatalf("pending = %v, want nil", s.Pending)
	}
}
