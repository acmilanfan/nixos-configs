package telegram

import (
	"bufio"
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"github.com/gotd/td/telegram"
	"github.com/gotd/td/telegram/auth"
	"github.com/gotd/td/telegram/query/dialogs"
	"github.com/gotd/td/tg"
	"golang.org/x/term"

	"tg2kobo/internal/render"
)

// Client wraps a gotd Telegram client with file-backed sessions.
type Client struct {
	appID       int
	appHash     string
	sessionPath string
}

func NewClient(appID int, appHash, sessionPath string) *Client {
	return &Client{appID: appID, appHash: appHash, sessionPath: sessionPath}
}

// stdinAuth prompts interactively for phone, code, and optional 2FA password.
type stdinAuth struct{}

// One reader for all prompts: a fresh bufio.Reader per call would
// discard already-buffered input (e.g. pasted "phone\n code\n").
var stdin = bufio.NewReader(os.Stdin)

func readLine(prompt string) (string, error) {
	fmt.Print(prompt)
	line, err := stdin.ReadString('\n')
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(line), nil
}

func (stdinAuth) Phone(context.Context) (string, error) {
	return readLine("Phone number (international format, e.g. +491701234567): ")
}

func (stdinAuth) Code(_ context.Context, _ *tg.AuthSentCode) (string, error) {
	return readLine("Login code: ")
}

func (stdinAuth) Password(context.Context) (string, error) {
	if !term.IsTerminal(int(os.Stdin.Fd())) {
		return "", errors.New("2FA required but stdin is not a terminal")
	}
	fmt.Print("2FA password: ")
	pw, err := term.ReadPassword(int(os.Stdin.Fd()))
	fmt.Println()
	return string(pw), err
}

func (stdinAuth) AcceptTermsOfService(context.Context, tg.HelpTermsOfService) error {
	return nil
}

func (stdinAuth) SignUp(context.Context) (auth.UserInfo, error) {
	return auth.UserInfo{}, errors.New("sign-up is not supported; create the Telegram account elsewhere first")
}

var _ auth.UserAuthenticator = stdinAuth{}

// EnsureParentDir creates the directory containing path, so that the
// session file can actually be persisted. A newly created directory is
// private (0700): the session file is a full account login. Existing
// directories keep their permissions.
func EnsureParentDir(path string) error {
	return os.MkdirAll(filepath.Dir(path), 0o700)
}

// Run connects (and optionally performs first-time login), then calls fn.
func (c *Client) Run(ctx context.Context, doLogin bool, fn func(api *tg.Client) error) error {
	if err := EnsureParentDir(c.sessionPath); err != nil {
		return fmt.Errorf("prepare session dir: %w", err)
	}
	client := telegram.NewClient(c.appID, c.appHash, telegram.Options{
		SessionStorage: &atomicFileStorage{path: c.sessionPath},
	})
	return client.Run(ctx, func(ctx context.Context) error {
		if doLogin {
			flow := auth.NewFlow(stdinAuth{}, auth.SendCodeOptions{})
			if err := flow.Run(ctx, client.Auth()); err != nil {
				return fmt.Errorf("login: %w", err)
			}
			// Verify the session really hit the disk before claiming
			// success — gotd swallows storage errors into its Nop logger.
			if _, err := os.Stat(c.sessionPath); err != nil {
				return fmt.Errorf("session file was not written to %s: %w", c.sessionPath, err)
			}
			fmt.Println("Logged in; session saved to", c.sessionPath)
			return nil
		}
		status, err := client.Auth().Status(ctx)
		if err != nil {
			return err
		}
		if !status.Authorized {
			return errors.New("no saved session; run `tg2kobo -login` first")
		}
		return fn(client.API())
	})
}

// Telegram caps one messages.getDialogs / messages.getHistory page at
// 100 entries, however large the requested Limit.
const (
	dialogsBatch = 100
	historyBatch = 100
)

// maxSeenTitles bounds how many dialog titles a not-found error lists.
const maxSeenTitles = 10

// FindInbox resolves a chat/channel by exact case-insensitive title,
// paging through the whole dialog list rather than only the most
// recent page. (gotd's iterator starts from InputPeerEmpty: Telegram
// cannot encode a nil offset_peer.)
func FindInbox(ctx context.Context, api *tg.Client, title string) (tg.InputPeerClass, error) {
	return findInbox(ctx, dialogs.NewQueryBuilder(api).GetDialogs().BatchSize(dialogsBatch).Iter(), title)
}

func findInbox(ctx context.Context, it *dialogs.Iterator, title string) (tg.InputPeerClass, error) {
	var seen []string
	for it.Next(ctx) {
		el := it.Value()
		var name string
		switch p := el.Peer.(type) {
		case *tg.InputPeerChat:
			c, ok := el.Entities.Chat(p.ChatID)
			if !ok {
				continue
			}
			name = c.Title
		case *tg.InputPeerChannel:
			c, ok := el.Entities.Channel(p.ChannelID)
			if !ok || c.Min {
				continue // min channels carry no usable access hash
			}
			name = c.Title
		default:
			continue // users and bots are never the inbox
		}
		if strings.EqualFold(name, title) {
			return el.Peer, nil
		}
		seen = append(seen, name)
	}
	if err := it.Err(); err != nil {
		return nil, fmt.Errorf("list dialogs: %w", err)
	}
	sample := seen
	if len(sample) > maxSeenTitles {
		sample = sample[:maxSeenTitles]
	}
	return nil, fmt.Errorf("no dialog titled %q among %d chats/channels (first: %q)", title, len(seen), sample)
}

// historyGetter is the part of *tg.Client that fetchHistory needs.
type historyGetter interface {
	MessagesGetHistory(ctx context.Context, req *tg.MessagesGetHistoryRequest) (tg.MessagesMessagesClass, error)
}

// fetchHistory returns every message with ID > afterID, oldest first.
// Telegram answers newest-first with at most historyBatch messages per
// request, so this pages backwards (OffsetID = lowest ID seen so far)
// until a page brings nothing new or afterID is reached.
func fetchHistory(ctx context.Context, api historyGetter, peer tg.InputPeerClass, afterID int) ([]tg.MessageClass, error) {
	var all []tg.MessageClass
	offsetID := 0 // 0 = start from the newest message
	for {
		hist, err := api.MessagesGetHistory(ctx, &tg.MessagesGetHistoryRequest{
			Peer:     peer,
			OffsetID: offsetID,
			Limit:    historyBatch,
			MinID:    afterID,
		})
		if err != nil {
			return nil, fmt.Errorf("get history: %w", err)
		}
		var page []tg.MessageClass
		complete := false
		switch v := hist.(type) {
		case *tg.MessagesChannelMessages:
			page = v.Messages
		case *tg.MessagesMessagesSlice:
			page = v.Messages
		case *tg.MessagesMessages:
			page = v.Messages
			complete = true // not a slice: the server sent everything
		default:
			return nil, errors.New("unexpected history response")
		}
		lowest := offsetID
		for _, mc := range page {
			id := mc.GetID()
			if id <= afterID || (offsetID != 0 && id >= offsetID) {
				continue // outside the requested window (or a repeat)
			}
			all = append(all, mc)
			if lowest == 0 || id < lowest {
				lowest = id
			}
		}
		// Stop when done, when a page made no progress (never loop
		// forever on a misbehaving server), or when nothing older than
		// lowest can still be newer than afterID.
		if complete || lowest == offsetID || lowest <= afterID+1 {
			break
		}
		offsetID = lowest
	}
	sort.SliceStable(all, func(i, j int) bool { return all[i].GetID() < all[j].GetID() })
	return all, nil
}

// FetchInbox downloads all messages newer than afterID, oldest first.
// A message whose formatting cannot be rendered is exported as plain
// text (with a warning on stderr) instead of failing every future run.
func FetchInbox(ctx context.Context, api *tg.Client, inboxTitle string, afterID int) ([]render.Message, error) {
	peer, err := FindInbox(ctx, api, inboxTitle)
	if err != nil {
		return nil, err
	}
	class, err := fetchHistory(ctx, api, peer, afterID)
	if err != nil {
		return nil, err
	}
	return convertMessages(class, os.Stderr), nil
}

// convertMessages converts the regular messages in class (service
// messages etc. are skipped), reporting rendering problems to warn.
func convertMessages(class []tg.MessageClass, warn io.Writer) []render.Message {
	msgs := make([]render.Message, 0, len(class))
	for _, mc := range class {
		m, ok := mc.(*tg.Message)
		if !ok {
			continue // service messages etc.
		}
		rm, err := convertMessage(m)
		if err != nil {
			fmt.Fprintf(warn, "tg2kobo: message %d: %v; exporting it as plain text\n", m.ID, err)
		}
		msgs = append(msgs, rm)
	}
	return msgs
}

// convertMessage maps a gotd message onto the renderer model. For
// forwards, the date of the ORIGINAL message wins over the date it
// landed in the inbox channel.
//
// The returned message is always usable: if the entities cannot be
// rendered, the body falls back to escaped plain text and the error
// says why.
func convertMessage(m *tg.Message) (render.Message, error) {
	body, err := render.ToHTML(m.Message, ConvertEntities(m.Entities))
	if err != nil {
		body, _ = render.ToHTML(m.Message, nil) // no entities: cannot fail
	}
	date := time.Unix(int64(m.Date), 0).Local()
	from := m.PostAuthor
	if m.FwdFrom.FromName != "" {
		from = m.FwdFrom.FromName
		if m.FwdFrom.Date != 0 {
			date = time.Unix(int64(m.FwdFrom.Date), 0).Local()
		}
	}
	return render.Message{
		ID:       int(m.ID),
		Date:     date,
		FromName: from,
		Text:     m.Message,
		BodyHTML: body,
	}, err
}
