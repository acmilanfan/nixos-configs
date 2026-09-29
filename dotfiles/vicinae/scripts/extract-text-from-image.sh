#!/bin/bash

# @vicinae.schemaVersion 1
# @vicinae.title Extract Text from Image
# @vicinae.mode compact
# @vicinae.packageName OCR
# @vicinae.icon 📝
# @vicinae.description Copy text from an image file path, or the image currently in your clipboard, using the macOS Vision framework. No Shortcut required. The extracted text is copied to the clipboard.
# @vicinae.argument1 { "type": "text", "placeholder": "image path (optional — defaults to clipboard image)", "optional": true }

set -euo pipefail

tmp=""
cleanup() {
  if [ -n "$tmp" ]; then rm -f "$tmp"; fi
  return 0
}
trap cleanup EXIT

if [ $# -ge 1 ] && [ -n "$1" ]; then
  img="$1"
else
  # No argument: prefer an image file referenced by the clipboard (Vicinae's
  # file search "Copy path" puts file:///… there), otherwise treat the
  # clipboard as an image. Screenshots land on the clipboard as TIFF
  # (Cmd+Ctrl+Shift+4) while images copied from apps usually are PNG.
  img="$(pbpaste 2>/dev/null || true)"
  img="$(printf '%s' "$img" | tr -d '\n')"
  case "$img" in
    file://* | /*) : ;; # file reference from Vicinae's "Copy path"
    *) img="" ;;
  esac
fi

# Accept file:// URLs (arguments or clipboard text), convert to a plain path.
case "$img" in
  file://*)
    img="$(python3 -c 'import sys, urllib.parse; print(urllib.parse.unquote(urllib.parse.urlparse(sys.argv[1]).path))' "$img")"
    ;;
esac

if [ -n "$img" ] && [ -f "$img" ]; then
  : # use the referenced file
else
  tmp="$(mktemp /tmp/vicinae-ocr-XXXXXX)"
  osascript - "$tmp" <<'AS'
on run argv
  set outPath to POSIX file (item 1 of argv)
  try
    set imgData to (the clipboard as «class PNGf»)
  on error
    set imgData to (the clipboard as «class TIFF»)
  end try
  set fh to open for access outPath with write permission
  set eof fh to 0
  write imgData to fh
  close access fh
end run
AS
  img="$tmp"
fi

export OCR_INPUT="$img"
# osascript prints JXA console.log output to stderr, hence 2>&1.
text="$(/usr/bin/osascript -l JavaScript - 2>&1 <<'JXA'
ObjC.import('Vision');

function ocr(path) {
  const url = $.NSURL.fileURLWithPath(path);
  const request = $.VNRecognizeTextRequest.alloc.init;
  request.recognitionLevel = 0; // accurate
  const handler = $.VNImageRequestHandler.alloc.initWithURLOptions(url, $());
  handler.performRequestsError($.NSArray.arrayWithObject(request), $());
  const results = request.results;
  const out = [];
  for (let i = 0; i < results.count; i++) {
    const cands = results.objectAtIndex(i).topCandidates(1);
    if (cands.count > 0) out.push(ObjC.unwrap(cands.objectAtIndex(0).string));
  }
  return out.join("\n");
}

console.log(ocr($.NSProcessInfo.processInfo.environment.objectForKey("OCR_INPUT").js));
JXA
)"

if [ -z "$text" ]; then
  echo "No text extracted from image"
  exit 1
fi

printf '%s' "$text" | pbcopy
echo "Copied ${#text} characters to clipboard"
