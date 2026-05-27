package status

import (
	"bytes"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
)

func CheckColima() Status {
	cmd := exec.Command("colima", "status")
	out, err := cmd.CombinedOutput()
	if err != nil {
		return Status{Name: "Colima", State: StateInactive, Details: "Stopped"}
	}

	if strings.Contains(string(out), "running") {
		return Status{Name: "Colima", State: StateActive, Details: "Running"}
	}

	return Status{Name: "Colima", State: StateInactive, Details: "Stopped"}
}

func CheckBrew() Status {
	cmd := exec.Command("brew", "outdated", "--json")
	out, err := cmd.Output()
	if err != nil {
		return Status{Name: "Brew", State: StateError, Details: "Error"}
	}

	jsonStr := string(out)
	start := strings.IndexAny(jsonStr, "{[")
	if start == -1 {
		return Status{Name: "Brew", State: StateError, Details: "No JSON"}
	}
	jsonStr = jsonStr[start:]

	var data struct {
		Formulae []interface{} `json:"formulae"`
		Casks    []interface{} `json:"casks"`
	}
	if err := json.Unmarshal([]byte(jsonStr), &data); err == nil {
		total := len(data.Formulae) + len(data.Casks)
		if total == 0 {
			return Status{Name: "Brew", State: StateIdle, Details: "Up to date"}
		}
		return Status{Name: "Brew", State: StateSyncing, Details: fmt.Sprintf("%d outdated", total)}
	}

	var list []interface{}
	if err := json.Unmarshal([]byte(jsonStr), &list); err == nil {
		if len(list) == 0 {
			return Status{Name: "Brew", State: StateIdle, Details: "Up to date"}
		}
		return Status{Name: "Brew", State: StateSyncing, Details: fmt.Sprintf("%d outdated", len(list))}
	}

	return Status{Name: "Brew", State: StateError, Details: "Parse error"}
}

func CheckNix(flakeDir string) Status {
	hostname, err := os.Hostname()
	if err != nil {
		hostname = "mac-home"
	}
	flakeTarget := fmt.Sprintf(".#darwinConfigurations.%s.system", hostname)
	currentSystemPath := "/run/current-system"

	args := []string{
		"build", flakeTarget,
		"--impure",
		"--no-write-lock-file",
		"--no-link",
		"--print-out-paths",
		"--update-input", "nixpkgs",
		"--update-input", "unstable-nixpkgs",
		"--update-input", "home-manager",
	}

	buildCmd := exec.Command("nix", args...)
	buildCmd.Dir = flakeDir

	var buildOut bytes.Buffer
	var buildErr bytes.Buffer
	buildCmd.Stdout = &buildOut
	buildCmd.Stderr = &buildErr
	err = buildCmd.Run()
	if err != nil {
		errMsg := "Build failed"
		errStr := buildErr.String()
		if strings.Contains(errStr, "error:") {
			lines := strings.Split(errStr, "\n")
			for _, line := range lines {
				if strings.Contains(line, "error:") {
					extracted := strings.TrimSpace(strings.Replace(line, "error:", "", 1))
					if extracted != "" {
						errMsg = extracted
						if len(errMsg) > 40 {
							errMsg = errMsg[:37] + "..."
						}
						break
					}
				}
			}
		} else if errStr != "" {
			// If no "error:" but we have output, show first line
			errMsg = strings.TrimSpace(strings.Split(errStr, "\n")[0])
			if len(errMsg) > 40 {
				errMsg = errMsg[:37] + "..."
			}
		}
		return Status{Name: "Nix", State: StateError, Details: errMsg}
	}

	newSystemPath := strings.TrimSpace(buildOut.String())
	if newSystemPath == "" {
		return Status{Name: "Nix", State: StateError, Details: "No path returned"}
	}

	nvdArgs := []string{"run", "nixpkgs#nvd", "--", "diff", currentSystemPath, newSystemPath}
	nvdCmd := exec.Command("nix", nvdArgs...)

	var nvdOut bytes.Buffer
	nvdCmd.Stdout = &nvdOut // FIXED: capture stdout
	err = nvdCmd.Run()
	if err != nil {
		return Status{Name: "Nix", State: StateError, Details: "Diff failed"}
	}

	upgradeRegex := regexp.MustCompile(`\[U\]\s+(.*)`)
	count := 0
	lines := strings.Split(nvdOut.String(), "\n")
	for _, line := range lines {
		if upgradeRegex.MatchString(line) {
			count++
		}
	}

	if count == 0 {
		return Status{Name: "Nix", State: StateIdle, Details: "Up to date"}
	}

	return Status{Name: "Nix", State: StateSyncing, Details: fmt.Sprintf("%d upgraded", count)}
}

func CheckNextcloud() Status {
	cmd := exec.Command("pgrep", "Nextcloud")
	err := cmd.Run()
	if err != nil {
		return Status{Name: "Nextcloud", State: StateInactive, Details: "Stopped"}
	}
	return Status{Name: "Nextcloud", State: StateActive, Details: "Active"}
}

func CheckNextcloudFile(ncRoot string, relPath string) Status {
	fullPath := filepath.Join(ncRoot, relPath)
	name := filepath.Base(relPath)

	info, err := os.Stat(fullPath)
	if err != nil {
		return Status{Name: name, State: StateError, Details: "Not found"}
	}
	mtime := info.ModTime().Unix()

	dir := filepath.Dir(fullPath)
	conflictCmd := exec.Command("find", dir, "-name", name+".sync-conflict-*")
	conflictOut, _ := conflictCmd.Output()
	if len(strings.TrimSpace(string(conflictOut))) > 0 {
		return Status{Name: name, State: StateError, Details: "Conflict!"}
	}

	files, _ := filepath.Glob(filepath.Join(ncRoot, ".sync_*.db"))
	if len(files) == 0 {
		return Status{Name: name, State: StateUnknown, Details: "No sync DB"}
	}
	syncDB := files[0]

	tmpDB := "/tmp/syncmon_nc.db"
	copyCmd := exec.Command("cp", syncDB, tmpDB)
	if err := copyCmd.Run(); err != nil {
		return Status{Name: name, State: StateError, Details: "DB locked"}
	}
	defer os.Remove(tmpDB)

	query := fmt.Sprintf("SELECT modtime FROM metadata WHERE path='%s';", relPath)
	dbCmd := exec.Command("sqlite3", tmpDB, query)
	dbOut, err := dbCmd.Output()
	if err != nil {
		return Status{Name: name, State: StateError, Details: "DB error"}
	}

	dbMtimeStr := strings.TrimSpace(string(dbOut))
	if dbMtimeStr == "" {
		return Status{Name: name, State: StateUnknown, Details: "Not tracked"}
	}

	dbMtime, _ := strconv.ParseInt(dbMtimeStr, 10, 64)

	if mtime <= dbMtime {
		return Status{Name: name, State: StateIdle, Details: "Synced"}
	}

	return Status{Name: name, State: StateSyncing, Details: "Pending"}
}
