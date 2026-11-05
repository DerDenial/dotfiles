#!/usr/bin/env python3
"""Private local notes for Quickshell.

Content-bearing mutations receive one JSON object on standard input. Notes are
never command line arguments and this helper does not print debug logs. JSON
responses containing notes are intended only for the local notes UI.
"""

from __future__ import annotations

import argparse
import contextlib
import fcntl
import json
import os
from pathlib import Path
import select
import sqlite3
import stat
import sys
import time
import unicodedata


os.umask(0o077)
STATE_BASE = Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local/state")
STATE = STATE_BASE / "quickshell-notes"
DATABASE = STATE / "notes.sqlite3"
MAX_TITLE_CHARS = 200
MAX_NOTE_BYTES = 1024 * 1024
MAX_REQUEST_BYTES = 8 * 1024 * 1024
MAX_NOTES = 5000
MAX_TOTAL_BYTES = 256 * 1024 * 1024
PREVIEW_CHARS = 180
DEFAULT_LIMIT = 500


class NotesError(Exception):
    def __init__(self, message: str, code: str = "STORAGE", **details):
        super().__init__(message)
        self.code = code
        self.details = details


def output(value: dict) -> None:
    try:
        print(json.dumps(value, ensure_ascii=False, separators=(",", ":")), flush=True)
    except BrokenPipeError:
        pass


def private_directory(path: Path) -> None:
    if not path.is_absolute():
        raise NotesError("Notes storage must use an absolute path.")
    path.mkdir(mode=0o700, parents=True, exist_ok=True)
    info = path.lstat()
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid():
        raise NotesError("Notes storage is not a private user directory.")
    path.chmod(0o700)


def private_open(path: Path, flags: int) -> int:
    fd = os.open(path, flags | os.O_CLOEXEC | os.O_NOFOLLOW, 0o600)
    info = os.fstat(fd)
    if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid():
        os.close(fd)
        raise NotesError("Notes storage has an unsafe file owner or type.")
    os.fchmod(fd, 0o600)
    return fd


@contextlib.contextmanager
def database():
    private_directory(STATE)
    lock_fd = private_open(STATE / "storage.lock", os.O_RDWR | os.O_CREAT)
    connection = None
    try:
        fcntl.flock(lock_fd, fcntl.LOCK_EX)
        # The directory is private. Refuse existing symlink, device or foreign
        # files before SQLite opens the main database or its sidecar files.
        for path in (DATABASE, Path(str(DATABASE) + "-wal"), Path(str(DATABASE) + "-shm"),
                     Path(str(DATABASE) + "-journal")):
            if path.exists() or path.is_symlink():
                info = path.lstat()
                if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid():
                    raise NotesError("Notes database is not a private user file.")
                path.chmod(0o600)
        connection = sqlite3.connect(DATABASE, timeout=8, isolation_level=None)
        connection.row_factory = sqlite3.Row
        DATABASE.chmod(0o600)
        connection.execute("PRAGMA journal_mode=WAL")
        connection.execute("PRAGMA synchronous=FULL")
        connection.execute("PRAGMA secure_delete=ON")
        connection.execute("PRAGMA busy_timeout=8000")
        version = connection.execute("PRAGMA user_version").fetchone()[0]
        if version > 1:
            raise NotesError("This notes database needs a newer version of the notes app.", "VERSION")
        connection.executescript("""
            BEGIN IMMEDIATE;
            CREATE TABLE IF NOT EXISTS metadata (
                key TEXT PRIMARY KEY, value INTEGER NOT NULL
            );
            INSERT OR IGNORE INTO metadata VALUES ('revision', 0);
            CREATE TABLE IF NOT EXISTS notes (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                title TEXT NOT NULL,
                content TEXT NOT NULL,
                created INTEGER NOT NULL,
                updated INTEGER NOT NULL,
                revision INTEGER NOT NULL DEFAULT 1,
                size INTEGER NOT NULL
            );
            CREATE INDEX IF NOT EXISTS notes_updated ON notes(updated DESC, id DESC);
            PRAGMA user_version=1;
            COMMIT;
        """)
        yield connection
    finally:
        if connection is not None:
            connection.close()
        fcntl.flock(lock_fd, fcntl.LOCK_UN)
        os.close(lock_fd)


@contextlib.contextmanager
def transaction(db):
    db.execute("BEGIN IMMEDIATE")
    try:
        yield
        db.execute("COMMIT")
    except BaseException:
        db.execute("ROLLBACK")
        raise


def read_request() -> dict:
    """Read bounded JSON until EOF, including a deadline for abandoned writers."""
    chunks = []
    size = 0
    deadline = time.monotonic() + 10
    fd = sys.stdin.fileno()
    while True:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise NotesError("The notes request was not completed. Your edit was not saved.", "INPUT")
        ready, _, _ = select.select([fd], [], [], remaining)
        if not ready:
            raise NotesError("The notes request was not completed. Your edit was not saved.", "INPUT")
        chunk = os.read(fd, min(65536, MAX_REQUEST_BYTES + 1 - size))
        if not chunk:
            break
        size += len(chunk)
        if size > MAX_REQUEST_BYTES:
            raise NotesError("This note is too large. The maximum is 1 MiB per note.", "LIMIT")
        chunks.append(chunk)
    try:
        request = json.loads(b"".join(chunks).decode("utf-8"))
    except (ValueError, UnicodeDecodeError):
        raise NotesError("The notes request is not valid JSON.", "INPUT") from None
    if not isinstance(request, dict):
        raise NotesError("The notes request must be a JSON object.", "INPUT")
    return request


def valid_text(value, field: str) -> str:
    if not isinstance(value, str):
        raise NotesError(f"The note {field} must be text.", "INPUT")
    if "\x00" in value:
        raise NotesError("Notes cannot contain null characters.", "INPUT")
    try:
        value.encode("utf-8")
    except UnicodeEncodeError:
        raise NotesError("The note contains invalid Unicode text.", "INPUT") from None
    return value


def note_fields(request: dict, old=None) -> tuple[str, str, int]:
    title = valid_text(request.get("title", old["title"] if old is not None else ""), "title")
    content = valid_text(request.get("content", old["content"] if old is not None else ""), "content")
    # Titles are a single line; the note body itself is stored byte-for-byte.
    title = " ".join(title.split()).strip() or "Neue Notiz"
    if len(title) > MAX_TITLE_CHARS:
        raise NotesError(f"The title may contain at most {MAX_TITLE_CHARS} characters.", "LIMIT")
    size = len(title.encode("utf-8")) + len(content.encode("utf-8"))
    if size > MAX_NOTE_BYTES:
        raise NotesError("This note is too large. The maximum is 1 MiB per note.", "LIMIT")
    return title, content, size


def compact_preview(content: str) -> str:
    text = " ".join("".join(
        char for char in content[:2048]
        if not unicodedata.category(char).startswith("C") or char.isspace()
    ).split())
    return text[:PREVIEW_CHARS] + ("…" if len(text) > PREVIEW_CHARS else "")


def note_json(row, include_content=True) -> dict:
    value = {
        "id": row["id"], "title": row["title"], "preview": compact_preview(row["content"]),
        "created": row["created"], "updated": row["updated"], "revision": row["revision"],
        "size": row["size"],
    }
    if include_content:
        value["content"] = row["content"]
    return value


def get_row(db, note_id: int):
    row = db.execute("SELECT * FROM notes WHERE id = ?", (note_id,)).fetchone()
    if row is None:
        raise NotesError("This note no longer exists. Your local edit has been kept.", "NOT_FOUND")
    return row


def check_revision(request: dict, row) -> None:
    expected = request.get("expectedRevision")
    if expected is None:
        return
    if isinstance(expected, bool) or not isinstance(expected, int) or expected < 1:
        raise NotesError("The note revision must be a positive integer.", "INPUT")
    if expected != row["revision"]:
        raise NotesError("This note changed in another window. Your local edit has been kept.",
                         "CONFLICT", note=note_json(row))


def changed(db) -> None:
    db.execute("UPDATE metadata SET value = value + 1 WHERE key = 'revision'")


def metadata(db) -> dict:
    row = db.execute("SELECT COUNT(*) AS count, COALESCE(SUM(size), 0) AS bytes FROM notes").fetchone()
    revision = db.execute("SELECT value FROM metadata WHERE key = 'revision'").fetchone()[0]
    return {"ok": True, "available": True, "total": row["count"], "bytes": row["bytes"],
            "revision": revision, "maxNoteBytes": MAX_NOTE_BYTES, "maxNotes": MAX_NOTES}


def list_notes(db, query: str, limit: int) -> dict:
    query = query[:512].strip().casefold()
    terms = query.split()
    notes = []
    count = 0
    # Python casefold also handles non-ASCII titles/content. SQLite's stock
    # LOWER/LIKE only fold ASCII without an optional ICU extension.
    for row in db.execute("SELECT * FROM notes ORDER BY updated DESC, id DESC"):
        if terms:
            searchable = (row["title"] + "\n" + row["content"]).casefold()
            if not all(term in searchable for term in terms):
                continue
        count += 1
        if len(notes) < limit:
            notes.append(note_json(row, include_content=False))
    return {**metadata(db), "count": count, "notes": notes, "hasMore": count > len(notes)}


def create_note(db, request: dict) -> dict:
    title, content, size = note_fields(request)
    with transaction(db):
        stats = metadata(db)
        if stats["total"] >= MAX_NOTES or stats["bytes"] + size > MAX_TOTAL_BYTES:
            raise NotesError("The notes storage is full. Delete an unneeded note to make room.", "LIMIT")
        now = int(time.time() * 1000)
        result = db.execute("""
            INSERT INTO notes(title, content, created, updated, revision, size)
            VALUES (?, ?, ?, ?, 1, ?)
        """, (title, content, now, now, size))
        row = get_row(db, result.lastrowid)
        changed(db)
    return {"ok": True, "note": note_json(row)}


def save_note(db, note_id: int, request: dict) -> dict:
    with transaction(db):
        old = get_row(db, note_id)
        check_revision(request, old)
        title, content, size = note_fields(request, old)
        if title == old["title"] and content == old["content"]:
            return {"ok": True, "note": note_json(old), "unchanged": True}
        if metadata(db)["bytes"] - old["size"] + size > MAX_TOTAL_BYTES:
            raise NotesError("The notes storage is full. Your edit was not saved.", "LIMIT")
        now = max(int(time.time() * 1000), old["updated"] + 1)
        db.execute("""
            UPDATE notes SET title = ?, content = ?, updated = ?, revision = revision + 1, size = ?
            WHERE id = ?
        """, (title, content, now, size, note_id))
        row = get_row(db, note_id)
        changed(db)
    return {"ok": True, "note": note_json(row)}


def delete_note(db, note_id: int, request: dict) -> dict:
    with transaction(db):
        row = get_row(db, note_id)
        check_revision(request, row)
        db.execute("DELETE FROM notes WHERE id = ?", (note_id,))
        changed(db)
    return {"ok": True, "deletedId": note_id}


def positive_int(value: str) -> int:
    try:
        number = int(value)
    except ValueError:
        raise argparse.ArgumentTypeError("must be a positive integer") from None
    if number <= 0 or number > 2**53 - 1:
        raise argparse.ArgumentTypeError("must be a positive integer")
    return number


def main() -> int:
    parser = argparse.ArgumentParser(description="Private local notes for Quickshell")
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("status")
    listing = commands.add_parser("list")
    listing.add_argument("--query", default="")
    listing.add_argument("--limit", type=positive_int, default=DEFAULT_LIMIT)
    for command in ("get", "save", "delete"):
        commands.add_parser(command).add_argument("id", type=positive_int)
    commands.add_parser("create")
    arguments = parser.parse_args()
    try:
        # Consume the whole request before opening a transaction or lock.
        request = read_request() if arguments.command in ("create", "save", "delete") else None
        with database() as db:
            if arguments.command == "status":
                result = metadata(db)
            elif arguments.command == "list":
                result = list_notes(db, arguments.query, min(arguments.limit, 1000))
            elif arguments.command == "get":
                result = {"ok": True, "note": note_json(get_row(db, arguments.id))}
            elif arguments.command == "create":
                result = create_note(db, request)
            elif arguments.command == "save":
                result = save_note(db, arguments.id, request)
            else:
                result = delete_note(db, arguments.id, request)
        output(result)
        return 0
    except NotesError as error:
        output({"ok": False, "error": str(error), "code": error.code, **error.details})
    except sqlite3.DatabaseError:
        output({"ok": False, "error": "Notes storage could not be read or updated. Your local edit has been kept.",
                "code": "STORAGE"})
    except (OSError, ValueError):
        output({"ok": False, "error": "Notes storage is unavailable. Your local edit has been kept.",
                "code": "STORAGE"})
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
