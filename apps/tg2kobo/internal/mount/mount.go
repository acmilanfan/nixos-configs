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
	var roots []string
	switch runtime.GOOS {
	case "darwin":
		roots = []string{"/Volumes"}
	case "linux":
		roots = []string{"/run/media", "/media"}
	default:
		return nil
	}
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

// CopyTo copies src into dir under its base name and returns the destination path.
func CopyTo(src, dir string) (string, error) {
	dst := filepath.Join(dir, filepath.Base(src))
	in, err := os.Open(src)
	if err != nil {
		return "", err
	}
	defer in.Close()
	out, err := os.Create(dst)
	if err != nil {
		return "", err
	}
	defer out.Close()
	if _, err := io.Copy(out, in); err != nil {
		return "", err
	}
	return dst, nil
}
