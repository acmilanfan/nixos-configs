package status

import (
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/url"
	"time"
)

type SyncthingClient struct {
	URL    string
	APIKey string
}

type DeviceConfig struct {
	DeviceID string `json:"deviceID"`
	Name     string `json:"name"`
}

type FolderConfig struct {
	ID      string         `json:"id"`
	Label   string         `json:"label"`
	Devices []FolderDevice `json:"devices"`
}

type FolderDevice struct {
	DeviceID string `json:"deviceID"`
}

type ConnectionInfo struct {
	Connected bool `json:"connected"`
}

type CompletionInfo struct {
	Completion float64 `json:"completion"`
}

// httpStatusError is a non-2xx answer from the Syncthing REST API (a wrong
// API key gives 403), as opposed to Syncthing not running at all.
type httpStatusError struct {
	Code int
}

func (e *httpStatusError) Error() string {
	return fmt.Sprintf("HTTP %d", e.Code)
}

// getJSON GETs a Syncthing REST path and decodes the JSON answer into out.
// Transport errors (Syncthing not running) are returned unchanged; a
// non-2xx status is an *httpStatusError.
func (c *SyncthingClient) getJSON(client *http.Client, path string, out any) error {
	req, err := http.NewRequest(http.MethodGet, c.URL+path, nil)
	if err != nil {
		return err
	}
	req.Header.Set("X-API-Key", c.APIKey)
	resp, err := client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode > 299 {
		return &httpStatusError{Code: resp.StatusCode}
	}
	return json.NewDecoder(resp.Body).Decode(out)
}

// apiErrorStatus maps a failed API call to the Syncthing row: not reachable
// is Inactive; an HTTP error or an unparseable answer is an Error, so a bad
// API key no longer shows as "Connected".
func apiErrorStatus(err error) Status {
	var se *httpStatusError
	switch {
	case errors.As(err, &se) && (se.Code == http.StatusUnauthorized || se.Code == http.StatusForbidden):
		return Status{Name: "Syncthing", State: StateError, Details: fmt.Sprintf("Auth failed (%d)", se.Code)}
	case errors.As(err, &se):
		return Status{Name: "Syncthing", State: StateError, Details: se.Error()}
	}
	var ue *url.Error
	if errors.As(err, &ue) {
		return Status{Name: "Syncthing", State: StateInactive}
	}
	return Status{Name: "Syncthing", State: StateError, Details: "Bad response"}
}

func (c *SyncthingClient) GetStatus() (Status, error) {
	client := &http.Client{Timeout: 3 * time.Second}

	// 1. Get Config (folders and devices)
	var configData struct {
		Devices []DeviceConfig `json:"devices"`
		Folders []FolderConfig `json:"folders"`
	}
	if err := c.getJSON(client, "/rest/system/config", &configData); err != nil {
		return apiErrorStatus(err), nil
	}

	// 2. Get Connections
	var connData struct {
		Connections map[string]ConnectionInfo `json:"connections"`
	}
	if err := c.getJSON(client, "/rest/system/connections", &connData); err != nil {
		return apiErrorStatus(err), nil
	}

	// 3. Get System Status (for local ID)
	var systemData struct {
		MyID string `json:"myID"`
	}
	if err := c.getJSON(client, "/rest/system/status", &systemData); err != nil {
		return apiErrorStatus(err), nil
	}

	// Build device statuses
	var devices []Status
	for _, dev := range configData.Devices {
		if dev.DeviceID == systemData.MyID {
			continue
		}

		conn, connected := connData.Connections[dev.DeviceID]
		if !connected || !conn.Connected {
			devices = append(devices, Status{
				Name:    dev.Name,
				State:   StateInactive,
				Details: "Disconnected",
			})
			continue
		}

		// If connected, check completion for all folders shared with this device
		totalCompletion := 0.0
		folderCount := 0
		for _, folder := range configData.Folders {
			shared := false
			for _, fd := range folder.Devices {
				if fd.DeviceID == dev.DeviceID {
					shared = true
					break
				}
			}

			if shared {
				q := url.Values{"folder": {folder.ID}, "device": {dev.DeviceID}}
				var compData CompletionInfo
				if err := c.getJSON(client, "/rest/db/completion?"+q.Encode(), &compData); err == nil {
					totalCompletion += compData.Completion
					folderCount++
				}
			}
		}

		state := StateActive
		details := "Connected"
		if folderCount > 0 {
			avg := totalCompletion / float64(folderCount)
			if avg >= 100 {
				details = "Synced"
			} else {
				state = StateSyncing
				details = fmt.Sprintf("%.0f%% Syncing", avg)
			}
		}

		devices = append(devices, Status{
			Name:    dev.Name,
			State:   state,
			Details: details,
		})
	}

	return Status{
		Name:    "Syncthing",
		State:   StateIdle,
		Details: "Connected",
		Devices: devices,
	}, nil
}
