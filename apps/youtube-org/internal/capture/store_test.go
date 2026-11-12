package capture

import (
	"context"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
	"testing"
	"time"
)

func put(t *testing.T, path, contents string) {
	t.Helper()
	if err := os.WriteFile(path, []byte(contents), 0600); err != nil {
		t.Fatal(err)
	}
}
func read(t *testing.T, path string) string {
	t.Helper()
	b, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	return string(b)
}

func TestStoreLegacyArchiveAndActiveIndex(t *testing.T) {
	dir := t.TempDir()
	put(t, filepath.Join(dir, "youtube1.org"), "* Pool\n** TODO A\n:PROPERTIES:\n:Link: [[https://youtu.be/"+testID+"?t=3]]\n:END:\n")
	put(t, filepath.Join(dir, "youtube1.org_archive"), "* DONE B\n:PROPERTIES:\n:Link: [[https://youtube.com/shorts/abcdefghijk]]\n:END:\n** DONE C\n:PROPERTIES:\n:VIDEO_ID: 01234567890\n:END:\n")
	ids, err := (&Store{Dir: dir}).ExistingIDs(context.Background())
	if err != nil || len(ids) != 3 || !ids[testID] || !ids["abcdefghijk"] || !ids["01234567890"] {
		t.Fatalf("%#v %v", ids, err)
	}
}

func TestStoreCommitPreservesAndDeduplicates(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "2026-11.org")
	original := "* Existing header\n\n** TODO unrelated\nText retained\n"
	put(t, path, original)
	if err := os.Chmod(path, 0640); err != nil {
		t.Fatal(err)
	}
	s := &Store{Dir: dir}
	now := time.Date(2026, 11, 11, 0, 0, 0, 0, time.UTC)
	r, err := s.Commit(context.Background(), now, []Video{fixtureVideo(), fixtureVideo()}, false)
	if err != nil || len(r.Saved) != 1 || r.Path != path {
		t.Fatalf("%#v %v", r, err)
	}
	contents := read(t, path)
	if !strings.HasPrefix(contents, original) || strings.Count(contents, ":VIDEO_ID: "+testID) != 1 {
		t.Fatal(contents)
	}
	info, _ := os.Stat(path)
	if info.Mode().Perm() != 0640 {
		t.Fatal("permissions changed")
	}
	r, err = s.Commit(context.Background(), now, []Video{fixtureVideo()}, false)
	if err != nil || len(r.Saved) != 0 || len(r.Existing) != 1 || read(t, path) != contents {
		t.Fatalf("retry changed file: %#v %v", r, err)
	}
}

func TestStoreNewFileAndDryRun(t *testing.T) {
	dir := filepath.Join(t.TempDir(), "not-created")
	s := &Store{Dir: dir}
	now := time.Date(2026, 11, 1, 0, 0, 0, 0, time.UTC)
	if _, err := s.Commit(context.Background(), now, []Video{fixtureVideo()}, true); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(dir); !os.IsNotExist(err) {
		t.Fatal("dry-run mutated filesystem")
	}
	if _, err := s.Commit(context.Background(), now, []Video{fixtureVideo()}, false); err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(dir, "2026-11.org")
	contents := read(t, path)
	if !strings.HasPrefix(contents, "* Consume reflection videos YouTube :video:youtube:\n\n** TODO") {
		t.Fatal(contents)
	}
	info, _ := os.Stat(path)
	if info.Mode().Perm() != 0600 {
		t.Fatal(info.Mode())
	}
	// Optional test-only artifact for the installed Neovim compatibility regression.
	if output := os.Getenv("YOUTUBE_ORG_PICKER_FIXTURE"); output != "" {
		if err := os.WriteFile(output, []byte(contents), 0600); err != nil {
			t.Fatal(err)
		}
	}
}

func TestStoreRejectsSymlinksAndCorruptIdentity(t *testing.T) {
	for _, kind := range []string{"dir", "destination", "archive", "lock", "malformed-id", "mismatch"} {
		t.Run(kind, func(t *testing.T) {
			root := t.TempDir()
			dir := filepath.Join(root, "collection")
			os.Mkdir(dir, 0700)
			target := filepath.Join(root, "outside")
			put(t, target, "preserve")
			s := &Store{Dir: dir}
			switch kind {
			case "dir":
				s.Dir = filepath.Join(root, "link")
				os.Symlink(dir, s.Dir)
			case "destination":
				os.Symlink(target, filepath.Join(dir, "2026-11.org"))
			case "archive":
				os.Symlink(target, filepath.Join(dir, "youtube1.org_archive"))
			case "lock":
				os.Symlink(target, filepath.Join(dir, ".youtube-org.lock"))
			case "malformed-id":
				put(t, filepath.Join(dir, "youtube1.org"), "** TODO x\n:PROPERTIES:\n:VIDEO_ID: wrong\n:END:\n")
			case "mismatch":
				put(t, filepath.Join(dir, "youtube1.org"), "** TODO x\n:PROPERTIES:\n:VIDEO_ID: abcdefghijk\n:Link: [["+testURL+"]]\n:END:\n")
			}
			if _, err := s.Commit(context.Background(), time.Date(2026, 11, 1, 0, 0, 0, 0, time.UTC), []Video{fixtureVideo()}, false); err == nil {
				t.Fatal("accepted unsafe collection")
			}
			if read(t, target) != "preserve" {
				t.Fatal("external target modified")
			}
		})
	}
}

func TestStoreReadErrorsFailClosed(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "youtube1.org")
	put(t, path, "x")
	os.Chmod(path, 0000)
	t.Cleanup(func() { os.Chmod(path, 0600) })
	if _, err := (&Store{Dir: dir}).ExistingIDs(context.Background()); err == nil {
		t.Fatal("ignored read error")
	}
}

func TestStoreLockCancellation(t *testing.T) {
	dir := t.TempDir()
	f, err := os.OpenFile(filepath.Join(dir, ".youtube-org.lock"), os.O_CREATE|os.O_RDWR, 0600)
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()
	if err := syscall.Flock(int(f.Fd()), syscall.LOCK_EX); err != nil {
		t.Fatal(err)
	}
	defer syscall.Flock(int(f.Fd()), syscall.LOCK_UN)
	ctx, cancel := context.WithTimeout(context.Background(), 40*time.Millisecond)
	defer cancel()
	if _, err := (&Store{Dir: dir}).Commit(ctx, time.Now(), []Video{fixtureVideo()}, false); err == nil {
		t.Fatal("ignored lock cancellation")
	}
}

func TestStoreConcurrentProcess(t *testing.T) {
	if dir := os.Getenv("YOUTUBE_ORG_STORE_TEST_DIR"); dir != "" {
		_, err := (&Store{Dir: dir}).Commit(context.Background(), time.Date(2026, 11, 1, 0, 0, 0, 0, time.UTC), []Video{fixtureVideo()}, false)
		if err != nil {
			t.Fatal(err)
		}
		return
	}
	dir := t.TempDir()
	var cmds []*exec.Cmd
	for i := 0; i < 2; i++ {
		c := exec.Command(os.Args[0], "-test.run=^TestStoreConcurrentProcess$")
		c.Env = append(os.Environ(), "YOUTUBE_ORG_STORE_TEST_DIR="+dir)
		if err := c.Start(); err != nil {
			t.Fatal(err)
		}
		cmds = append(cmds, c)
	}
	for _, c := range cmds {
		if err := c.Wait(); err != nil {
			t.Fatal(err)
		}
	}
	if got := strings.Count(read(t, filepath.Join(dir, "2026-11.org")), ":VIDEO_ID: "+testID); got != 1 {
		t.Fatalf("got %d copies", got)
	}
}

func TestStoreAtomicReplaceRejectsChangedDestination(t *testing.T) {
	path := filepath.Join(t.TempDir(), "file")
	put(t, path, "newer")
	if err := atomicReplace(path, []byte("replacement"), 0600, []byte("old"), true); err == nil {
		t.Fatal("overwrote changed destination")
	}
	if read(t, path) != "newer" {
		t.Fatal("lost external edit")
	}
}

func TestStoreAtomicReplaceFailurePreservesOriginal(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "file")
	put(t, path, "original")
	os.Chmod(dir, 0500)
	defer os.Chmod(dir, 0700)
	if err := atomicReplace(path, []byte("replacement"), 0600, []byte("original"), true); err == nil {
		t.Fatal("ignored write failure")
	}
	if read(t, path) != "original" {
		t.Fatal("damaged original")
	}
}
