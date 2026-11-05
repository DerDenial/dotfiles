#!/usr/bin/env python3
"""One-shot, read-only shortcut catalogue for the Quickshell overview.

Live key combinations come from Hyprland's JSON socket. Lua callbacks are
opaque in that API, so their friendly names can be enriched from the current
configuration, matched by exact keys and flags. No Lua or shell is evaluated.
No commands, paths, session identifiers or callback references leave this file.
"""

from __future__ import annotations

from dataclasses import dataclass, replace
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import socket
import stat
import sys


MAX_SOURCE_BYTES = 512 * 1024
MAX_REPLY_BYTES = 2 * 1024 * 1024
MAX_BINDS = 2048
INSTANCE = re.compile(r"[a-zA-Z0-9_.-]{1,240}\Z")
CONFIG = Path(os.environ.get("XDG_CONFIG_HOME", str(Path.home() / ".config")))
GROUPS = (
    ("apps", "Apps & tools", "apps"),
    ("windows", "Windows", "web_asset"),
    ("workspaces", "Workspaces", "view_carousel"),
    ("system", "Media & system", "tune"),
)
MODS = ((64, "Super"), (4, "Ctrl"), (8, "Alt"), (1, "Shift"),
        (2, "Caps"), (16, "Mod2"), (32, "Mod3"), (128, "Mod5"))
MOD_NAMES = {"SUPER": 64, "WIN": 64, "LOGO": 64, "MOD4": 64, "META": 64,
             "CTRL": 4, "CONTROL": 4, "ALT": 8, "MOD1": 8, "SHIFT": 1,
             "CAPS": 2, "MOD2": 16, "MOD3": 32, "MOD5": 128}
KEY_NAMES = {
    "return": "Enter", "kp_enter": "Num Enter", "space": "Space",
    "escape": "Esc", "backspace": "Backspace", "tab": "Tab",
    "left": "←", "right": "→", "up": "↑", "down": "↓",
    "period": ".", "comma": ",", "minus": "−", "plus": "+",
    "slash": "/", "backslash": "\\", "print": "Print",
    "mouse_down": "Scroll ↓", "mouse_up": "Scroll ↑",
    "mouse_left": "Scroll ←", "mouse_right": "Scroll →",
    "mouse:272": "Left mouse", "mouse:273": "Right mouse",
    "mouse:274": "Middle mouse", "xf86audioraisevolume": "Vol +",
    "xf86audiolowervolume": "Vol −", "xf86audiomute": "Mute",
    "xf86audiomicmute": "Mic mute", "xf86monbrightnessup": "Brightness +",
    "xf86monbrightnessdown": "Brightness −", "xf86audionext": "Next track",
    "xf86audioprev": "Previous track", "xf86audioplay": "Play",
    "xf86audiopause": "Pause",
}


class CatalogError(Exception):
    pass


@dataclass(frozen=True)
class Action:
    group: str = "apps"
    label: str = "Custom action"
    family: str = "custom"
    target: str = ""


@dataclass(frozen=True)
class Binding:
    mask: int
    key: str
    action: Action
    description: str = ""
    submap: str = ""
    release: bool = False
    long_press: bool = False
    mouse: bool = False
    count: int = 1
    display_key: str = ""
    config_label: bool = False

    def identity(self) -> tuple:
        return self.mask, self.key.casefold(), self.submap, self.release, self.long_press

    def partition(self) -> tuple:
        return self.mask, self.submap, self.release, self.long_press, self.mouse


def clean(value, limit: int = 120) -> str:
    if not isinstance(value, str):
        return ""
    return " ".join("".join(c for c in value if c.isprintable()).split())[:limit]


def live_bindings() -> list[dict]:
    signature = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE", "")
    if not INSTANCE.fullmatch(signature) or signature in {".", ".."}:
        raise CatalogError("No active Hyprland session.")
    runtime = Path(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}"))
    path = runtime / "hypr" / signature / ".socket.sock"
    try:
        info = path.stat()
        if not stat.S_ISSOCK(info.st_mode) or info.st_uid != os.getuid():
            raise CatalogError("Hyprland is unavailable.")
        chunks, total = [], 0
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as connection:
            connection.settimeout(0.8)
            connection.connect(str(path))
            connection.sendall(b"j/binds")
            while True:
                chunk = connection.recv(65536)
                if not chunk:
                    break
                total += len(chunk)
                if total > MAX_REPLY_BYTES:
                    raise CatalogError("The shortcut response is too large.")
                chunks.append(chunk)
        data = json.loads(b"".join(chunks))
    except (OSError, UnicodeError, ValueError) as error:
        raise CatalogError("Live shortcuts are temporarily unavailable.") from error
    if not isinstance(data, list) or len(data) > MAX_BINDS:
        raise CatalogError("The shortcut response is invalid.")
    return [row for row in data if isinstance(row, dict) and row.get("enabled") is not False]


def exec_action(command: str) -> Action:
    """Recognise actions without displaying or executing command arguments."""
    try:
        words = shlex.split(command)
    except ValueError:
        return Action(label="Run command", family="exec")
    if not words:
        return Action(label="Run command", family="exec")
    lowered = [word.casefold() for word in words]
    if len(words) >= 5 and lowered[:3] == ["qs", "ipc", "call"]:
        target, method = lowered[3:5]
        tools = {"applauncher": "App launcher", "clipboardhistory": "Clipboard history",
                 "taskmanager": "Task Manager", "hardwarepanel": "Hardware monitor", "networkpanel": "Live network traffic", "speedtest": "Internet speed test",
                 "emojipicker": "Emoji picker", "settingsapp": "Settings",
                 "quicknotes": "Quick notes", "quicksettings": "Quick settings",
                 "notificationcenter": "Notifications",
                 "hotkeyoverview": "Keyboard shortcuts", "hotkeys": "Keyboard shortcuts",
                 "hotkeyguide": "Keyboard shortcuts",
                 "themeswitcher": "Themes & wallpapers"}
        if target == "screenshoteditor" and method == "capture":
            return Action("apps", "Capture and edit region", "screenshot")
        if target == "windowbar":
            return Action("windows", "Open windows", "window-bar")
        if target == "powermenu":
            return Action("system", "Power menu", "power-menu")
        if target == "themeswitcher" and method == "randomwallpaper":
            return Action("apps", "Random wallpaper", "random-wallpaper")
        if target in tools:
            return Action("apps", tools[target], target)
    name = Path(words[0]).name.casefold()
    if name == "wpctl":
        if "set-volume" in lowered:
            if any(word.endswith("%+") for word in words):
                return Action("system", "Volume up", "volume", "+")
            if any(word.endswith("%-") for word in words):
                return Action("system", "Volume down", "volume", "-")
        if "set-mute" in lowered:
            microphone = any("audio_source" in word for word in lowered)
            return Action("system", "Mute microphone" if microphone else "Mute sound",
                          "mute-mic" if microphone else "mute-sound")
    if name == "brightnessctl":
        if any(word.endswith("%+") for word in words):
            return Action("system", "Brightness up", "brightness", "+")
        if any(word.endswith("%-") for word in words):
            return Action("system", "Brightness down", "brightness", "-")
    if name == "playerctl" and len(words) > 1:
        method = lowered[1]
        if method in {"next", "previous"}:
            return Action("system", "Next track" if method == "next" else "Previous track",
                          "track", method)
        if method in {"play-pause", "play", "pause", "stop"}:
            return Action("system", {"play-pause": "Play / pause", "play": "Play",
                                     "pause": "Pause", "stop": "Stop playback"}[method],
                          "playback", method)
    if name == "hyprshot":
        return Action("apps", "Capture screen region" if "region" in lowered else "Screenshot", "screenshot")
    if name == "swaync-client":
        return Action("apps", "Notifications", "notifications")
    if any(word.endswith("/LockScreen/lock.py") for word in words):
        return Action("system", "Lock screen", "lock")
    if any(word.endswith("/Logout/launch.py") for word in words):
        return Action("system", "Log out", "logout")
    if any(word.endswith("/waybar/scripts/launch.sh") for word in words):
        return Action("apps", "Restart desktop bar", "bar")
    programs = {"kitty": "Terminal", "alacritty": "Terminal", "foot": "Terminal",
                "nautilus": "File manager", "thunar": "File manager", "dolphin": "File manager",
                "firefox": "Firefox", "codium": "VSCodium", "code": "Visual Studio Code",
                "rofi": "App launcher", "wofi": "App launcher", "fuzzel": "App launcher"}
    if name in programs:
        return Action("apps", programs[name], "program")
    if re.fullmatch(r"[a-zA-Z0-9_+-]{1,40}", name):
        return Action("apps", f"Open {name}", "exec")
    return Action("apps", "Run command", "exec")


def dispatcher_action(dispatcher: str, argument: str) -> Action:
    dispatcher, argument = dispatcher.casefold(), argument.strip()
    if dispatcher in {"exec", "execr", "exec-once"}:
        return exec_action(argument)
    if dispatcher == "workspace":
        return Action("workspaces", "Switch workspace", "workspace", argument)
    if dispatcher in {"movetoworkspace", "movetoworkspacesilent"}:
        return Action("workspaces", "Move window to workspace", dispatcher, argument.split(",", 1)[0])
    if dispatcher == "movefocus":
        directions = {"l": "left", "r": "right", "u": "up", "d": "down"}
        target = directions.get(argument, argument)
        return Action("windows", f"Focus {target}" if target in directions.values() else "Move focus", "focus", target)
    if dispatcher == "movewindow":
        directions = {"l": "left", "r": "right", "u": "up", "d": "down"}
        return Action("windows", "Move window", "window-move", directions.get(argument, argument))
    known = {"killactive": ("windows", "Close focused window"),
             "togglefloating": ("windows", "Toggle floating"), "fullscreen": ("windows", "Toggle fullscreen"),
             "pseudo": ("windows", "Toggle pseudo tiling"), "togglesplit": ("windows", "Toggle split direction"),
             "movewindowpixel": ("windows", "Move window"), "resizewindowpixel": ("windows", "Resize window"),
             "movewindow": ("windows", "Move window"), "resizeactive": ("windows", "Resize window"),
             "togglespecialworkspace": ("workspaces", "Toggle scratchpad"),
             "exit": ("system", "Log out"), "dpms": ("system", "Display power"),
             "submap": ("system", "Change shortcut mode")}
    if dispatcher in known:
        group, label = known[dispatcher]
        return Action(group, label, dispatcher, argument if dispatcher == "togglespecialworkspace" else "")
    return Action()


@dataclass(frozen=True)
class Token:
    value: str
    position: int
    string: bool = False


def lua_tokens(source: str) -> list[Token]:
    """A bounded lexical reader, deliberately not a Lua interpreter."""
    tokens, index, size = [], 0, len(source)
    while index < size:
        char = source[index]
        if char.isspace():
            index += 1
            continue
        if source.startswith("--", index):
            start = index + 2
            long = re.match(r"\[(=*)\[", source[start:])
            if long:
                closer = "]" + long.group(1) + "]"
                end = source.find(closer, start + len(long.group(0)))
                index = size if end < 0 else end + len(closer)
            else:
                end = source.find("\n", start)
                index = size if end < 0 else end + 1
            continue
        if char in {"'", '"'}:
            start, quote, value = index, char, []
            index += 1
            valid = True
            while index < size and source[index] != quote:
                if source[index] == "\\":
                    index += 1
                    if index >= size:
                        valid = False
                        break
                    escape = source[index]
                    values = {"n": "\n", "r": "\r", "t": "\t", "\\": "\\", "'": "'", '"': '"'}
                    if escape not in values:
                        valid = False
                    value.append(values.get(escape, ""))
                else:
                    value.append(source[index])
                index += 1
            if index >= size:
                break
            index += 1
            tokens.append(Token("".join(value) if valid else "", start, True))
            continue
        match = re.match(r"(?:[A-Za-z_][A-Za-z_0-9]*|[0-9]+|\.\.)", source[index:])
        if match:
            value = match.group(0)
            tokens.append(Token(value, index))
            index += len(value)
        else:
            tokens.append(Token(char, index))
            index += 1
    return tokens


def literal(tokens: list[Token], env: dict[str, str | int]) -> str | int | None:
    if not tokens:
        return None
    values = []
    expect_value = True
    for token in tokens:
        if expect_value:
            if token.string:
                value = token.value
            elif token.value.isdecimal():
                value = int(token.value)
            else:
                value = env.get(token.value)
            if value is None:
                return None
            values.append(value)
        elif token.value != "..":
            return None
        expect_value = not expect_value
    if expect_value:
        return None
    return values[0] if len(values) == 1 else "".join(str(value) for value in values)


def split_arguments(tokens: list[Token]) -> list[list[Token]]:
    arguments, current, depth = [], [], 0
    for token in tokens:
        if not token.string:
            if token.value in {"(", "{", "["}:
                depth += 1
            elif token.value in {")", "}", "]"}:
                depth -= 1
            elif token.value == "," and depth == 0:
                arguments.append(current)
                current = []
                continue
        current.append(token)
    arguments.append(current)
    return arguments


def calls(tokens: list[Token], name: tuple[str, ...]):
    for index in range(len(tokens) - len(name)):
        if tuple(token.value for token in tokens[index:index + len(name)]) != name:
            continue
        opening = index + len(name)
        if tokens[opening].value != "(" or tokens[opening].string:
            continue
        depth, end = 1, opening + 1
        while end < len(tokens) and depth:
            token = tokens[end]
            if not token.string:
                depth += token.value == "("
                depth -= token.value == ")"
            end += 1
        if not depth:
            yield tokens[index].position, split_arguments(tokens[opening + 1:end - 1])


def table_value(tokens: list[Token], field: str, env: dict) -> str | int | None:
    for index in range(len(tokens) - 2):
        if tokens[index].value == field and tokens[index + 1].value == "=":
            end = index + 2
            while end < len(tokens) and (tokens[end].string or tokens[end].value not in {",", "}"}):
                end += 1
            return literal(tokens[index + 2:end], env)
    return None


def table_true(tokens: list[Token], field: str) -> bool:
    return any(tuple(token.value for token in tokens[index:index + 3]) == (field, "=", "true")
               for index in range(max(0, len(tokens) - 2)))


def lua_action(tokens: list[Token], env: dict) -> Action:
    for _, arguments in calls(tokens, ("hl", ".", "dsp", ".", "exec_cmd")):
        if arguments and isinstance(command := literal(arguments[0], env), str):
            return exec_action(command)
    for _, arguments in calls(tokens, ("hl", ".", "dsp", ".", "focus")):
        if arguments:
            workspace = table_value(arguments[0], "workspace", env)
            if workspace is not None:
                return Action("workspaces", "Switch workspace", "workspace", str(workspace))
            direction = table_value(arguments[0], "direction", env)
            if direction in {"left", "right", "up", "down"}:
                return Action("windows", f"Focus {direction}", "focus", str(direction))
    for _, arguments in calls(tokens, ("hl", ".", "dsp", ".", "window", ".", "move")):
        if arguments and (workspace := table_value(arguments[0], "workspace", env)) is not None:
            return Action("workspaces", "Move window to workspace", "movetoworkspace", str(workspace))
        return Action("windows", "Move window", "window-move")
    for _, arguments in calls(tokens, ("hl", ".", "dsp", ".", "layout")):
        argument = literal(arguments[0], env) if arguments else None
        if argument == "togglesplit":
            return Action("windows", "Toggle split direction", "togglesplit")
    known = {("window", "close"): ("windows", "Close focused window", "killactive"),
             ("window", "float"): ("windows", "Toggle floating", "togglefloating"),
             ("window", "pseudo"): ("windows", "Toggle pseudo tiling", "pseudo"),
             ("window", "drag"): ("windows", "Move window", "window-drag"),
             ("window", "resize"): ("windows", "Resize window", "window-resize"),
             ("workspace", "toggle_special"): ("workspaces", "Toggle scratchpad", "togglespecialworkspace")}
    for (owner, method), (group, label, family) in known.items():
        if next(calls(tokens, ("hl", ".", "dsp", ".", owner, ".", method)), None) is not None:
            return Action(group, label, family)
    return Action()


def split_key_combo(combo: str) -> tuple[int, str] | None:
    parts = [part.strip() for part in combo.split("+")]
    mask = 0
    while parts and parts[0].upper() in MOD_NAMES:
        mask |= MOD_NAMES[parts.pop(0).upper()]
    if len(parts) != 1 or not parts[0] or len(parts[0]) > 60:
        return None
    return mask, parts[0]


def config_bindings() -> list[Binding]:
    path = CONFIG / "hypr/modules/binds.lua"
    try:
        with path.open("rb") as handle:
            raw = handle.read(MAX_SOURCE_BYTES + 1)
        if len(raw) > MAX_SOURCE_BYTES:
            return []
        source = raw.decode("utf-8")
    except (OSError, UnicodeError):
        return []
    tokens, env = lua_tokens(source), {}
    # Only simple local string/integer constants are accepted. Function calls,
    # requires, tables, file access and other expressions are never evaluated.
    for index in range(len(tokens) - 3):
        if tokens[index].value == "local" and tokens[index + 2].value == "=":
            name, value = tokens[index + 1].value, tokens[index + 3]
            if value.string or value.value.isdecimal():
                env[name] = value.value if value.string else int(value.value)
    loops = []
    for match in re.finditer(r"(?m)^\s*for\s+([A-Za-z_][A-Za-z_0-9]*)\s*=\s*(\d+)\s*,\s*(\d+)\s+do\s*$", source):
        end = re.search(r"(?m)^\s*end\s*$", source[match.end():])
        start_value, end_value = int(match[2]), int(match[3])
        if end and 0 <= start_value <= end_value <= 20:
            stop = match.end() + end.start()
            body = source[match.end():stop]
            # Nested controls cannot be understood by this limited fallback.
            if not re.search(r"\b(?:if|for|while|repeat|function)\b", body):
                loops.append((match.start(), stop, match[1], start_value, end_value, lua_tokens(body)))
    result = []
    for position, arguments in calls(tokens, ("hl", ".", "bind")):
        if len(arguments) < 2 or len(result) >= MAX_BINDS:
            continue
        contexts = [env]
        for start, stop, variable, first, last, body_tokens in loops:
            if start <= position <= stop:
                contexts = []
                for value in range(first, last + 1):
                    context = {**env, variable: value}
                    # Restricted local alias `local key = i % 10` supports the
                    # existing 1..10 workspace series without running its loop.
                    for i in range(len(body_tokens) - 5):
                        part = tuple(token.value for token in body_tokens[i:i + 6])
                        if part[0] == "local" and part[2:5] == ("=", variable, "%") and part[5].isdecimal():
                            divisor = int(part[5])
                            if divisor:
                                context[part[1]] = value % divisor
                    contexts.append(context)
                break
        for context in contexts:
            combo = literal(arguments[0], context)
            parsed = split_key_combo(combo) if isinstance(combo, str) else None
            if not parsed:
                continue
            mask, key = parsed
            options = arguments[2] if len(arguments) > 2 else []
            description = clean(table_value(options, "description", context) or table_value(options, "desc", context))
            action = lua_action(arguments[1], context)
            result.append(Binding(mask, key, action, description,
                                  release=table_true(options, "release"),
                                  long_press=table_true(options, "long_press"),
                                  mouse=table_true(options, "mouse")))
    return result


def description_action(description: str, action: Action) -> Action:
    if not description:
        return action
    known = {
        "Show desktop / restore windows": ("windows", "Show desktop / restore windows"),
        "Expand column / edge-to-edge taskbar": ("windows", "Expand window / full-width taskbar"),
        "Restore normal column and notch": ("windows", "Restore window and notch"),
        "Expand focused scrolling column to full width": ("windows", "Expand focused column"),
        "Reset focused scrolling column to normal width": ("windows", "Restore column width"),
        "Random wallpaper from current theme": ("apps", "Random wallpaper"),
        "Lock screen": ("system", "Lock screen"), "Log out": ("system", "Log out"),
        "Power menu": ("system", "Power menu"),
    }
    group, label = known.get(description, (action.group, description))
    return replace(action, group=group, label=label)


def normalise_live(rows: list[dict], configured: list[Binding]) -> list[Binding]:
    enrichment: dict[tuple, list[Binding]] = {}
    for binding in configured:
        enrichment.setdefault(binding.identity(), []).append(binding)
    result = []
    for row in rows:
        if clean(row.get("description")).startswith("Hotkey guide:"):
            continue
        mask = row.get("modmask", 0)
        if isinstance(mask, bool) or not isinstance(mask, int) or not 0 <= mask <= 255:
            continue
        key = clean(row.get("key"), 60)
        if not key:
            code = row.get("keycode")
            if isinstance(code, int) and not isinstance(code, bool) and 0 < code <= 767:
                key = f"code:{code}"
            else:
                continue
        if row.get("catch_all") is True:
            key = "Any key"
        action = dispatcher_action(clean(row.get("dispatcher"), 50), str(row.get("arg", ""))[:65536])
        binding = Binding(mask, key, action, clean(row.get("description")), clean(row.get("submap"), 40),
                          row.get("release") is True, row.get("longPress") is True,
                          row.get("mouse") is True)
        candidates = enrichment.get(binding.identity(), [])
        # Only an unambiguous current-config match can label opaque Lua code.
        if action.family == "custom" and len(candidates) == 1:
            candidate = candidates[0]
            binding = replace(binding, action=candidate.action,
                              description=binding.description or candidate.description,
                              mouse=binding.mouse or candidate.mouse,
                              config_label=not bool(binding.description))
        result.append(replace(binding, action=description_action(binding.description, binding.action)))
    return result


def collapse(bindings: list[Binding]) -> list[Binding]:
    """Only summarise complete, verified key sets with matching action semantics."""
    result, used = [], set()
    for index, binding in enumerate(bindings):
        if index in used:
            continue
        candidates = [(i, item) for i, item in enumerate(bindings)
                      if i not in used and item.partition() == binding.partition()
                      and item.action.family == binding.action.family]
        selected, display, label = [], "", ""
        if (binding.action.family in {"workspace", "movetoworkspace", "movetoworkspacesilent"}
                and binding.action.target in {str(n) for n in range(1, 11)}):
            numeric = [(i, item) for i, item in candidates if item.action.target in {str(n) for n in range(1, 11)}]
            expected = {(str(n % 10), str(n)) for n in range(1, 11)}
            if len(numeric) == 10 and {(item.key.casefold(), item.action.target) for _, item in numeric} == expected:
                selected, display = numeric, "1–9 / 0"
                label = "Switch workspace" if binding.action.family == "workspace" else "Move window to workspace"
        pairs = {
            "focus": ({("left", "left"), ("right", "right")}, "← / →", "Focus left / right"),
            "volume": ({("xf86audiolowervolume", "-"), ("xf86audioraisevolume", "+")}, "Vol − / +", "Adjust volume"),
            "brightness": ({("xf86monbrightnessdown", "-"), ("xf86monbrightnessup", "+")}, "Brightness − / +", "Adjust brightness"),
            "track": ({("xf86audioprev", "previous"), ("xf86audionext", "next")}, "Previous / Next", "Previous / next track"),
            "playback": ({("xf86audioplay", "play-pause"), ("xf86audiopause", "play-pause")}, "Play / Pause", "Play / pause"),
        }
        if binding.action.family in pairs:
            expected, pair_display, pair_label = pairs[binding.action.family]
            matched = [(i, item) for i, item in candidates if (item.key.casefold(), item.action.target) in expected]
            if ((binding.key.casefold(), binding.action.target) in expected
                    and len(matched) == len(expected)
                    and {(item.key.casefold(), item.action.target) for _, item in matched} == expected):
                selected, display, label = matched, pair_display, pair_label
        if binding.action.family == "workspace":
            expected = {("mouse_down", "e+1"), ("mouse_up", "e-1")}
            matched = [(i, item) for i, item in candidates if (item.key.casefold(), item.action.target) in expected]
            if ((binding.key.casefold(), binding.action.target) in expected and len(matched) == 2
                    and {(item.key.casefold(), item.action.target) for _, item in matched} == expected):
                selected, display, label = matched, "Scroll ↑ / ↓", "Previous / next workspace"
        if selected:
            used.update(i for i, _ in selected)
            result.append(replace(binding, action=replace(binding.action, label=label),
                                  display_key=display, count=sum(item.count for _, item in selected),
                                  config_label=any(item.config_label for _, item in selected)))
        else:
            used.add(index)
            result.append(binding)
    return result


def display_keys(binding: Binding) -> list[str]:
    keys = [name for bit, name in MODS if binding.mask & bit]
    key = binding.display_key or KEY_NAMES.get(binding.key.casefold())
    if not key:
        key = binding.key.upper() if len(binding.key) == 1 else binding.key
    return [*keys, key]


def catalogue() -> dict:
    configured = config_bindings()
    try:
        bindings = normalise_live(live_bindings(), configured)
        source, source_label, notice = "hyprland", "Live keybindings", ""
    except CatalogError:
        bindings = [replace(item, action=description_action(item.description, item.action))
                    for item in configured if not item.description.startswith("Hotkey guide:")]
        source, source_label = "config", "From configuration"
        notice = "Hyprland is unavailable. These shortcuts come from the configuration and may differ from the active session."
    if not bindings:
        return {"ok": False, "source": source, "sourceLabel": source_label, "groups": [],
                "count": 0, "bindingCount": 0, "error": "No shortcuts are available right now."}
    count = len(bindings)
    grouped = {name: [] for name, _, _ in GROUPS}
    for binding in collapse(bindings):
        keys = display_keys(binding)
        hints = []
        if binding.submap:
            hints.append("Mode: " + binding.submap)
        if binding.release:
            hints.append("On release")
        if binding.long_press:
            hints.append("Hold")
        if binding.mouse:
            hints.append("Drag")
        label = binding.action.label
        # Hash only friendly text/keys; raw commands and callback IDs are absent.
        identity = "\0".join([*keys, label, *hints]).encode("utf-8")
        grouped[binding.action.group].append({
            "id": hashlib.sha256(identity).hexdigest()[:16], "keys": keys, "label": label,
            "hint": " · ".join(hints), "search": " ".join([label, *keys, *hints]).casefold(),
            "bindingCount": binding.count,
        })
    groups = [{"id": name, "title": title, "icon": icon, "entries": grouped[name]}
              for name, title, icon in GROUPS if grouped[name]]
    return {"ok": True, "source": source, "sourceLabel": source_label, "notice": notice,
            "count": sum(len(group["entries"]) for group in groups), "bindingCount": count, "groups": groups}


def main() -> None:
    try:
        value = catalogue()
    except (OSError, ValueError, TypeError, OverflowError, RecursionError):
        value = {"ok": False, "groups": [], "count": 0, "bindingCount": 0,
                 "error": "The shortcut overview is temporarily unavailable."}
    try:
        print(json.dumps(value, ensure_ascii=False, separators=(",", ":")), flush=True)
    except BrokenPipeError:
        pass


if __name__ == "__main__":
    main()
