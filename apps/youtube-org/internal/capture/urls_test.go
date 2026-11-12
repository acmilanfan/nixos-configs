package capture

import (
	"strings"
	"testing"
	"time"
)

const testID = "3V_wgHB4eFw"
const testURL = "https://www.youtube.com/watch?v=3V_wgHB4eFw"

func fixtureVideo() Video {
	return Video{VideoRef: VideoRef{ID: testID, URL: testURL}, Title: "A video", Channel: "A channel", Duration: 599, Published: time.Date(2020, 1, 2, 3, 4, 5, 0, time.UTC)}
}

func TestNormalizeURL(t *testing.T) {
	for _, input := range []string{
		testURL, "https://youtu.be/3V_wgHB4eFw?t=30", "https://www.youtu.be/3V_wgHB4eFw",
		"http://youtube.com/watch?v=3V_wgHB4eFw&list=abc", "https://m.youtube.com/watch?v=3V_wgHB4eFw#fragment",
		"https://www.youtube.com/shorts/3V_wgHB4eFw?si=test", "https://youtube.com/live/3V_wgHB4eFw",
	} {
		t.Run(input, func(t *testing.T) {
			ref, err := NormalizeURL(input)
			if err != nil || ref.ID != testID || ref.URL != testURL {
				t.Fatalf("got %#v, %v", ref, err)
			}
		})
	}
	for _, input := range []string{
		"", "https://youtube.com/playlist?list=abc", "https://youtube.com/@channel", "https://youtube.com.evil.org/watch?v=" + testID,
		"https://youtube.com@evil.org/watch?v=" + testID, "https://evil@youtube.com/watch?v=" + testID,
		"https://youtube.com:8443/watch?v=" + testID, "file://youtube.com/watch?v=" + testID,
		"https://youtube.com/watch?v=" + testID + "&v=abcdefghijk", "https://youtu.be/short", "https://youtu.be/3V_wgHB4eFw/more",
		testURL + "\n" + testURL, "https://youtu.be/3V_wgHB4eF!", "https://youtube.com/watch?v=%ZZ",
	} {
		t.Run("reject:"+input, func(t *testing.T) {
			if _, err := NormalizeURL(input); err == nil {
				t.Fatalf("accepted %q", input)
			}
		})
	}
}

func TestReadLegacyStash(t *testing.T) {
	urls, err := ReadLegacyStash(strings.NewReader(testURL + "\n\n5,1,https://youtu.be/abcdefghijk\n"))
	if err != nil || len(urls) != 2 || urls[0] != testURL || urls[1] != "https://youtu.be/abcdefghijk" {
		t.Fatalf("%#v %v", urls, err)
	}
	if _, err := ReadLegacyStash(strings.NewReader("5,one\n")); err == nil {
		t.Fatal("accepted ambiguous legacy row")
	}
}

func TestRenderEntry(t *testing.T) {
	v := fixtureVideo()
	v.Title = "Title\n** TODO injected\r:PROPERTIES:\x00"
	v.Channel = "Channel\n:END:"
	entry, err := RenderEntry(v, time.Date(2026, 11, 11, 12, 0, 0, 0, time.UTC))
	if err != nil {
		t.Fatal(err)
	}
	if strings.Count(entry, "\n** ") != 0 || strings.Count(entry, "\n:PROPERTIES:\n") != 1 || strings.Count(entry, "\n:END:\n") != 1 {
		t.Fatalf("Org injection: %s", entry)
	}
	for _, want := range []string{"** TODO Title ", ":VIDEO_ID: 3V_wgHB4eFw", ":Duration: 599", ":Created: 2026-11-11T12:00:00Z", ":Published: 2020-01-02T03:04:05Z"} {
		if !strings.Contains(entry, want) {
			t.Fatalf("missing %q in %s", want, entry)
		}
	}
	for _, unwanted := range []string{":Importance:", ":Focus:", ":Rating:", ":Revisiting:"} {
		if strings.Contains(entry, unwanted) {
			t.Fatal(unwanted)
		}
	}
	v.Duration = 0
	if _, err := RenderEntry(v, time.Now()); err == nil {
		t.Fatal("accepted zero duration")
	}
	v = fixtureVideo()
	v.URL = "https://evil.org"
	if _, err := RenderEntry(v, time.Now()); err == nil {
		t.Fatal("accepted mismatched identity")
	}
}
