#!/usr/bin/env python3
"""Bounded filename search for the launcher; no content index or daemon."""

import argparse
from collections import deque
import heapq
import json
import os
from pathlib import Path
import re
import sys
import time
import unicodedata


MAX_RESULTS = 60
MAX_ENTRIES = 120_000
MAX_DIRECTORIES = 12_000
MAX_DEPTH = 18
TIME_BUDGET = 1.4
SKIP_DIRECTORIES = {
    "node_modules", "__pycache__", "venv", "env", "site-packages",
    "build", "dist", "target", "vendor", "bower_components", "coverage",
}
LOCATION_TYPES = (
    ("DOCUMENTS", "Documents", "description", "folder-documents"),
    ("DOWNLOAD", "Downloads", "download", "folder-download"),
    ("DESKTOP", "Desktop", "desktop_windows", "user-desktop"),
    ("PICTURES", "Pictures", "image", "folder-pictures"),
    ("VIDEOS", "Videos", "movie", "folder-videos"),
    ("MUSIC", "Music", "music_note", "folder-music"),
)


def normalize(text):
    return "".join(char for char in unicodedata.normalize("NFKD", text.casefold())
                   if not unicodedata.combining(char))


def display_path(path, home):
    try:
        relative = path.relative_to(home)
        text = "~" if str(relative) == "." else "~/" + str(relative)
    except ValueError:
        text = str(path)
    return re.sub(r"[\x00-\x1f\x7f]", " ", text)


def configured_locations(home):
    directory = Path(os.environ.get("XDG_CONFIG_HOME", home / ".config"))
    configured = {}
    try:
        text = (directory / "user-dirs.dirs").read_text(encoding="utf-8")
    except (OSError, UnicodeError):
        text = ""
    for line in text.splitlines():
        match = re.fullmatch(r'\s*XDG_([A-Z]+)_DIR="((?:\\.|[^"\\])*)"\s*(?:#.*)?', line)
        if not match:
            continue
        value = re.sub(r'\\([\\"$`])', r'\1', match[2])
        value = value.replace("${HOME}", str(home)).replace("$HOME", str(home))
        path = Path(value)
        if path.is_absolute() and "\0" not in value:
            configured[match[1]] = path
    return configured


def icon_for(path, directory):
    if directory:
        return "folder_open", "folder"
    suffix = path.suffix.casefold()
    if suffix == ".pdf":
        return "picture_as_pdf", "application-pdf"
    if suffix in {".doc", ".docx", ".odt", ".rtf", ".pages"}:
        return "description", "x-office-document"
    if suffix in {".xls", ".xlsx", ".ods", ".csv", ".numbers"}:
        return "table_chart", "x-office-spreadsheet"
    if suffix in {".ppt", ".pptx", ".odp", ".key"}:
        return "slideshow", "x-office-presentation"
    if suffix in {".png", ".jpg", ".jpeg", ".webp", ".gif", ".svg", ".avif", ".bmp", ".heic"}:
        return "image", "image-x-generic"
    if suffix in {".mp4", ".mkv", ".webm", ".mov", ".avi"}:
        return "movie", "video-x-generic"
    if suffix in {".mp3", ".ogg", ".opus", ".flac", ".wav", ".m4a"}:
        return "audio_file", "audio-x-generic"
    if suffix in {".zip", ".7z", ".rar", ".tar", ".gz", ".xz", ".bz2", ".zst"}:
        return "folder_zip", "package-x-generic"
    if suffix in {".py", ".js", ".ts", ".tsx", ".jsx", ".java", ".c", ".cpp", ".h", ".rs", ".go", ".sh", ".qml", ".lua", ".html", ".css"}:
        return "code", "text-x-script"
    return "draft", "text-x-generic"


def descriptor(path, home, directory, *, title=None, icon=None, theme_icon=None, group="Files"):
    symbol, themed = icon_for(path, directory)
    return {
        "title": re.sub(r"[\x00-\x1f\x7f]", " ", title or path.name or str(path)),
        "detail": display_path(path.parent, home),
        "parent": str(path.parent),
        "path": str(path),
        "ref": path.as_uri(),
        "kind": "directory" if directory else "file",
        "icon": icon or symbol,
        "themeIcon": theme_icon or themed,
        "group": group,
    }


def locations(home):
    configured = configured_locations(home)
    items = [descriptor(home, home, True, title="Home", icon="home", theme_icon="user-home", group="Locations")]
    items[0]["detail"] = "~"
    seen = {str(home)}
    for key, default, symbol, themed in LOCATION_TYPES:
        path = configured.get(key, home / default)
        if str(path) in seen:
            continue
        try:
            available = path.is_dir()
        except OSError:
            available = False
        if available:
            item = descriptor(path, home, True, title=default, icon=symbol, theme_icon=themed, group="Locations")
            item["detail"] = display_path(path, home)
            items.append(item)
            seen.add(str(path))
    return items


def subsequence_penalty(token, text):
    if len(token) < 3:
        return None
    previous = -1
    first = -1
    gaps = 0
    for character in token:
        found = text.find(character, previous + 1)
        if found < 0:
            return None
        if first < 0:
            first = found
        elif found != previous + 1:
            gaps += found - previous - 1
        previous = found
    # Avoid weak, widely scattered letter matches for short queries.
    if gaps > max(5, len(token)):
        return None
    return first + gaps * 2


def match_score(name, normalized_parent, tokens, query):
    folded = normalize(name)
    if folded == query:
        return 0, 0
    if folded.startswith(query):
        return 1, len(folded) - len(query)
    positions = [folded.find(token) for token in tokens]
    if all(position >= 0 for position in positions):
        return 2, sum(positions)
    # A filename token plus a folder token is a stronger match than arbitrary
    # subsequence matching, but a folder-only match stays below filename matches.
    normalized_path = normalized_parent.rstrip("/") + "/" + folded
    if all(position >= 0 or token in normalized_path for token, position in zip(tokens, positions)):
        return 3, sum(position if position >= 0 else 20 for position in positions)
    penalties = [position if position >= 0 else subsequence_penalty(token, folded)
                 for token, position in zip(tokens, positions)]
    if all(penalty is not None for penalty in penalties):
        return 4, sum(penalties)
    return None


class WorstFirst:
    __slots__ = ("score", "item")

    def __init__(self, score, item):
        self.score, self.item = score, item

    def __lt__(self, other):
        return self.score > other.score


def search(home, query):
    folded_query = normalize(" ".join(query.split()))
    tokens = folded_query.split()
    if len(folded_query) < 2 or len(folded_query) > 160 or len(tokens) > 12:
        return [], False
    deadline = time.monotonic() + TIME_BUDGET
    try:
        device = home.stat().st_dev
    except OSError:
        return [], False
    configured = configured_locations(home)
    priorities = [configured.get(key, home / default) for key, default, _, _ in LOCATION_TYPES]
    priorities[3:3] = [home / "Projects", home / "IdeaProjects", home / "Files"]
    root_rank = {str(path): rank for rank, path in enumerate(priorities)}
    pending = deque([(home, 0, 0)])
    best = []
    entries_seen = 0
    directories_seen = 0
    partial = False
    truncated = False
    matches_seen = 0

    while pending:
        if time.monotonic() >= deadline or entries_seen >= MAX_ENTRIES or directories_seen >= MAX_DIRECTORIES:
            partial = True
            break
        folder, depth, priority = pending.popleft()
        directories_seen += 1
        normalized_parent = normalize(display_path(folder, home))
        children = []
        try:
            with os.scandir(folder) as listing:
                for entry in listing:
                    entries_seen += 1
                    if entries_seen % 32 == 0 and (time.monotonic() >= deadline or entries_seen >= MAX_ENTRIES):
                        partial = True
                        break
                    if entry.name.startswith("."):
                        continue
                    try:
                        entry.name.encode("utf-8")
                        if entry.is_symlink():
                            continue
                        directory = entry.is_dir(follow_symlinks=False)
                        if not directory and not entry.is_file(follow_symlinks=False):
                            continue
                        if directory and entry.name.casefold() in SKIP_DIRECTORIES:
                            continue
                        path = Path(entry.path)
                        child_priority = root_rank.get(str(path), priority if depth else len(root_rank))
                        if directory:
                            if depth >= MAX_DEPTH or len(children) + len(pending) + directories_seen >= MAX_DIRECTORIES:
                                truncated = True
                            elif entry.stat(follow_symlinks=False).st_dev == device:
                                children.append((path, depth + 1, child_priority))
                        score = match_score(entry.name, normalized_parent, tokens, folded_query)
                        if score is None:
                            continue
                        matches_seen += 1
                        ranking = (*score, child_priority, depth, len(entry.name), entry.name.casefold(), str(path))
                        if len(best) >= MAX_RESULTS and ranking >= best[0].score:
                            continue
                        candidate = WorstFirst(ranking, descriptor(path, home, directory))
                        if len(best) < MAX_RESULTS:
                            heapq.heappush(best, candidate)
                        else:
                            heapq.heapreplace(best, candidate)
                    except (OSError, UnicodeError):
                        continue
        except OSError:
            continue
        children.sort(key=lambda child: (child[2], str(child[0]).casefold()))
        pending.extend(children)
        if partial:
            break
    return [candidate.item for candidate in sorted(best, key=lambda value: value.score)], partial or truncated or matches_seen > MAX_RESULTS


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("search", "locations"))
    parser.add_argument("--query", default="")
    parser.add_argument("--request", type=int, default=0)
    args = parser.parse_args()
    home = Path.home().absolute()
    result = {"request": args.request, "query": args.query, "items": [], "partial": False}
    try:
        if args.action == "locations":
            result["items"] = locations(home)
        else:
            result["items"], result["partial"] = search(home, args.query.strip())
    except (OSError, ValueError, UnicodeError):
        result["error"] = "File search is unavailable."
    print(json.dumps(result, ensure_ascii=True, separators=(",", ":")))


if __name__ == "__main__":
    main()
