# YouTube capture (macOS)

Explicitly save videos from Newsboat or the focused Firefox window directly into
`~/org/consume/youtube/YYYY-MM.org`. No Firefox extension, permanent server,
clipboard copying, or stash/queue is used. Linux configuration is unchanged.

## Setup and activation

1. From `~/Projects/YouTubeToOrgJava`, run `sh scripts/install-local.sh` to build
   `~/.local/bin/youtube-org`. The installer refuses an existing executable;
   inspect it before choosing `--replace`. Reinstall after Go source changes.
2. Keep the existing private `client_secret.json` and `token.json` in that Go
   project. Do not copy them here. If authorization needs renewing, run
   `~/.local/bin/youtube-org auth` explicitly in a terminal. Save commands never
   open an interactive login. Existing token files must have mode `0600`.
3. Apply the normal macOS configuration (`sup` / the appropriate Darwin rebuild).
   This installs Newsboat configuration and Hammerspoon sources. The existing
   activation machinery reloads Hammerspoon when its Lua changes. Do not reload
   before the helper is installed.
4. Test with a disposable Firefox window and an **isolated output root first**.
   Do not use all of your real tabs as an installation test. A real capture writes
   to your collection; authorization/rebuild and GUI smoke tests are explicit
   rollout actions, not part of the automated fixture suite.

The Go project is currently not Git-managed. Its README describes the CLI and
tests. Both integrations use the absolute installed executable, not `go run`.

## Controls

| Location | Key | Action |
| --- | --- | --- |
| Firefox focused | Cmd+Alt+Y | Save the current YouTube video |
| Firefox focused | Cmd+Alt+Shift+Y | Save video tabs from this window |
| During Firefox tab collection | Esc | Cancel; no batch is submitted |
| Newsboat article list or article | s | Save the selected video |

Other Newsboat browser-opening keys remain unchanged. `s` replaces Newsboat's
default save-article action in those views. Only explicit saves happen; browsing
or opening a tab does not save it. Non-YouTube Newsboat bookmarks fail visibly.

## Firefox behavior and limits

The current-video action reads macOS accessibility information without touching
the clipboard. With multiple tabs, it briefly visits one other tab and returns
to establish the original tab's page identity; **only the original video is
saved**. This extra check avoids saving a stale URL during a tab transition and
may load that other tab if suspended. If the check cannot complete, nothing is
saved. The window action snapshots browser-tab controls in the focused
window, briefly selects each, collects video URLs, then restores the starting tab
**before** metadata fetching starts. It does not visit another Firefox window,
close/reorder tabs, navigate pages, or intentionally change playback/muting.
Selecting suspended tabs may load them or trigger page behavior.

Grouped/hidden tabs are conservatively rejected when complete enumeration cannot
be established. Expand/ungroup them first; there is no silent "all saved" on a
partial collection. Firefox UI changes can require adapter updates. A URL must
belong to the selected page and agree with the address display; an edited address
bar, inaccessible/special page, or readiness timeout aborts safely. Per-tab waits
are bounded to five seconds and collection to two minutes.

Typing, clicking, closing a tab/window, or switching away interrupts traversal.
Middle-button clicks and scrolling interrupt it too.
The original tab is restored only if its window is still focused and the tab
survives; the tool never steals focus back. Repeated capture/save requests are
rejected while one is active. Ordinary Escape is not captured outside traversal.

## Storage, failures, and retry

New entries retain the existing depth-two TODO format and integer Duration used
by the Neovim random/duration picker. The local save month controls the filename,
not the video's publication month. Existing numbered files/archives are not
renamed, retagged, or rewritten. New entries do not fabricate Importance or Focus.

The Go helper deduplicates video IDs across both active `.org` and `.org_archive`
files, including URL variations. It fetches new metadata in batches, serializes
cooperating commits with an advisory lock, preserves existing file content/modes,
and atomically replaces the monthly file. Symlink destinations are refused.
These measures do not protect unsaved editor buffers or coordinate sync clients
on another machine. Save/reload any already-open monthly Org buffer around
external captures; use `:OrgYoutubeReload` for immediate picker visibility (the
existing cache otherwise expires after five minutes).

Feedback distinguishes saved, already present, non-video tabs skipped, and
failed/unavailable videos. "Saved" means the file write completed. Bulk metadata
fetches can partially succeed; a traversal failure/cancellation submits nothing.
There is **no durable retry queue**: keep failed videos open and retry the shortcut.
Earlier successes are skipped. Closing unsaved failed tabs loses those pending
URLs. If the helper reports uncertainty after a filesystem error, inspect/retry;
deduplication prevents duplicating already-durable entries.

Newsboat's bookmark API treats nonempty stdout as an error, regardless of exit
status. Its adapter therefore keeps successful stdout empty, displays failures in
Newsboat, and sends saved/existing counts as a macOS notification. Notification
delivery depends on macOS notification settings; a suppressed notification does
not turn a successful save into an error.

## Manual commands, old stash, and isolated smoke tests

```sh
~/.local/bin/youtube-org save --dry-run 'https://youtu.be/VIDEO_ID'
~/.local/bin/youtube-org import-stash --dry-run ~/org/consume/video_stash
```

Replace `VIDEO_ID` with a real 11-character video ID. Preview may fetch metadata
and refresh an existing token, but never writes collection files. Remove
`--dry-run` only when you explicitly want to save. The old stash accepts URL-only
and legacy CSV rows and is **never modified or cleared**. New captures do not use
it. No-argument `go run youtube_extractor.go` now shows help instead of silently
importing the stash or generating an output file for copy/paste.

`YOUTUBE_ORG_ROOT` (default `~/org`) and `YOUTUBE_ORG_CREDENTIALS_DIR` (default the
Go project) accept absolute paths. GUI processes do not inherit temporary terminal
environment overrides. For an agreed isolated Firefox smoke test, explicitly
configure the Hammerspoon module with an absolute fixture `orgRoot` option:

```lua
require("youtube-capture").setup({orgRoot = "/absolute/path/to/isolated-org-root"})
```

This replaces only the capture module's bindings, not the whole Hammerspoon
configuration. Wait for any in-flight save to finish before replacing setup;
replacement during saving can otherwise overlap helper invocations/notifications
(the Go writer lock still deduplicates). Call `.setup()` again without overrides after the isolated test to
restore normal capture paths. Do not invoke bulk capture on a work window during
testing. Verify the starting tab and clipboard remain as expected.

Automated checks: Go `go test -race ./...` / `go vet ./...`, the Hammerspoon fixture
runner under `dotfiles/hammerspoon/tests/`, and
`python3 nixos/home-manager/common/tests/youtube-capture-config-test.py`. Fixtures
do not authorize an account, touch live tabs, or write to the real collection.
