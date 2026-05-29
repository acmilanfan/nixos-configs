package status

import (
	"os"
	"path/filepath"
	"strings"
)

type State string

const (
	StateIdle     State = "idle"
	StateActive   State = "active"
	StateSyncing  State = "syncing"
	StateError    State = "error"
	StateInactive State = "inactive"
	StateUnknown  State = "unknown"
	StateHidden   State = "hidden"
)

func (s State) String() string {
	switch s {
	case StateIdle:
		return "Idle"
	case StateSyncing:
		return "Syncing"
	case StateError:
		return "Error"
	case StateInactive:
		return "Inactive"
	case StateActive:
		return "Active"
	case StateHidden:
		return "Hidden"
	default:
		return "Unknown"
	}
}

func ExpandPath(path string) string {
	if strings.HasPrefix(path, "~/") {
		home, _ := os.UserHomeDir()
		return filepath.Join(home, path[2:])
	}
	// Migration helper: handle legacy hardcoded paths
	if strings.HasPrefix(path, "/Users/gentooway/") {
		home, _ := os.UserHomeDir()
		return filepath.Join(home, path[len("/Users/gentooway/"):])
	}
	if strings.HasPrefix(path, "/home/gentooway/") {
		home, _ := os.UserHomeDir()
		return filepath.Join(home, path[len("/home/gentooway/"):])
	}
	return path
}

type Status struct {
	Name    string
	State   State
	Details string
	Devices []Status // Nested statuses for sub-items like devices
}

type StatusMsg struct {
	Service string
	Status  Status
	Err     error
}
