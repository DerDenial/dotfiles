#!/usr/bin/env python3
"""Render the lock screen from the saved Quickshell appearance, without locking."""
import configparser
import importlib.util
import os
from pathlib import Path
import re
import tempfile

HOME = Path.home()
COMPONENT = Path(__file__).resolve().parent
CONFIG = HOME / ".config/hypr/hyprlock.conf"
FALLBACK = {"bg0": "#141218", "surface": "#232127", "border": "#5e5a63",
            "text": "#e6e1e9", "muted": "#cac4cf", "accent": "#cebdfe", "red": "#ffb4ab"}


def current_appearance():
    try:
        source = HOME / ".config/quickshell/sync-sddm.py"
        spec = importlib.util.spec_from_file_location("quickshell_saved_appearance", source)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        _, palette, wallpaper = module.current_appearance()
        return palette, wallpaper
    except (OSError, ValueError, KeyError, AttributeError, TypeError):
        # A missing theme state must not prevent the real session lock.
        public = configparser.ConfigParser(interpolation=None)
        try:
            public.read("/var/lib/quickshell-sddm/theme.ini")
            data = public["Theme"]
            palette = {"bg0": data.get("backgroundColor"), "surface": data.get("surface"),
                       "border": data.get("border"), "text": data.get("text"),
                       "muted": data.get("muted"), "accent": data.get("accent"), "red": data.get("error")}
            return palette, data.get("background", "")
        except (OSError, KeyError, configparser.Error):
            return FALLBACK, ""


def color(palette, role, alpha="ff"):
    value = palette.get(role) or FALLBACK[role]
    if not isinstance(value, str) or not re.fullmatch(r"#[0-9a-fA-F]{6}", value):
        value = FALLBACK[role]
    return "rgba(" + value[1:].lower() + alpha + ")"


def atomic_write(path, content):
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(prefix="." + path.name + "-", dir=path.parent)
    try:
        with os.fdopen(descriptor, "w") as output:
            output.write(content)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def image_link(source, prefix):
    """Keep user-provided filenames outside the Hyprlang configuration."""
    generated = COMPONENT / "generated"
    generated.mkdir(mode=0o700, exist_ok=True)
    source = Path(source).resolve(strict=True)
    if not source.is_file() or source.suffix.lower() not in (".png", ".jpg", ".jpeg", ".webp"):
        raise ValueError("Unsupported lock-screen image")
    target = generated / (prefix + source.suffix.lower())
    descriptor, temporary = tempfile.mkstemp(prefix="." + prefix + "-", dir=generated)
    os.close(descriptor)
    os.unlink(temporary)
    try:
        os.symlink(source, temporary)
        os.replace(temporary, target)
    finally:
        if os.path.lexists(temporary):
            os.unlink(temporary)
    return str(target)


def wallpaper_link(wallpaper):
    candidates = [Path(wallpaper)] if wallpaper else []
    candidates.append(Path("/usr/share/sddm/themes/notch-minimal/assets/background.png"))
    for source in candidates:
        try:
            return image_link(source, "wallpaper")
        except (OSError, ValueError):
            continue
    return ""  # Hyprlock's configured background color is the final fallback.


def avatar_block(palette, publish=True):
    """Select the same profile image as SDDM each time a real lock starts."""
    avatar = ""
    try:
        helper = HOME / ".config/quickshell/profile-avatar.py"
        spec = importlib.util.spec_from_file_location("quickshell_profile_avatar", helper)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        selected = module.ensure_avatar(publish=publish)
        if selected is not None:
            avatar = image_link(selected, "avatar")
    except (OSError, ValueError, ImportError, AttributeError, TypeError):
        # An optional profile image must never prevent locking the session.
        pass

    if avatar:
        return """image {
    monitor =
    path = %s
    size = 88
    rounding = -1
    border_size = 0
    position = 0, 60
    halign = center
    valign = center
    shadow_passes = 1
    shadow_size = 4
    shadow_color = rgba(00000040)
}""" % avatar

    return """shape {
    monitor =
    size = 88, 88
    rounding = -1
    color = %s
    border_size = 1
    border_color = %s
    position = 0, 60
    halign = center
    valign = center
}

label {
    monitor =
    text = \ue7fd
    color = %s
    font_size = 30
    font_family = Material Symbols Rounded
    position = 0, 60
    halign = center
    valign = center
    zindex = 1
}""" % (color(palette, "surface", "a6"), color(palette, "border"), color(palette, "accent"))


def render(publish_avatar=True):
    palette, wallpaper = current_appearance()
    tokens = {"WALLPAPER": wallpaper_link(wallpaper), "AVATAR_BLOCK": avatar_block(palette, publish=publish_avatar),
              "BG": color(palette, "bg0"),
              "SURFACE_SOFT": color(palette, "surface", "a6"), "BORDER": color(palette, "border"),
              "TEXT": color(palette, "text"), "MUTED": color(palette, "muted"),
              "MUTED_SOFT": color(palette, "muted", "cc"), "ACCENT": color(palette, "accent"),
              "ERROR": color(palette, "red")}
    config = (COMPONENT / "design.conf.in").read_text()
    for name, value in tokens.items():
        config = config.replace("@" + name + "@", value)
    if re.search(r"@[A-Z_]+@", config):
        raise ValueError("Lock screen template has an unresolved token")
    atomic_write(CONFIG, config)
    return CONFIG


if __name__ == "__main__":
    render()
