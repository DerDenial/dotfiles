#!/usr/bin/env python3
"""Private, bounded clipboard/paste bridge for the Quickshell emoji picker.

No shell, clipboard reading, typing daemon, target titles, or persistent targets.
Only exact emoji strings shipped in emojis.json can reach the clipboard.
The UI must capture before opening. For multi-insert it must release input and
await QWindow.active == false before insert; closing mode must unmap instead.
"""

from __future__ import annotations

import argparse
import contextlib
import fcntl
import json
import os
from pathlib import Path
import re
import shutil
import socket
import stat
import subprocess
import sys
import tempfile
import time


os.umask(0o077)
CATALOG = Path(__file__).resolve().with_name("emojis.json")
STATE = Path(os.environ.get("XDG_STATE_HOME", str(Path.home() / ".local/state"))) / "quickshell-emoji"
RUNTIME = Path(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}"))
PICKER_NAMESPACE = "qs-emoji-picker"
MAX_RECENTS = 48
MAX_JSON_BYTES = 64 * 1024
ADDRESS = re.compile(r"0x[0-9a-fA-F]{1,24}\Z")
INSTANCE = re.compile(r"[a-zA-Z0-9_.-]{1,240}\Z")


class PickerError(Exception):
    """An expected user-facing failure; never include private window details."""


def output(value: dict) -> None:
    try:
        print(json.dumps(value, ensure_ascii=False, separators=(",", ":")), flush=True)
    except BrokenPipeError:
        pass


def load_catalog() -> list:
    try:
        data = json.loads(CATALOG.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, ValueError) as error:
        raise PickerError("Der Emoji-Katalog konnte nicht geladen werden.") from error
    entries = data.get("emojis", []) if isinstance(data, dict) else data
    if not isinstance(entries, list):
        raise PickerError("Der Emoji-Katalog hat ein ungültiges Format.")
    return entries


def allowed_emojis() -> set[str]:
    allowed = set()
    pending = list(load_catalog())
    while pending:
        item = pending.pop()
        value = item.get("emoji") if isinstance(item, dict) else item
        if isinstance(value, str) and 0 < len(value.encode("utf-8")) <= 128:
            # The catalog is an explicit allowlist, including complete ZWJ/flag
            # sequences. Whitespace and control characters never form an emoji.
            if not any(ord(char) < 32 or char.isspace() for char in value):
                allowed.add(value)
        if isinstance(item, dict) and isinstance(item.get("variants"), list):
            pending.extend(item["variants"])
    if not allowed:
        raise PickerError("Der Emoji-Katalog ist leer.")
    return allowed


def private_directory(path: Path) -> None:
    path.mkdir(mode=0o700, parents=True, exist_ok=True)
    info = path.lstat()
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid():
        raise PickerError("Der Emoji-Speicher ist kein privater Benutzerordner.")
    path.chmod(0o700)


def private_open(path: Path, flags: int) -> int:
    fd = os.open(path, flags | os.O_CLOEXEC | os.O_NOFOLLOW, 0o600)
    info = os.fstat(fd)
    if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid():
        os.close(fd)
        raise PickerError("Der Emoji-Speicher hat einen ungültigen Dateityp.")
    os.fchmod(fd, 0o600)
    return fd


def read_recents(allowed: set[str]) -> list[str]:
    try:
        info = STATE.lstat()
        if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid():
            return []
        fd = private_open(STATE / "recents.json", os.O_RDONLY)
    except FileNotFoundError:
        return []
    with os.fdopen(fd, "rb") as handle:
        raw = handle.read(MAX_JSON_BYTES + 1)
    if len(raw) > MAX_JSON_BYTES:
        return []
    try:
        data = json.loads(raw)
    except (UnicodeError, ValueError):
        return []
    items = data.get("items", []) if isinstance(data, dict) else []
    if not isinstance(items, list):
        return []
    # No timestamps, target app names, titles, or copied text are recorded.
    return list(dict.fromkeys(item for item in items if isinstance(item, str) and item in allowed))[:MAX_RECENTS]


def remember(emoji: str, allowed: set[str]) -> list[str]:
    private_directory(STATE)
    fd = private_open(STATE / "storage.lock", os.O_RDWR | os.O_CREAT)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX)
        items = [emoji, *(item for item in read_recents(allowed) if item != emoji)][:MAX_RECENTS]
        temp_fd, name = tempfile.mkstemp(prefix=".recents-", dir=STATE)
        try:
            with os.fdopen(temp_fd, "w", encoding="utf-8") as handle:
                json.dump({"version": 1, "items": items}, handle, ensure_ascii=False, separators=(",", ":"))
                handle.write("\n")
                handle.flush()
                os.fsync(handle.fileno())
            os.replace(name, STATE / "recents.json")
        finally:
            with contextlib.suppress(FileNotFoundError):
                os.unlink(name)
        return items
    finally:
        os.close(fd)


class Hyprland:
    """Use the same documented UNIX socket protocol as hyprctl, without a shell."""

    def __init__(self) -> None:
        self.instance = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE", "")
        if not INSTANCE.fullmatch(self.instance) or self.instance in {".", ".."}:
            raise PickerError("Keine aktive Hyprland-Sitzung gefunden.")
        self.path = RUNTIME / "hypr" / self.instance / ".socket.sock"
        try:
            info = self.path.stat()
        except OSError as error:
            raise PickerError("Die Hyprland-Verbindung ist nicht verfügbar.") from error
        if not stat.S_ISSOCK(info.st_mode) or info.st_uid != os.getuid():
            raise PickerError("Die Hyprland-Verbindung ist nicht verfügbar.")

    def request(self, command: str, *, as_json: bool = False):
        chunks = []
        total = 0
        try:
            with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as connection:
                connection.settimeout(0.8)
                connection.connect(str(self.path))
                connection.sendall((("j/" if as_json else "/") + command).encode("utf-8"))
                while True:
                    chunk = connection.recv(65536)
                    if not chunk:
                        break
                    total += len(chunk)
                    if total > 8 * 1024 * 1024:
                        raise PickerError("Die Hyprland-Antwort ist zu groß.")
                    chunks.append(chunk)
            raw = b"".join(chunks).decode("utf-8")
            return json.loads(raw) if as_json else raw.strip()
        except (OSError, UnicodeError, ValueError) as error:
            raise PickerError("Die Hyprland-Verbindung antwortet nicht.") from error

    def query(self, command: str):
        return self.request(command, as_json=True)

    def dispatch(self, command: str) -> None:
        if self.request("dispatch " + command) != "ok":
            raise PickerError("Hyprland konnte das Emoji nicht einfügen; es wurde kopiert.")


def window_identity(window: dict, instance: str) -> dict | None:
    if not isinstance(window, dict):
        return None
    address = window.get("address", "")
    pid = window.get("pid")
    workspace = window.get("workspace", {})
    if (not isinstance(address, str) or not ADDRESS.fullmatch(address) or int(address, 16) == 0
            or not isinstance(pid, int) or isinstance(pid, bool) or pid <= 0
            or not isinstance(workspace, dict) or not isinstance(workspace.get("id"), int)
            or window.get("mapped") is False):
        return None
    app_class = window.get("class", "")
    initial_class = window.get("initialClass", "")
    stable_id = window.get("stableId", "")
    if (not isinstance(app_class, str) or not isinstance(initial_class, str)
            or not isinstance(stable_id, str) or not re.fullmatch(r"[a-fA-F0-9]{1,24}", stable_id)
            or window.get("hidden") is True or window.get("acceptsInput") is False):
        return None
    return {"address": address.lower(), "pid": pid, "class": app_class,
            "initialClass": initial_class, "workspace": workspace["id"], "instance": instance,
            "stableId": stable_id.lower()}


def validate_target(target, hypr: Hyprland) -> dict:
    if not isinstance(target, dict) or target.get("instance") != hypr.instance:
        raise PickerError("Kein Eingabefenster ausgewählt; das Emoji wurde kopiert.")
    address = target.get("address", "")
    if not isinstance(address, str) or not ADDRESS.fullmatch(address) or int(address, 16) == 0:
        raise PickerError("Das Eingabefenster ist nicht mehr verfügbar; das Emoji wurde kopiert.")
    clients = hypr.query("clients")
    if not isinstance(clients, list):
        raise PickerError("Das Eingabefenster ist nicht mehr verfügbar; das Emoji wurde kopiert.")
    live = next((window_identity(window, hypr.instance) for window in clients
                 if isinstance(window, dict) and isinstance(window.get("address"), str)
                 and window["address"].lower() == address.lower()), None)
    keys = ("address", "pid", "class", "initialClass", "workspace", "instance", "stableId")
    if live is None or any(live[key] != target.get(key) for key in keys):
        raise PickerError("Das Eingabefenster wurde geschlossen oder gewechselt; das Emoji wurde kopiert.")
    return live


def picker_is_mapped(layers) -> bool:
    if not isinstance(layers, dict):
        raise PickerError("Der Emoji-Picker konnte den Tastaturfokus nicht freigeben; das Emoji wurde kopiert.")
    for monitor in layers.values():
        if not isinstance(monitor, dict):
            continue
        levels = monitor.get("levels", {})
        if not isinstance(levels, dict):
            continue
        for level in levels.values():
            if not isinstance(level, list):
                continue
            for layer in level:
                if not isinstance(layer, dict) or layer.get("namespace") != PICKER_NAMESPACE:
                    continue
                # Unmapped layer surfaces can remain in the fade-out list.
                alpha = layer.get("alpha", 1)
                if not isinstance(alpha, (int, float)) or alpha > 0.001:
                    return True
    return False


def assert_original_focus(hypr: Hyprland, target: dict, *, allow_unfocused: bool) -> bool:
    active = hypr.query("activewindow")
    if not isinstance(active, dict):
        raise PickerError("Der Eingabefokus ist nicht verfügbar; das Emoji wurde kopiert.")
    address = active.get("address", "")
    if address and address != "0x0":
        if window_identity(active, hypr.instance) != target:
            raise PickerError("Ein anderes Fenster ist aktiv; das Emoji wurde kopiert.")
        return True
    if not allow_unfocused:
        raise PickerError("Der Eingabefokus konnte nicht wiederhergestellt werden; das Emoji wurde kopiert.")
    return False


def assert_unlocked(hypr: Hyprland) -> None:
    lock_state = hypr.query("locked")
    if not isinstance(lock_state, dict) or lock_state.get("locked") is not False:
        raise PickerError("Der Bildschirm ist gesperrt; das Emoji wurde kopiert.")


def paste_to_original(target, hypr: Hyprland, *, keep_open: bool = False) -> None:
    target = validate_target(target, hypr)
    assert_unlocked(hypr)
    if not keep_open:
        deadline = time.monotonic() + 0.9
        while True:
            assert_unlocked(hypr)
            assert_original_focus(hypr, target, allow_unfocused=True)
            if not picker_is_mapped(hypr.query("layers")):
                break
            if time.monotonic() >= deadline:
                raise PickerError("Der Emoji-Picker hat noch den Fokus; das Emoji wurde kopiert.")
            # Poll compositor state only while the surface is still mapped; no
            # blind fixed delay and no background watcher after this invocation.
            time.sleep(0.025)
        validate_target(target, hypr)
        assert_original_focus(hypr, target, allow_unfocused=True)
        hypr.dispatch("focuswindow address:" + target["address"])
    # Multi-insert mode uses the root UI's QWindow.active=false acknowledgement.
    # Do not focuswindow here: it warps the cursor away from the visible picker.
    assert_original_focus(hypr, target, allow_unfocused=False)
    # The address selector is essential: even a last-millisecond focus change
    # cannot redirect this shortcut into another application.
    app_class = target["class"].casefold()
    initial_class = target["initialClass"].casefold()
    terminal = {"kitty", "alacritty", "org.wezfurlong.wezterm", "wezterm", "foot", "footclient"}
    modifiers = "CTRL SHIFT" if app_class in terminal or initial_class in terminal else "CTRL"
    # This desktop uses the German layout: V is evdev KEY_V(47) + XKB offset 8.
    # A physical code also avoids Caps Lock / held Shift breaking Hyprland's
    # current-state keysym lookup before applying the synthetic modifiers.
    hypr.dispatch(f"sendshortcut {modifiers},code:55,address:{target['address']}")


@contextlib.contextmanager
def insertion_lock():
    try:
        info = RUNTIME.stat()
        if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid():
            raise PickerError("Die Desktop-Sitzung ist nicht verfügbar.")
        fd = private_open(RUNTIME / "quickshell-emoji-insert.lock", os.O_RDWR | os.O_CREAT)
    except OSError as error:
        raise PickerError("Die Desktop-Sitzung ist nicht verfügbar.") from error
    try:
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise PickerError("Ein Emoji wird bereits eingefügt.") from error
        yield
    finally:
        os.close(fd)


def insert(request: dict, allowed: set[str]) -> dict:
    emoji = request.get("emoji")
    if not isinstance(emoji, str) or emoji not in allowed:
        raise PickerError("Bitte wähle ein Emoji aus dem Katalog.")
    if not shutil.which("wl-copy"):
        raise PickerError("wl-copy ist nicht installiert.")
    keep_open = request.get("keepOpen") is True
    if keep_open and request.get("inputReleased") is not True:
        raise PickerError("Der Emoji-Picker hat den Tastaturfokus noch nicht freigegeben.")
    with insertion_lock():
        hypr = None
        paste_error = None
        # Check before touching the clipboard as well as immediately before key
        # delivery. An invalid target still permits the documented copy fallback.
        try:
            hypr = Hyprland()
            target = validate_target(request.get("target"), hypr)
            assert_unlocked(hypr)
            assert_original_focus(hypr, target, allow_unfocused=not keep_open)
        except PickerError as error:
            paste_error = str(error)
        environment = dict(os.environ)
        environment.pop("WAYLAND_DEBUG", None)
        # wl-copy forks its owner and returns only after the new selection is
        # ready. Paste never races a separate fire-and-forget clipboard process.
        result = subprocess.run(["wl-copy", "--type", "text/plain;charset=utf-8"],
                                input=emoji.encode("utf-8"), stdout=subprocess.DEVNULL,
                                stderr=subprocess.DEVNULL, env=environment, timeout=3, check=False)
        if result.returncode:
            raise PickerError("Die Zwischenablage ist nicht verfügbar.")
        answer = {"ok": True, "copied": True, "inserted": False}
        try:
            answer["recents"] = remember(emoji, allowed)
        except (OSError, PickerError):
            answer["recents"] = [emoji]
            answer["warning"] = "Die zuletzt benutzten Emojis konnten nicht gespeichert werden."
        try:
            if paste_error:
                raise PickerError(paste_error)
            if hypr is None:
                raise PickerError("Keine aktive Hyprland-Sitzung gefunden; das Emoji wurde kopiert.")
            paste_to_original(request.get("target"), hypr, keep_open=keep_open)
            answer["inserted"] = True
        except PickerError as error:
            answer["message"] = str(error)
        return answer


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("capture")
    sub.add_parser("catalog")
    sub.add_parser("recents")
    insert_parser = sub.add_parser("insert")
    insert_parser.add_argument("--request", help="JSON object; reads bounded stdin when omitted")
    args = parser.parse_args()
    try:
        if args.command == "capture":
            hypr = Hyprland()
            target = window_identity(hypr.query("activewindow"), hypr.instance)
            output({"ok": True, "target": target})
        elif args.command == "recents":
            output({"ok": True, "recents": read_recents(allowed_emojis())})
        elif args.command == "catalog":
            output({"ok": True, "emojis": load_catalog()})
        else:
            raw = args.request if args.request is not None else sys.stdin.buffer.read(MAX_JSON_BYTES + 1)
            if len(raw) > MAX_JSON_BYTES:
                raise PickerError("Die Emoji-Anfrage ist zu groß.")
            request = json.loads(raw)
            if not isinstance(request, dict):
                raise PickerError("Die Emoji-Anfrage hat ein ungültiges Format.")
            output(insert(request, allowed_emojis()))
        return 0
    except (PickerError, OSError, ValueError, subprocess.SubprocessError) as error:
        message = str(error) if isinstance(error, PickerError) else "Der Emoji-Picker ist gerade nicht verfügbar."
        output({"ok": False, "copied": False, "inserted": False, "message": message})
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
