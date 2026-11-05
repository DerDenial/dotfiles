#!/usr/bin/env python3
"""Start the idle daemon once; --detach activates it from an ordinary terminal."""
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time

from runtime import already_running, claim, runtime_directory, supervise


def available():
    return bool(shutil.which("hyprlock") and shutil.which("hypridle")
                and Path("/etc/pam.d/hyprlock").is_file()
                and (Path.home() / ".config/hypr/hyprlock.conf").is_file()
                and (Path.home() / ".config/hypr/hypridle.conf").is_file())


def main():
    detached = sys.argv[1:] == ["--detach"]
    if sys.argv[1:] and not detached:
        print("Use start-idle.py [--detach]", file=sys.stderr)
        return 2
    if os.getuid() == 0 or not os.environ.get("WAYLAND_DISPLAY"):
        print("Bitte im Terminal deiner normalen Desktop-Sitzung starten.", file=sys.stderr)
        return 1
    if not available():
        if detached:
            print("Bitte zuerst hyprlock und hypridle mit dem Paketmanager installieren.", file=sys.stderr)
            return 1
        return 0  # Autostart stays dormant until the official packages are installed.
    if detached:
        if already_running("hypridle"):
            print("Automatische Sperre ist bereits aktiv.")
            return 0
        path = runtime_directory() / "idle.log"
        descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_APPEND | os.O_NOFOLLOW, 0o600)
        with os.fdopen(descriptor, "a") as log:
            process = subprocess.Popen([sys.executable, str(Path(__file__).resolve())],
                                       stdin=subprocess.DEVNULL, stdout=log, stderr=log,
                                       start_new_session=True)
        time.sleep(0.25)
        if process.poll() is not None and process.returncode != 0:
            print("Die automatische Sperre konnte nicht starten. Siehe " + str(path), file=sys.stderr)
            return 1
        print("Automatische Sperre aktiviert: 5 Minuten; Bildschirm aus nach 10 Minuten.")
        return 0
    ownership = claim("idle.lock")
    if ownership is None or already_running("hypridle"):
        return 0
    binary = shutil.which("hypridle")
    config = Path.home() / ".config/hypr/hypridle.conf"
    return supervise([binary, "--config", str(config)])


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, RuntimeError) as error:
        print("Automatische Sperre konnte nicht gestartet werden: " + str(error), file=sys.stderr)
        sys.exit(1)
