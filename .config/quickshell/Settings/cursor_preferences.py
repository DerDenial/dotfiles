#!/usr/bin/env python3
"""Installed Xcursor themes, bounded previews and reversible desktop preferences.

The only live mutation entry points are ``set THEME SIZE`` and ``apply``.
Listing reads installed themes and may populate the small PNG preview cache.
"""
from __future__ import annotations

from contextlib import contextmanager
from dataclasses import dataclass
import configparser
import fcntl
import hashlib
import io
import json
import os
from pathlib import Path
import re
import shutil
import signal
import stat
import struct
import subprocess
import sys
import tempfile
import time
import zlib


SIZES = (16, 24, 32, 40, 48, 64)
DEFAULT = {"theme": "Bibata-Modern-Ice", "size": 24}
SCHEMA = "org.gnome.desktop.interface"
IMAGE_TYPE = 0xFFFD0002
MAX_FILE = 16 * 1024 * 1024
MAX_DIMENSION = 256
MAX_THEMES = 256
THEME_ID = re.compile(r"[A-Za-z0-9][A-Za-z0-9_.+ -]{0,127}\Z")


class PreferenceError(Exception):
    pass


@dataclass(frozen=True)
class Paths:
    home: Path
    config: Path
    data: Path
    cache: Path
    settings: Path
    roots: tuple[Path, ...]
    lock: Path

    @property
    def state(self):
        return self.settings / "cursor-preferences.json"


def paths_from_environment():
    home = Path.home()
    config = Path(os.environ.get("XDG_CONFIG_HOME", home / ".config"))
    data = Path(os.environ.get("XDG_DATA_HOME", home / ".local/share"))
    cache = Path(os.environ.get("XDG_CACHE_HOME", home / ".cache"))
    system_roots = [Path(root) / "icons" for root in os.environ.get(
        "XDG_DATA_DIRS", "/usr/local/share:/usr/share").split(":") if root.startswith("/")]
    roots = tuple(dict.fromkeys([data / "icons", home / ".icons", *system_roots]))
    runtime = Path(os.environ.get("XDG_RUNTIME_DIR", tempfile.gettempdir()))
    return Paths(home, config, data, cache, Path(__file__).resolve().parent, roots,
                 runtime / ("quickshell-appearance-" + str(os.getuid()) + ".lock"))


def bounded_read(path, limit=MAX_FILE):
    with path.open("rb") as source:
        data = source.read(limit + 1)
    if len(data) > limit:
        raise ValueError("File exceeds the cursor preview limit")
    return data


def cursor_image(path, wanted_size=48):
    """Decode one Xcursor ARGB frame, without opening a display or loading code."""
    data = bounded_read(path)
    if len(data) < 16:
        raise ValueError("Truncated Xcursor header")
    magic, header, version, count = struct.unpack_from("<4I", data)
    if magic != 0x72756358 or not 16 <= header <= len(data) or count > 4096:
        raise ValueError("Invalid Xcursor header")
    if header + count * 12 > len(data):
        raise ValueError("Truncated Xcursor table")
    images = []
    for index in range(count):
        kind, size, offset = struct.unpack_from("<3I", data, header + index * 12)
        if kind == IMAGE_TYPE and 1 <= size <= MAX_DIMENSION:
            images.append((abs(size - wanted_size), index, size, offset))
    if not images:
        raise ValueError("No supported cursor image")
    sizes = sorted({entry[2] for entry in images})
    for _, _, size, offset in sorted(images):
        if offset + 36 > len(data):
            continue
        length, kind, subtype, chunk_version, width, height, xhot, yhot, delay = struct.unpack_from("<9I", data, offset)
        if (kind != IMAGE_TYPE or subtype != size or length < 36
                or not 1 <= width <= MAX_DIMENSION or not 1 <= height <= MAX_DIMENSION
                or xhot >= width or yhot >= height):
            continue
        start, end = offset + length, offset + length + width * height * 4
        if start > len(data) or end > len(data):
            continue
        rgba = bytearray(width * height * 4)
        for index, (pixel,) in enumerate(struct.iter_unpack("<I", data[start:end])):
            alpha = pixel >> 24
            red, green, blue = (pixel >> 16) & 255, (pixel >> 8) & 255, pixel & 255
            # Xcursor pixels are premultiplied; PNG stores straight alpha.
            if alpha:
                red, green, blue = (min(255, (value * 255 + alpha // 2) // alpha)
                                    for value in (red, green, blue))
            else:
                red = green = blue = 0
            rgba[index * 4:index * 4 + 4] = bytes((red, green, blue, alpha))
        return width, height, bytes(rgba), sizes
    raise ValueError("No valid cursor image")


def png_bytes(width, height, rgba):
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)
    rows = b"".join(b"\0" + rgba[row * width * 4:(row + 1) * width * 4]
                    for row in range(height))
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">2I5B", width, height, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(rows, 6)) + chunk(b"IEND", b""))


def atomic_write(path, content, mode=0o644):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix="." + path.name + "-", dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as output:
            output.write(content)
            output.flush()
            os.fsync(output.fileno())
        os.chmod(temporary, mode)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def theme_catalog(paths):
    entries, seen = [], set()
    for root in paths.roots:
        try:
            children = sorted(root.iterdir(), key=lambda value: value.name.casefold())
        except OSError:
            continue
        for directory in children:
            identifier = directory.name
            if identifier in seen or not THEME_ID.fullmatch(identifier) or not (directory / "cursors").is_dir():
                continue
            # The first installed directory wins exactly as in Xcursor's lookup.
            seen.add(identifier)
            decoded = None
            source = None
            for pointer in ("left_ptr", "default", "arrow", "top_left_arrow"):
                try:
                    source = directory / "cursors" / pointer
                    decoded = cursor_image(source)
                    break
                except (OSError, ValueError, struct.error):
                    continue
            if decoded is None:
                continue
            name = identifier
            try:
                index = configparser.ConfigParser(interpolation=None, strict=False)
                index.read_string(bounded_read(directory / "index.theme", 128 * 1024).decode("utf-8"))
                candidate = index.get("Icon Theme", "Name", fallback=identifier)
                if candidate.strip() and len(candidate) < 160:
                    name = " ".join(candidate.split())
            except (OSError, ValueError, UnicodeError, configparser.Error):
                pass
            width, height, rgba, native_sizes = decoded
            digest = hashlib.sha256(str(source.resolve()).encode() + rgba + struct.pack("<2I", width, height)).hexdigest()[:24]
            preview = paths.cache / "quickshell/cursors" / (digest + ".png")
            preview_url = ""
            try:
                if not preview.is_file():
                    atomic_write(preview, png_bytes(width, height, rgba))
                preview_url = preview.as_uri()
            except OSError:
                pass
            entries.append({"id": identifier, "name": name, "preview": preview_url,
                            "sizes": list(SIZES), "nativeSizes": native_sizes})
            if len(entries) >= MAX_THEMES:
                return sorted(entries, key=lambda value: value["name"].casefold())
    return sorted(entries, key=lambda value: value["name"].casefold())


def saved_selection(paths):
    try:
        value = json.loads(bounded_read(paths.state, 16384))
        if (isinstance(value, dict) and type(value.get("theme")) is str
                and THEME_ID.fullmatch(value["theme"]) and type(value.get("size")) is int
                and value["size"] in SIZES):
            return {"theme": value["theme"], "size": value["size"]}
    except (OSError, ValueError, TypeError):
        pass
    return None


def current_selection(paths, catalog):
    saved = saved_selection(paths)
    if saved:
        return saved
    identifiers = {entry["id"] for entry in catalog}
    theme = os.environ.get("XCURSOR_THEME") or os.environ.get("HYPRCURSOR_THEME") or DEFAULT["theme"]
    if theme not in identifiers:
        theme = DEFAULT["theme"] if DEFAULT["theme"] in identifiers else next(iter(catalog), {}).get("id", "")
    try:
        size = int(os.environ.get("XCURSOR_SIZE", "24"))
    except ValueError:
        size = 24
    return {"theme": theme, "size": size if size in SIZES else 24}


def describe(paths, catalog=None, warnings=(), error=""):
    catalog = theme_catalog(paths) if catalog is None else catalog
    current = current_selection(paths, catalog)
    notices = list(warnings)
    if saved_selection(paths) and current["theme"] not in {entry["id"] for entry in catalog}:
        notices.append("The saved cursor theme is no longer installed. Choose an installed theme.")
    return {"themes": catalog, "current": current, "saved": saved_selection(paths) is not None,
            "warnings": notices, "error": error}


def run(arguments, *, timeout=3):
    try:
        result = subprocess.run(arguments, capture_output=True, text=True, timeout=timeout, check=False)
    except (OSError, subprocess.TimeoutExpired) as error:
        raise PreferenceError("A desktop service did not respond. Please try again.") from error
    if len(result.stdout) + len(result.stderr) > 65536:
        raise PreferenceError("A desktop service returned an invalid response.")
    if result.returncode:
        raise PreferenceError("A desktop service did not accept the cursor setting.")
    return result


def native_cursor(selection):
    # setcursor reloads the cursor manager, but it does not update the process
    # environment inherited by newly launched applications. Native Lua env calls
    # update that environment without reloading the whole desktop configuration.
    values = {"XCURSOR_THEME": selection["theme"], "XCURSOR_SIZE": str(selection["size"]),
              "HYPRCURSOR_THEME": selection["theme"], "HYPRCURSOR_SIZE": str(selection["size"])}
    code = "; ".join("hl.env(" + json.dumps(key) + ", " + json.dumps(value) + ")"
                     for key, value in values.items())
    result = run(["hyprctl", "eval", code])
    if result.stdout.strip().lower() != "ok":
        raise PreferenceError("Hyprland did not confirm the app-launch environment change.")
    result = run(["hyprctl", "setcursor", selection["theme"], str(selection["size"])])
    if result.stdout.strip().lower() != "ok":
        raise PreferenceError("Hyprland did not confirm the cursor change. Your previous selection was kept.")


@contextmanager
def appearance_lock(paths):
    paths.lock.parent.mkdir(parents=True, exist_ok=True)
    with paths.lock.open("a") as handle:
        deadline = time.monotonic() + 20
        while True:
            try:
                fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                if time.monotonic() >= deadline:
                    raise PreferenceError("Another appearance change is still running. Please try again.")
                time.sleep(0.05)
        try:
            yield
        finally:
            fcntl.flock(handle, fcntl.LOCK_UN)


def text_at(path):
    try:
        return bounded_read(path, 2 * 1024 * 1024).decode("utf-8")
    except FileNotFoundError:
        return ""


def replace_lines(text, replacements):
    for pattern, replacement in replacements:
        expression = re.compile(pattern, re.M)
        if expression.search(text):
            text = expression.sub(lambda match: replacement, text)
        else:
            text = text.rstrip() + ("\n" if text.strip() else "") + replacement + "\n"
    return text


def gtk_ini(text, selection):
    parser = configparser.ConfigParser(interpolation=None, strict=False)
    parser.optionxform = str
    if text.strip():
        parser.read_string(text)
    if "Settings" not in parser:
        parser["Settings"] = {}
    parser["Settings"]["gtk-cursor-theme-name"] = selection["theme"]
    parser["Settings"]["gtk-cursor-theme-size"] = str(selection["size"])
    output = io.StringIO()
    parser.write(output)
    return output.getvalue()


def generated_files(paths, selection):
    theme, size = selection["theme"], str(selection["size"])
    result = {}
    result[paths.state] = json.dumps({"theme": theme, "size": selection["size"]}, indent=2) + "\n"
    values = {"XCURSOR_THEME": theme, "XCURSOR_SIZE": size,
              "HYPRCURSOR_THEME": theme, "HYPRCURSOR_SIZE": size}
    result[paths.settings / "cursor-overrides.lua"] = ("-- Generated by the Settings cursor switcher.\n"
        + "".join("hl.env(" + json.dumps(key) + ", " + json.dumps(value) + ")\n" for key, value in values.items()))
    result[paths.config / "environment.d/90-quickshell-cursor.conf"] = ("# Generated by the Settings cursor switcher.\n"
        + "".join(key + "=" + json.dumps(value) + "\n" for key, value in values.items()))
    for version in (3, 4):
        path = paths.config / f"gtk-{version}.0/settings.ini"
        result[path] = gtk_ini(text_at(path), selection)
    for path in (paths.config / "gtk-2.0/gtkrc", paths.home / ".gtkrc-2.0"):
        if path.name == ".gtkrc-2.0" and not path.exists():
            continue
        result[path] = replace_lines(text_at(path), [
            (r'^\s*gtk-cursor-theme-name\s*=.*$', 'gtk-cursor-theme-name="' + theme + '"'),
            (r'^\s*gtk-cursor-theme-size\s*=.*$', 'gtk-cursor-theme-size=' + size)])
    path = paths.config / "xsettingsd/xsettingsd.conf"
    result[path] = replace_lines(text_at(path), [
        (r'^\s*Gtk/CursorThemeName\s+.*$', 'Gtk/CursorThemeName "' + theme + '"'),
        (r'^\s*Gtk/CursorThemeSize\s+.*$', 'Gtk/CursorThemeSize ' + size)])
    defaults = [paths.data / "icons/default/index.theme"]
    if (paths.home / ".icons/default").is_dir():
        defaults.append(paths.home / ".icons/default/index.theme")
    for path in dict.fromkeys(defaults):
        parser = configparser.ConfigParser(interpolation=None, strict=False)
        parser.optionxform = str
        old = text_at(path)
        if old.strip():
            parser.read_string(old)
        if "Icon Theme" not in parser:
            parser["Icon Theme"] = {}
        parser["Icon Theme"]["Inherits"] = theme
        output = io.StringIO()
        parser.write(output)
        result[path] = output.getvalue()
    return {path: text.encode("utf-8") for path, text in result.items()}


def notify_toolkits(selection):
    warnings = []
    if shutil.which("gsettings"):
        previous = {}
        changed = []
        try:
            for key in ("cursor-theme", "cursor-size"):
                previous[key] = run(["gsettings", "get", SCHEMA, key]).stdout.strip()
            for key, value in (("cursor-theme", json.dumps(selection["theme"])),
                               ("cursor-size", str(selection["size"]))):
                result = run(["gsettings", "set", SCHEMA, key, value])
                changed.append(key)
                if re.search(r"failed|error", result.stderr, re.I):
                    raise PreferenceError("GTK settings could not be committed")
            theme = run(["gsettings", "get", SCHEMA, "cursor-theme"]).stdout.strip()
            size = run(["gsettings", "get", SCHEMA, "cursor-size"]).stdout.strip()
            # GVariant string output uses single quotes and escapes; IDs exclude quotes.
            if theme not in (json.dumps(selection["theme"]), "'" + selection["theme"] + "'") or size != str(selection["size"]):
                raise PreferenceError("GTK settings did not confirm the change")
        except PreferenceError:
            for key in reversed(changed):
                try:
                    run(["gsettings", "set", SCHEMA, key, previous[key]])
                except PreferenceError:
                    pass
            warnings.append("GTK's live settings service could not be updated. Reopen affected apps or sign out and back in.")
    else:
        warnings.append("GTK's live settings service is unavailable. Reopen affected apps to use the saved cursor.")
    if shutil.which("pgrep") and shutil.which("pkill"):
        try:
            # pgrep's no-match result is normal and must not start a new daemon.
            result = subprocess.run(["pgrep", "-u", str(os.getuid()), "-x", "xsettingsd"],
                                    capture_output=True, text=True, timeout=2, check=False)
            if result.returncode == 0:
                run(["pkill", "-HUP", "-u", str(os.getuid()), "-x", "xsettingsd"])
        except (PreferenceError, OSError, subprocess.TimeoutExpired):
            warnings.append("Some X11 applications may need reopening to update their cursor.")
    if shutil.which("dbus-update-activation-environment"):
        try:
            run(["dbus-update-activation-environment", "--systemd",
                 "XCURSOR_THEME=" + selection["theme"], "XCURSOR_SIZE=" + str(selection["size"]),
                 "HYPRCURSOR_THEME=" + selection["theme"], "HYPRCURSOR_SIZE=" + str(selection["size"])])
        except PreferenceError:
            warnings.append("The app-launch environment will use this cursor after the next login.")
    return warnings


def set_selection(paths, theme, size, *, catalog=None, native=native_cursor, notify=notify_toolkits):
    catalog = theme_catalog(paths) if catalog is None else catalog
    if type(theme) is not str or not THEME_ID.fullmatch(theme) or theme not in {item["id"] for item in catalog}:
        raise PreferenceError("Choose an installed cursor theme.")
    if type(size) is not int or size not in SIZES:
        raise PreferenceError("Choose a cursor size between 16 and 64 pixels.")
    selection = {"theme": theme, "size": size}
    with appearance_lock(paths):
        previous = current_selection(paths, catalog)
        try:
            proposed = generated_files(paths, selection)
        except (OSError, UnicodeError, configparser.Error, ValueError) as error:
            raise PreferenceError("Could not read the existing appearance settings. Nothing was changed.") from error
        originals = {}
        for path in proposed:
            if path.is_symlink():
                raise PreferenceError("A cursor settings file is linked elsewhere. Resolve that link before changing it here.")
            try:
                originals[path] = (path.read_bytes(), stat.S_IMODE(path.stat().st_mode))
            except FileNotFoundError:
                originals[path] = (None, 0o644)
        written = []
        native_changed = False
        try:
            # Even a failed native call may have applied its environment update
            # before the cursor reload failed; always attempt native rollback.
            native_changed = True
            native(selection)
            for path, content in proposed.items():
                if originals[path][0] != content:
                    # Journal before replacement: a termination arriving just
                    # after os.replace must still restore this exact file.
                    written.append(path)
                    atomic_write(path, content, originals[path][1])
            for path, content in proposed.items():
                if path.read_bytes() != content:
                    raise OSError("Cursor settings changed while saving")
        except BaseException as error:
            recovery_failed = False
            for path in reversed(written):
                content, mode = originals[path]
                try:
                    if content is None:
                        path.unlink(missing_ok=True)
                    else:
                        atomic_write(path, content, mode)
                except OSError:
                    recovery_failed = True
            if native_changed:
                try:
                    native(previous)
                except PreferenceError:
                    recovery_failed = True
            if recovery_failed:
                raise PreferenceError("The cursor change failed and could not be fully restored. Reopen Appearance and apply a selection again.") from error
            if isinstance(error, PreferenceError):
                raise
            raise PreferenceError("Could not save the cursor setting. The previous selection was restored.") from error
        warnings = notify(selection)
    result = describe(paths, catalog, warnings)
    result["ok"] = True
    return result


def main(arguments=None, paths=None):
    paths = paths or paths_from_environment()
    arguments = sys.argv[1:] if arguments is None else arguments
    try:
        catalog = theme_catalog(paths)
        if arguments == ["get"]:
            result = describe(paths, catalog)
        elif len(arguments) == 3 and arguments[0] == "set":
            try:
                size = int(arguments[2])
            except ValueError as error:
                raise PreferenceError("Choose a supported cursor size.") from error
            result = set_selection(paths, arguments[1], size, catalog=catalog)
        elif arguments == ["apply"]:
            selection = saved_selection(paths) or DEFAULT
            result = set_selection(paths, selection["theme"], selection["size"], catalog=catalog)
        else:
            raise PreferenceError("Usage: cursor_preferences.py get | set THEME SIZE | apply")
        print(json.dumps(result, ensure_ascii=False))
        return 0
    except (PreferenceError, OSError, ValueError) as error:
        result = {"ok": False, "error": str(error), "warnings": []}
        print(json.dumps(result, ensure_ascii=False))
        return 1


if __name__ == "__main__":
    def interrupted(signum, frame):
        raise PreferenceError("The cursor change was interrupted. Please try again.")
    signal.signal(signal.SIGTERM, interrupted)
    raise SystemExit(main())
