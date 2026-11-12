package capture

import (
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
)

const usage = `Usage:
  youtube-org save [--json] [--dry-run] [--stdin] [--] URL...
  youtube-org bookmark URL TITLE DESCRIPTION FEED_TITLE
  youtube-org auth
  youtube-org import-stash [--dry-run] PATH

Saves directly into $YOUTUBE_ORG_ROOT/consume/youtube/YYYY-MM.org.
Defaults: YOUTUBE_ORG_ROOT=$HOME/org
          YOUTUBE_ORG_CREDENTIALS_DIR=$HOME/Projects/YouTubeToOrgJava
No queue: keep failed videos open and retry. import-stash preserves its input.
`

func Run(ctx context.Context, args []string, stdin io.Reader, stdout, stderr io.Writer) int {
	home, err := os.UserHomeDir()
	if err != nil {
		return cliError(stdout, stderr, jsonRequested(args), 2, errors.New("cannot determine HOME"))
	}
	root := os.Getenv("YOUTUBE_ORG_ROOT")
	if root == "" {
		root = filepath.Join(home, "org")
	}
	credentials := os.Getenv("YOUTUBE_ORG_CREDENTIALS_DIR")
	if credentials == "" {
		credentials = filepath.Join(home, "Projects/YouTubeToOrgJava")
	}
	if !filepath.IsAbs(root) || !filepath.IsAbs(credentials) {
		return cliError(stdout, stderr, jsonRequested(args), 2, errors.New("configured directories must be absolute"))
	}
	fetcher, _ := NewFetcher(ctx, credentials)
	return runCommand(ctx, args, stdin, stdout, stderr, &Service{Store: &Store{Dir: filepath.Join(root, "consume/youtube")}, Fetcher: fetcher}, credentials)
}

func jsonRequested(args []string) bool {
	if len(args) == 0 || args[0] != "save" {
		return false
	}
	for _, arg := range args[1:] {
		if arg == "--" {
			break
		}
		if arg == "--json" || arg == "--json=true" {
			return true
		}
	}
	return false
}

func cliError(stdout, stderr io.Writer, jsonOutput bool, code int, err error) int {
	if jsonOutput {
		if encodeErr := json.NewEncoder(stdout).Encode(Result{Items: []ItemResult{}, Error: err.Error()}); encodeErr != nil {
			fmt.Fprintln(stderr, "could not write result")
			return 1
		}
	} else {
		fmt.Fprintln(stderr, err)
	}
	return code
}

func runCommand(ctx context.Context, args []string, stdin io.Reader, stdout, stderr io.Writer, service *Service, credentials string) int {
	if len(args) == 0 {
		fmt.Fprint(stderr, usage)
		return 2
	}
	if args[0] == "--help" || args[0] == "help" || args[0] == "-h" {
		fmt.Fprint(stdout, usage)
		return 0
	}
	jsonOutput := jsonRequested(args)
	fail := func(code int, err error) int {
		return cliError(stdout, stderr, jsonOutput, code, err)
	}
	var urls []string
	dryRun := false
	switch args[0] {
	case "auth":
		if len(args) != 1 {
			return fail(2, errors.New("auth takes no arguments"))
		}
		if err := Authenticate(ctx, credentials); err != nil {
			return fail(1, err)
		}
		fmt.Fprintln(stdout, "Authorization saved.")
		return 0
	case "bookmark":
		if len(args) != 5 {
			return fail(2, errors.New("bookmark requires URL, title, description and feed title"))
		}
		jsonOutput = false
		urls = []string{args[1]}
	case "save", "import-stash":
		flags := flag.NewFlagSet(args[0], flag.ContinueOnError)
		flags.SetOutput(io.Discard)
		flags.BoolVar(&dryRun, "dry-run", false, "preview without writing")
		fromStdin := false
		if args[0] == "save" {
			flags.BoolVar(&jsonOutput, "json", jsonOutput, "JSON result")
			flags.BoolVar(&fromStdin, "stdin", false, "one URL per input line")
		}
		if err := flags.Parse(args[1:]); err != nil {
			return fail(2, err)
		}
		if args[0] == "import-stash" {
			if flags.NArg() != 1 {
				return fail(2, errors.New("import-stash requires one explicit input path"))
			}
			f, err := os.Open(flags.Arg(0))
			if err != nil {
				return fail(1, err)
			}
			defer f.Close()
			data, err := boundedInput(f)
			if err != nil {
				return fail(2, err)
			}
			urls, err = ReadLegacyStash(strings.NewReader(string(data)))
			if err != nil {
				return fail(2, err)
			}
		} else if fromStdin {
			if flags.NArg() != 0 {
				return fail(2, errors.New("do not combine --stdin and URL arguments"))
			}
			data, err := boundedInput(stdin)
			if err != nil {
				return fail(2, err)
			}
			for _, line := range strings.Split(string(data), "\n") {
				line = strings.TrimSuffix(line, "\r")
				if strings.TrimSpace(line) != "" {
					urls = append(urls, line)
				}
			}
		} else {
			urls = flags.Args()
		}
	default:
		return fail(2, errors.New("unknown command; use youtube-org --help"))
	}
	if len(urls) == 0 || len(urls) > 4096 {
		return fail(2, errors.New("provide between 1 and 4096 URLs"))
	}
	var size int
	for _, raw := range urls {
		size += len(raw) + 1
		if len(raw) > 8192 || size > 16<<20 {
			return fail(2, errors.New("URL/input size limit exceeded"))
		}
	}
	result, err := service.Save(ctx, urls, dryRun)
	if jsonOutput {
		if encodeErr := json.NewEncoder(stdout).Encode(result); encodeErr != nil {
			fmt.Fprintln(stderr, "could not write result")
			return 1
		}
	} else {
		if dryRun {
			count := 0
			for _, item := range result.Items {
				if item.Status == "would_save" {
					count++
				}
			}
			fmt.Fprintf(stdout, "Preview: %d would be saved; no files changed.\n", count)
		}
		fmt.Fprintf(stdout, "Saved: %d; already present: %d; failed: %d\n", result.Saved, result.Existing, result.Failed)
		for _, item := range result.Items {
			if item.Message != "" {
				fmt.Fprintf(stderr, "%s: %s\n", item.URL, item.Message)
			}
		}
		if result.Error != "" {
			fmt.Fprintln(stderr, result.Error)
		}
	}
	if err != nil || result.Failed > 0 {
		return 1
	}
	return 0
}

func boundedInput(r io.Reader) ([]byte, error) {
	data, err := io.ReadAll(io.LimitReader(r, (16<<20)+1))
	if err != nil {
		return nil, err
	}
	if len(data) > 16<<20 {
		return nil, errors.New("input exceeds 16 MiB")
	}
	return data, nil
}
