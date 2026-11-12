# youtube-org

Authoritative, Nix-packaged Go implementation of direct YouTube-to-Org capture.
It originated in the Go version of `~/Projects/YouTubeToOrgJava`; that original
project is preserved, but is no longer required as build source.

On macOS, the shared Home Manager configuration installs this package during
`sup`. Both Newsboat and generated Hammerspoon settings reference the same
absolute Nix-store executable. No manual installer, shell PATH, or local Go
installation is needed for normal use.

```sh
nix build .#youtube-org --no-link
nix run .#youtube-org -- --help
```

For development here: `go test -race ./...`, `go vet ./...`, and
`go run ./cmd/youtube-org --help`.

## Private runtime credentials

`client_secret.json` and `token.json` are never included in the package. Existing
credentials remain in `$HOME/Projects/YouTubeToOrgJava` by default, or an absolute
`YOUTUBE_ORG_CREDENTIALS_DIR`. Authorize explicitly with `youtube-org auth` if
needed; saves never start interactive login. Tokens stay private runtime files.

`YOUTUBE_ORG_ROOT` defaults to `$HOME/org`. Saves go to
`consume/youtube/YYYY-MM.org`; old numbered files and archives are deduplicated,
not migrated. Failed captures have no hidden queue: keep videos open and retry.

See [`../../docs/youtube-capture.md`](../../docs/youtube-capture.md) for shortcuts,
Newsboat behavior, preview/legacy-stash commands, editor safety and GUI testing.
