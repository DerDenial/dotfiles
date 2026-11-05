#!/usr/bin/env python3
"""Explicit, validated Hyprland window preferences with reversible persistence.

Reads do not change layouts. Writes use the live compositor and keep generated
Lua separate from the user's base configuration. The saved file is loaded with
dofile, so changing one preference does not require a compositor-wide reload.
"""
from __future__ import annotations

import concurrent.futures
from contextlib import contextmanager
import fcntl
import json
import math
import os
from pathlib import Path
import signal
import stat
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parent
STATE = ROOT / "window-preferences.json"
LUA = ROOT / "window-overrides.lua"
LOCK = ROOT / ".window-preferences.lock"
TIMEOUT = 1.5
LAYOUTS = ("scrolling", "dwindle", "master", "monocle")
# name: (IPC option, Lua category, field, type, allowed enum or native limits)
OPTIONS = {
    "layout": ("general:layout", "general", "layout", str, LAYOUTS),
    "columnWidth": ("scrolling:column_width", "scrolling", "column_width", float, (0.1, 1.0)),
    "singleColumnFull": ("scrolling:fullscreen_on_one_column", "scrolling", "fullscreen_on_one_column", bool, None),
    "scrollDirection": ("scrolling:direction", "scrolling", "direction", str, ("right", "left", "down", "up")),
    "masterRatio": ("master:mfact", "master", "mfact", float, (0.0, 1.0)),
    "newWindowPosition": ("master:new_status", "master", "new_status", str, ("master", "slave", "inherit")),
    "preserveSplit": ("dwindle:preserve_split", "dwindle", "preserve_split", bool, None),
}


class PreferenceError(Exception):
    pass


def validate(key, value):
    if key not in OPTIONS:
        raise PreferenceError("Unknown window preference.")
    kind, limits = OPTIONS[key][3:]
    if kind is bool:
        if type(value) is not bool:
            raise PreferenceError("This preference requires an on/off value.")
    elif kind is str:
        if type(value) is not str or value not in limits:
            raise PreferenceError("This window option is not supported.")
    elif isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value) or not limits[0] <= value <= limits[1]:
        raise PreferenceError("The value is outside its supported range.")
    return float(value) if kind is float else value


def run(arguments):
    try:
        result = subprocess.run(arguments, capture_output=True, text=True, timeout=TIMEOUT, check=False)
    except (OSError, subprocess.TimeoutExpired) as error:
        raise PreferenceError("The compositor is not responding. Please try again.") from error
    if result.returncode:
        raise PreferenceError("The compositor did not accept this request.")
    if len(result.stdout) > 65536:
        raise PreferenceError("The compositor response was invalid.")
    return result.stdout.strip()


def read_option(key):
    try:
        info = json.loads(run(["hyprctl", "-j", "getoption", OPTIONS[key][0]]))
        if not isinstance(info, dict):
            raise ValueError("Invalid option")
        kind = OPTIONS[key][3]
        if kind is str:
            value = info.get("str", info.get("string", info.get("current")))
        elif kind is float:
            value = info.get("float", info.get("current"))
        else:
            value = info.get("bool", info.get("int", info.get("current")))
            if type(value) is int and value in (0, 1):
                value = bool(value)
        return key, validate(key, value)
    except (PreferenceError, ValueError, TypeError):
        return key, None


def read_options(keys=OPTIONS):
    keys = list(keys)
    if not keys:
        return {}
    with concurrent.futures.ThreadPoolExecutor(max_workers=len(keys)) as executor:
        return dict(executor.map(read_option, keys))


def same(left, right):
    if type(left) is bool or type(right) is bool:
        return type(left) is type(right) and left == right
    if isinstance(left, (int, float)) and isinstance(right, (int, float)):
        return math.isclose(left, right, rel_tol=1e-5, abs_tol=1e-5)
    return type(left) is type(right) and left == right


def load():
    if not STATE.exists():
        return {"schema": 1, "values": {}, "original": {}}
    if STATE.is_symlink() or STATE.stat().st_size > 65536:
        raise PreferenceError("The saved window preferences are invalid.")
    try:
        data = json.loads(STATE.read_text())
        if not isinstance(data, dict) or data.get("schema") != 1:
            raise ValueError("Invalid preferences")
        values, original = data["values"], data["original"]
        if not isinstance(values, dict) or not isinstance(original, dict) or values.keys() != original.keys():
            raise ValueError("Invalid preference history")
        return {"schema": 1,
                "values": {key: validate(key, value) for key, value in values.items()},
                "original": {key: validate(key, value) for key, value in original.items()}}
    except (OSError, ValueError, TypeError, KeyError, PreferenceError) as error:
        raise PreferenceError("The saved window preferences could not be read.") from error


def lua_for(values):
    groups = {}
    for key in OPTIONS:
        if key not in values:
            continue
        value = validate(key, values[key])
        _, group, field, kind, _ = OPTIONS[key]
        encoded = "true" if value is True else "false" if value is False else json.dumps(value, allow_nan=False)
        groups.setdefault(group, []).append(field + " = " + encoded)
    if not groups:
        return ""
    return "hl.config({ " + ", ".join(group + " = { " + ", ".join(fields) + " }" for group, fields in groups.items()) + " })"


def eval_lua(source):
    # Lua runtime errors may exit with code 0. Only the exact native ack succeeds.
    if run(["hyprctl", "eval", source]) != "ok":
        raise PreferenceError("The compositor could not apply this window preference.")


def apply(values, prepare_edge=False):
    source = lua_for(values)
    if not source:
        return
    if prepare_edge:
        source = 'require("modules.edge-mode").prepareLayoutChange(); ' + source
    eval_lua(source)


def check_applied(wanted):
    actual = read_options(wanted)
    if any(actual[key] is None or not same(actual[key], value) for key, value in wanted.items()):
        raise PreferenceError("The compositor did not confirm the new window setting.")


def snapshot_files():
    result = {}
    for path in (STATE, LUA):
        if path.is_symlink():
            raise PreferenceError("The saved window preference path is invalid.")
        result[path] = (path.read_bytes(), stat.S_IMODE(path.stat().st_mode)) if path.exists() else (None, 0o600)
    return result


def atomic(path, content, mode=0o600):
    fd, temporary = tempfile.mkstemp(prefix="." + path.name + "-", dir=ROOT)
    try:
        with os.fdopen(fd, "wb") as output:
            output.write(content)
            output.flush()
            os.fsync(output.fileno())
        os.chmod(temporary, mode)
        os.replace(temporary, path)
    finally:
        Path(temporary).unlink(missing_ok=True)


def restore_files(previous):
    for path, (content, mode) in previous.items():
        if content is None:
            path.unlink(missing_ok=True)
        else:
            atomic(path, content, mode)


def save(data, previous):
    source = "-- Managed by Settings > Windows. Restore in Settings to remove these overrides.\n"
    source += lua_for(data["values"]) + "\n"
    atomic(STATE, (json.dumps(data, indent=2, allow_nan=False) + "\n").encode(), previous[STATE][1])
    atomic(LUA, source.encode(), previous[LUA][1])


@contextmanager
def writer_lock():
    try:
        descriptor = os.open(LOCK, os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o600)
    except OSError as error:
        raise PreferenceError("Window preferences cannot be saved right now.") from error
    try:
        try:
            fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise PreferenceError("Another window preference is being saved. Please try again.") from error
        yield
    finally:
        os.close(descriptor)


def update(wanted, data):
    wanted = {key: validate(key, value) for key, value in wanted.items()}
    previous = read_options(wanted)
    if any(value is None for value in previous.values()):
        raise PreferenceError("These window settings are not available from the running compositor.")
    changes = {key: value for key, value in wanted.items() if not same(value, previous[key])}
    layout_change = "layout" in changes
    files_before = snapshot_files()
    attempted = False
    saved = False
    try:
        if changes:
            attempted = True
            apply(changes, prepare_edge=layout_change)
            check_applied(changes)
        saved = True
        save(data, files_before)
        if layout_change:
            eval_lua('require("modules.edge-mode").commitLayoutChange()')
    except BaseException as error:
        # A closed Settings page may terminate its helper. Finish rollback even
        # then, so a cancelled write cannot leave an unsaved live layout behind.
        signal_handlers = {}
        for name in (signal.SIGTERM, signal.SIGINT):
            signal_handlers[name] = signal.signal(name, signal.SIG_IGN)
        failures = []
        try:
            if saved:
                try:
                    restore_files(files_before)
                except OSError:
                    failures.append("saved files")
            if attempted:
                try:
                    apply({key: previous[key] for key in changes})
                except PreferenceError:
                    failures.append("live settings")
            if layout_change and attempted:
                try:
                    eval_lua('require("modules.edge-mode").restoreLayoutChange()')
                except PreferenceError:
                    failures.append("expanded windows")
        finally:
            for name, handler in signal_handlers.items():
                signal.signal(name, handler)
        if failures:
            raise PreferenceError("The change failed and could not fully restore " + ", ".join(failures) + ". Please reload Hyprland.") from error
        if isinstance(error, PreferenceError):
            raise
        if not isinstance(error, OSError):
            raise
        raise PreferenceError("Window preferences could not be saved; the previous settings were restored.") from error


def main(arguments=None):
    arguments = sys.argv[1:] if arguments is None else arguments
    action = arguments[0] if arguments else "get"
    if action == "get":
        values = read_options()
        result = {"available": any(value is not None for value in values.values()),
                  "values": values, "changed": 0, "layouts": list(LAYOUTS)}
        try:
            result["changed"] = len(load()["values"])
        except PreferenceError as error:
            result["error"] = str(error)
        return result
    if action not in ("set", "reset"):
        raise PreferenceError("Unknown window preference action.")
    with writer_lock():
        data = load()
        if action == "set":
            if len(arguments) != 3:
                raise PreferenceError("Choose one window preference and value.")
            key = arguments[1]
            try:
                value = validate(key, json.loads(arguments[2]))
            except (ValueError, TypeError) as error:
                raise PreferenceError("The window preference value is invalid.") from error
            _, previous = read_option(key)
            if previous is None:
                raise PreferenceError("This setting is not available from the running compositor.")
            if key not in data["values"] and same(previous, value):
                return {"ok": True}
            data["original"].setdefault(key, previous)
            if same(value, data["original"][key]):
                data["values"].pop(key, None)
                data["original"].pop(key, None)
            else:
                data["values"][key] = value
            update({key: value}, data)
        else:
            update(data["original"], {"schema": 1, "values": {}, "original": {}})
        return {"ok": True}


if __name__ == "__main__":
    def cancelled(_number, _frame):
        raise PreferenceError("The window preference change was cancelled.")
    signal.signal(signal.SIGTERM, cancelled)
    signal.signal(signal.SIGINT, cancelled)
    try:
        print(json.dumps(main(), allow_nan=False))
    except (PreferenceError, OSError, ValueError) as error:
        print(json.dumps({"ok": False, "error": str(error)[:240]}))
        raise SystemExit(1)
