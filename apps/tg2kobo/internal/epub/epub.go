package epub

import (
	"archive/zip"
	"crypto/sha256"
	"fmt"
	"html"
	"io"
	"strings"
	"time"
)

const fixedTime = 946684800 // 2000-01-01T00:00:00Z, keeps output byte-deterministic

type Chapter struct {
	Title string
	Body  string
}

type Book struct {
	Title    string
	Author   string
	Chapters []Chapter
}

func Write(w io.Writer, b Book) error {
	zw := zip.NewWriter(w)

	add := func(name, data string, store bool) error {
		method := zip.Deflate
		if store {
			method = zip.Store
		}
		h := &zip.FileHeader{
			Name:     name,
			Method:   method,
			Modified: time.Unix(fixedTime, 0).UTC(),
		}
		fw, err := zw.CreateHeader(h)
		if err != nil {
			return err
		}
		_, err = io.WriteString(fw, data)
		return err
	}

	if err := add("mimetype", "application/epub+zip", true); err != nil {
		return fmt.Errorf("mimetype: %w", err)
	}
	container := `<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>
`
	if err := add("META-INF/container.xml", container, false); err != nil {
		return fmt.Errorf("container.xml: %w", err)
	}

	id := bookID(b)
	opf := buildOPF(b, id)
	if err := add("OEBPS/content.opf", opf, false); err != nil {
		return fmt.Errorf("content.opf: %w", err)
	}
	nav := buildNav(b)
	if err := add("OEBPS/nav.xhtml", nav, false); err != nil {
		return fmt.Errorf("nav.xhtml: %w", err)
	}
	css := `body { font-family: serif; margin: 0.5em; line-height: 1.4; }
.msg { margin-bottom: 1.2em; }
p.meta { color: #666; font-size: 0.8em; font-style: italic; margin: 0 0 0.2em 0; }
.body p { margin: 0.3em 0; }
a { color: inherit; }
pre { white-space: pre-wrap; }
`
	if err := add("OEBPS/style.css", css, false); err != nil {
		return fmt.Errorf("style.css: %w", err)
	}

	for i, ch := range b.Chapters {
		x := chapterXHTML(ch)
		name := fmt.Sprintf("OEBPS/chapter-%02d.xhtml", i+1)
		if err := add(name, x, false); err != nil {
			return fmt.Errorf("%s: %w", name, err)
		}
	}

	return zw.Close()
}

func chapterXHTML(ch Chapter) string {
	return fmt.Sprintf(`<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml">
<head>
<title>%s</title>
<link rel="stylesheet" type="text/css" href="style.css"/>
</head>
<body>
%s
</body>
</html>
`, html.EscapeString(ch.Title), ch.Body)
}

func buildNav(b Book) string {
	var s strings.Builder
	s.WriteString(`<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
<head><title>Contents</title></head>
<body>
<nav epub:type="toc"><ol>
`)
	for i, ch := range b.Chapters {
		fmt.Fprintf(&s, "<li><a href=\"chapter-%02d.xhtml\">%s</a></li>\n", i+1, html.EscapeString(ch.Title))
	}
	s.WriteString("</ol></nav>\n</body>\n</html>\n")
	return s.String()
}

func buildOPF(b Book, id string) string {
	var manifest, spine strings.Builder
	for i := range b.Chapters {
		fmt.Fprintf(&manifest, "    <item id=\"ch%02d\" href=\"chapter-%02d.xhtml\" media-type=\"application/xhtml+xml\"/>\n", i+1, i+1)
		fmt.Fprintf(&spine, "    <itemref idref=\"ch%02d\"/>\n", i+1)
	}
	modified := time.Unix(fixedTime, 0).UTC().Format("2006-01-02T15:04:05Z")
	return fmt.Sprintf(`<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="bookid">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="bookid">%s</dc:identifier>
    <dc:title>%s</dc:title>
    <dc:creator>%s</dc:creator>
    <dc:language>und</dc:language>
    <meta property="dcterms:modified">%s</meta>
  </metadata>
  <manifest>
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
    <item id="css" href="style.css" media-type="text/css"/>
%s  </manifest>
  <spine>
%s  </spine>
</package>
`, id, html.EscapeString(b.Title), html.EscapeString(b.Author), modified, manifest.String(), spine.String())
}

// bookID derives a stable UUID-shaped identifier from the book content.
func bookID(b Book) string {
	h := sha256.New()
	fmt.Fprintf(h, "%s|%s|%v", b.Title, b.Author, b.Chapters)
	sum := fmt.Sprintf("%x", h.Sum(nil))
	u := sum[:32]
	return fmt.Sprintf("urn:uuid:%s-%s-%s-%s-%s", u[:8], u[8:12], u[12:16], u[16:20], u[20:32])
}
