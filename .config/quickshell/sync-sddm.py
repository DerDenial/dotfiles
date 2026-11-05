#!/usr/bin/env python3
"""Copy desktop appearance data into a greeter-readable, data-only directory."""
import argparse
import configparser
import fcntl
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import tempfile


def current_appearance():
    home = Path.home()
    states = list((home / ".local/share/quickshell").rglob("theme.json"))
    if not states:
        raise ValueError("No saved Quickshell theme found")
    saved = json.loads(max(states, key=lambda path: path.stat().st_mtime).read_text())
    theme_id = saved["activeThemeId"]
    source = (home / ".config/quickshell/Theme/Theme.qml").read_text()
    if theme_id == "material":
        if saved.get("materialPalette"):
            palette = json.loads(saved["materialPalette"])
        else:
            fallback = re.search(r"materialFallback: (.*)", source).group(1)
            palette = json.loads(json.loads(fallback))
        return theme_id, palette, saved["activeWallpaper"]
    found = re.search(r'(?:"id"|\bid)\s*:\s*"' + re.escape(theme_id) + r'".*?(?:"colors"|\bcolors)\s*:\s*\{([^{}]+)\}', source, re.S)
    if not found:
        raise ValueError("Cannot read active theme palette")
    palette = {}
    for quoted, bare, color in re.findall(r'(?:"([A-Za-z0-9]+)"|([A-Za-z0-9]+))\s*:\s*"(#[0-9A-Fa-f]{6,8})"', found.group(1)):
        palette[quoted or bare] = color
    return theme_id, palette, saved["activeWallpaper"]


def profile_settings(directory):
    source = Path(__file__).with_name("profile-avatar.py")
    if not source.is_file():
        return {"avatar": "", "profileUsername": ""}
    spec = importlib.util.spec_from_file_location("quickshell_profile_avatar", source)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    try:
        return module.avatar_settings(directory, module.ensure_avatar(publish=False))
    except (OSError, ValueError):
        return {"avatar": "", "profileUsername": ""}


def sync(theme_id, palette, wallpaper, directory):
    if not directory.is_dir():
        raise PermissionError(f"Theme-Datenordner fehlt: {directory}")
    with (directory / ".appearance.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        _sync(theme_id, palette, wallpaper, directory)


def _sync(theme_id, palette, wallpaper, directory):
    if not directory.is_dir() or not os.access(directory, os.W_OK | os.X_OK):
        raise PermissionError(f"Theme-Datenordner nicht zugänglich oder nicht beschreibbar: {directory}")
    source = Path(wallpaper)
    suffix = source.suffix.lower()
    if not source.is_file() or suffix not in (".png", ".jpg", ".jpeg", ".webp", ".bmp"):
        raise ValueError(f"Wallpaper fehlt oder Dateiformat wird nicht unterstützt: {source}")
    for role in ("bg0", "surface", "border", "text", "muted", "aqua", "red"):
        if not re.fullmatch(r"#[0-9A-Fa-f]{6}", palette[role]):
            raise ValueError("Invalid palette color")
    target = directory / ("background" + suffix)
    descriptor, name = tempfile.mkstemp(prefix=".wallpaper-", dir=directory)
    os.close(descriptor)
    try:
        shutil.copyfile(source, name)
        os.chmod(name, 0o644)
        os.replace(name, target)
    finally:
        if os.path.exists(name): os.unlink(name)
    settings = configparser.ConfigParser(interpolation=None)
    settings.optionxform = str
    settings["Theme"] = {
        "themeId": theme_id, "background": str(target),
        "backgroundColor": palette["bg0"], "surface": palette["surface"],
        "border": palette["border"], "text": palette["text"], "muted": palette["muted"],
        "accent": palette.get("accent", palette["aqua"]), "error": palette["red"],
    }
    settings["Theme"].update(profile_settings(directory))
    descriptor, name = tempfile.mkstemp(prefix=".theme-", dir=directory, text=True)
    try:
        with os.fdopen(descriptor, "w") as output: settings.write(output)
        os.chmod(name, 0o644)
        os.replace(name, directory / "theme.ini")
    finally:
        if os.path.exists(name): os.unlink(name)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("theme_id", nargs="?")
    parser.add_argument("palette_json", nargs="?")
    parser.add_argument("wallpaper", nargs="?")
    parser.add_argument("--current", action="store_true")
    parser.add_argument("--state-dir", type=Path, default=Path("/var/lib/quickshell-sddm"))
    args = parser.parse_args()
    if args.current:
        theme_id, palette, wallpaper = current_appearance()
    elif args.theme_id and args.palette_json and args.wallpaper:
        theme_id, palette, wallpaper = args.theme_id, json.loads(args.palette_json), args.wallpaper
    else:
        parser.error("Use --current or supply theme ID, palette JSON and wallpaper")
    sync(theme_id, palette, wallpaper, args.state_dir)
