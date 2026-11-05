#!/usr/bin/env python3
"""Private Wayland clipboard history for the Quickshell notch.

Only `watch` / its `capture` callbacks read the current clipboard. Other commands
read the history database. Clipboard bytes are never command line arguments,
printed, or passed through a shell. The sole content-bearing output is `list`,
whose deliberately short previews are intended for the visible history UI.
"""

from __future__ import annotations

import argparse
import contextlib
import ctypes
import fcntl
import hashlib
import json
import os
from pathlib import Path
import select
import shutil
import signal
import sqlite3
import stat
import subprocess
import sys
import time
import unicodedata


os.umask(0o077)
STATE = Path(os.environ.get("XDG_STATE_HOME", str(Path.home() / ".local/state"))) / "quickshell-clipboard"
DATABASE = STATE / "history.sqlite3"
IMAGES = STATE / "images"
MAX_ITEMS = 100
MAX_PINS = 50
MAX_BYTES = 64 * 1024 * 1024
MAX_ITEM_BYTES = 24 * 1024 * 1024
MAX_TEXT_BYTES = 2 * 1024 * 1024
TEXT_MIMES = (
    "text/plain;charset=utf-8", "text/plain;charset=UTF-8", "text/plain", "UTF8_STRING",
)
IMAGE_MIMES = {
    "image/png": "png", "image/jpeg": "jpg", "image/jpg": "jpg",
    "image/webp": "webp", "image/gif": "gif", "image/bmp": "bmp",
    "image/tiff": "tiff", "image/avif": "avif",
}
# One image watcher requests one offered representation per clipboard event.
# wl-clipboard 2.3 cannot export that representation's MIME; identify its standard
# image type from these bytes instead of racing a second clipboard query.
WATCH_MIMES = (*TEXT_MIMES, "image")
STOPPING = False


class HistoryError(Exception):
    pass


def output(value: dict) -> None:
    try:
        print(json.dumps(value, ensure_ascii=False, separators=(",", ":")), flush=True)
    except BrokenPipeError:
        pass


def private_directory(path: Path) -> None:
    path.mkdir(mode=0o700, parents=True, exist_ok=True)
    info = path.lstat()
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid():
        raise HistoryError("Clipboard storage is not a private user directory.")
    path.chmod(0o700)


def private_open(path: Path, flags: int) -> int:
    fd = os.open(path, flags | os.O_CLOEXEC | os.O_NOFOLLOW, 0o600)
    info = os.fstat(fd)
    if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid():
        os.close(fd)
        raise HistoryError("Clipboard storage has an unsafe file owner or type.")
    os.fchmod(fd, 0o600)
    return fd


def watcher_lock_path() -> Path:
    runtime = Path(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}"))
    try:
        info = runtime.stat()
        if runtime.is_dir() and info.st_uid == os.getuid():
            return runtime / "quickshell-clipboard-watch.lock"
    except OSError:
        pass
    return STATE / "watch.lock"


def is_watching() -> bool:
    try:
        fd = private_open(watcher_lock_path(), os.O_RDWR | os.O_CREAT)
    except OSError:
        return False
    try:
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return True
        fcntl.flock(fd, fcntl.LOCK_UN)
        return False
    finally:
        os.close(fd)


@contextlib.contextmanager
def database():
    private_directory(STATE)
    private_directory(IMAGES)
    fd = private_open(STATE / "storage.lock", os.O_RDWR | os.O_CREAT)
    fcntl.flock(fd, fcntl.LOCK_EX)
    connection = None
    try:
        # Refuse symlinks before SQLite opens the database / auxiliary files.
        for name in (DATABASE, Path(str(DATABASE) + "-wal"), Path(str(DATABASE) + "-shm")):
            if name.exists() or name.is_symlink():
                info = name.lstat()
                if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid():
                    raise HistoryError("Clipboard database is not a private user file.")
                name.chmod(0o600)
        connection = sqlite3.connect(DATABASE, timeout=8)
        connection.row_factory = sqlite3.Row
        DATABASE.chmod(0o600)
        connection.execute("PRAGMA journal_mode=WAL")
        connection.execute("PRAGMA secure_delete=ON")
        connection.execute("PRAGMA busy_timeout=8000")
        connection.executescript("""
            CREATE TABLE IF NOT EXISTS metadata (
                key TEXT PRIMARY KEY, value TEXT NOT NULL
            );
            INSERT OR IGNORE INTO metadata VALUES ('paused', '0');
            INSERT OR IGNORE INTO metadata VALUES ('revision', '0');
            CREATE TABLE IF NOT EXISTS entries (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                digest TEXT UNIQUE NOT NULL,
                kind TEXT NOT NULL CHECK (kind IN ('text', 'image')),
                mime TEXT NOT NULL,
                payload BLOB,
                image_file TEXT,
                preview TEXT NOT NULL,
                title TEXT NOT NULL,
                search_text TEXT NOT NULL,
                size INTEGER NOT NULL,
                created INTEGER NOT NULL,
                updated INTEGER NOT NULL,
                pinned INTEGER NOT NULL DEFAULT 0
            );
            CREATE INDEX IF NOT EXISTS entries_order ON entries(pinned DESC, updated DESC);
        """)
        yield connection
    finally:
        if connection is not None:
            connection.close()
        fcntl.flock(fd, fcntl.LOCK_UN)
        os.close(fd)


def meta(db, name: str) -> str:
    return db.execute("SELECT value FROM metadata WHERE key = ?", (name,)).fetchone()[0]


def changed(db) -> None:
    db.execute("UPDATE metadata SET value = CAST(value AS INTEGER) + 1 WHERE key = 'revision'")


def status(db) -> dict:
    row = db.execute("SELECT COUNT(*) AS total, COALESCE(SUM(pinned), 0) AS pins, COALESCE(SUM(size), 0) AS bytes FROM entries").fetchone()
    return {
        "ok": True, "available": bool(shutil.which("wl-paste") and shutil.which("wl-copy")),
        "paused": meta(db, "paused") == "1", "total": row["total"], "count": row["total"],
        "pinnedCount": row["pins"], "bytes": row["bytes"], "revision": int(meta(db, "revision")),
        "watching": is_watching(), "maxItems": MAX_ITEMS, "maxPins": MAX_PINS,
        "maxBytes": MAX_BYTES, "maxItemBytes": MAX_ITEM_BYTES,
    }


def safe_preview(text: str, limit: int = 420) -> str:
    # Text.RichText is disabled in the UI as well; strip bidi / C0 controls here.
    return "".join(char for char in text if char in "\n\t" or not unicodedata.category(char).startswith("C"))[:limit]


def image_path(row) -> Path | None:
    name = row["image_file"]
    if not name:
        return None
    if Path(name).name != name or "/" in name or "\\" in name:
        raise HistoryError("Clipboard image reference is invalid.")
    return IMAGES / name


def list_items(args) -> dict:
    with database() as db:
        result = status(db)
        where, parameters = [], []
        if args.filter in ("text", "image"):
            where.append("kind = ?")
            parameters.append(args.filter)
        elif args.filter == "pinned":
            where.append("pinned = 1")
        query = args.query[:512].casefold()
        if query:
            where.append("search_text LIKE ? ESCAPE '\\'")
            escaped = query.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")
            parameters.append("%" + escaped + "%")
        statement = "SELECT * FROM entries" + (" WHERE " + " AND ".join(where) if where else "")
        statement += " ORDER BY pinned DESC, updated DESC, id DESC LIMIT ?"
        parameters.append(max(1, min(150, args.limit)))
        items = []
        for row in db.execute(statement, parameters):
            path = image_path(row)
            items.append({
                "id": row["id"], "type": row["kind"], "preview": row["preview"],
                "title": row["title"], "mime": row["mime"], "size": row["size"],
                "created": row["updated"], "firstCreated": row["created"], "pinned": bool(row["pinned"]),
                "imagePath": str(path) if path else "", "imageUrl": path.as_uri() if path else "",
            })
        result["items"] = items
        return result


def remove_images(rows) -> None:
    for row in rows:
        path = image_path(row)
        if path:
            try:
                path.unlink(missing_ok=True)
            except OSError:
                pass


def cleanup_orphan_images(db) -> None:
    referenced = {row[0] for row in db.execute("SELECT image_file FROM entries WHERE image_file IS NOT NULL")}
    for path in IMAGES.iterdir():
        # Only remove files with this helper's content-addressed naming scheme.
        # Run under the same storage lock as captures, so an uncommitted image
        # from another process cannot be mistaken for an abandoned file.
        digest = path.stem
        if path.name in referenced or len(digest) != 64 or any(char not in "0123456789abcdef" for char in digest):
            continue
        if path.suffix[1:] not in IMAGE_MIMES.values():
            continue
        try:
            path.unlink(missing_ok=True)
        except OSError:
            pass


def mutation(args) -> dict:
    with database() as db:
        deleted = []
        db.execute("BEGIN IMMEDIATE")
        if args.command == "pause":
            was_paused = meta(db, "paused") == "1"
            paused = (not was_paused) if args.value == "toggle" else args.value == "on"
            if paused != was_paused:
                db.execute("UPDATE metadata SET value = ? WHERE key = 'paused'", ("1" if paused else "0",))
                changed(db)
        elif args.command == "clear":
            deleted = list(db.execute("SELECT id, image_file FROM entries WHERE pinned = 0"))
            db.execute("DELETE FROM entries WHERE pinned = 0")
            if deleted:
                changed(db)
        else:
            row = db.execute("SELECT id, image_file, pinned FROM entries WHERE id = ?", (args.id,)).fetchone()
            if row is None:
                raise HistoryError("This clipboard item is no longer available.")
            if args.command == "pin":
                pins = db.execute("SELECT COUNT(*) FROM entries WHERE pinned = 1").fetchone()[0]
                if not row["pinned"] and pins >= MAX_PINS:
                    raise HistoryError("The maximum number of pinned items has been reached.")
                db.execute("UPDATE entries SET pinned = 1 - pinned WHERE id = ?", (args.id,))
            elif args.command == "delete":
                deleted = [row]
                db.execute("DELETE FROM entries WHERE id = ?", (args.id,))
            changed(db)
        db.commit()
        remove_images(deleted)
        if deleted:
            db.execute("PRAGMA wal_checkpoint(TRUNCATE)")
        result = status(db)
        result["deleted"] = len(deleted)
        if args.command in ("pin", "delete"):
            result["id"] = args.id
        return result


def copy_item(identifier: int) -> dict:
    if not shutil.which("wl-copy"):
        raise HistoryError("wl-copy is not installed.")
    with database() as db:
        row = db.execute("SELECT * FROM entries WHERE id = ?", (identifier,)).fetchone()
        if row is None:
            raise HistoryError("This clipboard item is no longer available.")
        path = image_path(row)
        if path:
            fd = private_open(path, os.O_RDONLY)
            with os.fdopen(fd, "rb") as handle:
                payload = handle.read(MAX_ITEM_BYTES + 1)
        else:
            payload = bytes(row["payload"])
        mime = row["mime"]
    if len(payload) > MAX_ITEM_BYTES:
        raise HistoryError("This clipboard item exceeds the size limit.")
    environment = dict(os.environ)
    environment.pop("WAYLAND_DEBUG", None)
    # wl-copy forks its clipboard owner and returns once it is ready. No auto-paste.
    result = subprocess.run(["wl-copy", "--type", mime], input=payload, stdout=subprocess.DEVNULL,
                            stderr=subprocess.DEVNULL, timeout=8, env=environment, check=False)
    if result.returncode:
        raise HistoryError("The clipboard is unavailable. Try again in the desktop session.")
    with database() as db:
        # Re-copies move to the top even if recording is paused. The user's explicit
        # copy is distinct from the background capture permission.
        db.execute("UPDATE entries SET updated = ? WHERE id = ?", (int(time.time() * 1000), identifier))
        changed(db)
        db.commit()
        answer = status(db)
        answer["id"] = identifier
        return answer


def read_bounded(limit: int) -> bytes | None:
    deadline = time.monotonic() + 10
    chunks, length = [], 0
    fd = sys.stdin.fileno()
    while time.monotonic() < deadline:
        readable, _, _ = select.select([fd], [], [], max(0, deadline - time.monotonic()))
        if not readable:
            return None
        chunk = os.read(fd, min(65536, limit + 1 - length))
        if not chunk:
            return b"".join(chunks)
        chunks.append(chunk)
        length += len(chunk)
        if length > limit:
            return None
    return None


def looks_like_image(payload: bytes, mime: str) -> bool:
    # Do not save arbitrary binary data under an image extension / SVG markup.
    if mime == "image/png":
        return payload.startswith(b"\x89PNG\r\n\x1a\n")
    if mime in ("image/jpeg", "image/jpg"):
        return payload.startswith(b"\xff\xd8\xff")
    if mime == "image/webp":
        return payload[:4] == b"RIFF" and payload[8:12] == b"WEBP"
    if mime == "image/gif":
        return payload[:6] in (b"GIF87a", b"GIF89a")
    if mime == "image/bmp":
        return payload.startswith(b"BM")
    if mime == "image/tiff":
        return payload[:4] in (b"II*\x00", b"MM\x00*")
    if mime == "image/avif":
        return payload[4:8] == b"ftyp" and (b"avif" in payload[8:64] or b"avis" in payload[8:64])
    return False


def capture(mime: str) -> None:
    # wl-clipboard 2.3 supplies this directly from the same selection's offer,
    # including x-kde-passwordManagerHint. Never re-query the live offer: a
    # newer selection could make a MIME / sensitivity check race with stdin.
    if os.environ.get("CLIPBOARD_STATE", "data") != "data":
        return
    if mime not in WATCH_MIMES:
        return
    with database() as db:
        if meta(db, "paused") == "1":
            return
    kind = "image" if mime == "image" else "text"
    payload = read_bounded(MAX_ITEM_BYTES if kind == "image" else MAX_TEXT_BYTES)
    if not payload:
        return
    if kind == "image":
        offered = os.environ.get("CLIPBOARD_TYPE", "")
        if offered in IMAGE_MIMES and looks_like_image(payload, offered):
            mime = offered
        else:
            mime = next((candidate for candidate in IMAGE_MIMES if looks_like_image(payload, candidate)), "")
        if not mime:
            return
        title = f"{IMAGE_MIMES[mime].upper()} image"
        preview, search_text = title, title.casefold()
    else:
        try:
            text = payload.decode("utf-8", errors="strict")
        except UnicodeDecodeError:
            return
        if "\x00" in text or not text.strip():
            return
        preview = safe_preview(text)
        title = " ".join(preview.split())[:100] or "Text"
        search_text = text.casefold()
        # The input was validated as UTF-8; offer standard text to both native
        # clients and XWayland rather than re-offering X11's UTF8_STRING atom.
        mime = "text/plain;charset=utf-8"
    digest = hashlib.sha256(kind.encode() + b"\0" + payload).hexdigest()
    now = int(time.time() * 1000)
    with database() as db:
        db.execute("BEGIN IMMEDIATE")
        if meta(db, "paused") == "1":
            db.rollback()
            return
        previous = db.execute("SELECT id, updated FROM entries WHERE digest = ?", (digest,)).fetchone()
        if previous:
            latest = db.execute("SELECT id FROM entries ORDER BY updated DESC, id DESC LIMIT 1").fetchone()
            if latest and latest[0] == previous["id"] and now - previous["updated"] < 1000:
                db.rollback()
                return
            db.execute("UPDATE entries SET updated = ? WHERE id = ?", (now, previous["id"]))
            changed(db)
            db.commit()
            return
        rows = list(db.execute("SELECT id, image_file, size FROM entries WHERE pinned = 0 ORDER BY updated ASC, id ASC"))
        total_bytes = db.execute("SELECT COALESCE(SUM(size), 0) FROM entries").fetchone()[0]
        unpinned = len(rows)
        deleted = []
        while rows and (unpinned >= MAX_ITEMS or total_bytes + len(payload) > MAX_BYTES):
            oldest = rows.pop(0)
            deleted.append(oldest)
            total_bytes -= oldest["size"]
            unpinned -= 1
        if total_bytes + len(payload) > MAX_BYTES:
            # Never silently evict pinned items to make room.
            db.rollback()
            return
        image_file = digest + "." + IMAGE_MIMES[mime] if kind == "image" else None
        if image_file:
            path = IMAGES / image_file
            fd = private_open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC)
            try:
                with os.fdopen(fd, "wb") as handle:
                    handle.write(payload)
            except BaseException:
                path.unlink(missing_ok=True)
                raise
        for old in deleted:
            db.execute("DELETE FROM entries WHERE id = ?", (old["id"],))
        db.execute("""INSERT INTO entries
            (digest, kind, mime, payload, image_file, preview, title, search_text, size, created, updated)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
            (digest, kind, mime, payload if kind == "text" else None, image_file,
             preview, title, search_text, len(payload), now, now))
        changed(db)
        db.commit()
        remove_images(deleted)


def request_stop(_signum=None, _frame=None) -> None:
    global STOPPING
    STOPPING = True


def parent_death_signal() -> None:
    # Linux: do not leave a clipboard recorder alive after its shell dies.
    try:
        original_parent = os.getppid()
        ctypes.CDLL(None).prctl(1, signal.SIGTERM)
        if os.getppid() != original_parent:
            request_stop()
    except (AttributeError, OSError):
        pass


def stop_children(children) -> None:
    for entry in children.values():
        process = entry.get("process")
        if process and process.poll() is None:
            try:
                os.killpg(process.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
    deadline = time.monotonic() + 1
    for entry in children.values():
        process = entry.get("process")
        if process:
            try:
                process.wait(timeout=max(0.01, deadline - time.monotonic()))
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass


def watch() -> int:
    if not shutil.which("wl-paste"):
        raise HistoryError("wl-paste is not installed.")
    with database() as db:
        cleanup_orphan_images(db)
    signal.signal(signal.SIGTERM, request_stop)
    signal.signal(signal.SIGINT, request_stop)
    parent_death_signal()
    fd = private_open(watcher_lock_path(), os.O_RDWR | os.O_CREAT)
    children = {}
    try:
        # A replacement shell may start before its predecessor exits. Wait for
        # ownership; never start a second recorder or kill another shell's one.
        while not STOPPING:
            try:
                fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                time.sleep(0.2)
        if STOPPING:
            return 0
        environment = dict(os.environ)
        environment.pop("WAYLAND_DEBUG", None)
        environment.pop("CLIPBOARD_STATE", None)
        environment.pop("CLIPBOARD_TYPE", None)
        script = str(Path(__file__).resolve())
        previous_status = None
        next_status = 0
        for mime in WATCH_MIMES:
            children[mime] = {"process": None, "retry": 0, "failures": 0, "started": 0}
        while not STOPPING:
            now = time.monotonic()
            for mime, entry in children.items():
                process = entry["process"]
                if process and process.poll() is not None:
                    lifetime = now - entry["started"]
                    entry["failures"] = 0 if lifetime > 30 else min(5, entry["failures"] + 1)
                    entry["retry"] = now + min(30, 2 ** entry["failures"])
                    entry["process"] = None
                if entry["process"] is None and now >= entry["retry"]:
                    # Text uses explicit MIME; image asks for one representation
                    # and detects its format from bytes. No list-types race and
                    # no duplicate PNG + JPEG entries for a single picture.
                    entry["process"] = subprocess.Popen(
                        ["wl-paste", "--no-newline", "--type", mime, "--watch",
                         sys.executable, script, "capture", "--mime", mime],
                        stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                        stderr=subprocess.DEVNULL, start_new_session=True, env=environment,
                    )
                    entry["started"] = now
            if now >= next_status:
                with database() as db:
                    current_status = status(db)
                alive = sum(entry["process"] is not None and entry["process"].poll() is None for entry in children.values())
                current_status["watcherCount"] = alive
                current_status["watching"] = alive > 0
                if not alive:
                    current_status["error"] = "Clipboard monitoring is waiting for the Wayland session."
                if current_status != previous_status:
                    output(current_status)
                    previous_status = current_status
                next_status = now + 0.7
            time.sleep(0.15)
        return 0
    finally:
        stop_children(children)
        fcntl.flock(fd, fcntl.LOCK_UN)
        os.close(fd)


def main() -> int:
    parser = argparse.ArgumentParser(description="Private Quickshell clipboard history")
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("status")
    listing = commands.add_parser("list")
    listing.add_argument("--query", default="")
    listing.add_argument("--filter", choices=("all", "text", "image", "pinned"), default="all")
    listing.add_argument("--limit", type=int, default=150)
    for command in ("copy", "pin", "delete"):
        commands.add_parser(command).add_argument("id", type=int)
    commands.add_parser("clear")
    commands.add_parser("pause").add_argument("value", choices=("on", "off", "toggle"), nargs="?", default="toggle")
    commands.add_parser("watch")
    storing = commands.add_parser("capture")
    storing.add_argument("--mime", required=True, choices=WATCH_MIMES)
    args = parser.parse_args()
    try:
        if args.command == "capture":
            capture(args.mime)
        elif args.command == "watch":
            return watch()
        elif args.command == "list":
            output(list_items(args))
        elif args.command == "status":
            with database() as db:
                output(status(db))
        elif args.command == "copy":
            output(copy_item(args.id))
        else:
            output(mutation(args))
        return 0
    except HistoryError as error:
        if args.command != "capture":
            output({"ok": False, "error": str(error), "items": []})
    except subprocess.TimeoutExpired:
        if args.command != "capture":
            output({"ok": False, "error": "Clipboard access timed out. Try again.", "items": []})
    except (OSError, sqlite3.Error, ValueError):
        # Exception strings can include arbitrary paths or input. Keep them out
        # of Quickshell logs, especially when invoked by watcher callbacks.
        if args.command != "capture":
            output({"ok": False, "error": "Clipboard storage is currently unavailable.", "items": []})
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
