#!/usr/bin/env python3
"""Start one real Hyprlock session with the current wallpaper and palette."""
import os
from pathlib import Path
import shutil
import sys

from runtime import already_running, claim, supervise
from sync import CONFIG, render


def main():
    binary = shutil.which("hyprlock")
    if not binary or not Path("/etc/pam.d/hyprlock").is_file():
        print("Hyprlock fehlt. Bitte die Pakete hyprlock und hypridle installieren.", file=sys.stderr)
        return 1
    if not os.environ.get("WAYLAND_DISPLAY"):
        print("Der Sperrbildschirm braucht eine laufende Wayland-Sitzung.", file=sys.stderr)
        return 1
    ownership = claim("locker.lock")
    if ownership is None or already_running("hyprlock"):
        return 0
    try:
        config = render()
    except Exception:
        # Retain the last generated configuration if appearance synchronization fails.
        if not CONFIG.is_file():
            print("Die Sperrbildschirm-Konfiguration konnte nicht erstellt werden.", file=sys.stderr)
            return 1
        config = CONFIG
    return supervise([binary, "--grace", "0", "--config", str(config)])


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, RuntimeError) as error:
        print("Sperrbildschirm konnte nicht gestartet werden: " + str(error), file=sys.stderr)
        sys.exit(1)
