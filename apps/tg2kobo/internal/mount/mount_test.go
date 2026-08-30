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

func TestDefaultCandidatesNonEmpty(t *testing.T) {
	if len(DefaultCandidates()) == 0 {
		t.Fatal("DefaultCandidates() is empty")
	}
}
