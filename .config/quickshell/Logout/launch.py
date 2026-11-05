#!/usr/bin/env python3
"""Launch the compact native logout UI, keeping the packaged tool as fallback."""
import json
import os
from pathlib import Path
import subprocess
import sys


INSTALL = Path.home() / ".config/quickshell/Logout/native"
PACKAGED = Path("/usr/bin/hyprshutdown")
PACKAGES = ("hyprshutdown", "hyprtoolkit", "hyprutils-git", "hyprlang-git",
            "hyprgraphics-git", "aquamarine-git", "hyprland")


def package_versions():
    result = subprocess.run(
        ["/usr/bin/pacman", "-Q", *PACKAGES],
        capture_output=True, text=True, check=True, timeout=3,
    )
    return dict(line.split(maxsplit=1) for line in result.stdout.splitlines())


def compatible_binary():
    candidate = INSTALL / "hyprshutdown"
    if not candidate.is_file() or not os.access(candidate, os.X_OK):
        return None
    try:
        manifest = json.loads((INSTALL / "build.json").read_text(encoding="utf-8"))
        if isinstance(manifest, dict) and manifest.get("packages") == package_versions():
            return candidate
    except (OSError, ValueError, subprocess.SubprocessError):
        pass
    return None


def main():
    if sys.argv[1:]:
        print("Use launch.py without arguments", file=sys.stderr)
        return 2
    binary = compatible_binary() or PACKAGED
    arguments = [str(binary), "--top-label", "Abmelden …"]
    try:
        os.execv(str(binary), arguments)
    except OSError:
        if binary == PACKAGED:
            raise
        os.execv(str(PACKAGED), [str(PACKAGED), "--top-label", "Abmelden …"])


if __name__ == "__main__":
    try:
        sys.exit(main())
    except OSError as error:
        print("Der Abmeldebildschirm konnte nicht gestartet werden: " + str(error), file=sys.stderr)
        sys.exit(1)
