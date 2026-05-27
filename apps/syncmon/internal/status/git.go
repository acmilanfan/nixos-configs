package status

import (
	"fmt"
	"os/exec"
	"strings"
)

func CheckGitStatus(path string, name string) Status {
	cmd := exec.Command("git", "-C", path, "status", "--porcelain")
	out, err := cmd.Output()
	if err != nil {
		return Status{Name: name, State: StateError, Details: "Git error"}
	}

	lines := strings.Split(strings.TrimSpace(string(out)), "\n")
	count := 0
	if len(lines) > 0 && lines[0] != "" {
		count = len(lines)
	}

	if count == 0 {
		return Status{Name: name, State: StateIdle, Details: "Clean"}
	}

	state := StateSyncing
	if name == "Configs" {
		state = StateIdle // Don't highlight config changes as "Syncing" necessarily
	}

	return Status{Name: name, State: state, Details: fmt.Sprintf("%d changes", count)}
}
