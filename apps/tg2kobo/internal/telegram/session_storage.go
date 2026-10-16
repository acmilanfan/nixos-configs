package telegram

import (
	"context"
	"os"
	"path/filepath"
	"sync"

	"github.com/gotd/td/session"
)

// atomicFileStorage is a session.Storage like gotd's session.FileStorage,
// except that it replaces the file atomically (temp file + fsync +
// rename): a crash or full disk mid-write can no longer leave a
// truncated session behind and force a fresh interactive login.
type atomicFileStorage struct {
	path string
	mu   sync.Mutex
}

var _ session.Storage = (*atomicFileStorage)(nil)

func (s *atomicFileStorage) LoadSession(context.Context) ([]byte, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	data, err := os.ReadFile(s.path)
	if os.IsNotExist(err) {
		return nil, session.ErrNotFound
	}
	return data, err
}

func (s *atomicFileStorage) StoreSession(_ context.Context, data []byte) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	// CreateTemp opens the file 0600, like gotd's FileStorage.
	tmp, err := os.CreateTemp(filepath.Dir(s.path), filepath.Base(s.path)+".tmp*")
	if err != nil {
		return err
	}
	defer os.Remove(tmp.Name()) // fails harmlessly once renamed
	if _, err := tmp.Write(data); err != nil {
		tmp.Close()
		return err
	}
	if err := tmp.Sync(); err != nil {
		tmp.Close()
		return err
	}
	if err := tmp.Close(); err != nil {
		return err
	}
	return os.Rename(tmp.Name(), s.path)
}
