package state

import (
	"encoding/json"
	"os"
	"path/filepath"
)

type State struct {
	LastMessageID int      `json:"last_message_id"`
	Pending       []string `json:"pending,omitempty"`
}

func Load(path string) (State, error) {
	data, err := os.ReadFile(path)
	if os.IsNotExist(err) {
		return State{}, nil
	}
	if err != nil {
		return State{}, err
	}
	var s State
	if err := json.Unmarshal(data, &s); err != nil {
		return State{}, err
	}
	return s, nil
}

func (s State) Save(path string) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	data, err := json.MarshalIndent(s, "", "  ")
	if err != nil {
		return err
	}
	tmp := path + ".tmp"
	if err := os.WriteFile(tmp, append(data, '\n'), 0o644); err != nil {
		return err
	}
	return os.Rename(tmp, path)
}

func NewIDs(ids []int, last int) []int {
	var out []int
	for _, id := range ids {
		if id > last {
			out = append(out, id)
		}
	}
	return out
}

func Max(ids []int) int {
	m := 0
	for _, id := range ids {
		if id > m {
			m = id
		}
	}
	return m
}
