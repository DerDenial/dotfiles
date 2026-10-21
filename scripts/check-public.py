#!/usr/bin/env python3
"""Inspect this public export without reading private data or printing values."""
import hashlib
import json
from pathlib import Path
import re
import sys


ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "EXPORT-MANIFEST.json"
PATTERNS = {
    "private-key block": re.compile(r"-----BEGIN (?:(?:OPENSSH |RSA |EC |DSA |ENCRYPTED )?PRIVATE KEY|PGP PRIVATE KEY BLOCK)-----"),
    "token format": re.compile(r"(?<![A-Za-z0-9])(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,}|sk-(?:proj-)?[A-Za-z0-9_-]{30,}|xox[baprs]-[A-Za-z0-9-]{20,}|tskey-[A-Za-z0-9_-]{20,}|AKIA[A-Z0-9]{16})(?![A-Za-z0-9])"),
    "credentials in URL": re.compile(r"[a-zA-Z][a-zA-Z0-9+.-]*://[^\s/:@\"']+:[^\s/@\"']+@"),
    "literal credential": re.compile(r"(?i)(?:api[_-]?key|access[_-]?token|auth[_-]?token|client[_-]?secret|password|passwd|psk)[\"']?\s*[:=]\s*[\"']([^\"'\n]{8,})[\"']"),
    "personal home path": re.compile(r"(?:/home/|/Users/)[A-Za-z0-9_.-]+/"),
    "MAC address": re.compile(r"(?<![A-Fa-f0-9])(?:[A-Fa-f0-9]{2}:){5}[A-Fa-f0-9]{2}(?![A-Fa-f0-9])"),
}


def main():
    if not MANIFEST.is_file():
        print("Missing export manifest; no files scanned.")
        return 2
    try:
        manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
        expected = manifest["files"]
        if not isinstance(expected, dict):
            raise ValueError("invalid file list")
    except (OSError, ValueError, KeyError, TypeError):
        print("Invalid export manifest; no files scanned.")
        return 2
    allowed = set(expected) | {"EXPORT-MANIFEST.json"}
    problems = []
    changed = []
    seen = set()
    for file in sorted(ROOT.rglob("*")):
        relative = file.relative_to(ROOT)
        if ".git" in relative.parts:
            continue
        name = relative.as_posix()
        if file.is_symlink():
            problems.append((name, "symlink; target not opened"))
            continue
        if not file.is_file():
            continue
        seen.add(name)
        if name not in allowed:
            problems.append((name, "not in public file list; contents not opened"))
            continue
        if file.stat().st_size > 5_000_000:
            problems.append((name, "unexpectedly large file; contents not opened"))
            continue
        payload = file.read_bytes()
        if name in expected and hashlib.sha256(payload).hexdigest() != expected[name]:
            changed.append(name)
        try:
            source = payload.decode("utf-8")
        except UnicodeError:
            problems.append((name, "non-text content"))
            continue
        for category, expression in PATTERNS.items():
            for match in expression.finditer(source):
                line = source.count("\n", 0, match.start()) + 1
                problems.append((f"{name}:{line}", category))
    for missing in sorted(allowed - seen):
        problems.append((missing, "missing exported file"))
    for name, reason in problems:
        print(f"REVIEW {name}: {reason}")
    for name in changed:
        print(f"CHANGED {name}: review changes before publishing")
    print(f"Files: {len(seen)}; findings: {len(problems)}; changed: {len(changed)}.")
    return 1 if problems or changed else 0


if __name__ == "__main__":
    sys.exit(main())
