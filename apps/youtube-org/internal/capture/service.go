package capture

import (
	"context"
	"errors"
	"time"
)

var ErrUnavailable = errors.New("video unavailable (private, deleted, or not returned by YouTube)")

func (s *Service) Save(ctx context.Context, urls []string, dryRun bool) (Result, error) {
	ctx, cancel := context.WithTimeout(ctx, 120*time.Second)
	defer cancel()
	now := time.Now()
	if s.Now != nil {
		now = s.Now()
	}
	r := Result{Items: []ItemResult{}, DryRun: dryRun}
	fatal := func(err error) (Result, error) {
		r.Error = err.Error()
		for i := range r.Items {
			if r.Items[i].Status == "pending" {
				r.Items[i].Status = "failed"
				r.Items[i].Message = err.Error()
				r.Failed++
			}
		}
		return r, err
	}
	known, err := s.Store.ExistingIDs(ctx)
	if err != nil {
		return fatal(err)
	}
	seen := map[string]bool{}
	var ids []string
	for _, raw := range urls {
		ref, err := NormalizeURL(raw)
		if err != nil {
			r.Items = append(r.Items, ItemResult{URL: raw, Status: "invalid", Message: err.Error()})
			r.Failed++
			continue
		}
		if seen[ref.ID] {
			continue
		}
		seen[ref.ID] = true
		item := ItemResult{ID: ref.ID, URL: ref.URL, Status: "pending"}
		if known[ref.ID] {
			item.Status = "existing"
			r.Existing++
		} else {
			ids = append(ids, ref.ID)
		}
		r.Items = append(r.Items, item)
	}
	if len(ids) == 0 {
		return r, nil
	}
	if err := ctx.Err(); err != nil {
		return fatal(err)
	}
	if s.Fetcher == nil {
		return fatal(errors.New("metadata fetcher is not configured"))
	}
	metadata, failures, err := s.Fetcher.Fetch(ctx, ids)
	if err != nil {
		return fatal(err)
	}
	if err := ctx.Err(); err != nil {
		return fatal(err)
	}
	var videos []Video
	for i := range r.Items {
		item := &r.Items[i]
		if item.Status != "pending" {
			continue
		}
		failure := failures[item.ID]
		v, found := metadata[item.ID]
		if failure == nil && !found {
			failure = ErrUnavailable
		}
		if failure == nil {
			if v.ID != item.ID {
				failure = errors.New("metadata video identity mismatch")
			} else {
				_, failure = RenderEntry(v, now)
			}
		}
		if failure != nil {
			item.Status = "failed"
			if errors.Is(failure, ErrUnavailable) {
				item.Status = "unavailable"
			}
			item.Message = failure.Error()
			r.Failed++
			continue
		}
		videos = append(videos, v)
	}
	if len(videos) == 0 {
		return r, nil
	}
	commit, err := s.Store.Commit(ctx, now, videos, dryRun)
	if err != nil {
		return fatal(err)
	}
	r.Path = commit.Path
	saved := map[string]bool{}
	for _, id := range commit.Saved {
		saved[id] = true
	}
	for i := range r.Items {
		item := &r.Items[i]
		if item.Status != "pending" {
			continue
		}
		if saved[item.ID] {
			if dryRun {
				item.Status = "would_save"
			} else {
				item.Status = "saved"
				r.Saved++
			}
		} else {
			item.Status = "existing"
			r.Existing++
		}
	}
	return r, nil
}
