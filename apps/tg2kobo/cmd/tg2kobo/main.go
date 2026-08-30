package main

import (
	"context"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"strconv"

	"github.com/gotd/td/tg"

	"tg2kobo/internal/book"
	"tg2kobo/internal/epub"
	"tg2kobo/internal/mount"
	"tg2kobo/internal/render"
	"tg2kobo/internal/state"
	"tg2kobo/internal/telegram"
)

func defaultOut() string {
	home, err := os.UserHomeDir()
	if err != nil {
		return "tg2kobo-books"
	}
	return filepath.Join(home, "Documents", "tg2kobo")
}

func defaultSession() string {
	home, err := os.UserHomeDir()
	if err != nil {
		return "tg2kobo-session.json"
	}
	return filepath.Join(home, ".local", "share", "tg2kobo", "session.json")
}

func fatal(err error) {
	fmt.Fprintln(os.Stderr, "tg2kobo:", err)
	os.Exit(1)
}

func envOr(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

func credentials() (int, string, error) {
	idStr := os.Getenv("TG_API_ID")
	hash := os.Getenv("TG_API_HASH")
	if idStr == "" || hash == "" {
		return 0, "", fmt.Errorf("set TG_API_ID and TG_API_HASH (get them at https://my.telegram.org/apps)")
	}
	id, err := strconv.Atoi(idStr)
	if err != nil {
		return 0, "", fmt.Errorf("TG_API_ID must be numeric: %w", err)
	}
	return id, hash, nil
}

// flushPending tries to copy every queued EPUB to the Kobo; returns the
// list of paths that are still pending.
func flushPending(pending []string) (remaining []string) {
	dir, ok := mount.Find(mount.DefaultCandidates())
	if !ok {
		return pending
	}
	for _, p := range pending {
		if _, err := os.Stat(p); err != nil {
			fmt.Printf("dropping missing queued book %s\n", p)
			continue
		}
		dst, err := mount.CopyTo(p, dir)
		if err != nil {
			fmt.Fprintf(os.Stderr, "copy %s failed: %v\n", p, err)
			remaining = append(remaining, p)
			continue
		}
		fmt.Printf("copied %s -> %s\n", filepath.Base(p), dst)
	}
	return remaining
}

func main() {
	var (
		inbox   = flag.String("inbox", envOr("TG2KOBO_INBOX", "Kobo Inbox"), "title of the Telegram chat/channel used as inbox")
		out     = flag.String("out", defaultOut(), "directory for generated EPUBs and state file")
		session = flag.String("session", defaultSession(), "path of the Telegram session file")
		login   = flag.Bool("login", false, "perform interactive login and exit")
		noCopy  = flag.Bool("no-copy", false, "build the EPUB but do not copy to a mounted Kobo")
	)
	flag.Parse()

	appID, appHash, err := credentials()
	if err != nil {
		fatal(err)
	}

	st, err := state.Load(filepath.Join(*out, ".state.json"))
	if err != nil {
		fatal(err)
	}

	ctx := context.Background()
	client := telegram.NewClient(appID, appHash, *session)

	if *login {
		err = client.Run(ctx, true, func(api *tg.Client) error { return nil })
		if err != nil {
			fatal(err)
		}
		return
	}

	var msgs []render.Message
	err = client.Run(ctx, false, func(api *tg.Client) error {
		msgs, err = telegram.FetchInbox(ctx, api, *inbox, st.LastMessageID)
		return err
	})
	if err != nil {
		fatal(err)
	}

	if len(msgs) == 0 && len(st.Pending) == 0 {
		fmt.Println("nothing new in the inbox; nothing pending for the Kobo")
		return
	}

	if err := os.MkdirAll(*out, 0o755); err != nil {
		fatal(err)
	}

	if len(msgs) > 0 {
		for _, m := range msgs {
			path := filepath.Join(*out, book.FilenameFor(m))
			b := epub.Book{
				Title:    book.TitleFor(m),
				Author:   "tg2kobo",
				Chapters: []epub.Chapter{book.ChapterFor(m)},
			}
			f, err := os.Create(path)
			if err != nil {
				fatal(err)
			}
			if err := epub.Write(f, b); err != nil {
				f.Close()
				fatal(err)
			}
			if err := f.Close(); err != nil {
				fatal(err)
			}
			fmt.Printf("built %s\n", path)
			st.Pending = append(st.Pending, path)

			if m.ID > st.LastMessageID {
				st.LastMessageID = m.ID
			}
		}
		fmt.Printf("%d new message(s) exported\n", len(msgs))
	}

	if *noCopy {
		st.Pending = []string{}
	} else {
		st.Pending = flushPending(st.Pending)
	}

	if err := st.Save(filepath.Join(*out, ".state.json")); err != nil {
		fatal(err)
	}

	switch {
	case *noCopy:
		fmt.Println("-no-copy set: EPUB left in output dir only")
	case len(st.Pending) > 0:
		fmt.Printf("%d book(s) still queued — plug in the Kobo and re-run to copy\n", len(st.Pending))
	}
}
