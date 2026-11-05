#!/usr/bin/env python3
"""Persist a private avatar selection and publish data-only greeter images.

The import API intentionally needs only the standard library: the lock screen
and palette sync import it with system Python. Pillow is loaded only by ``set``.
"""
import configparser
import fcntl
import hashlib
from io import BytesIO, StringIO
import json
import os
from pathlib import Path
import pwd
import re
import stat
import sys
import tempfile
import warnings

HOME = Path.home()
PUBLIC = Path('/var/lib/quickshell-sddm')
CACHE = HOME / '.config/quickshell/LockScreen/generated/profile'
EXTENSIONS = {'.png', '.jpg', '.jpeg', '.webp'}
MAX_BYTES = 20 * 1024 * 1024
MAX_PIXELS = 40_000_000
MAX_DIMENSION = 16_384
AVATAR_SIZE = 512
_CACHE_NAME = re.compile(r'avatar(?:-[a-f0-9]{20})?\.(?:png|jpe?g|webp)\Z')


def atomic_bytes(path, data, mode=0o600):
    """Replace a file without exposing a partial image or selection record."""
    path = Path(path)
    if path.is_file() and not path.is_symlink() and path.read_bytes() == data:
        os.chmod(path, mode)
        return
    descriptor, temporary = tempfile.mkstemp(prefix='.' + path.name + '-', dir=path.parent)
    try:
        with os.fdopen(descriptor, 'wb') as output:
            output.write(data)
            output.flush()
            os.fsync(output.fileno())
            os.fchmod(output.fileno(), mode)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def _selection_path():
    return CACHE / 'selection.json'


def _read_selection():
    try:
        value = json.loads(_selection_path().read_text(encoding='utf-8'))
    except FileNotFoundError:
        return {'mode': 'auto'}
    except (OSError, ValueError, TypeError):
        return {'mode': 'cleared', 'unreadable': True}
    if isinstance(value, dict) and value.get('version') == 1:
        if value.get('mode') == 'cleared':
            return {'mode': 'cleared'}
        if (value.get('mode') == 'selected'
                and isinstance(value.get('sourcePath'), str)
                and Path(value['sourcePath']).is_absolute()
                and isinstance(value.get('avatar'), str)
                and _CACHE_NAME.fullmatch(value['avatar'])):
            return value
    # A damaged explicit choice must not reactivate automatic folder selection.
    return {'mode': 'cleared', 'unreadable': True}


def _automatic_image():
    candidates = []
    try:
        folders = [item for item in (HOME / 'Pictures').iterdir()
                   if item.is_dir() and item.name.casefold() == 'profile pictures']
        for folder in folders:
            for image in folder.iterdir():
                try:
                    info = image.stat()
                    if (stat.S_ISREG(info.st_mode) and image.suffix.lower() in EXTENSIONS
                            and 0 < info.st_size <= MAX_BYTES):
                        candidates.append((info.st_mtime_ns, image.name, image))
                except OSError:
                    continue
    except OSError:
        pass
    return max(candidates, key=lambda item: item[:2])[2] if candidates else None


def selected_image():
    """Return the explicit source, or the latest legacy folder image by default."""
    state = _read_selection()
    if state['mode'] == 'selected':
        return Path(state['sourcePath'])
    return _automatic_image() if state['mode'] == 'auto' else None


def _image_suffix(data):
    if data.startswith(b'\x89PNG\r\n\x1a\n'):
        return '.png'
    if data.startswith(b'\xff\xd8\xff'):
        return '.jpg'
    if data[:4] == b'RIFF' and data[8:12] == b'WEBP':
        return '.webp'
    return None


def _read_image(path):
    with Path(path).open('rb') as source:
        info = os.fstat(source.fileno())
        if not stat.S_ISREG(info.st_mode) or not 0 < info.st_size <= MAX_BYTES:
            raise ValueError('Choose a regular image file no larger than 20 MiB.')
        data = source.read(MAX_BYTES + 1)
    if len(data) > MAX_BYTES or not _image_suffix(data):
        raise ValueError('Choose a PNG, JPEG or WebP image no larger than 20 MiB.')
    return data


def _private_directory():
    CACHE.mkdir(mode=0o700, parents=True, exist_ok=True)
    os.chmod(CACHE, 0o700)


def _cached_avatar(name):
    if not isinstance(name, str) or not _CACHE_NAME.fullmatch(name):
        return None
    candidate = CACHE / name
    try:
        _read_image(candidate)
        return candidate
    except (OSError, ValueError):
        return None


def _retained_avatar():
    """Keep the existing cached portrait when its old source folder is gone."""
    try:
        candidates = sorted((item for item in CACHE.iterdir()
                             if _CACHE_NAME.fullmatch(item.name)),
                            key=lambda item: (item.stat().st_mtime_ns, item.name), reverse=True)
        for candidate in candidates:
            valid = _cached_avatar(candidate.name)
            if valid is not None:
                return valid
    except OSError:
        pass
    return None


def _resolve_avatar():
    state = _read_selection()
    if state['mode'] == 'cleared':
        return None, state, ''
    if state['mode'] == 'selected':
        return _cached_avatar(state['avatar']), state, state['sourcePath']
    source = _automatic_image()
    if source is not None:
        try:
            data = _read_image(source)
            _private_directory()
            avatar = CACHE / ('avatar-' + hashlib.sha256(data).hexdigest()[:20] + _image_suffix(data))
            atomic_bytes(avatar, data)
            return avatar, state, str(source)
        except (OSError, ValueError):
            pass
    return _retained_avatar(), state, ''


def avatar_settings(directory, avatar):
    """Called under the shared appearance lock; publish no private source path."""
    username = pwd.getpwuid(os.getuid()).pw_name
    if avatar is None:
        return {'avatar': '', 'profileUsername': username}
    data = _read_image(avatar)
    name = 'avatar-' + hashlib.sha256(data).hexdigest()[:20] + _image_suffix(data)
    target = Path(directory) / name
    atomic_bytes(target, data, 0o644)
    return {'avatar': str(target), 'profileUsername': username}


def publish_profile(avatar):
    """Update only avatar fields while respecting the palette writer's lock."""
    if not PUBLIC.is_dir():
        raise OSError('The sign-in screen data folder is unavailable.')
    with (PUBLIC / '.appearance.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        path = PUBLIC / 'theme.ini'
        settings = configparser.ConfigParser(interpolation=None)
        settings.optionxform = str
        with path.open(encoding='utf-8') as source:
            settings.read_file(source)
        if not settings.has_section('Theme'):
            raise ValueError('The sign-in screen does not yet have a complete color palette.')
        for key, value in avatar_settings(PUBLIC, avatar).items():
            settings['Theme'][key] = value
        output = StringIO()
        settings.write(output)
        atomic_bytes(path, output.getvalue().encode('utf-8'), 0o644)


def ensure_avatar(publish=True):
    """Keep lock-screen and existing palette-sync imports failure tolerant."""
    try:
        avatar, _state, _source = _resolve_avatar()
    except (OSError, ValueError, TypeError):
        avatar = None
    if publish:
        try:
            publish_profile(avatar)
        except (OSError, ValueError, configparser.Error):
            pass
    return avatar


def _current():
    avatar, state, source = _resolve_avatar()
    return {'sourcePath': source, 'fileUrl': avatar.as_uri() if avatar else '',
            'hasImage': avatar is not None, 'mode': state['mode']}


def _response(ok=True, extra_warnings=None, error=None):
    issues = list(extra_warnings or [])
    if _read_selection().get('unreadable'):
        issues.append('The saved profile picture selection could not be read.')
    try:
        current = _current()
    except (OSError, ValueError, TypeError):
        current = {'sourcePath': '', 'fileUrl': '', 'hasImage': False, 'mode': 'cleared'}
    result = {'ok': ok, 'current': current, 'warnings': issues}
    if error is not None:
        result['error'] = str(error)
    return result


def _normalize_image(source):
    """Decode once, orient, center-crop and strip all input metadata."""
    from PIL import Image, ImageOps, UnidentifiedImageError

    path = Path(source)
    if not path.is_absolute():
        raise ValueError('Choose an image using its absolute file path.')
    if path.suffix.lower() not in EXTENSIONS:
        raise ValueError('Choose a PNG, JPEG or WebP image.')
    data = _read_image(path)
    try:
        with warnings.catch_warnings():
            warnings.simplefilter('error', Image.DecompressionBombWarning)
            with Image.open(BytesIO(data)) as original:
                if original.format not in {'PNG', 'JPEG', 'WEBP'}:
                    raise ValueError('This image format is not supported.')
                width, height = original.size
                if (width < 1 or height < 1 or width * height > MAX_PIXELS
                        or max(width, height) > MAX_DIMENSION):
                    raise ValueError('The image must be no larger than 40 megapixels or 16,384 pixels per side.')
                oriented = ImageOps.exif_transpose(original)
                crop = ImageOps.fit(oriented.convert('RGBA'), (AVATAR_SIZE, AVATAR_SIZE),
                                    method=Image.Resampling.LANCZOS, centering=(0.5, 0.5))
                clean = Image.new('RGBA', (AVATAR_SIZE, AVATAR_SIZE))
                clean.paste(crop)
                output = BytesIO()
                clean.save(output, format='PNG', optimize=True)
                return path.resolve(), output.getvalue()
    except (UnidentifiedImageError, Image.DecompressionBombError,
            Image.DecompressionBombWarning, OSError, SyntaxError) as error:
        raise ValueError('This image could not be safely read.') from error


def _publication_warnings(avatar):
    try:
        publish_profile(avatar)
        return []
    except (OSError, ValueError, configparser.Error) as error:
        return ['Profile picture choice saved. The sign-in screen could not be updated yet: ' + str(error)]


def set_avatar(source):
    """Commit the normalized snapshot before exposing the explicit selection."""
    try:
        path, data = _normalize_image(source)
        _private_directory()
        with (CACHE / '.profile.lock').open('a') as lock:
            os.chmod(CACHE / '.profile.lock', 0o600)
            fcntl.flock(lock, fcntl.LOCK_EX)
            name = 'avatar-' + hashlib.sha256(data).hexdigest()[:20] + '.png'
            avatar = CACHE / name
            atomic_bytes(avatar, data)
            state = {'version': 1, 'mode': 'selected', 'sourcePath': str(path), 'avatar': name}
            atomic_bytes(_selection_path(), (json.dumps(state, ensure_ascii=False) + '\n').encode('utf-8'))
            issues = _publication_warnings(avatar)
        return _response(extra_warnings=issues)
    except (OSError, ValueError, TypeError, ImportError) as error:
        return _response(ok=False, error=error)


def clear_avatar():
    """Persist an intentional empty avatar; do not resume folder auto-selection."""
    try:
        _private_directory()
        with (CACHE / '.profile.lock').open('a') as lock:
            os.chmod(CACHE / '.profile.lock', 0o600)
            fcntl.flock(lock, fcntl.LOCK_EX)
            state = {'version': 1, 'mode': 'cleared'}
            atomic_bytes(_selection_path(), (json.dumps(state) + '\n').encode('utf-8'))
            issues = _publication_warnings(None)
        return _response(extra_warnings=issues)
    except (OSError, ValueError, TypeError) as error:
        return _response(ok=False, error=error)


def main(arguments=None):
    arguments = sys.argv[1:] if arguments is None else arguments
    if not arguments:
        print(ensure_avatar() or 'Kein Profilbild gefunden.')
        return 0
    if arguments == ['get']:
        result = _response()
    elif len(arguments) == 2 and arguments[0] == 'set':
        result = set_avatar(arguments[1])
    elif arguments == ['clear']:
        result = clear_avatar()
    else:
        result = _response(ok=False, error='Usage: profile-avatar.py get | set /absolute/image/path | clear')
    print(json.dumps(result, ensure_ascii=False))
    return 0 if result['ok'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
