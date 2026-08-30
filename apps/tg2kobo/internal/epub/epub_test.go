package epub

import (
	"archive/zip"
	"bytes"
	"encoding/xml"
	"strings"
	"testing"
)

func sampleBook() Book {
	return Book{
		Title:  "Telegram Inbox 2026-08-24",
		Author: "tg2kobo",
		Chapters: []Chapter{
			{Title: "2026-08-24", Body: `<div class="msg"><p class="meta">2026-08-24 14:03 · Alice</p><div class="body">hello</div></div>`},
			{Title: "2026-08-25", Body: `<div class="msg"><p class="meta">2026-08-25 09:00 · Bob</p><div class="body">world &amp; more</div></div>`},
		},
	}
}

type zipEntry struct {
	Name   string
	Method uint16
	Data   string
}

type zipView struct {
	ordered []*zipEntry
	byName  map[string]*zipEntry
}

func writeBook(t *testing.T, b Book) []byte {
	t.Helper()
	var buf bytes.Buffer
	if err := Write(&buf, b); err != nil {
		t.Fatalf("Write() = %v", err)
	}
	return buf.Bytes()
}

func readZip(t *testing.T, data []byte) *zipView {
	t.Helper()
	zr, err := zip.NewReader(bytes.NewReader(data), int64(len(data)))
	if err != nil {
		t.Fatalf("open zip: %v", err)
	}
	v := &zipView{byName: map[string]*zipEntry{}}
	for _, f := range zr.File {
		rc, err := f.Open()
		if err != nil {
			t.Fatalf("open %s: %v", f.Name, err)
		}
		var buf bytes.Buffer
		if _, err := buf.ReadFrom(rc); err != nil {
			t.Fatalf("read %s: %v", f.Name, err)
		}
		rc.Close()
		e := &zipEntry{Name: f.Name, Method: f.Method, Data: buf.String()}
		v.ordered = append(v.ordered, e)
		v.byName[f.Name] = e
	}
	return v
}

func TestMimetypeIsFirstAndStored(t *testing.T) {
	v := readZip(t, writeBook(t, sampleBook()))
	first := v.ordered[0]
	if first.Name != "mimetype" {
		t.Fatalf("first entry = %q, want mimetype", first.Name)
	}
	if first.Method != 0 { // 0 == Store
		t.Fatalf("mimetype compression = %d, want Store(0)", first.Method)
	}
	if first.Data != "application/epub+zip" {
		t.Fatalf("mimetype content = %q", first.Data)
	}
}

func TestContainerPointsToOPF(t *testing.T) {
	v := readZip(t, writeBook(t, sampleBook()))
	e, ok := v.byName["META-INF/container.xml"]
	if !ok {
		t.Fatal("missing META-INF/container.xml")
	}
	if !strings.Contains(e.Data, "OEBPS/content.opf") {
		t.Fatalf("container.xml missing OPF reference:\n%s", e.Data)
	}
}

func TestOPFParsesAndListsChapters(t *testing.T) {
	v := readZip(t, writeBook(t, sampleBook()))
	e, ok := v.byName["OEBPS/content.opf"]
	if !ok {
		t.Fatal("missing content.opf")
	}
	var opf struct {
		Metadata struct {
			Title   string `xml:"title"`
			Creator string `xml:"creator"`
		} `xml:"metadata"`
		Manifest struct {
			Items []struct {
				Href string `xml:"href,attr"`
			} `xml:"item"`
		} `xml:"manifest"`
		Spine struct {
			ItemRefs []struct {
				IDRef string `xml:"idref,attr"`
			} `xml:"itemref"`
		} `xml:"spine"`
	}
	if err := xml.Unmarshal([]byte(e.Data), &opf); err != nil {
		t.Fatalf("opf does not parse: %v", err)
	}
	if opf.Metadata.Title != "Telegram Inbox 2026-08-24" {
		t.Fatalf("title = %q", opf.Metadata.Title)
	}
	if opf.Metadata.Creator != "tg2kobo" {
		t.Fatalf("creator = %q", opf.Metadata.Creator)
	}
	hrefs := map[string]bool{}
	for _, it := range opf.Manifest.Items {
		hrefs[it.Href] = true
	}
	for _, want := range []string{"chapter-01.xhtml", "chapter-02.xhtml", "nav.xhtml"} {
		if !hrefs[want] {
			t.Fatalf("manifest missing %q; have %v", want, hrefs)
		}
	}
	if len(opf.Spine.ItemRefs) != 2 {
		t.Fatalf("spine has %d itemrefs, want 2", len(opf.Spine.ItemRefs))
	}
}

func TestNavListsTitles(t *testing.T) {
	v := readZip(t, writeBook(t, sampleBook()))
	e, ok := v.byName["OEBPS/nav.xhtml"]
	if !ok {
		t.Fatal("missing nav.xhtml")
	}
	s := e.Data
	for _, want := range []string{"2026-08-24", "2026-08-25"} {
		if !strings.Contains(s, want) {
			t.Fatalf("nav missing %q:\n%s", want, s)
		}
	}
	if !strings.Contains(s, `xmlns="http://www.w3.org/1999/xhtml"`) {
		t.Fatal("nav.xhtml not XHTML namespace")
	}
}

func TestChapterContainsBodyFragment(t *testing.T) {
	v := readZip(t, writeBook(t, sampleBook()))
	e, ok := v.byName["OEBPS/chapter-02.xhtml"]
	if !ok {
		t.Fatal("missing chapter-02.xhtml")
	}
	s := e.Data
	if !strings.Contains(s, "world &amp; more") {
		t.Fatalf("chapter-02 missing body:\n%s", s)
	}
	if !strings.Contains(s, `<html xmlns="http://www.w3.org/1999/xhtml"`) {
		t.Fatal("chapter not XHTML")
	}
}

func TestDeterministicOutput(t *testing.T) {
	a := writeBook(t, sampleBook())
	b := writeBook(t, sampleBook())
	if !bytes.Equal(a, b) {
		t.Fatal("two writes of the same book differ byte-wise")
	}
}
