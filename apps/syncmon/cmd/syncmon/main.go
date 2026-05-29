package main

import (
	"fmt"
	"os"
	"strings"
	"syncmon/internal/status"

	"github.com/charmbracelet/bubbles/spinner"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/spf13/viper"
)

type model struct {
	syncthing     status.Status
	nextcloud     status.Status
	newsboatCache status.Status
	orgGit        status.Status
	configGit     status.Status
	conflicts     status.Status
	containers    status.Status
	brew          status.Status
	nix           status.Status
	nixLoading    bool
	spinner       spinner.Model
	quitting      bool
	err           error
}

func initialModel() model {
	s := spinner.New()
	s.Spinner = spinner.Dot
	s.Style = lipgloss.NewStyle().Foreground(lipgloss.Color("205"))

	return model{
		syncthing:     status.Status{Name: "Syncthing", State: status.StateUnknown},
		nextcloud:     status.Status{Name: "Nextcloud", State: status.StateUnknown},
		newsboatCache: status.Status{Name: "Newsboat", State: status.StateUnknown},
		orgGit:        status.Status{Name: "Org Repo", State: status.StateUnknown},
		configGit:     status.Status{Name: "Configs", State: status.StateUnknown},
		conflicts:     status.Status{Name: "Conflicts", State: status.StateUnknown},
		containers:    status.Status{Name: "Containers", State: status.StateUnknown},
		brew:          status.Status{Name: "Brew", State: status.StateUnknown},
		nix:           status.Status{Name: "Nix", State: status.StateUnknown, Details: "Ready"},
		spinner:       s,
	}
}

func (m model) Init() tea.Cmd {
	return tea.Batch(
		m.spinner.Tick,
		refreshCmd(),
	)
}

func (m model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.KeyMsg:
		switch msg.String() {
		case "q", "ctrl+c":
			m.quitting = true
			return m, tea.Quit
		case "r":
			return m, refreshCmd()
		case "u":
			m.nixLoading = true
			return m, nixCmd()
		}

	case status.StatusMsg:
		switch msg.Service {
		case "syncthing":
			m.syncthing = msg.Status
		case "nextcloud":
			m.nextcloud = msg.Status
		case "newsboatCache":
			m.newsboatCache = msg.Status
		case "orgGit":
			m.orgGit = msg.Status
		case "configGit":
			m.configGit = msg.Status
		case "conflicts":
			m.conflicts = msg.Status
		case "containers":
			m.containers = msg.Status
		case "brew":
			m.brew = msg.Status
		case "nix":
			m.nix = msg.Status
			m.nixLoading = false
		}

	case spinner.TickMsg:
		var cmd tea.Cmd
		m.spinner, cmd = m.spinner.Update(msg)
		return m, cmd
	}

	return m, nil
}

func refreshCmd() tea.Cmd {
	return tea.Batch(
		func() tea.Msg {
			client := &status.SyncthingClient{
				URL:    viper.GetString("syncthing.url"),
				APIKey: viper.GetString("syncthing.apikey"),
			}
			st, _ := client.GetStatus()
			return status.StatusMsg{Service: "syncthing", Status: st}
		},
		func() tea.Msg {
			return status.StatusMsg{Service: "nextcloud", Status: status.CheckNextcloud()}
		},
		func() tea.Msg {
			// Check newsboat cache in Nextcloud
			ncPath := viper.GetString("paths.nextcloud")
			if ncPath == "" {
				ncPath = "~/Nextcloud"
			}
			ncRoot := status.ExpandPath(ncPath)
			relPath := "newsboat/cache.db"
			return status.StatusMsg{Service: "newsboatCache", Status: status.CheckNextcloudFile(ncRoot, relPath)}
		},
		func() tea.Msg {
			path := viper.GetString("paths.org")
			if path == "" {
				return status.StatusMsg{Service: "orgGit", Status: status.Status{Name: "Org Repo", State: status.StateUnknown, Details: "No path"}}
			}
			return status.StatusMsg{Service: "orgGit", Status: status.CheckGitStatus(status.ExpandPath(path), "Org Repo")}
		},
		func() tea.Msg {
			path := viper.GetString("paths.configs")
			if path == "" {
				return status.StatusMsg{Service: "configGit", Status: status.Status{Name: "Configs", State: status.StateUnknown, Details: "No path"}}
			}
			return status.StatusMsg{Service: "configGit", Status: status.CheckGitStatus(status.ExpandPath(path), "Configs")}
		},
		func() tea.Msg {
			path := viper.GetString("paths.org")
			if path == "" {
				return status.StatusMsg{Service: "conflicts", Status: status.Status{Name: "Conflicts", State: status.StateUnknown, Details: "No path"}}
			}
			return status.StatusMsg{Service: "conflicts", Status: status.CheckConflicts(status.ExpandPath(path))}
		},
		func() tea.Msg {
			return status.StatusMsg{Service: "containers", Status: status.CheckContainerEngine()}
		},
		func() tea.Msg {
			return status.StatusMsg{Service: "brew", Status: status.CheckBrew()}
		},
	)
}

func nixCmd() tea.Cmd {
	return func() tea.Msg {
		path := viper.GetString("paths.configs")
		if path == "" {
			return status.StatusMsg{Service: "nix", Status: status.Status{Name: "Nix", State: status.StateError, Details: "No path"}}
		}
		return status.StatusMsg{Service: "nix", Status: status.CheckNix(status.ExpandPath(path))}
	}
}


func (m model) View() string {
	if m.quitting {
		return "Bye!\n"
	}

	header := lipgloss.NewStyle().
		Bold(true).
		Foreground(lipgloss.Color("5")).
		Padding(1, 2).
		Render("SYNCMON [Sync Dashboard]")

	// Columns
	syncCol := m.renderPanel("SYNC STATUS", []status.Status{
		m.syncthing, m.nextcloud, m.newsboatCache, m.orgGit, m.configGit, m.conflicts,
	})

	sysCol := m.renderPanel("SYSTEM", []status.Status{
		m.containers, m.brew, m.nix,
	})

	body := lipgloss.JoinHorizontal(lipgloss.Top, syncCol, sysCol)

	footer := lipgloss.NewStyle().
		Foreground(lipgloss.Color("241")).
		Padding(1, 2).
		Render("[r] Refresh  [u] Nix Update  [q] Quit")

	return fmt.Sprintf("\n%s\n\n%s\n\n%s\n", header, body, footer)
}

func (m model) renderPanel(title string, items []status.Status) string {
	titleStyle := lipgloss.NewStyle().
		Bold(true).
		Underline(true).
		MarginBottom(1).
		PaddingLeft(2).
		Render(title)

	var lines []string
	for _, item := range items {
		if item.State == status.StateHidden {
			continue
		}
		lines = append(lines, m.renderStatusLine(item, 0))
		for _, device := range item.Devices {
			lines = append(lines, m.renderStatusLine(device, 1))
		}
	}

	return lipgloss.NewStyle().
		Width(40).
		Padding(0, 2).
		Render(titleStyle + "\n" + lipgloss.JoinVertical(lipgloss.Left, lines...))
}

func (m model) renderStatusLine(item status.Status, indent int) string {
	stateColor := "2" // green
	if item.State == status.StateError || item.State == status.StateInactive {
		stateColor = "1" // red
	} else if item.State == status.StateSyncing {
		stateColor = "3" // yellow
	}

	stateStyle := lipgloss.NewStyle().Foreground(lipgloss.Color(stateColor))

	val := item.Details
	if item.Name == "Nix" && m.nixLoading {
		val = m.spinner.View() + " Checking..."
	}

	prefix := ""
	if indent > 0 {
		prefix = "  └ "
	} else {
		prefix = "  "
	}

	name := item.Name
	if indent > 0 {
		// Device names can be long, truncate if needed
		if len(name) > 12 {
			name = name[:10] + ".."
		}
	}

	return fmt.Sprintf("%s%-12s %s", prefix, name+":", stateStyle.Render("["+val+"]"))
}

func main() {
	viper.SetConfigName(".syncmon")
	viper.SetConfigType("yaml")

	if home, err := os.UserHomeDir(); err == nil {
		viper.AddConfigPath(home)
	}
	viper.AddConfigPath(".")
	viper.SetEnvPrefix("SYNCMON")
	viper.AutomaticEnv()

	// Handle nested keys like SYNCMON_SYNCTHING_APIKEY
	viper.SetEnvKeyReplacer(strings.NewReplacer(".", "_"))

	if err := viper.ReadInConfig(); err != nil {
		if _, ok := err.(viper.ConfigFileNotFoundError); !ok {
			fmt.Printf("Error reading config: %v\n", err)
			os.Exit(1)
		}
	}

	p := tea.NewProgram(initialModel())
	if _, err := p.Run(); err != nil {
		fmt.Printf("Alas, there's been an error: %v", err)
		os.Exit(1)
	}
}
