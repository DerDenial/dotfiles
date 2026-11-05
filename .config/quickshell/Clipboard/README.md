# Clipboard history backend

`store.py` uses Python's standard library and the installed `wl-copy` / `wl-paste`.
No package installation or clipboard service is required. The Quickshell state
object owns one foreground `python3 <installed-path>/store.py watch` process.

## API

- `list --query <search> --filter all|text|image|pinned`: UI JSON, including short
  previews; up to 150 entries, pinned first and then most recently copied.
- `status`: the same metadata without the `items` list.
- `copy <id>`: copies the original bytes and MIME to the clipboard; never pastes
  into another application. Explicit selection also works while recording is paused.
- `pin <id>`: toggles the pin.
- `delete <id>`: deletes that entry, including an explicitly selected pinned entry.
- `clear`: deletes unpinned entries and their image files, preserving pins.
- `pause [on|off|toggle]`: persists the recording state across restarts.
- `watch`: foreground supervisor with an exclusive lock, child restart backoff,
  parent-death cleanup, and content-free status JSON on stdout.
- `capture --mime <type>`: internal watcher callback. Bytes arrive solely on stdin.

All successful command responses contain `ok: true`; errors contain `ok: false`
and a static human-readable `error`. `list` also contains:

```json
{
  "items": [
    {
      "id": 1,
      "type": "text",
      "preview": "Short display excerpt",
      "title": "First line",
      "mime": "text/plain;charset=utf-8",
      "size": 23,
      "created": 1792320000000,
      "firstCreated": 1792320000000,
      "pinned": false,
      "imagePath": "",
      "imageUrl": ""
    }
  ],
  "paused": false,
  "total": 1,
  "pinnedCount": 0,
  "revision": 1,
  "available": true,
  "watching": true
}
```

`created` is the latest copy time in Unix milliseconds, suitable for JavaScript
`Date`. Image entries have an absolute `imagePath` and a `file://` `imageUrl`.
UI previews must use `Text.PlainText`. Only the UI's list response contains any
text excerpts; watcher status, action responses, and errors never do.

## Storage and limits

Data lives in `$XDG_STATE_HOME/quickshell-clipboard`, normally
`~/.local/state/quickshell-clipboard`. Directories are user-owned `0700`; SQLite,
locks and image files are `0600`. A private runtime lock normally lives in
`$XDG_RUNTIME_DIR/quickshell-clipboard-watch.lock`.

- 100 unpinned entries, plus up to 50 pins.
- 64 MiB combined original payload; database search/index overhead is additional.
- 24 MiB per image and 2 MiB per UTF-8 text entry.
- Input reads end after 10 seconds or the size limit.
- Capacity evicts oldest unpinned entries. Pins are never silently evicted.
- Exact bytes are deduplicated by SHA-256. Image data is not recompressed.
- PNG, JPEG, WebP, GIF, BMP, TIFF and AVIF are recognized by signature. The MIME
  is canonicalized when wl-clipboard does not expose its offered MIME.
- SVG and arbitrary binary clipboard formats are not captured.

The history is persistent, not encrypted. It remains restricted to the user by
filesystem permissions. `CLIPBOARD_STATE=sensitive`, `nil`, or other non-data
states are ignored. With wl-clipboard 2.3, password-manager sensitivity is
recognized when the provider offers `x-kde-passwordManagerHint`. Unmarked
passwords cannot be reliably distinguished from ordinary text; pause is available.

One generic image watcher requests one offered representation, avoiding separate
PNG / JPEG copies of the same image. Plain text MIME aliases have separate
watchers and deduplicate by content. No race-prone second clipboard read or
`--list-types` query is used. Newer `CLIPBOARD_TYPE` metadata is honored if present.

Implementation was prepared without reading, overwriting, or recording the real
clipboard during development, and without running tests.
