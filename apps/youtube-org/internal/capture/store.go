package capture

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"strings"
	"syscall"
	"time"
)

// Check existing path components as well as leaf files. Advisory locks coordinate
// this tool's writers; they cannot protect unsaved editor buffers or hostile peers.
func safeParents(path string) error {
	abs, err := filepath.Abs(path)
	if err != nil {
		return err
	}
	for current := abs; ; current = filepath.Dir(current) {
		info, err := os.Lstat(current)
		if err != nil && !os.IsNotExist(err) {
			return err
		}
		if err == nil && info.Mode()&os.ModeSymlink != 0 {
			return fmt.Errorf("refusing symlink: %s", current)
		}
		if filepath.Dir(current) == current {
			return nil
		}
	}
}

func readRegular(path string) ([]byte, fs.FileMode, bool, error) {
	info, err := os.Lstat(path)
	if os.IsNotExist(err) {
		return nil, 0600, false, nil
	}
	if err != nil {
		return nil, 0, false, err
	}
	if !info.Mode().IsRegular() {
		return nil, 0, false, fmt.Errorf("not a regular file: %s", path)
	}
	f, err := os.OpenFile(path, os.O_RDONLY|syscall.O_NOFOLLOW, 0)
	if err != nil {
		return nil, 0, false, err
	}
	defer f.Close()
	actual, err := f.Stat()
	if err != nil {
		return nil, 0, false, err
	}
	if !os.SameFile(info, actual) {
		return nil, 0, false, errors.New("file changed while opening")
	}
	// Read through the checked descriptor, never reopen a potentially replaced path.
	data, err := readDescriptor(f)
	return data, info.Mode().Perm(), true, err
}

func readDescriptor(f *os.File) ([]byte, error) {
	var b bytes.Buffer
	_, err := b.ReadFrom(f)
	return b.Bytes(), err
}

func (s *Store) ExistingIDs(ctx context.Context) (map[string]bool, error) {
	ids := make(map[string]bool)
	if err := safeParents(s.Dir); err != nil {
		return nil, err
	}
	entries, err := os.ReadDir(s.Dir)
	if os.IsNotExist(err) {
		return ids, nil
	}
	if err != nil {
		return nil, err
	}
	for _, entry := range entries {
		if err := ctx.Err(); err != nil {
			return nil, err
		}
		name := entry.Name()
		if !strings.HasSuffix(name, ".org") && !strings.HasSuffix(name, ".org_archive") {
			continue
		}
		path := filepath.Join(s.Dir, name)
		data, _, exists, err := readRegular(path)
		if err != nil {
			return nil, err
		}
		if !exists {
			return nil, fmt.Errorf("collection changed while scanning: %s", path)
		}
		if err := indexOrg(bytes.NewReader(data), ids); err != nil {
			return nil, fmt.Errorf("%s: %w", name, err)
		}
	}
	return ids, nil
}

func (s *Store) Commit(ctx context.Context, when time.Time, videos []Video, dryRun bool) (CommitResult, error) {
	result := CommitResult{Path: filepath.Join(s.Dir, when.Format("2006-01")+".org")}
	if err := safeParents(s.Dir); err != nil {
		return result, err
	}
	if !dryRun {
		if err := os.MkdirAll(s.Dir, 0700); err != nil {
			return result, err
		}
		lockCtx, cancel := context.WithTimeout(ctx, 10*time.Second)
		defer cancel()
		unlock, err := acquireLock(lockCtx, filepath.Join(s.Dir, ".youtube-org.lock"))
		if err != nil {
			return result, err
		}
		defer unlock()
	}
	ids, err := s.ExistingIDs(ctx)
	if err != nil {
		return result, err
	}
	old, mode, exists, err := readRegular(result.Path)
	if err != nil {
		return result, err
	}
	var additions strings.Builder
	for _, v := range videos {
		if ids[v.ID] {
			result.Existing = append(result.Existing, v.ID)
			continue
		}
		entry, err := RenderEntry(v, when)
		if err != nil {
			return result, err
		}
		additions.WriteString("\n" + entry)
		ids[v.ID] = true
		result.Saved = append(result.Saved, v.ID)
	}
	if dryRun || len(result.Saved) == 0 {
		return result, nil
	}
	data := append([]byte{}, old...)
	if !exists {
		data = []byte("* Consume reflection videos YouTube :video:youtube:\n")
	}
	if len(data) > 0 && data[len(data)-1] != '\n' {
		data = append(data, '\n')
	}
	data = append(data, additions.String()...)
	if err := ctx.Err(); err != nil {
		return result, err
	}
	if err := atomicReplace(result.Path, data, mode, old, exists); err != nil {
		result.Saved = nil
		return result, err
	}
	return result, nil
}

func acquireLock(ctx context.Context, path string) (func(), error) {
	fd, err := syscall.Open(path, syscall.O_CREAT|syscall.O_RDWR|syscall.O_NOFOLLOW, 0600)
	if err != nil {
		return nil, err
	}
	f := os.NewFile(uintptr(fd), path)
	info, err := f.Stat()
	if err != nil || !info.Mode().IsRegular() {
		f.Close()
		return nil, errors.New("invalid collection lock file")
	}
	for {
		err = syscall.Flock(fd, syscall.LOCK_EX|syscall.LOCK_NB)
		if err == nil {
			return func() { syscall.Flock(fd, syscall.LOCK_UN); f.Close() }, nil
		}
		if err != syscall.EWOULDBLOCK && err != syscall.EAGAIN && err != syscall.EINTR {
			f.Close()
			return nil, err
		}
		select {
		case <-ctx.Done():
			f.Close()
			return nil, ctx.Err()
		case <-time.After(20 * time.Millisecond):
		}
	}
}

func atomicReplace(path string, data []byte, mode fs.FileMode, expected []byte, existed bool) error {
	if err := safeParents(path); err != nil {
		return err
	}
	f, err := os.CreateTemp(filepath.Dir(path), ".youtube-org-write-*")
	if err != nil {
		return err
	}
	name := f.Name()
	defer os.Remove(name)
	if err = f.Chmod(mode); err == nil {
		_, err = f.Write(data)
	}
	if err == nil {
		err = f.Sync()
	}
	closeErr := f.Close()
	if err != nil {
		return err
	}
	if closeErr != nil {
		return closeErr
	}
	actual, actualMode, exists, err := readRegular(path)
	if err != nil {
		return err
	}
	if exists != existed || !bytes.Equal(actual, expected) || (exists && actualMode != mode) {
		return errors.New("destination changed; retry after saving/reloading the editor")
	}
	if err := os.Rename(name, path); err != nil {
		return err
	}
	dir, err := os.Open(filepath.Dir(path))
	if err != nil {
		return fmt.Errorf("file replaced but directory durability uncertain: %w", err)
	}
	defer dir.Close()
	if err := dir.Sync(); err != nil {
		return fmt.Errorf("file replaced but directory durability uncertain: %w", err)
	}
	return nil
}
