package mount

import (
	"os"
	"path/filepath"
	"testing"
)

func TestFindMatchesKoboCaseInsensitive(t *testing.T) {
	root := t.TempDir()
	kobo := filepath.Join(root, "KOBOeReader")
	if err := os.Mkdir(kobo, 0o755); err != nil {
		t.Fatal(err)
	}
	got, ok := Find([]string{filepath.Join(root, "Other"), kobo})
	if !ok {
		t.Fatal("Find() = !ok, want true")
	}
	if got != kobo {
		t.Fatalf("Find() = %q, want %q", got, kobo)
	}
}

func TestFindSkipsMissingPaths(t *testing.T) {
	root := t.TempDir()
	kobo := filepath.Join(root, "kobo-reader")
	if err := os.Mkdir(kobo, 0o755); err != nil {
		t.Fatal(err)
	}
	got, ok := Find([]string{filepath.Join(root, "ghost", "KOBOeReader"), kobo})
	if !ok || got != kobo {
		t.Fatalf("Find() = %q,%v; want %q,true", got, ok, kobo)
	}
}

func TestFindNoneReturnsFalse(t *testing.T) {
	root := t.TempDir()
	_, ok := Find([]string{root})
	if ok {
		t.Fatal("Find() = ok, want false")
	}
}

func TestCopyToPlacesFileUnderDir(t *testing.T) {
	srcDir := t.TempDir()
	dstDir := t.TempDir()
	src := filepath.Join(srcDir, "inbox-2026-08-24.epub")
	if err := os.WriteFile(src, []byte("epub-bytes"), 0o644); err != nil {
		t.Fatal(err)
	}
	dst, err := CopyTo(src, dstDir)
	if err != nil {
		t.Fatalf("CopyTo() = %v", err)
	}
	want := filepath.Join(dstDir, "inbox-2026-08-24.epub")
	if dst != want {
		t.Fatalf("dst = %q, want %q", dst, want)
	}
	data, err := os.ReadFile(want)
	if err != nil {
		t.Fatalf("read dst: %v", err)
	}
	if string(data) != "epub-bytes" {
		t.Fatalf("dst content = %q", data)
	}
}

// Environment-independent: real mount roots (/Volumes, /run/media,
// /media) may be empty or missing, e.g. in the nix build sandbox.
func TestCandidatesInListsEntriesAndSkipsMissingRoots(t *testing.T) {
	root := t.TempDir()
	for _, name := range []string{"KOBOeReader", "USB"} {
		if err := os.Mkdir(filepath.Join(root, name), 0o755); err != nil {
			t.Fatal(err)
		}
	}
	got := candidatesIn([]string{filepath.Join(root, "missing"), root})
	want := []string{filepath.Join(root, "KOBOeReader"), filepath.Join(root, "USB")}
	if len(got) != len(want) {
		t.Fatalf("candidatesIn() = %v, want %v", got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("candidatesIn()[%d] = %q, want %q", i, got[i], want[i])
		}
	}
	if dir, ok := Find(got); !ok || dir != want[0] {
		t.Fatalf("Find(candidatesIn()) = %q,%v; want %q,true", dir, ok, want[0])
	}
}

func TestCopyToFailureLeavesNoPartialFile(t *testing.T) {
	dstDir := t.TempDir()
	srcDir := t.TempDir() // a directory: Open works, reading fails
	if _, err := CopyTo(srcDir, dstDir); err == nil {
		t.Fatal("CopyTo(directory) = nil error")
	}
	entries, err := os.ReadDir(dstDir)
	if err != nil {
		t.Fatal(err)
	}
	if len(entries) != 0 {
		t.Fatalf("partial copy left behind: %v", entries)
	}
}
