#!/usr/bin/env python3
"""Generate small persistent wallpaper previews without changing the originals.

Protocol: one JSON object on stdin, {"paths": ["/absolute/image", ...]}.
Each path produces a JSON line with path, source (a file: URL or ""), and
status (ready/error). A final {"done": true} line ends the batch. Requires
Pillow; invoke with the existing material-runtime Python interpreter.
"""

from __future__ import annotations

from contextlib import contextmanager
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import sys
import tempfile
import warnings

from PIL import Image, ImageOps


MAX_BATCH = 16
MAX_REQUEST_BYTES = 1024 * 1024
MAX_SOURCE_BYTES = 256 * 1024 * 1024
MAX_SOURCE_PIXELS = 40_000_000
PREVIEW_SIZE = (528, 352)
MAX_CACHE_BYTES = 128 * 1024 * 1024
MAX_CACHE_ENTRIES = 512
# Bump when rendering settings change so old thumbnails cannot be reused.
CACHE_VERSION = "v1"
ENTRY_RE = re.compile(r"^thumb-v1-[0-9a-f]{64}\.png$")
TEMP_RE = re.compile(r"^\.thumb-v1-[0-9a-f]{64}\.[a-z0-9_]+\.tmp$")


class PreviewError(Exception):
    pass


def file_identity(info: os.stat_result) -> tuple[int, int, int, int]:
    return info.st_dev, info.st_ino, info.st_size, info.st_mtime_ns


def default_cache_dir() -> Path:
    xdg_cache = os.environ.get("XDG_CACHE_HOME", "")
    base = Path(xdg_cache) if os.path.isabs(xdg_cache) else Path.home() / ".cache"
    return base / "quickshell" / "wallpaper-previews"


class ThumbnailCache:
    def __init__(
        self,
        directory: Path | None = None,
        *,
        max_bytes: int = MAX_CACHE_BYTES,
        max_entries: int = MAX_CACHE_ENTRIES,
    ) -> None:
        self.directory = directory if directory is not None else default_cache_dir()
        self.max_bytes = max_bytes
        self.max_entries = max_entries

    @contextmanager
    def batch(self):
        """Serialize writers and prune only files belonging to this cache."""
        self.directory.mkdir(mode=0o700, parents=True, exist_ok=True)
        lock_flags = os.O_CREAT | os.O_RDWR | os.O_CLOEXEC | os.O_NOFOLLOW
        lock_fd = os.open(self.directory / ".lock", lock_flags, 0o600)
        try:
            if not stat.S_ISREG(os.fstat(lock_fd).st_mode):
                raise PreviewError("cache-unavailable")
            fcntl.flock(lock_fd, fcntl.LOCK_EX)
            self.prune()
            try:
                yield self
            finally:
                self.prune()
        finally:
            os.close(lock_fd)

    def prune(self) -> None:
        entries = []
        with os.scandir(self.directory) as scanned:
            for entry in scanned:
                # Do not follow links or remove unrelated content.
                if not (ENTRY_RE.fullmatch(entry.name) or TEMP_RE.fullmatch(entry.name)):
                    continue
                try:
                    info = entry.stat(follow_symlinks=False)
                    if not stat.S_ISREG(info.st_mode):
                        continue
                    if TEMP_RE.fullmatch(entry.name):
                        # No other writer can have an active temporary file while
                        # this process holds the batch lock.
                        os.unlink(entry.path)
                    else:
                        entries.append((info.st_mtime_ns, entry.name, info.st_size))
                except FileNotFoundError:
                    continue
        entries.sort()
        byte_count = sum(entry[2] for entry in entries)
        entry_count = len(entries)
        for _, name, size in entries:
            if entry_count <= self.max_entries and byte_count <= self.max_bytes:
                break
            try:
                (self.directory / name).unlink()
            except FileNotFoundError:
                pass
            entry_count -= 1
            byte_count -= size

    def source_info(self, requested: str) -> tuple[Path, os.stat_result]:
        if not isinstance(requested, str) or not os.path.isabs(requested):
            raise PreviewError("absolute-local-path-required")
        try:
            canonical = Path(requested).resolve(strict=True)
            info = canonical.stat()
        except (OSError, ValueError, RuntimeError) as error:
            raise PreviewError("source-unavailable") from error
        if not stat.S_ISREG(info.st_mode):
            raise PreviewError("regular-file-required")
        if info.st_size <= 0 or info.st_size > MAX_SOURCE_BYTES:
            raise PreviewError("source-size-limit")
        return canonical, info

    def entry_path(self, canonical: Path, info: os.stat_result) -> Path:
        key_data = [CACHE_VERSION, str(canonical), *file_identity(info)]
        key = hashlib.sha256(json.dumps(key_data, ensure_ascii=True).encode()).hexdigest()
        return self.directory / f"thumb-{CACHE_VERSION}-{key}.png"

    def preview(self, requested: str) -> str:
        canonical, info = self.source_info(requested)
        destination = self.entry_path(canonical, info)
        try:
            cached = destination.lstat()
        except FileNotFoundError:
            cached = None
        if cached is not None and stat.S_ISREG(cached.st_mode) and cached.st_size > 0:
            # Touch only the small cached file. A hit does not open or decode the
            # original, nor repeatedly decode the thumbnail in this helper.
            os.utime(destination, None, follow_symlinks=False)
            return destination.as_uri()
        self.render(canonical, info, destination)
        return destination.as_uri()

    def render(self, canonical: Path, before: os.stat_result, destination: Path) -> None:
        temporary = None
        # O_NOFOLLOW handles a source replaced by a symlink after canonicalizing;
        # O_NONBLOCK prevents a regular file swapped for a FIFO from hanging us.
        source_fd = os.open(canonical, os.O_RDONLY | os.O_CLOEXEC | os.O_NOFOLLOW | os.O_NONBLOCK)
        try:
            with os.fdopen(source_fd, "rb") as source:
                source_fd = -1
                opened = os.fstat(source.fileno())
                if not stat.S_ISREG(opened.st_mode) or file_identity(opened) != file_identity(before):
                    raise PreviewError("source-changed")
                with warnings.catch_warnings():
                    warnings.simplefilter("error", Image.DecompressionBombWarning)
                    with Image.open(source) as original:
                        width, height = original.size
                        if width <= 0 or height <= 0 or width * height > MAX_SOURCE_PIXELS:
                            raise PreviewError("source-pixel-limit")
                        original.seek(0)
                        # Resize before applying EXIF so rotation does not make a
                        # second full-resolution image. JPEG also supports reduced
                        # decoding; other formats remain bounded by the pixel limit.
                        swaps_axes = original.getexif().get(274) in (5, 6, 7, 8)
                        target_size = PREVIEW_SIZE[::-1] if swaps_axes else PREVIEW_SIZE
                        original.draft("RGB", target_size)
                        original.thumbnail(target_size, Image.Resampling.LANCZOS, reducing_gap=3.0)
                        oriented = ImageOps.exif_transpose(original)
                        try:
                            has_alpha = "A" in oriented.getbands() or "transparency" in oriented.info
                            with oriented.convert("RGBA" if has_alpha else "RGB") as preview:
                                handle, temporary = tempfile.mkstemp(
                                    prefix=f".{destination.stem}.", suffix=".tmp", dir=self.directory
                                )
                                with os.fdopen(handle, "wb") as output:
                                    preview.save(
                                        output,
                                        format="PNG",
                                        compress_level=6,
                                        exif=b"",
                                        icc_profile=b"",
                                    )
                        finally:
                            oriented.close()
                if file_identity(os.fstat(source.fileno())) != file_identity(before):
                    raise PreviewError("source-changed")
                # Detect replacement of the path itself while the old inode was
                # still open, including edits that change size or modification time.
                if file_identity(canonical.stat()) != file_identity(before):
                    raise PreviewError("source-changed")
            os.replace(temporary, destination)
            temporary = None
        finally:
            if source_fd >= 0:
                os.close(source_fd)
            if temporary is not None:
                try:
                    os.unlink(temporary)
                except FileNotFoundError:
                    pass


def emit(result: dict) -> None:
    print(json.dumps(result, ensure_ascii=True, separators=(",", ":")), flush=True)


def main() -> int:
    try:
        data = sys.stdin.buffer.read(MAX_REQUEST_BYTES + 1)
        if len(data) > MAX_REQUEST_BYTES:
            raise PreviewError("request-size-limit")
        request = json.loads(data)
        paths = request.get("paths") if isinstance(request, dict) else None
        if not isinstance(paths, list) or len(paths) > MAX_BATCH or any(not isinstance(p, str) for p in paths):
            raise PreviewError("paths-must-be-a-list-of-at-most-16-strings")
    except (ValueError, RecursionError, PreviewError) as error:
        emit({"done": True, "error": str(error) if isinstance(error, PreviewError) else "invalid-json"})
        return 1

    # Normalize Pillow's decompression-bomb ceiling to the explicit input limit.
    Image.MAX_IMAGE_PIXELS = MAX_SOURCE_PIXELS
    next_index = 0
    try:
        cache = ThumbnailCache()
        with cache.batch():
            for requested in paths:
                try:
                    source = cache.preview(requested)
                    result = {"path": requested, "source": source, "status": "ready"}
                except PreviewError as error:
                    result = {"path": requested, "source": "", "status": "error", "error": str(error)}
                except Exception:
                    # Pillow format plugins raise several different exception
                    # types for corrupt data. A bad file must not strand the rest
                    # of the caller's pending thumbnail requests.
                    result = {"path": requested, "source": "", "status": "error", "error": "preview-unavailable"}
                emit(result)
                next_index += 1
    except (OSError, PreviewError):
        for requested in paths[next_index:]:
            emit({"path": requested, "source": "", "status": "error", "error": "cache-unavailable"})
    emit({"done": True})
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
