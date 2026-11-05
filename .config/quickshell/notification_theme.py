#!/usr/bin/env python3
"""Keep the notification center on the desktop's semantic color palette."""
import importlib.util
import os
from pathlib import Path
import re
import sys
import tempfile


def render_notification_palette(palette):
    accent = palette.get("accent", palette["aqua"])
    colors = {
        "nc_bg": palette.get("notchBg", palette["bgDim"]),
        "nc_bg_dim": palette["bgDim"],
        "nc_surface": palette["surface"],
        "nc_surface_alt": palette["surfaceAlt"],
        "nc_surface_raised": palette["surfaceRaised"],
        "nc_border": palette["border"],
        "nc_text": palette["text"],
        "nc_text_bright": palette["textBright"],
        "nc_muted": palette["muted"],
        "nc_subtle": palette["mutedStrong"],
        "nc_accent": accent,
        "nc_accent_soft": palette.get("accentSoft", palette["surfaceAlt"]),
        "nc_on_accent": palette.get("onAccent", palette["bg0"]),
        "nc_on_accent_soft": palette.get("onAccentContainer", palette["text"]),
        "nc_error": palette["red"],
    }
    for role, value in colors.items():
        if not isinstance(value, str) or not re.fullmatch(r"#[0-9a-fA-F]{6}", value):
            raise ValueError("Invalid notification color: " + role)
    return "/* Generated from the active Quickshell palette. */\n" + "".join(
        "@define-color " + role + " " + value + ";\n" for role, value in colors.items()
    )


def apply_notification_theme(palette, config, write):
    colors = render_notification_palette(palette)
    template = config / "swaync/style-template.css"
    write(config / "swaync/colors/theme.css", colors)
    if template.exists():
        write(config / "swaync/style.css", template.read_text(encoding="utf-8"))


def atomic_write(path, content):
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(prefix="." + path.name + "-", dir=path.parent)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as output:
            output.write(content)
        os.chmod(temporary, 0o644)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


if __name__ == "__main__":
    if sys.argv[1:] != ["--current"]:
        raise SystemExit("Use notification_theme.py --current")
    home = Path.home()
    config = Path(os.environ.get("XDG_CONFIG_HOME", home / ".config"))
    source = config / "quickshell/sync-sddm.py"
    spec = importlib.util.spec_from_file_location("quickshell_saved_appearance", source)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    _, palette, _ = module.current_appearance()
    apply_notification_theme(palette, config, atomic_write)
