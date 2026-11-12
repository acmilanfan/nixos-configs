package capture

import (
	"bytes"
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestCLIJSONPartialResult(t *testing.T) {
	s := serviceFixture(t)
	var out, stderr bytes.Buffer
	code := runCommand(context.Background(), []string{"save", "--json", "--stdin"}, strings.NewReader(testURL+"\nhttps://evil.org\n"), &out, &stderr, s, t.TempDir())
	var got Result
	if code != 1 || json.Unmarshal(out.Bytes(), &got) != nil || got.Saved != 1 || got.Failed != 1 {
		t.Fatalf("code=%d stdout=%q stderr=%q", code, out.String(), stderr.String())
	}
}

func TestCLIInputBounds(t *testing.T) {
	for _, args := range [][]string{{"save", "--unknown"}, {"save", "--unknown", "--json"}, {"save", "--json", "--stdin"}, {"save", "--json", "--stdin", "extra"}} {
		s := serviceFixture(t)
		var out, stderr bytes.Buffer
		input := strings.NewReader(strings.Repeat("x", 8193))
		code := runCommand(context.Background(), args, input, &out, &stderr, s, t.TempDir())
		if code != 2 {
			t.Fatalf("%v: %d %s", args, code, out.String())
		}
		if _, err := os.Stat(s.Store.Dir); !os.IsNotExist(err) {
			t.Fatal("invalid input wrote collection")
		}
		if strings.Contains(strings.Join(args, " "), "--json") {
			var result Result
			if json.Unmarshal(out.Bytes(), &result) != nil || result.Error == "" {
				t.Fatal("missing JSON error")
			}
		}
	}
	for _, input := range []string{strings.Repeat(testURL+"\n", 4097), strings.Repeat("x", (16<<20)+1)} {
		var out, stderr bytes.Buffer
		if code := runCommand(context.Background(), []string{"save", "--json", "--stdin"}, strings.NewReader(input), &out, &stderr, serviceFixture(t), t.TempDir()); code != 2 {
			t.Fatalf("unbounded input: %d", code)
		}
	}
}

func TestCLIJSONConfigurationFailure(t *testing.T) {
	t.Setenv("YOUTUBE_ORG_ROOT", "relative/path")
	var out, stderr bytes.Buffer
	code := Run(context.Background(), []string{"save", "--json", testURL}, strings.NewReader(""), &out, &stderr)
	var result Result
	if code != 2 || json.Unmarshal(out.Bytes(), &result) != nil || result.Error == "" {
		t.Fatalf("missing JSON configuration failure: code=%d out=%q stderr=%q", code, out.String(), stderr.String())
	}
}

func TestCLINoArgsDoesNotAuthorize(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	t.Setenv("YOUTUBE_ORG_ROOT", "")
	t.Setenv("YOUTUBE_ORG_CREDENTIALS_DIR", "")
	var out, stderr bytes.Buffer
	if code := Run(context.Background(), nil, strings.NewReader(""), &out, &stderr); code != 2 {
		t.Fatalf("code=%d", code)
	}
	if !strings.Contains(stderr.String(), "Usage:") {
		t.Fatal("missing help")
	}
	entries, _ := os.ReadDir(home)
	if len(entries) != 0 {
		t.Fatal("no-args invocation wrote data")
	}
}

func TestCLIPathsIndependentOfCWD(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	t.Setenv("YOUTUBE_ORG_ROOT", "")
	t.Setenv("YOUTUBE_ORG_CREDENTIALS_DIR", "")
	dir := filepath.Join(home, "org/consume/youtube")
	os.MkdirAll(dir, 0700)
	put(t, filepath.Join(dir, "youtube1.org"), "* Pool\n** TODO existing\n:PROPERTIES:\n:Link: [["+testURL+"]]\n:END:\n")
	var out, stderr bytes.Buffer
	if code := Run(context.Background(), []string{"save", "--json", testURL}, strings.NewReader(""), &out, &stderr); code != 0 {
		t.Fatalf("%d %s %s", code, out.String(), stderr.String())
	}
	var result Result
	json.Unmarshal(out.Bytes(), &result)
	if result.Existing != 1 {
		t.Fatal(result)
	}
	out.Reset()
	stderr.Reset()
	if code := Run(context.Background(), []string{"save", "--json", "https://youtu.be/abcdefghijk"}, strings.NewReader(""), &out, &stderr); code != 1 || !strings.Contains(out.String(), "youtube-org auth") {
		t.Fatalf("%d %s", code, out.String())
	}
}

func TestCLIImportPreservesStash(t *testing.T) {
	path := filepath.Join(t.TempDir(), "stash")
	original := "5,1," + testURL + "\n"
	put(t, path, original)
	var out, stderr bytes.Buffer
	if code := runCommand(context.Background(), []string{"import-stash", path}, strings.NewReader(""), &out, &stderr, serviceFixture(t), t.TempDir()); code != 0 || read(t, path) != original {
		t.Fatalf("%d %s %s", code, out.String(), stderr.String())
	}
}

func TestCLIBookmarkIgnoresTitleShellSyntax(t *testing.T) {
	s := serviceFixture(t)
	var out, stderr bytes.Buffer
	code := runCommand(context.Background(), []string{"bookmark", testURL, "$(touch should-not-exist)", "quote ' \"", "feed"}, strings.NewReader(""), &out, &stderr, s, t.TempDir())
	if code != 0 || !strings.Contains(out.String(), "Saved: 1") {
		t.Fatalf("%d %s %s", code, out.String(), stderr.String())
	}
}
