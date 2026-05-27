package status

import (
	"encoding/json"
	"fmt"
	"net/http"
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

func (c *SyncthingClient) GetStatus() (Status, error) {
	client := &http.Client{Timeout: 3 * time.Second}

	// 1. Get Config (folders and devices)
	reqConfig, _ := http.NewRequest("GET", c.URL+"/rest/system/config", nil)
	reqConfig.Header.Set("X-API-Key", c.APIKey)
	respConfig, err := client.Do(reqConfig)
	if err != nil {
		return Status{Name: "Syncthing", State: StateInactive}, nil
	}
	defer respConfig.Body.Close()

	var configData struct {
		Devices []DeviceConfig `json:"devices"`
		Folders []FolderConfig `json:"folders"`
	}
	json.NewDecoder(respConfig.Body).Decode(&configData)

	// 2. Get Connections
	reqConn, _ := http.NewRequest("GET", c.URL+"/rest/system/connections", nil)
	reqConn.Header.Set("X-API-Key", c.APIKey)
	respConn, err := client.Do(reqConn)
	if err != nil {
		return Status{Name: "Syncthing", State: StateInactive}, nil
	}
	defer respConn.Body.Close()

	var connData struct {
		Connections map[string]ConnectionInfo `json:"connections"`
	}
	json.NewDecoder(respConn.Body).Decode(&connData)

	// 3. Get System Status (for local ID)
	reqStatus, _ := http.NewRequest("GET", c.URL+"/rest/system/status", nil)
	reqStatus.Header.Set("X-API-Key", c.APIKey)
	respStatus, err := client.Do(reqStatus)
	if err != nil {
		return Status{Name: "Syncthing", State: StateInactive}, nil
	}
	defer respStatus.Body.Close()

	var systemData struct {
		MyID string `json:"myID"`
	}
	json.NewDecoder(respStatus.Body).Decode(&systemData)

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
				compURL := fmt.Sprintf("%s/rest/db/completion?folder=%s&device=%s", c.URL, folder.ID, dev.DeviceID)
				reqComp, _ := http.NewRequest("GET", compURL, nil)
				reqComp.Header.Set("X-API-Key", c.APIKey)
				respComp, err := client.Do(reqComp)
				if err == nil {
					var compData CompletionInfo
					json.NewDecoder(respComp.Body).Decode(&compData)
					totalCompletion += compData.Completion
					folderCount++
					respComp.Body.Close()
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
