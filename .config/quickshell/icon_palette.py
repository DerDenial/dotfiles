"""Build a small Colloid folder overlay from the current desktop accent.

The installed Colloid theme remains unchanged. Only ordinary Places icons are
copied, and aliases are materialized so they cannot escape the generated theme.
"""

import configparser
import hashlib
import json
import logging
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import tempfile


_VERSION = 1
_OWNER = "quickshell-colloid-folder-overlay"
_MARKER = ".quickshell-colloid.json"
_PREFIX = "Quickshell-Colloid-"
_NAME = re.compile(r"Quickshell-Colloid-([0-9a-f]{12})\Z")
_COLOR = re.compile(r"#[0-9a-fA-F]{6}\Z")
_BLUE = re.compile(r"#60c0f0(?![0-9a-fA-F])", re.IGNORECASE)
_OUTLINE = re.compile(r"#(?:dedede|363636)(?![0-9a-fA-F])", re.IGNORECASE)
_SIZES = ("16", "22", "24", "scalable")
_LOG = logging.getLogger(__name__)


def _inside(path, parent):
    try:
        path.relative_to(parent)
        return True
    except ValueError:
        return False


def _regular_owned(path):
    info = path.lstat()
    return stat.S_ISREG(info.st_mode) and info.st_uid == os.getuid()


def _manifest(path):
    """Recognize only directories created by this generator, never symlinks."""
    try:
        info = path.lstat()
        match = _NAME.fullmatch(path.name)
        if not match or not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid():
            return None
        marker = path / _MARKER
        if not _regular_owned(marker):
            return None
        manifest = json.loads(marker.read_text(encoding="utf-8"))
        if (manifest.get("owner") != _OWNER
                or manifest.get("version") != _VERSION
                or not isinstance(manifest.get("digest"), str)
                or not re.fullmatch(r"[0-9a-f]{64}", manifest["digest"])
                or manifest["digest"][:12] != match.group(1)
                or not isinstance(manifest.get("files"), dict)):
            return None
        # Reject path traversal and unrecognized content before pruning a theme.
        for name, digest in manifest["files"].items():
            relative = Path(name)
            if (relative.is_absolute() or ".." in relative.parts
                    or name not in ("index.theme", "COPYING", "README.quickshell")
                    and not (len(relative.parts) == 3
                             and relative.parts[0] == "places"
                             and relative.parts[1] in _SIZES
                             and relative.suffix == ".svg")
                    or not isinstance(digest, str)
                    or not re.fullmatch(r"[0-9a-f]{64}", digest)):
                return None
        return manifest
    except (OSError, ValueError, TypeError):
        return None


def _known_contents(path, manifest, verify_hashes=False):
    expected = set(manifest["files"]) | {_MARKER}
    allowed_dirs = {"places", *("places/" + size for size in _SIZES)}
    found = set()
    try:
        for root, directories, files in os.walk(path, followlinks=False):
            root = Path(root)
            for name in directories[:]:
                child = root / name
                relative = child.relative_to(path).as_posix()
                if child.is_symlink():
                    if relative not in ("places@2x", "places@3x") or os.readlink(child) != "places":
                        return False
                    directories.remove(name)
                elif relative not in allowed_dirs:
                    return False
            for name in files:
                child = root / name
                relative = child.relative_to(path).as_posix()
                if relative == "icon-theme.cache":
                    if not _regular_owned(child):
                        return False
                    continue
                if relative not in expected or not _regular_owned(child):
                    return False
                if verify_hashes and relative in manifest["files"]:
                    if hashlib.sha256(child.read_bytes()).hexdigest() != manifest["files"][relative]:
                        return False
                found.add(relative)
        return found == expected and all((path / link).is_symlink() for link in ("places@2x", "places@3x"))
    except OSError:
        return False


def _selected_icons(base, accent):
    places = (base / "places").resolve(strict=True)
    result = {}
    for size in _SIZES:
        directory = places / size
        if not directory.is_dir() or not _inside(directory.resolve(), places):
            continue
        for source in sorted(directory.glob("*.svg")):
            try:
                resolved = source.resolve(strict=True)
                if (not _inside(resolved, places) or not resolved.is_file()
                        or "-symbolic" in source.name or "-symbolic" in resolved.name):
                    continue
                original = source.read_text(encoding="utf-8")
            except (OSError, UnicodeError, RuntimeError):
                continue
            if size == "scalable":
                changed, count = _BLUE.subn(accent, original)
            elif (source.stem.startswith("folder") or resolved.stem.startswith("folder")
                  or source.stem in ("user-home", "inode-directory")):
                changed, count = _OUTLINE.subn(accent, original)
            else:
                continue
            if count:
                result[f"places/{size}/{source.name}"] = changed.encode("utf-8")
    return result


def _theme_index(base):
    original = configparser.ConfigParser(interpolation=None)
    original.optionxform = str
    original.read(base / "index.theme", encoding="utf-8")
    ordinary = ["places/" + size for size in _SIZES]
    scaled = [f"places@{scale}x/{size}" for scale in (2, 3) for size in _SIZES]
    text = ("[Icon Theme]\nName=Colloid Material\n"
            "Comment=Colloid folders following the Quickshell desktop accent.\n"
            "Inherits=Colloid-Dark,hicolor\nExample=folder\n"
            "Directories=" + ",".join(ordinary) + "\n"
            "ScaledDirectories=" + ",".join(scaled) + "\n")
    for scale in (1, 2, 3):
        for size in _SIZES:
            source = original[f"places/{size}"]
            section = f"places/{size}" if scale == 1 else f"places@{scale}x/{size}"
            text += f"\n[{section}]\nSize={source['Size']}\nContext=Places\nType={source['Type']}\n"
            if scale != 1:
                text += f"Scale={scale}\n"
            for key in ("MinSize", "MaxSize"):
                if key in source:
                    text += f"{key}={source[key]}\n"
    return text.encode("utf-8")


def _license(base):
    candidates = (base / "COPYING", base / "LICENSE",
                  Path(__file__).resolve().parent / "upstream/LICENSE")
    for candidate in candidates:
        if candidate.is_file():
            return candidate.read_bytes()
    raise FileNotFoundError("Colloid's COPYING or LICENSE is required for its generated folder overlay")


def _protected_themes():
    """Keep the theme still displayed while GTK receives the new selection."""
    config = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
    protected = set()
    for version in (3, 4):
        settings = configparser.ConfigParser(interpolation=None)
        try:
            settings.read(config / f"gtk-{version}.0/settings.ini", encoding="utf-8")
            value = settings.get("Settings", "gtk-icon-theme-name", fallback="")
            if _NAME.fullmatch(value):
                protected.add(value)
        except (OSError, configparser.Error):
            pass
    return protected


def _prune(icons, current):
    candidates = []
    try:
        for path in icons.glob(_PREFIX + "*"):
            manifest = _manifest(path)
            if manifest and _known_contents(path, manifest):
                candidates.append(path)
        previous = sorted((path for path in candidates if path.name != current),
                          key=lambda path: path.stat().st_mtime_ns, reverse=True)
        keep = {current, *[path.name for path in previous[:2]], *_protected_themes()}
        for path in previous:
            if path.name not in keep:
                # Recheck immediately before removal. rmtree does not follow the
                # two known HiDPI symlinks and rejects a symlink at its root.
                manifest = _manifest(path)
                if manifest and _known_contents(path, manifest):
                    shutil.rmtree(path)
    except OSError as error:
        _LOG.warning("Old Colloid folder overlays could not be cleaned up: %s", error)


def build_colloid_overlay(palette, data_home=None, base_theme=None):
    """Return a ready icon theme name, or None when Colloid-Dark is absent.

    All output is written beneath data_home/icons. Palette and theme format
    errors are surfaced to the caller, which can preserve the active theme.
    """
    accent = palette.get("accent", palette.get("aqua"))
    if not isinstance(accent, str) or not _COLOR.fullmatch(accent):
        raise ValueError("Colloid folder accent must be a six-digit hexadecimal color")
    accent = accent.lower()
    data = Path(data_home) if data_home is not None else Path(os.environ.get("XDG_DATA_HOME") or Path.home() / ".local/share")
    base = Path(base_theme) if base_theme is not None else data / "icons/Colloid-Dark"
    if not (base / "index.theme").is_file() or not (base / "places").is_dir():
        return None

    assets = _selected_icons(base, accent)
    if not assets:
        raise ValueError("Installed Colloid-Dark has no supported folder color markers")
    try:
        assets["index.theme"] = _theme_index(base)
    except (configparser.Error, KeyError) as error:
        raise ValueError("Colloid-Dark has an unsupported icon index") from error
    assets["COPYING"] = _license(base)
    assets["README.quickshell"] = (
        "Colloid icon theme by vinceliuice and contributors.\n"
        "https://github.com/vinceliuice/Colloid-icon-theme\n"
        "License: GNU GPL version 3; see COPYING.\n\n"
        "Modified by Quickshell: folder colors follow the desktop accent.\n"
        "Shapes, embedded shadows and gradients remain from Colloid.\n"
        f"Generator format: {_VERSION}\nAccent: {accent}\n"
    ).encode("utf-8")
    digest = hashlib.sha256(f"{_OWNER}\n{_VERSION}\n{accent}\n".encode())
    hashes = {}
    for name, contents in sorted(assets.items()):
        digest.update(name.encode() + b"\0" + contents + b"\0")
        hashes[name] = hashlib.sha256(contents).hexdigest()
    full_digest = digest.hexdigest()
    name = _PREFIX + full_digest[:12]
    icons = data / "icons"
    icons.mkdir(parents=True, exist_ok=True)
    target = icons / name
    existing = _manifest(target)
    if existing and existing["digest"] == full_digest and existing["files"] == hashes and _known_contents(target, existing, verify_hashes=True):
        os.utime(target, None)
        _prune(icons, name)
        return name
    if target.exists() or target.is_symlink():
        raise FileExistsError(f"Refusing to replace an unrecognized or incomplete icon theme: {target}")

    temporary = Path(tempfile.mkdtemp(prefix=".quickshell-colloid-build-", dir=icons))
    try:
        for relative, contents in assets.items():
            output = temporary / relative
            output.parent.mkdir(parents=True, exist_ok=True)
            output.write_bytes(contents)
        for scale in (2, 3):
            (temporary / f"places@{scale}x").symlink_to("places", target_is_directory=True)
        marker = {"owner": _OWNER, "version": _VERSION, "digest": full_digest,
                  "accent": accent, "files": hashes}
        (temporary / _MARKER).write_text(json.dumps(marker, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        cache_tool = shutil.which("gtk-update-icon-cache")
        if cache_tool:
            try:
                # Use only options supported by the installed GTK utility.
                result = subprocess.run([cache_tool, "-f", "-q", str(temporary)],
                                        stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
                                        text=True, check=False, timeout=20)
                if result.returncode:
                    _LOG.warning("Colloid icon cache was skipped: %s", result.stderr.strip())
            except subprocess.SubprocessError as error:
                _LOG.warning("Colloid icon cache was skipped: %s", error)
        # Publish only a complete theme. Existing generations are never edited.
        temporary.rename(target)
        _prune(icons, name)
        return name
    finally:
        if temporary.exists():
            shutil.rmtree(temporary)
