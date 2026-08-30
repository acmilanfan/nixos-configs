package state

import (
	"path/filepath"
	"testing"
)

func TestLoadMissingFileReturnsZeroState(t *testing.T) {
	s, err := Load(filepath.Join(t.TempDir(), "nope.json"))
	if err != nil {
		t.Fatalf("Load(missing) = %v, want nil error", err)
	}
	if s.LastMessageID != 0 {
		t.Fatalf("LastMessageID = %d, want 0", s.LastMessageID)
	}
}

func TestSaveThenLoadRoundtrip(t *testing.T) {
	path := filepath.Join(t.TempDir(), "state.json")
	want := State{LastMessageID: 4242}
	if err := want.Save(path); err != nil {
		t.Fatalf("Save() = %v, want nil", err)
	}
	got, err := Load(path)
	if err != nil {
		t.Fatalf("Load() = %v, want nil", err)
	}
	if got.LastMessageID != 4242 {
		t.Fatalf("roundtrip LastMessageID = %d, want 4242", got.LastMessageID)
	}
}

func TestNewIDsKeepsOnlyIdsAboveLast(t *testing.T) {
	ids := []int{10, 11, 12, 13}
	got := NewIDs(ids, 11)
	want := []int{12, 13}
	if len(got) != len(want) {
		t.Fatalf("NewIDs = %v, want %v", got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("NewIDs = %v, want %v", got, want)
		}
	}
}

func TestNewIDsEmptyWhenAllExported(t *testing.T) {
	got := NewIDs([]int{10}, 10)
	if len(got) != 0 {
		t.Fatalf("NewIDs = %v, want empty", got)
	}
}

func TestMaxOfIDs(t *testing.T) {
	if got := Max([]int{7, 42, 9}); got != 42 {
		t.Fatalf("Max = %d, want 42", got)
	}
}

func TestMaxOfEmptyIsZero(t *testing.T) {
	if got := Max(nil); got != 0 {
		t.Fatalf("Max(nil) = %d, want 0", got)
	}
}
