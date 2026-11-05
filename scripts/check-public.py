#!/usr/bin/env python3
"""Check the public export; findings contain locations and categories, never values.

Only files in the embedded reviewed inventory are read. Installed payload hashes
are parsed from the installer as data, without executing its code. Unknown
entries, runtime/private paths, symlinks, large files and binary files fail closed.
This is a review aid, not a proof that arbitrary text is free of personal data.
"""
import argparse
import ast
import hashlib
import ipaddress
import json
import os
from pathlib import Path, PurePosixPath
import re
import stat
import struct
import sys
import zlib


INSTALLER_NAME = "scripts/install.py"
MAX_FILE_BYTES = 5_000_000
MAX_TOTAL_BYTES = 32_000_000
MAX_FILES = 2_000

# Exact files reviewed for this public export, including documentation and tools.
# Update this tuple deliberately when adding or removing an exported source file.
PUBLIC_FILES = (
    '.config/VSCodium/User/settings.json',
    '.config/fastfetch/config.jsonc',
    '.config/fish/config.fish',
    '.config/gtk-3.0/gtk.css',
    '.config/gtk-3.0/settings.ini',
    '.config/gtk-4.0/gtk.css',
    '.config/gtk-4.0/settings.ini',
    '.config/hypr/hypridle.conf',
    '.config/hypr/hyprland.lua',
    '.config/hypr/hyprlock.conf',
    '.config/hypr/hyprtoolkit.conf',
    '.config/hypr/modules/autostart.lua',
    '.config/hypr/modules/binds.lua',
    '.config/hypr/modules/decorations.lua',
    '.config/hypr/modules/edge-mode.lua',
    '.config/hypr/modules/env.lua',
    '.config/hypr/modules/hotkey-guide.lua',
    '.config/hypr/modules/input.lua',
    '.config/hypr/modules/layout.lua',
    '.config/hypr/modules/misc.lua',
    '.config/hypr/modules/monitors.lua',
    '.config/hypr/modules/pin-window.lua',
    '.config/hypr/modules/show-desktop.lua',
    '.config/hypr/modules/theme-colors.lua',
    '.config/hypr/modules/windowrules.lua',
    '.config/kitty/colors/colors.conf',
    '.config/kitty/kitty.conf',
    '.config/quickshell/AppLauncher.qml',
    '.config/quickshell/AudioPopup.qml',
    '.config/quickshell/BatteryIndicator.qml',
    '.config/quickshell/BatteryPopup.qml',
    '.config/quickshell/BluetoothPopup.qml',
    '.config/quickshell/Calculator.js',
    '.config/quickshell/CalendarPopup.qml',
    '.config/quickshell/Clipboard/README.md',
    '.config/quickshell/Clipboard/store.py',
    '.config/quickshell/ClipboardHistory.qml',
    '.config/quickshell/ClipboardState.qml',
    '.config/quickshell/CompactNotch.qml',
    '.config/quickshell/ConnectionCheckBody.qml',
    '.config/quickshell/ConnectionCheckState.qml',
    '.config/quickshell/EdgeBarState.qml',
    '.config/quickshell/EdgeTaskbarContent.qml',
    '.config/quickshell/Emoji/CATALOG.md',
    '.config/quickshell/Emoji/LICENSE-UNICODE.txt',
    '.config/quickshell/Emoji/README-backend.md',
    '.config/quickshell/Emoji/backend.py',
    '.config/quickshell/Emoji/catalog-info.json',
    '.config/quickshell/Emoji/catalog-sources.json',
    '.config/quickshell/Emoji/emojis.json',
    '.config/quickshell/EmojiPicker.qml',
    '.config/quickshell/EmojiState.qml',
    '.config/quickshell/FileSearchState.qml',
    '.config/quickshell/FileShelf.qml',
    '.config/quickshell/FileShelfPanel.qml',
    '.config/quickshell/FileShelfState.qml',
    '.config/quickshell/Files/files.py',
    '.config/quickshell/FlipClock.qml',
    '.config/quickshell/FlipDigit.qml',
    '.config/quickshell/Hardware/telemetry.py',
    '.config/quickshell/HardwarePanel.qml',
    '.config/quickshell/HardwarePanelBody.qml',
    '.config/quickshell/HardwareTelemetry.qml',
    '.config/quickshell/HotkeyGuideState.qml',
    '.config/quickshell/HotkeyOverview.qml',
    '.config/quickshell/Hotkeys/README-backend.md',
    '.config/quickshell/Hotkeys/catalog.py',
    '.config/quickshell/HoverNotchContent.qml',
    '.config/quickshell/LockScreen/design.conf.in',
    '.config/quickshell/LockScreen/lock.py',
    '.config/quickshell/LockScreen/runtime.py',
    '.config/quickshell/LockScreen/start-idle.py',
    '.config/quickshell/LockScreen/sync.py',
    '.config/quickshell/Logout/launch.py',
    '.config/quickshell/MenuBodyLoader.qml',
    '.config/quickshell/Network/README-check.md',
    '.config/quickshell/Network/check.py',
    '.config/quickshell/Network/telemetry.py',
    '.config/quickshell/NetworkPanel.qml',
    '.config/quickshell/NetworkPanelBody.qml',
    '.config/quickshell/NetworkPopup.qml',
    '.config/quickshell/NetworkTelemetry.qml',
    '.config/quickshell/NotchContentStretch.qml',
    '.config/quickshell/NotchMenuSurface.qml',
    '.config/quickshell/NotchMotion.qml',
    '.config/quickshell/NotchOsdContent.qml',
    '.config/quickshell/NotchOsdState.qml',
    '.config/quickshell/NotchTransition.qml',
    '.config/quickshell/Notes/README.md',
    '.config/quickshell/Notes/store.py',
    '.config/quickshell/NotesState.qml',
    '.config/quickshell/NotificationCard.qml',
    '.config/quickshell/NotificationCenter.qml',
    '.config/quickshell/NotificationCenterBody.qml',
    '.config/quickshell/NotificationToastContent.qml',
    '.config/quickshell/Notifications/README-backend.md',
    '.config/quickshell/Notifications/Service.qml',
    '.config/quickshell/Notifications/qmldir',
    '.config/quickshell/Osd/backlight.py',
    '.config/quickshell/PerformancePopup.qml',
    '.config/quickshell/PickerButton.qml',
    '.config/quickshell/PickerRail.qml',
    '.config/quickshell/PickerThemeCard.qml',
    '.config/quickshell/PickerWallpaperCard.qml',
    '.config/quickshell/Pill.qml',
    '.config/quickshell/Poller.qml',
    '.config/quickshell/PowerMenu.qml',
    '.config/quickshell/PowerPopup.qml',
    '.config/quickshell/QuickNotes.qml',
    '.config/quickshell/QuickSettings.qml',
    '.config/quickshell/QuickSlider.qml',
    '.config/quickshell/QuickToggle.qml',
    '.config/quickshell/ScreenshotEditor.qml',
    '.config/quickshell/ScreenshotEditorBody.qml',
    '.config/quickshell/Screenshots/backend.py',
    '.config/quickshell/SelectionTrail.qml',
    '.config/quickshell/Settings/AppImagePreferences.qml',
    '.config/quickshell/Settings/AppImagesPage.qml',
    '.config/quickshell/Settings/AppearancePage.qml',
    '.config/quickshell/Settings/AudioPage.qml',
    '.config/quickshell/Settings/BluetoothPage.qml',
    '.config/quickshell/Settings/CursorPreferences.qml',
    '.config/quickshell/Settings/CursorSettings.qml',
    '.config/quickshell/Settings/DisplayPage.qml',
    '.config/quickshell/Settings/InputPage.qml',
    '.config/quickshell/Settings/NetworkPage.qml',
    '.config/quickshell/Settings/NotificationsPage.qml',
    '.config/quickshell/Settings/OverviewPage.qml',
    '.config/quickshell/Settings/PowerPage.qml',
    '.config/quickshell/Settings/ProfilePreferences.qml',
    '.config/quickshell/Settings/ProfileSettings.qml',
    '.config/quickshell/Settings/SButton.qml',
    '.config/quickshell/Settings/SCard.qml',
    '.config/quickshell/Settings/SLabel.qml',
    '.config/quickshell/Settings/SMomentumFlickable.qml',
    '.config/quickshell/Settings/SNotice.qml',
    '.config/quickshell/Settings/SPage.qml',
    '.config/quickshell/Settings/SRow.qml',
    '.config/quickshell/Settings/SSlider.qml',
    '.config/quickshell/Settings/SToggle.qml',
    '.config/quickshell/Settings/SystemPage.qml',
    '.config/quickshell/Settings/WallpaperMotionSettings.qml',
    '.config/quickshell/Settings/WindowsPage.qml',
    '.config/quickshell/Settings/appimage_manager.py',
    '.config/quickshell/Settings/cursor_preferences.py',
    '.config/quickshell/Settings/input-preferences.py',
    '.config/quickshell/Settings/system-info.py',
    '.config/quickshell/Settings/window-preferences.py',
    '.config/quickshell/SettingsApp.qml',
    '.config/quickshell/SettingsPageHeader.qml',
    '.config/quickshell/Shelf/store.py',
    '.config/quickshell/SpeedTest/README-backend.md',
    '.config/quickshell/SpeedTest/run.py',
    '.config/quickshell/SpeedTestBody.qml',
    '.config/quickshell/SpeedTestPanel.qml',
    '.config/quickshell/SpeedTestState.qml',
    '.config/quickshell/Speedometer.qml',
    '.config/quickshell/SystemState/BluetoothPower.qml',
    '.config/quickshell/SystemState/qmldir',
    '.config/quickshell/TailscaleState.qml',
    '.config/quickshell/TaskManager.qml',
    '.config/quickshell/TaskManager/processes.py',
    '.config/quickshell/TaskManagerPanel.qml',
    '.config/quickshell/TaskManagerState.qml',
    '.config/quickshell/Theme/Theme.qml',
    '.config/quickshell/Theme/qmldir',
    '.config/quickshell/ThemeSwitcher.qml',
    '.config/quickshell/TrayIcons.qml',
    '.config/quickshell/Wallpapers/Cache.qml',
    '.config/quickshell/Wallpapers/Preview.qml',
    '.config/quickshell/Wallpapers/qmldir',
    '.config/quickshell/Wallpapers/thumbnail-cache.README.md',
    '.config/quickshell/Wallpapers/thumbnail-cache.py',
    '.config/quickshell/WifiSignalIndicator.qml',
    '.config/quickshell/WindowActions.qml',
    '.config/quickshell/WindowBar.qml',
    '.config/quickshell/WindowBarState.qml',
    '.config/quickshell/WindowPreview.qml',
    '.config/quickshell/WorkspaceIndicators.qml',
    '.config/quickshell/Workspaces.qml',
    '.config/quickshell/appearance_targets.py',
    '.config/quickshell/apply-theme.py',
    '.config/quickshell/desktop_theme.py',
    '.config/quickshell/hypr_appearance.py',
    '.config/quickshell/icon_palette.py',
    '.config/quickshell/material-palette.py',
    '.config/quickshell/notification_theme.py',
    '.config/quickshell/profile-avatar.py',
    '.config/quickshell/session-power.py',
    '.config/quickshell/shell.qml',
    '.config/quickshell/sync-chatgpt-theme.py',
    '.config/quickshell/sync-sddm.py',
    '.config/quickshell/templates/fastfetch.jsonc.template',
    '.config/quickshell/templates/starship.toml.template',
    '.config/starship.toml',
    '.config/xsettingsd/xsettingsd.conf',
    '.gitignore',
    '.local/share/applications/org.gnome.Settings.desktop',
    '.local/share/applications/org.quickshell.TaskManager.desktop',
    '.local/share/applications/quickshell-notes.desktop',
    '.local/share/dbus-1/services/org.erikreider.swaync.service',
    'CREDITS.md',
    'INSTALL.md',
    'README.md',
    'assets/wallpapers/notch-default.png',
    'extras/hyprshutdown/CMakeLists.txt',
    'extras/hyprshutdown/LICENSE',
    'extras/hyprshutdown/README.md',
    'extras/hyprshutdown/VERSION',
    'extras/hyprshutdown/src/helpers/Asserts.hpp',
    'extras/hyprshutdown/src/helpers/Logger.hpp',
    'extras/hyprshutdown/src/helpers/Memory.hpp',
    'extras/hyprshutdown/src/helpers/OS.cpp',
    'extras/hyprshutdown/src/helpers/OS.hpp',
    'extras/hyprshutdown/src/main.cpp',
    'extras/hyprshutdown/src/state/AppState.cpp',
    'extras/hyprshutdown/src/state/AppState.hpp',
    'extras/hyprshutdown/src/state/HyprlandIPC.cpp',
    'extras/hyprshutdown/src/state/HyprlandIPC.hpp',
    'extras/hyprshutdown/src/ui/UI.cpp',
    'extras/hyprshutdown/src/ui/UI.hpp',
    'extras/sddm/README.md',
    'extras/sddm/notch-minimal/Main.qml',
    'extras/sddm/notch-minimal/assets/background.svg',
    'extras/sddm/notch-minimal/metadata.desktop',
    'extras/sddm/notch-minimal/theme.conf',
    'extras/sddm/theme.ini.example',
    'install.sh',
    'requirements-material.txt',
    'scripts/check-public.py',
    'scripts/install.py',
)

# Reviewed exceptions must identify an exact file, rule and matched value.
# Never exempt a complete file or globally exempt a token/address.
REVIEWED_TEXT = {
    (".config/quickshell/Network/check.py", "literal IP address"): {
        "1.1.1.1": "Cloudflare public DNS endpoint; route/direct TCP diagnostics only",
        "2606:4700:4700::1111": "Cloudflare public DNS endpoint; IPv6 diagnostics only",
    },
    (".config/quickshell/Network/README-check.md", "literal IP address"): {
        "1.1.1.1": "Documents the public diagnostic endpoint used by check.py",
        "2606:4700:4700::1111": "Documents the public IPv6 diagnostic endpoint",
    },
    ("scripts/check-public.py", "literal IP address"): {
        "1.1.1.1": "This scanner's exact public-probe review entries",
        "2606:4700:4700::1111": "This scanner's exact public-probe review entries",
    },
}

# Only this newly generated neutral image may bypass UTF-8 decoding. Its digest
# is fixed here and in the installer; existing personal images are excluded.
REVIEWED_PNG = {
    "assets/wallpapers/notch-default.png": "8380b02d262c2fadd761295a296f50d183c48da9b428a4d0a73d9a7e0ae194ee",
}

PROHIBITED_PARTS = {
    ".git", ".hg", ".svn", ".codex", ".agents", ".aws", ".ssh", ".gnupg",
    ".venv", "venv", "virtualenv", "material-runtime", "node_modules",
    "__pycache__", ".cache", "cache", "caches", "logs", "backups",
    "globalstorage", "workspacestorage", "local storage", "session storage",
    "indexeddb", "webstorage", "blob_storage", "generated",
    "keyrings", "wallets", "system-connections",
}
PROHIBITED_NAMES = {
    "cookies", "login data", "history", "shell_history", "fish_history",
    ".bash_history", ".zsh_history", "known_hosts", "authorized_keys",
    ".python_history", ".lesshst", ".wget-hsts", ".git-credentials", "fish_variables",
    "id_rsa", "id_dsa", "id_ecdsa", "id_ed25519", ".netrc", ".npmrc",
    "credentials", "credentials.json", "service-account.json", "pyvenv.cfg",
    "launcher-state.json", "theme-state.json", "bluetooth-state.json",
    "bluetooth-power.json", "input-preferences.json", "cursor-preferences.json",
    "window-preferences.json", "cursor-overrides.lua", "input-overrides.lua",
    "window-overrides.lua", ".window-preferences.lock", "input.generated.conf", "recently-used.xbel",
    "bookmarks", "bookmarks.json", "storage.json", "state.json",
    "clipboard.json", "notes.json", "shelf.json", "notifications.json",
    "pinned-apps.json", "recent-apps.json", "connections.json",
}
PROHIBITED_SUFFIXES = {
    ".db", ".sqlite", ".sqlite3", ".db-wal", ".db-shm", ".db-journal",
    ".pyc", ".pyo", ".log", ".bak", ".swp", ".tmp", ".pem", ".key",
    ".p12", ".pfx", ".der", ".asc", ".kdbx", ".wallet",
    ".so", ".a", ".o", ".exe", ".dll", ".appimage", ".bin",
    ".zip", ".tar", ".gz", ".xz", ".7z", ".rar", ".pdf",
    ".jpg", ".jpeg", ".webp", ".gif", ".ico", ".ttf", ".otf",
}

PATTERNS = {
    "private-key block": re.compile(
        r"-----BEGIN (?:(?:OPENSSH |RSA |EC |DSA |ENCRYPTED )?PRIVATE KEY|PGP PRIVATE KEY BLOCK)-----"),
    "known credential format": re.compile(
        r"(?<![A-Za-z0-9])(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,}"
        r"|sk-(?:proj-)?[A-Za-z0-9_-]{30,}|xox[baprs]-[A-Za-z0-9-]{20,}"
        r"|tskey-(?:auth-|api-)?[A-Za-z0-9_-]{20,}|(?:AKIA|ASIA)[A-Z0-9]{16}"
        r"|AIza[A-Za-z0-9_-]{35}|(?:sk|rk)_live_[A-Za-z0-9]{16,}"
        r"|glpat-[A-Za-z0-9_-]{20,}|npm_[A-Za-z0-9]{30,})(?![A-Za-z0-9])"),
    "credentials in URL": re.compile(
        r"[a-zA-Z][a-zA-Z0-9+.-]*://[^\s/:@\"']+:[^\s/@\"']+@"),
    "literal credential": re.compile(
        r"(?i)(?<![\w\"'])(?:[\"'](?:api[_-]?key|access[_-]?token|auth[_-]?token|client[_-]?secret|password|passwd|psk)[\"']"
        r"|(?:api[_-]?key|access[_-]?token|auth[_-]?token|client[_-]?secret|password|passwd|psk))"
        r"\s*[:=]\s*[\"']([^\"'\n]+)[\"']"),
    "personal home path": re.compile(
        r"(?:(?:/home/|/Users/)[A-Za-z0-9_.-]+(?:/|\b)|[A-Za-z]:\\Users\\[^\\\s\"']+)"),
    "email address": re.compile(
        r"(?<![\w.+-])[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+"),
    "MAC address": re.compile(
        r"(?<![A-Fa-f0-9])(?:[A-Fa-f0-9]{2}[:-]){5}[A-Fa-f0-9]{2}(?![A-Fa-f0-9])"),
    "device/account UUID": re.compile(
        r"(?i)(?<![A-F0-9])[A-F0-9]{8}-(?:[A-F0-9]{4}-){3}[A-F0-9]{12}(?![A-F0-9])"),
    "literal host/device setting": re.compile(
        r"(?i)(?<![\w\"'])(?:[\"'](?:hostname|host_name|machine_id|device_id|serial_number|ssid|bssid|tailscale_hostname)[\"']"
        r"|(?:hostname|host_name|machine_id|device_id|serial_number|ssid|bssid|tailscale_hostname))"
        r"\s*[:=]\s*[\"']([^\"'\n]+)[\"']"),
    "private tailnet hostname": re.compile(
        r"(?i)\b(?:[a-z0-9-]+\.)+[a-z0-9-]+\.(?:ts|tailscale)\.net\b"),
}
IPV4 = re.compile(r"(?<![\w.])(?:[0-9]{1,3}\.){3}[0-9]{1,3}(?![\w.])")
IPV6 = re.compile(r"(?<![\w:])(?:[A-Fa-f0-9]{0,4}:){2,}[A-Fa-f0-9:.]*(?![\w:.-])")


def prohibited_path(name):
    parts = PurePosixPath(name).parts
    lower = [part.lower() for part in parts]
    return (any(part in PROHIBITED_PARTS for part in lower)
            or lower[-1] in PROHIBITED_NAMES
            or lower[-1] == ".env" or lower[-1].startswith(".env.")
            or any(lower[-1].endswith(suffix) for suffix in PROHIBITED_SUFFIXES))


def valid_relative(name):
    return (isinstance(name, str) and bool(name) and "\\" not in name
            and not any(ord(c) < 32 or ord(c) == 127 for c in name)
            and not name.startswith("/")
            and all(part not in {"", ".", ".."} for part in name.split("/")))


def read_regular(path, limit, *, root=None):
    """Bound reads and reject links, including links in export parent folders."""
    flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0) | getattr(os, "O_NONBLOCK", 0)
    directory_fds = []
    try:
        if root is None:
            fd = os.open(path, flags)
        else:
            parts = path.relative_to(root).parts
            if not parts or any(part in {"", ".", ".."} for part in parts):
                raise ValueError("invalid export path")
            directory_flags = flags | os.O_DIRECTORY
            parent_fd = os.open(root, directory_flags)
            directory_fds.append(parent_fd)
            for part in parts[:-1]:
                parent_fd = os.open(part, directory_flags, dir_fd=parent_fd)
                directory_fds.append(parent_fd)
            fd = os.open(parts[-1], flags, dir_fd=parent_fd)
    finally:
        for directory_fd in reversed(directory_fds):
            os.close(directory_fd)
    try:
        info = os.fstat(fd)
        if not stat.S_ISREG(info.st_mode) or info.st_size > limit:
            raise ValueError("not a bounded regular file")
        with os.fdopen(fd, "rb", closefd=False) as stream:
            payload = stream.read(limit + 1)
        if len(payload) > limit:
            raise ValueError("file grew beyond limit")
        return payload
    finally:
        os.close(fd)


def reviewed_inventory():
    """Validate the embedded allowlist before inspecting export contents."""
    if not isinstance(PUBLIC_FILES, tuple) or not (1 <= len(PUBLIC_FILES) <= MAX_FILES):
        raise ValueError("invalid public file inventory")
    if any(not valid_relative(name) or prohibited_path(name) for name in PUBLIC_FILES):
        raise ValueError("invalid public file inventory")
    allowed = set(PUBLIC_FILES)
    if len(allowed) != len(PUBLIC_FILES) or INSTALLER_NAME not in allowed:
        raise ValueError("invalid public file inventory")
    return allowed


def embedded_payload_hashes(source, allowed):
    """Read one literal hash table through AST inspection; never import or exec."""
    tree = ast.parse(source)
    bindings = [node for node in ast.walk(tree) if isinstance(node, ast.Name)
                and isinstance(node.ctx, ast.Store) and node.id == "PAYLOAD_SHA256"]
    assignments = [node for node in tree.body if isinstance(node, ast.Assign)
                   and len(node.targets) == 1 and isinstance(node.targets[0], ast.Name)
                   and node.targets[0].id == "PAYLOAD_SHA256"]
    if len(bindings) != 1 or len(assignments) != 1:
        raise ValueError("missing or repeated payload hash table")
    table = assignments[0].value
    if not isinstance(table, ast.Dict) or not (1 <= len(table.keys) <= MAX_FILES):
        raise ValueError("invalid payload hash table")
    result = {}
    for key, value in zip(table.keys, table.values):
        if not (isinstance(key, ast.Constant) and isinstance(key.value, str)
                and isinstance(value, ast.Constant) and isinstance(value.value, str)):
            raise ValueError("nonliteral payload hash entry")
        name, digest = key.value, value.value
        if (not valid_relative(name) or prohibited_path(name) or name not in allowed
                or name in result or name in {INSTALLER_NAME, "scripts/check-public.py"}
                or not re.fullmatch(r"[a-f0-9]{64}", digest)):
            raise ValueError("invalid payload hash entry")
        result[name] = digest
    return result


def valid_neutral_png(payload):
    """Check the reviewed image's structure; reject metadata and extra chunks."""
    if not payload.startswith(b"\x89PNG\r\n\x1a\n"):
        return False
    offset, chunks = 8, []
    while offset + 12 <= len(payload):
        length = struct.unpack(">I", payload[offset:offset + 4])[0]
        kind = payload[offset + 4:offset + 8]
        end = offset + 12 + length
        if end > len(payload) or kind not in {b"IHDR", b"IDAT", b"IEND"}:
            return False
        chunk = payload[offset + 8:offset + 8 + length]
        crc = struct.unpack(">I", payload[offset + 8 + length:end])[0]
        if zlib.crc32(kind + chunk) & 0xffffffff != crc:
            return False
        if kind == b"IHDR":
            if chunks or length != 13:
                return False
            width, height, depth, color, compression, filtering, interlace = struct.unpack(">IIBBBBB", chunk)
            if not (1 <= width <= 8192 and 1 <= height <= 8192
                    and depth == 8 and color in {2, 6}
                    and compression == filtering == interlace == 0):
                return False
        chunks.append(kind)
        offset = end
        if kind == b"IEND":
            return (length == 0 and offset == len(payload) and chunks[0] == b"IHDR"
                    and b"IDAT" in chunks and chunks.count(b"IHDR") == 1)
    return False


def content_findings(name, source):
    for rule, expression in PATTERNS.items():
        for match in expression.finditer(source):
            value = match.group(0)
            if value in REVIEWED_TEXT.get((name, rule), {}):
                continue
            yield source.count("\n", 0, match.start()) + 1, rule
    for expression in (IPV4, IPV6):
        for match in expression.finditer(source):
            value = match.group(0)
            try:
                ipaddress.ip_address(value)
            except ValueError:
                continue
            rule = "literal IP address"
            if value not in REVIEWED_TEXT.get((name, rule), {}):
                yield source.count("\n", 0, match.start()) + 1, rule


def inspect(root):
    """Return (regular file count, [(relative path, line or None, category)])."""
    findings = []
    if root.is_symlink() or not root.is_dir():
        return 0, [(".", None, "export root is not a regular directory")]
    try:
        allowed = reviewed_inventory()
    except (ValueError, TypeError):
        return 0, [(".", None, "invalid embedded public file inventory; payload not opened")]
    try:
        installer_source = read_regular(root / INSTALLER_NAME,
                                        min(MAX_FILE_BYTES, MAX_TOTAL_BYTES), root=root)
        expected = embedded_payload_hashes(installer_source.decode("utf-8"), allowed)
    except (OSError, ValueError, TypeError, UnicodeError, SyntaxError, RecursionError):
        return 0, [(INSTALLER_NAME, None, "missing/invalid embedded payload hashes; payload not opened")]

    allowed_directories = {str(parent) for name in allowed for parent in PurePosixPath(name).parents
                           if str(parent) != "."}
    seen, total_bytes = set(), 0
    for directory, subdirs, filenames in os.walk(root, followlinks=False):
        base = Path(directory)
        for child in list(subdirs):
            path = base / child
            name = path.relative_to(root).as_posix()
            if path.is_symlink():
                findings.append((name, None, "directory symlink; target not opened"))
                subdirs.remove(child)
            elif prohibited_path(name):
                findings.append((name, None, "private/runtime directory; contents not opened"))
                subdirs.remove(child)
            elif name not in allowed_directories:
                findings.append((name, None, "not in reviewed inventory; contents not opened"))
                subdirs.remove(child)
        for child in filenames:
            path = base / child
            name = path.relative_to(root).as_posix()
            if path.is_symlink():
                findings.append((name, None, "symlink; target not opened"))
                continue
            try:
                info = path.lstat()
            except OSError:
                findings.append((name, None, "unreadable entry"))
                continue
            if not stat.S_ISREG(info.st_mode):
                findings.append((name, None, "special file; contents not opened"))
                continue
            seen.add(name)
            if name not in allowed:
                findings.append((name, None, "not in reviewed inventory; contents not opened"))
                continue
            if prohibited_path(name):
                findings.append((name, None, "private/runtime path; contents not opened"))
                continue
            if info.st_size > MAX_FILE_BYTES or total_bytes + info.st_size > MAX_TOTAL_BYTES:
                findings.append((name, None, "size limit exceeded; contents not opened"))
                continue
            try:
                payload = read_regular(path, min(MAX_FILE_BYTES, MAX_TOTAL_BYTES - total_bytes), root=root)
            except (OSError, ValueError):
                findings.append((name, None, "not a readable bounded regular file"))
                continue
            total_bytes += len(payload)
            if name == INSTALLER_NAME and payload != installer_source:
                findings.append((name, None, "installer changed during scan"))
            digest = hashlib.sha256(payload).hexdigest()
            if name in expected and digest != expected[name]:
                findings.append((name, None, "SHA-256 differs from embedded payload hash"))
            if name in REVIEWED_PNG:
                if digest != REVIEWED_PNG[name] or not valid_neutral_png(payload):
                    findings.append((name, None, "unreviewed binary image or PNG metadata"))
                continue
            try:
                source = payload.decode("utf-8")
                if any(ord(char) < 32 and char not in "\t\n\r" for char in source):
                    raise UnicodeError("binary control character")
            except UnicodeError:
                findings.append((name, None, "non-text/binary content"))
                continue
            findings.extend((name, line, rule) for line, rule in content_findings(name, source))
    findings.extend((name, None, "missing exported file") for name in allowed - seen)
    return len(seen), sorted(set(findings), key=lambda item: (item[0], item[1] or 0, item[2]))


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).absolute().parents[1],
                        help="export directory (defaults to the parent of scripts)")
    args = parser.parse_args(argv)
    count, findings = inspect(args.root.absolute())
    for name, line, category in findings:
        location = name if line is None else f"{name}:{line}"
        # Escaping filenames prevents terminal control sequences in unknown paths.
        safe_location = json.dumps(location, ensure_ascii=True)
        print(f"REVIEW {safe_location}: {category}")
    print(f"Files: {count}; findings: {len(findings)}.")
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main())
