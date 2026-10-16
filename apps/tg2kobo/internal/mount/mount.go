package mount

import (
	"io"
	"os"
	"path/filepath"
	"runtime"
	"strings"
)

// Find returns the first existing candidate directory whose base name
// contains "kobo" (case-insensitive).
func Find(candidates []string) (string, bool) {
	for _, c := range candidates {
		st, err := os.Stat(c)
		if err != nil || !st.IsDir() {
			continue
		}
		if strings.Contains(strings.ToLower(filepath.Base(c)), "kobo") {
			return c, true
		}
	}
	return "", false
}

// DefaultCandidates lists the mount roots to scan on the current OS.
func DefaultCandidates() []string {
	switch runtime.GOOS {
	case "darwin":
		return candidatesIn([]string{"/Volumes"})
	case "linux":
		return candidatesIn([]string{"/run/media", "/media"})
	default:
		return nil
	}
}

// candidatesIn lists the entries of every existing root; missing roots
// are skipped.
func candidatesIn(roots []string) []string {
	var out []string
	for _, r := range roots {
		if entries, err := os.ReadDir(r); err == nil {
			for _, e := range entries {
				out = append(out, filepath.Join(r, e.Name()))
			}
		}
	}
	return out
}

// CopyTo copies src into dir under its base name and returns the
// destination path. The copy is fsynced and its close error checked:
// on a FAT-formatted Kobo a deferred, unchecked Close could report a
// truncated book as copied (and drop it from the queue). A failed copy
// removes the partial file.
func CopyTo(src, dir string) (dst string, err error) {
	dst = filepath.Join(dir, filepath.Base(src))
	in, err := os.Open(src)
	if err != nil {
		return "", err
	}
	defer in.Close()
	out, err := os.Create(dst)
	if err != nil {
		return "", err
	}
	defer func() {
		if err != nil {
			out.Close()
			os.Remove(dst)
			dst = ""
		}
	}()
	if _, err = io.Copy(out, in); err != nil {
		return dst, err
	}
	if err = out.Sync(); err != nil {
		return dst, err
	}
	if err = out.Close(); err != nil {
		return dst, err
	}
	return dst, nil
}
