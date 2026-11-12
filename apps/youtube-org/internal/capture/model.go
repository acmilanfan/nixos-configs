package capture

import (
	"context"
	"time"
)

type VideoRef struct{ ID, URL string }
type Video struct {
	VideoRef
	Title, Channel string
	Duration       int64
	Published      time.Time
}
type ItemResult struct {
	ID      string `json:"id,omitempty"`
	URL     string `json:"url"`
	Status  string `json:"status"`
	Message string `json:"message,omitempty"`
}
type Result struct {
	Saved    int          `json:"saved"`
	Existing int          `json:"existing"`
	Failed   int          `json:"failed"`
	Items    []ItemResult `json:"items"`
	Path     string       `json:"path,omitempty"`
	DryRun   bool         `json:"dry_run"`
	Error    string       `json:"error,omitempty"`
}
type CommitResult struct {
	Path            string
	Saved, Existing []string
}
type Store struct{ Dir string }
type Fetcher interface {
	Fetch(context.Context, []string) (map[string]Video, map[string]error, error)
}
type Service struct {
	Store   *Store
	Fetcher Fetcher
	Now     func() time.Time
}
