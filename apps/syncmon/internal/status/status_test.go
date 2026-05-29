package status

import (
	"os"
	"path/filepath"
	"testing"
)

func TestExpandPath(t *testing.T) {
	home, err := os.UserHomeDir()
	if err != nil {
		t.Skip("Skipping test: home directory not available")
	}

	tests := []struct {
		name     string
		path     string
		expected string
	}{
		{
			name:     "no tilde",
			path:     "/abs/path",
			expected: "/abs/path",
		},
		{
			name:     "with tilde",
			path:     "~/docs",
			expected: filepath.Join(home, "docs"),
		},
		{
			name:     "tilde only",
			path:     "~/",
			expected: home,
		},
		{
			name:     "no slash after tilde",
			path:     "~something",
			expected: "~something",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := ExpandPath(tt.path)
			if got != tt.expected {
				t.Errorf("ExpandPath(%q) = %q; want %q", tt.path, got, tt.expected)
			}
		})
	}
}
