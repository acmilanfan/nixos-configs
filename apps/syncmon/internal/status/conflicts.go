package status

import (
	"fmt"
	"os/exec"
	"strings"
)

func CheckConflicts(path string) Status {
	// Find conflicts but ignore .git directory and .DS_Store files
	// find path -not -path '*/.*' -name "*.sync-conflict-*"
	// Actually, let's just use -prune to skip .git
	cmd := exec.Command("find", path, "-name", ".git", "-prune", "-o", "-name", "*.sync-conflict-*", "-not", "-name", "*.DS_Store*", "-print")
	out, err := cmd.Output()
	if err != nil {
		return Status{Name: "Conflicts", State: StateError, Details: "Search error"}
	}

	lines := strings.Split(strings.TrimSpace(string(out)), "\n")
	count := 0
	if len(lines) > 0 && lines[0] != "" {
		count = len(lines)
	}

	if count == 0 {
		return Status{Name: "Conflicts", State: StateIdle, Details: "None"}
	}

	return Status{Name: "Conflicts", State: StateError, Details: fmt.Sprintf("%d found", count)}
}
