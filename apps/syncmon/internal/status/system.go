package status

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"runtime"
	"strconv"
	"strings"
)

func CheckContainerEngine() Status {
	if runtime.GOOS == "darwin" {
		cmd := exec.Command("colima", "status")
		if err := cmd.Run(); err == nil {
			return Status{Name: "Containers", State: StateActive, Details: "Colima"}
		}
	}

	// Fallback to docker check
	cmd := exec.Command("docker", "info")
	if err := cmd.Run(); err == nil {
		return Status{Name: "Containers", State: StateActive, Details: "Docker"}
	}

	return Status{Name: "Containers", State: StateInactive, Details: "Stopped"}
}

func CheckBrew() Status {
	_, err := exec.LookPath("brew")
	if err != nil && runtime.GOOS != "darwin" {
		return Status{Name: "Brew", State: StateHidden}
	}

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

	var flakeTarget string
	if runtime.GOOS == "darwin" {
		flakeTarget = fmt.Sprintf(".#darwinConfigurations.%s.system", hostname)
	} else {
		flakeTarget = fmt.Sprintf(".#nixosConfigurations.%s.config.system.build.toplevel", hostname)
	}

	currentSystemPath := "/run/current-system"

	// Build against the newest nixpkgs/unstable/home-manager without touching
	// the checkout's flake.lock: write the updated lock to a private temp dir
	// and build with it as the reference lock. (Replaces the deprecated
	// `nix build --update-input`.)
	lockDir, err := os.MkdirTemp("", "syncmon-flake-")
	if err != nil {
		return Status{Name: "Nix", State: StateError, Details: "Temp dir failed"}
	}
	defer os.RemoveAll(lockDir)
	lockFile := filepath.Join(lockDir, "flake.lock")

	var buildOut bytes.Buffer
	var buildErr bytes.Buffer

	updateCmd := exec.Command("nix", "flake", "update",
		"nixpkgs", "unstable-nixpkgs", "home-manager",
		"--flake", ".",
		"--output-lock-file", lockFile,
	)
	updateCmd.Dir = flakeDir
	updateCmd.Stderr = &buildErr
	err = updateCmd.Run()

	if err == nil {
		buildCmd := exec.Command("nix", "build", flakeTarget,
			"--reference-lock-file", lockFile,
			"--no-write-lock-file",
			"--no-link",
			"--print-out-paths",
		)
		buildCmd.Dir = flakeDir
		buildCmd.Stdout = &buildOut
		buildCmd.Stderr = &buildErr
		err = buildCmd.Run()
	}
	if err != nil {
		errMsg := "Build failed"
		errStr := buildErr.String()
		if strings.Contains(errStr, "error:") {
			lines := strings.Split(errStr, "\n")
			for _, line := range lines {
				if strings.Contains(line, "error:") {
					extracted := strings.TrimSpace(strings.Replace(line, "error:", "", 1))
					if extracted != "" {
						errMsg = Truncate(extracted, 40, "...")
						break
					}
				}
			}
		} else if errStr != "" {
			// If no "error:" but we have output, show first line
			errMsg = Truncate(strings.TrimSpace(strings.Split(errStr, "\n")[0]), 40, "...")
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
	processes := []string{"Nextcloud", "nextcloud"}
	for _, p := range processes {
		if err := exec.Command("pgrep", p).Run(); err == nil {
			return Status{Name: "Nextcloud", State: StateActive, Details: "Active"}
		}
	}
	return Status{Name: "Nextcloud", State: StateInactive, Details: "Stopped"}
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

	// Query a private copy (the client keeps its DB open). os.CreateTemp
	// makes a 0600 file with a random name in $TMPDIR, so no other local
	// user can pre-create or read it, unlike a fixed /tmp path.
	tmpDB, err := copyToTemp(syncDB, "syncmon_nc-*.db")
	if err != nil {
		return Status{Name: name, State: StateError, Details: "DB locked"}
	}
	defer os.Remove(tmpDB)

	query := fmt.Sprintf("SELECT modtime FROM metadata WHERE path='%s';",
		strings.ReplaceAll(relPath, "'", "''"))
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

// copyToTemp copies src into a new private temp file (pattern as for
// os.CreateTemp) and returns its path. The caller removes it.
func copyToTemp(src, pattern string) (string, error) {
	in, err := os.Open(src)
	if err != nil {
		return "", err
	}
	defer in.Close()

	out, err := os.CreateTemp("", pattern)
	if err != nil {
		return "", err
	}
	if _, err := io.Copy(out, in); err != nil {
		out.Close()
		os.Remove(out.Name())
		return "", err
	}
	if err := out.Close(); err != nil {
		os.Remove(out.Name())
		return "", err
	}
	return out.Name(), nil
}
