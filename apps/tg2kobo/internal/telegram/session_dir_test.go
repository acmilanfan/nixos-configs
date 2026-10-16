package telegram

import (
	"os"
	"path/filepath"
	"testing"
)

func TestEnsureParentDirCreatesMissingDirs(t *testing.T) {
	base := t.TempDir()
	target := filepath.Join(base, "deep", "nested", "dir", "session.json")
	if err := EnsureParentDir(target); err != nil {
		t.Fatalf("EnsureParentDir() = %v", err)
	}
	st, err := os.Stat(filepath.Dir(target))
	if err != nil || !st.IsDir() {
		t.Fatalf("parent dir not created: %v", err)
	}
}

func TestEnsureParentDirIsPrivate(t *testing.T) {
	target := filepath.Join(t.TempDir(), "tg2kobo", "session.json")
	if err := EnsureParentDir(target); err != nil {
		t.Fatalf("EnsureParentDir() = %v", err)
	}
	st, err := os.Stat(filepath.Dir(target))
	if err != nil {
		t.Fatal(err)
	}
	if perm := st.Mode().Perm(); perm&0o077 != 0 {
		t.Fatalf("session dir perms = %o, want no group/other access", perm)
	}
}

func TestEnsureParentDirExistingOK(t *testing.T) {
	dir := t.TempDir()
	if err := EnsureParentDir(filepath.Join(dir, "session.json")); err != nil {
		t.Fatalf("EnsureParentDir() = %v", err)
	}
}
