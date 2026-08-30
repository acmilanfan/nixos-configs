# tg2kobo

Forward selected Telegram messages to a private inbox chat, run one
command, and the new messages land on your Kobo as an EPUB.

## How it works

1. Create a private Telegram group or channel (e.g. **Kobo Inbox**) —
   this is your reading queue.
2. Forward any message you want to read into it.
3. Run `tg2kobo`. It pulls everything newer than the last export and
   builds one EPUB per message (titled from the message text; forwarded
   messages keep the ORIGINAL message's date and author). Each book is
   copied to a mounted Kobo. If the Kobo is not attached, the EPUBs are
   queued and copied automatically on the next successful run after
   you plug in.

## Setup (once)

```bash
# 1. API credentials: https://my.telegram.org/apps → API development tools
export TG_API_ID=12345
export TG_API_HASH=deadbeef...

# 2. Interactive login (phone + code, supports 2FA); session is saved:
tg2kobo -login
```

Credentials are only read from the environment; the session file
defaults to `~/.local/share/tg2kobo/session.json` — store both however
you like (`pass`, shell profile, direnv).

## Usage

```bash
tg2kobo                 # export + copy if Kobo mounted, else queue
tg2kobo -no-copy        # build EPUB into the out dir only
tg2kobo -inbox "My Q"   # different inbox title (default "Kobo Inbox", env TG2KOBO_INBOX)
tg2kobo -out ~/books    # custom output/state dir
```

Kobo mount detection scans `/Volumes/*` on macOS and
`/run/media/*` + `/media/*` on Linux for a directory containing
"kobo" (case-insensitive).

## Development

```bash
go test ./...   # unit tests for state, rendering, epub, mounts
nix build       # see nixos/common/pkgs/tg2kobo.nix (exposed via overlays as pkgs.tg2kobo)
```

Layout follows the repo convention: source in `apps/tg2kobo`,
packaging in `nixos/common/pkgs/`.
