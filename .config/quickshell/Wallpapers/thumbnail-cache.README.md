# Wallpaper preview cache helper

`thumbnail-cache.py` uses the already-installed material runtime interpreter:

```text
$HOME/.config/quickshell/material-runtime/bin/python thumbnail-cache.py
```

Dependency checked locally: Python 3.14.9 and Pillow 12.3.0. PNG previews work
with the existing Qt image support; no additional Qt image plugin is needed. The
helper does not install packages, contact remote services, or modify wallpaper
originals. Its tests generate their own temporary images.

Send one JSON object on standard input and close the input stream:

```json
{"paths":["/absolute/path/to/wallpaper.jpg","/absolute/path/to/another.png"]}
```

The helper emits newline-delimited JSON, flushing each result as it is ready:

```json
{"path":"/absolute/path/to/wallpaper.jpg","source":"file:///absolute/cache/quickshell/wallpaper-previews/thumb-v1-<hash>.png","status":"ready"}
{"path":"/absolute/path/to/another.png","source":"","status":"error","error":"preview-unavailable"}
{"done":true}
```

The returned `path` always matches the requested string, including paths through
symlinks. `source` is an encoded local file URL. Failed individual images do not
abort the rest of the batch. Invalid top-level input returns a single
`{"done":true,"error":"..."}` object and exit status 1. Valid batches exit 0;
each path's status reports any failure.

## Bounds and behavior

- At most 16 paths per request; at most 1 MiB of request data.
- Local absolute paths to regular files only. Symlinks resolve to the canonical
  source, so aliases share a cache entry. Symlink targets are never modified.
- Maximum source size: 256 MiB. Maximum source image area: 40,000,000 pixels.
- First image frame only. EXIF orientation is applied. Dimensions fit within
  528 × 352 pixels with the original aspect ratio; the QML image can still use
  `PreserveAspectCrop`. Images are not enlarged. Transparency is preserved.
- Small PNG files use compression level 6. Embedded source metadata is omitted.
- JPEG reduced decoding is used when available. Images resize before EXIF
  rotation so rotation does not duplicate a full-resolution decoded image.
- Cache location: `$XDG_CACHE_HOME/quickshell/wallpaper-previews`, when
  `XDG_CACHE_HOME` is absolute; otherwise `~/.cache/quickshell/wallpaper-previews`.
- Key: renderer version, canonical path, device, inode, byte size and nanosecond
  modification time. Replacing or changing a source produces a different URL.
  If a source changes during generation, its result is rejected and temporary
  output removed. A cached hit stats the source and touches the cached file;
  it does not open or decode the source.
- Cache limit: 128 MiB and 512 generated preview files. Least recently used
  files are removed at the start and end of a batch; at most one batch of
  temporary extra entries exists during generation. Only this helper's
  strictly named regular cache files are pruned. Unrelated files and symlinks
  in the cache directory are left alone. Source directories are never pruned.
- A local file lock serializes writers; atomic replacement publishes complete
  previews. Abandoned, strictly named temporary output is removed under the
  same lock. An interrupted process releases the lock automatically.

Run the temporary-image tests:

```text
$HOME/.config/quickshell/material-runtime/bin/python -m unittest discover -s tests -p test_thumbnail_cache.py -v
```

Tests cover disk hits with image opening disabled, same-path invalidation, URL
encoding, EXIF orientation, alpha, symlinks, source replacement during rendering,
corrupt source continuation, the pixel limit, request validation, LRU entry and
byte limits, and abandoned temporary output cleanup.
