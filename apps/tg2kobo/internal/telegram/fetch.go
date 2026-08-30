package telegram

import (
	"bufio"
	"context"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"github.com/gotd/td/session"
	"github.com/gotd/td/telegram"
	"github.com/gotd/td/telegram/auth"
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

// EnsureParentDir creates the directory containing path, so that
// gotd's FileStorage (plain os.WriteFile) can actually persist the
// session file.
func EnsureParentDir(path string) error {
	return os.MkdirAll(filepath.Dir(path), 0o755)
}

// Run connects (and optionally performs first-time login), then calls fn.
func (c *Client) Run(ctx context.Context, doLogin bool, fn func(api *tg.Client) error) error {
	if err := EnsureParentDir(c.sessionPath); err != nil {
		return fmt.Errorf("prepare session dir: %w", err)
	}
	client := telegram.NewClient(c.appID, c.appHash, telegram.Options{
		SessionStorage: &session.FileStorage{Path: c.sessionPath},
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

// dialogsRequest builds the initial messages.getDialogs request. The
// offset fields must be explicitly zero-valued (InputPeerEmpty), not
// nil — Telegram cannot encode a nil union field.
func dialogsRequest(limit int) *tg.MessagesGetDialogsRequest {
	return &tg.MessagesGetDialogsRequest{
		Limit:      limit,
		OffsetPeer: &tg.InputPeerEmpty{},
	}
}

// FindInbox resolves a chat/channel by exact case-insensitive title.
func FindInbox(ctx context.Context, api *tg.Client, title string) (tg.InputPeerClass, error) {
	res, err := api.MessagesGetDialogs(ctx, dialogsRequest(200))
	if err != nil {
		return nil, fmt.Errorf("list dialogs: %w", err)
	}
	var dialogs *tg.MessagesDialogs
	switch v := res.(type) {
	case *tg.MessagesDialogs:
		dialogs = v
	case *tg.MessagesDialogsSlice:
		dialogs = &tg.MessagesDialogs{Chats: v.Chats, Users: v.Users}
	default:
		return nil, errors.New("unexpected dialogs response")
	}

	want := strings.ToLower(title)
	var seen []string
	for _, ch := range dialogs.Chats {
		switch c := ch.(type) {
		case *tg.Chat:
			seen = append(seen, c.Title)
			if strings.EqualFold(strings.ToLower(c.Title), want) {
				return &tg.InputPeerChat{ChatID: c.ID}, nil
			}
		case *tg.Channel:
			seen = append(seen, c.Title)
			if strings.EqualFold(strings.ToLower(c.Title), want) {
				if c.Min {
					continue // no usable access hash; skip
				}
				return &tg.InputPeerChannel{ChannelID: c.ID, AccessHash: c.AccessHash}, nil
			}
		}
	}
	return nil, fmt.Errorf("no dialog titled %q (have %v)", title, seen)
}

// FetchInbox downloads messages newer than afterID, oldest first.
func FetchInbox(ctx context.Context, api *tg.Client, inboxTitle string, afterID int) ([]render.Message, error) {
	peer, err := FindInbox(ctx, api, inboxTitle)
	if err != nil {
		return nil, err
	}
	hist, err := api.MessagesGetHistory(ctx, &tg.MessagesGetHistoryRequest{
		Peer:  peer,
		Limit: 1000,
		MinID: afterID,
	})
	if err != nil {
		return nil, fmt.Errorf("get history: %w", err)
	}

	var class []tg.MessageClass
	switch v := hist.(type) {
	case *tg.MessagesChannelMessages:
		class = v.Messages
	case *tg.MessagesMessages:
		class = v.Messages
	case *tg.MessagesMessagesSlice:
		class = v.Messages
	default:
		return nil, errors.New("unexpected history response")
	}

	msgs := make([]render.Message, 0, len(class))
	for _, mc := range class {
		m, ok := mc.(*tg.Message)
		if !ok {
			continue // service messages etc.
		}
		rm, err := convertMessage(m)
		if err != nil {
			return nil, fmt.Errorf("render message %d: %w", m.ID, err)
		}
		msgs = append(msgs, rm)
	}
	sort.SliceStable(msgs, func(i, j int) bool { return msgs[i].ID < msgs[j].ID })
	return msgs, nil
}

// convertMessage maps a gotd message onto the renderer model. For
// forwards, the date of the ORIGINAL message wins over the date it
// landed in the inbox channel.
func convertMessage(m *tg.Message) (render.Message, error) {
	body, err := render.ToHTML(m.Message, ConvertEntities(m.Entities))
	if err != nil {
		return render.Message{}, err
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
	}, nil
}
