#!/usr/bin/env python3
"""Keep a bounded shelf of local file references; never modify original files."""
from collections import Counter
from contextlib import contextmanager
import fcntl
import hashlib
import json
import mimetypes
import os
from pathlib import Path
import re
import stat
import sys
import tempfile
from urllib.parse import unquote, urlsplit

MAX_ITEMS = 64
MAX_BATCH = 256
MAX_INPUT = 1024 * 1024
MAX_PATH = 16384
CONTROL = re.compile(r"[\x00-\x1f\x7f-\x9f]")
BAD_PERCENT = re.compile(r"%(?![0-9A-Fa-f]{2})")
VALID_ID = re.compile(r"[0-9a-f]{64}\Z")


class ShelfError(Exception):
    def __init__(self, code, message):
        super().__init__(message)
        self.code = code


def checked_path(value):
    if not isinstance(value, str) or not value or len(value) > MAX_PATH or CONTROL.search(value):
        raise ShelfError("invalid", "This is not a supported local file.")
    try:
        value.encode("utf-8", errors="strict")
    except UnicodeError:
        raise ShelfError("invalid", "This filename cannot be represented.") from None
    if value.startswith("/"):
        return Path(value)
    try:
        url = urlsplit(value)
        if (url.scheme.lower() != "file" or url.netloc.lower() not in ("", "localhost")
                or "?" in value or "#" in value or BAD_PERCENT.search(url.path)):
            raise ValueError
        decoded = unquote(url.path, encoding="utf-8", errors="strict")
        if not decoded.startswith("/") or CONTROL.search(decoded):
            raise ValueError
        return Path(decoded)
    except (ValueError, UnicodeError):
        raise ShelfError("invalid", "Only local files and folders can be added.") from None


def canonical_file(value):
    source = checked_path(value)
    try:
        path = source.resolve(strict=True)
        info = path.stat()
    except FileNotFoundError:
        raise ShelfError("missing", "Some files are no longer available.") from None
    except (OSError, RuntimeError):
        raise ShelfError("unavailable", "Some files could not be accessed.") from None
    if not (stat.S_ISREG(info.st_mode) or stat.S_ISDIR(info.st_mode)):
        raise ShelfError("unsupported", "Only files and folders can be added.")
    return path


def icon_name(path, is_directory):
    if is_directory:
        return "folder"
    mime, encoding = mimetypes.guess_type(path.name, strict=False)
    if mime == "application/pdf":
        return "application-pdf"
    if encoding or mime in {"application/zip", "application/x-tar", "application/x-7z-compressed",
                             "application/vnd.rar", "application/x-rar-compressed"}:
        return "package-x-generic"
    if mime and mime.startswith(("image/", "audio/", "video/", "text/")):
        return mime.split("/", 1)[0] + "-x-generic"
    if mime and ("opendocument" in mime or "officedocument" in mime or "msword" in mime):
        return "x-office-document"
    return "text-x-generic"


def item_for(path):
    missing, is_directory, size, modified = False, False, None, None
    try:
        info = path.stat()
        if not (stat.S_ISREG(info.st_mode) or stat.S_ISDIR(info.st_mode)):
            raise OSError
        is_directory = stat.S_ISDIR(info.st_mode)
        size = None if is_directory else info.st_size
        modified = info.st_mtime_ns // 1_000_000
    except OSError:
        missing = True
    text = str(path)
    return {
        "id": hashlib.sha256(text.encode("utf-8")).hexdigest(),
        "path": text,
        "fileUrl": path.as_uri(),
        "name": path.name or "/",
        "parent": str(path.parent),
        "isDir": is_directory,
        "size": size,
        "modified": modified,
        "missing": missing,
        "iconName": "unknown" if missing else icon_name(path, is_directory),
    }


def storage_directory():
    supplied = os.environ.get("XDG_DATA_HOME", "")
    home = Path(supplied) if supplied and Path(supplied).is_absolute() else Path.home() / ".local/share"
    return home / "quickshell"


@contextmanager
def locked_store():
    directory = storage_directory()
    directory.mkdir(mode=0o700, parents=True, exist_ok=True)
    info = directory.lstat()
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid():
        raise ShelfError("unsafe_storage", "The shelf storage is not a private directory.")
    os.chmod(directory, 0o700)
    descriptor = os.open(directory / ".file-shelf.lock", os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    try:
        info = os.fstat(descriptor)
        if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid():
            raise ShelfError("unsafe_storage", "The shelf lock is not a private file.")
        os.fchmod(descriptor, 0o600)
        fcntl.flock(descriptor, fcntl.LOCK_EX)
        yield directory
    finally:
        os.close(descriptor)


def load_paths(directory):
    path = directory / "file-shelf.json"
    try:
        descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    except FileNotFoundError:
        return []
    try:
        info = os.fstat(descriptor)
        if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_size > MAX_INPUT:
            raise ShelfError("unsafe_storage", "The shelf data could not be read safely.")
        with os.fdopen(descriptor, "rb", closefd=False) as source:
            raw = source.read(MAX_INPUT + 1)
    finally:
        os.close(descriptor)
    try:
        value = json.loads(raw)
        if (not isinstance(value, dict) or value.get("version") != 1
                or not isinstance(value.get("paths"), list) or len(value["paths"]) > MAX_ITEMS):
            raise ValueError
        paths = []
        seen = set()
        for text in value["paths"]:
            path = checked_path(text)
            # Missing references retain their stable ID and remain removable.
            try:
                path = canonical_file(str(path))
            except ShelfError:
                path = Path(os.path.normpath(str(path)))
            if str(path) not in seen:
                paths.append(path)
                seen.add(str(path))
        return paths
    except (ValueError, UnicodeError, ShelfError):
        raise ShelfError("invalid_storage", "The shelf data could not be read. Clear the shelf to reset it.") from None


def save_paths(directory, paths):
    data = json.dumps({"version": 1, "paths": [str(path) for path in paths]}, ensure_ascii=False) + "\n"
    descriptor, temporary = tempfile.mkstemp(prefix=".file-shelf-", dir=directory)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as target:
            target.write(data)
            target.flush()
            os.fsync(target.fileno())
        os.chmod(temporary, 0o600)
        os.replace(temporary, directory / "file-shelf.json")
        descriptor = os.open(directory, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(descriptor)
        finally:
            os.close(descriptor)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def read_request(stream):
    # A single JSON line lets QML write a request without keeping stdin/EOF open.
    raw = stream.readline(MAX_INPUT + 1)
    if len(raw) > MAX_INPUT:
        raise ShelfError("input_too_large", "Too many files were supplied at once.")
    try:
        value = json.loads(raw)
        if not isinstance(value, dict):
            raise ValueError
        return value
    except (ValueError, UnicodeError):
        raise ShelfError("invalid_input", "The shelf request could not be read.") from None


def operate(command, request=None):
    request = request or {}
    if command not in {"list", "add", "remove", "clear"}:
        raise ShelfError("invalid_command", "Unknown shelf action.")
    reasons = Counter()
    added = removed = 0
    with locked_store() as directory:
        # Clear can recover malformed metadata; it never touches referenced files.
        paths = [] if command == "clear" else load_paths(directory)
        original = list(paths)
        if command == "add":
            urls = request.get("urls")
            if not isinstance(urls, list):
                raise ShelfError("invalid_input", "Files must be supplied as a list of local URLs.")
            seen = {str(path) for path in paths}
            for value in urls[:MAX_BATCH]:
                try:
                    path = canonical_file(value)
                    if str(path) in seen:
                        reasons["duplicate"] += 1
                    elif len(paths) >= MAX_ITEMS:
                        reasons["full"] += 1
                    else:
                        paths.append(path)
                        seen.add(str(path))
                        added += 1
                except ShelfError as error:
                    reasons[error.code] += 1
            reasons["full"] += max(0, len(urls) - MAX_BATCH)
        elif command == "remove":
            ids = request.get("ids")
            if not isinstance(ids, list) or len(ids) > MAX_BATCH:
                raise ShelfError("invalid_input", "Shelf entries must be supplied as a list of IDs.")
            wanted = {value for value in ids if isinstance(value, str) and VALID_ID.fullmatch(value)}
            kept = [path for path in paths if item_for(path)["id"] not in wanted]
            removed = len(paths) - len(kept)
            paths = kept
            reasons["not_found"] += max(0, len(ids) - removed)
        if command == "clear" or paths != original:
            save_paths(directory, paths)
        result = {"ok": True, "items": [item_for(path) for path in paths],
                  "added": added, "removed": removed, "skipped": sum(reasons.values())}
        if result["skipped"]:
            result["reasons"] = {name: count for name, count in reasons.items() if count}
        return result


def main(argv=None):
    arguments = sys.argv[1:] if argv is None else argv
    try:
        if len(arguments) != 1 or arguments[0] not in {"list", "add", "remove", "clear"}:
            raise ShelfError("invalid_command", "Use store.py list, add, remove or clear.")
        command = arguments[0]
        request = read_request(sys.stdin.buffer) if command in {"add", "remove"} else None
        result = operate(command, request)
        exit_code = 0
    except ShelfError as error:
        result = {"ok": False, "items": [], "added": 0, "skipped": 0,
                  "code": error.code, "error": str(error)}
        exit_code = 1
    except (OSError, UnicodeError):
        result = {"ok": False, "items": [], "added": 0, "skipped": 0,
                  "code": "storage_unavailable", "error": "The shelf could not access its private storage."}
        exit_code = 1
    print(json.dumps(result, ensure_ascii=True))
    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
