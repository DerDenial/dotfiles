#!/usr/bin/env python3
"""User-local AppImage management. Selected binaries are never executed.

SquashFS layout follows Linux fs/squashfs/squashfs_fs.h. This deliberately
bounded reader extracts only desktop metadata and PNG icons, never a filesystem.
"""
from __future__ import annotations

import argparse
import base64
import configparser
import contextlib
import fcntl
import hashlib
import json
import lzma
import os
from pathlib import Path, PurePosixPath
import platform
import re
import shlex
import shutil
import stat
import struct
import subprocess
import sys
import tempfile
import time
import uuid
import zlib


class AppImageError(Exception):
    pass


def sha(path):
    result = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            result.update(block)
    return result.hexdigest()


def atomic(path, data, mode=0o600):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix='.' + path.name + '.', dir=path.parent)
    try:
        with os.fdopen(fd, 'wb') as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(temporary, mode)
        os.replace(temporary, path)
    finally:
        with contextlib.suppress(FileNotFoundError):
            os.unlink(temporary)


def json_write(path, data):
    atomic(path, (json.dumps(data, ensure_ascii=False, indent=2) + '\n').encode())


def read_json(path, default):
    try:
        return json.loads(path.read_text())
    except FileNotFoundError:
        return default


def fingerprint(path):
    info = path.stat()
    return {'size': info.st_size, 'mtime': info.st_mtime_ns, 'sha256': sha(path)}


def architecture(path):
    with path.open('rb') as stream:
        header = stream.read(64)
    if len(header) < 64 or header[:4] != b'\x7fELF' or header[5] != 1:
        raise AppImageError('This file is not a supported Linux AppImage.')
    if header[8:11] != b'AI\x02':
        raise AppImageError('Choose a type 2 AppImage. This image format is not supported.')
    machine = struct.unpack_from('<H', header, 18)[0]
    expected_class = {62: 2, 183: 2, 3: 1, 40: 1}.get(machine)
    if expected_class is not None and header[4] != expected_class:
        raise AppImageError('The AppImage ELF architecture header is inconsistent.')
    return {62: 'x86_64', 183: 'aarch64', 3: 'i686', 40: 'arm'}.get(machine, 'unknown')


def png_valid(data):
    if len(data) < 33 or data[:8] != b'\x89PNG\r\n\x1a\n' or data[12:16] != b'IHDR':
        return False
    width, height = struct.unpack_from('>II', data, 16)
    return 0 < width <= 2048 and 0 < height <= 2048 and len(data) <= 4 * 1024 * 1024


class SquashFS:
    """Read bounded SquashFS v4 metadata and small files from an AppImage."""
    def __init__(self, path):
        self.path = path
        self.stream = path.open('rb')
        self.length = path.stat().st_size
        prefix = self.stream.read(min(self.length, 16 * 1024 * 1024))
        self.offset = None
        start = 0
        while True:
            position = prefix.find(b'hsqs', start)
            if position < 0:
                break
            start = position + 4
            if position + 96 > len(prefix):
                continue
            fields = struct.unpack_from('<5I6H8Q', prefix, position)
            if (fields[9:11] == (4, 0) and 4096 <= fields[3] <= 1048576
                    and fields[3] & (fields[3] - 1) == 0
                    and 96 <= fields[12] <= self.length - position
                    and 96 <= fields[15] < fields[12]
                    and 96 <= fields[16] < fields[12]):
                self.offset, self.super = position, fields
                break
        if self.offset is None:
            self.close()
            raise AppImageError('Could not read the AppImage filesystem metadata.')
        self.block_size = self.super[3]
        self.compression = self.super[5]
        self.bytes_used = self.super[12]
        self.cache = {}
        self.visits = 0

    def close(self):
        self.stream.close()

    def raw(self, offset, size):
        if offset < 0 or size < 0 or offset + size > self.bytes_used:
            raise AppImageError('The AppImage filesystem contains invalid offsets.')
        self.stream.seek(self.offset + offset)
        result = self.stream.read(size)
        if len(result) != size:
            raise AppImageError('The AppImage is truncated.')
        return result

    def decompress(self, data, maximum):
        if self.compression == 1:
            decoder = zlib.decompressobj()
            result = decoder.decompress(data, maximum + 1)
            if not decoder.eof or decoder.unconsumed_tail:
                raise AppImageError('An AppImage compressed block exceeds its size limit.')
        elif self.compression == 4:
            decoder = lzma.LZMADecompressor(memlimit=128 * 1024 * 1024)
            result = decoder.decompress(data, max_length=maximum + 1)
            if not decoder.eof:
                raise AppImageError('An AppImage compressed block exceeds its size limit.')
        elif self.compression == 6:
            try:
                from compression import zstd
            except ImportError as exception:
                raise AppImageError('Reading this AppImage needs Python 3.14 or newer.') from exception
            decoder = zstd.ZstdDecompressor(options={zstd.DecompressionParameter.window_log_max: 27})
            result = decoder.decompress(data, max_length=maximum + 1)
            if not decoder.eof:
                raise AppImageError('An AppImage compressed block exceeds its size limit.')
        else:
            raise AppImageError('This AppImage compression is not supported (gzip, xz and zstd are supported).')
        if len(result) > maximum:
            raise AppImageError('An AppImage compressed block exceeds its size limit.')
        return result

    def metadata_block(self, offset):
        if offset in self.cache:
            return self.cache[offset]
        if len(self.cache) >= 512:
            raise AppImageError('The AppImage metadata is too large to inspect safely.')
        header = struct.unpack('<H', self.raw(offset, 2))[0]
        length = header & 0x7fff or 32768
        data = self.raw(offset + 2, length)
        if not header & 0x8000:
            data = self.decompress(data, 8192)
        if len(data) > 8192:
            raise AppImageError('An AppImage metadata block is invalid.')
        self.cache[offset] = (data, offset + 2 + length)
        return self.cache[offset]

    def metadata(self, offset, inner, size):
        if size > 4 * 1024 * 1024 or inner > 4 * 1024 * 1024:
            raise AppImageError('AppImage metadata exceeds its size limit.')
        result = bytearray()
        while len(result) < size:
            data, following = self.metadata_block(offset)
            if inner >= len(data):
                if not data:
                    raise AppImageError('The AppImage metadata offset is invalid.')
                inner -= len(data)
                offset = following
                continue
            take = min(size - len(result), len(data) - inner)
            if not take:
                raise AppImageError('The AppImage metadata is incomplete.')
            result.extend(data[inner:inner + take])
            offset, inner = following, 0
        return bytes(result)

    def inode(self, reference):
        block, inner = reference >> 16, reference & 0xffff
        base = self.super[15] + block
        data = self.metadata(base, inner, 16)
        kind = struct.unpack_from('<H', data)[0]
        if kind == 1:
            data = self.metadata(base, inner, 32)
            start, _, size, offset, _ = struct.unpack_from('<IIHHI', data, 16)
            return {'kind': 'directory', 'start': start, 'size': size - 3, 'offset': offset}
        if kind == 8:
            data = self.metadata(base, inner, 40)
            _, size, start, _, _, offset, _ = struct.unpack_from('<IIIIHHI', data, 16)
            return {'kind': 'directory', 'start': start, 'size': size - 3, 'offset': offset}
        if kind in (3, 10):
            data = self.metadata(base, inner, 24)
            length = struct.unpack_from('<I', data, 20)[0]
            if length > 4096:
                raise AppImageError('An AppImage symbolic link is too long.')
            link = self.metadata(base, inner + 24, length).decode('utf-8', 'strict')
            return {'kind': 'link', 'link': link}
        if kind == 2:
            data = self.metadata(base, inner, 32)
            start, fragment, offset, size = struct.unpack_from('<IIII', data, 16)
            header = 32
        elif kind == 9:
            data = self.metadata(base, inner, 56)
            start, size, _, _, fragment, offset, _ = struct.unpack_from('<QQQIIII', data, 16)
            header = 56
        else:
            return {'kind': 'other'}
        return {'kind': 'file', 'start': start, 'size': size, 'fragment': fragment,
                'offset': offset, 'meta': base, 'inner': inner + header}

    def directory(self, inode):
        if inode['size'] < 0 or inode['size'] > 1024 * 1024:
            raise AppImageError('An AppImage directory exceeds its size limit.')
        data = self.metadata(self.super[16] + inode['start'], inode['offset'], inode['size'])
        cursor = 0
        result = {}
        while cursor < len(data):
            if cursor + 12 > len(data):
                raise AppImageError('An AppImage directory is incomplete.')
            count, start, _ = struct.unpack_from('<III', data, cursor)
            cursor += 12
            if count > 255:
                raise AppImageError('An AppImage directory entry is invalid.')
            for _ in range(count + 1):
                if cursor + 8 > len(data):
                    raise AppImageError('An AppImage directory is incomplete.')
                offset, _, _, length = struct.unpack_from('<HHHH', data, cursor)
                cursor += 8
                if length > 255 or cursor + length + 1 > len(data):
                    raise AppImageError('An AppImage filename is invalid.')
                name = data[cursor:cursor + length + 1].decode('utf-8', 'strict')
                cursor += length + 1
                if name in ('.', '..') or '/' in name or '\x00' in name:
                    raise AppImageError('An AppImage filename is invalid.')
                self.visits += 1
                if self.visits > 20000:
                    raise AppImageError('This AppImage contains too many metadata entries.')
                result[name] = (start << 16) | offset
        return result

    def resolve(self, path, links=0):
        if links > 8:
            raise AppImageError('The AppImage contains a symbolic-link loop.')
        parts = list(PurePosixPath(path).parts)
        if parts and parts[0] == '/':
            parts.pop(0)
        normalized = []
        for part in parts:
            if part == '..':
                if not normalized:
                    raise AppImageError('An AppImage symbolic link escapes its filesystem.')
                normalized.pop()
            elif part not in ('', '.'):
                normalized.append(part)
        inode = self.inode(self.super[11])
        walked = []
        for index, part in enumerate(normalized):
            if inode['kind'] != 'directory':
                raise FileNotFoundError(path)
            reference = self.directory(inode).get(part)
            if reference is None:
                raise FileNotFoundError(path)
            inode = self.inode(reference)
            if inode['kind'] == 'link':
                link = inode['link']
                prefix = [] if link.startswith('/') else walked
                return self.resolve('/'.join(prefix + [link] + normalized[index + 1:]), links + 1)
            walked.append(part)
        return inode

    def file(self, path, limit=4 * 1024 * 1024):
        inode = self.resolve(path)
        if inode['kind'] != 'file' or inode['size'] > limit:
            raise AppImageError('The AppImage metadata file is missing or too large.')
        size = inode['size']
        blocks = size // self.block_size
        if inode['fragment'] == 0xffffffff and size % self.block_size:
            blocks += 1
        sizes = self.metadata(inode['meta'], inode['inner'], blocks * 4) if blocks else b''
        offset = inode['start']
        result = bytearray()
        for index in range(blocks):
            value = struct.unpack_from('<I', sizes, index * 4)[0]
            length = value & 0xffffff
            if value >> 25 or length > self.block_size + 65536:
                raise AppImageError('An AppImage data block is invalid.')
            data = self.raw(offset, length) if length else b'\0' * self.block_size
            if length and not value & 0x1000000:
                data = self.decompress(data, self.block_size)
            offset += length
            result.extend(data)
            if len(result) > limit + self.block_size:
                raise AppImageError('The AppImage metadata file exceeds its size limit.')
        remainder = size % self.block_size
        if inode['fragment'] != 0xffffffff and remainder:
            fragment = inode['fragment']
            if fragment >= self.super[4]:
                raise AppImageError('An AppImage fragment index is invalid.')
            table = fragment * 16
            pointer = struct.unpack('<Q', self.raw(self.super[17] + (table // 8192) * 8, 8))[0]
            raw = self.metadata(pointer, table % 8192, 16)
            start, value, _ = struct.unpack('<QII', raw)
            length = value & 0xffffff
            data = self.raw(start, length)
            if not value & 0x1000000:
                data = self.decompress(data, self.block_size)
            end = inode['offset'] + remainder
            if end > len(data):
                raise AppImageError('An AppImage fragment is incomplete.')
            result.extend(data[inode['offset']:end])
        if len(result) < size:
            raise AppImageError('The AppImage metadata file is incomplete.')
        return bytes(result[:size])

    def metadata_files(self):
        root = self.directory(self.inode(self.super[11]))
        desktops = sorted(name for name in root if name.endswith('.desktop'))
        if len(desktops) != 1:
            raise AppImageError('The AppImage must contain one identifiable desktop entry.')
        name = desktops[0]
        if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]{0,160}\.desktop', name):
            raise AppImageError('The AppImage desktop identifier is invalid.')
        desktop = parse_desktop(self.file(name, 128 * 1024))
        icon_name = desktop.get('Icon', '')
        candidates = [icon_name, icon_name + '.png', '.DirIcon']
        if icon_name and '/' not in icon_name:
            candidates.extend('usr/share/icons/hicolor/' + size + '/apps/' + icon_name + '.png'
                              for size in ('256x256', '512x512', '128x128', '64x64'))
            candidates.append('usr/share/pixmaps/' + icon_name + '.png')
        icon = None
        for candidate in candidates:
            if not candidate:
                continue
            try:
                data = self.file(candidate)
                if png_valid(data):
                    icon = data
                    break
            except (FileNotFoundError, AppImageError, UnicodeError, struct.error):
                continue
        return name[:-8], desktop, icon


def parse_desktop(data):
    parser = configparser.ConfigParser(interpolation=None, strict=True)
    parser.optionxform = str
    try:
        parser.read_string(data.decode('utf-8'))
        entry = dict(parser['Desktop Entry'])
    except (UnicodeError, configparser.Error, KeyError) as exception:
        raise AppImageError('The AppImage desktop metadata is invalid.') from exception
    if entry.get('Type') != 'Application' or not entry.get('Name', '').strip():
        raise AppImageError('The AppImage does not identify a desktop application.')
    return entry


class Manager:
    def __init__(self, home=None, machine=None):
        self.home = Path(home if home is not None else Path.home()).resolve()
        self.programs = self.home / 'Programs'
        self.applications = self.home / '.local/share/applications'
        self.icons = self.home / '.local/share/icons/hicolor/256x256/apps'
        self.state = self.home / '.local/share/quickshell/appimages'
        self.cache = self.home / '.cache/quickshell/appimages'
        self.machine = machine or platform.machine()
        self.records_path = self.state / 'records.json'
        self.journal = self.state / 'active.json'
        self.warnings = []

    @contextlib.contextmanager
    def locked(self):
        self.state.mkdir(parents=True, exist_ok=True, mode=0o700)
        with (self.state / 'lock').open('a') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            self.recover()
            yield

    def checked_target(self, path):
        path = Path(path)
        if any(ord(character) < 32 for character in str(path)):
            raise AppImageError('Application paths containing control characters are not supported.')
        if path.is_symlink() or not path.is_absolute():
            raise AppImageError('Symbolic-link application targets are not managed.')
        resolved = path.resolve()
        if not resolved.is_relative_to(self.programs) or resolved == self.programs:
            raise AppImageError('Only AppImages inside your Programs folder can be managed.')
        if resolved.suffix.lower() != '.appimage':
            raise AppImageError('Choose an AppImage file.')
        return resolved

    def records(self):
        return read_json(self.records_path, {})

    def desktop_entries(self):
        result = {}
        if not self.applications.is_dir():
            return result
        for path in sorted(self.applications.glob('*.desktop'))[:4000]:
            try:
                if path.stat().st_size > 128 * 1024:
                    continue
                entry = parse_desktop(path.read_bytes())
                command = shlex.split(entry.get('Exec', ''))
                if command and Path(command[0]).is_absolute():
                    target = str(Path(command[0]).resolve())
                    result.setdefault(target, (path, entry))
            except (OSError, ValueError, AppImageError):
                continue
        return result

    def inventory(self):
        entries = self.desktop_entries()
        records = self.records()
        files = []
        if self.programs.is_dir():
            for root, dirs, names in os.walk(self.programs, followlinks=False):
                relative = Path(root).relative_to(self.programs)
                dirs[:] = sorted(name for name in dirs if not name.startswith('.')
                                 and not (Path(root) / name).is_symlink()) if len(relative.parts) < 4 else []
                for name in sorted(names):
                    if name.lower().endswith('.appimage'):
                        files.append(Path(root) / name)
                if len(files) > 300:
                    self.warnings.append('Only the first 300 AppImages in Programs are shown.')
                    files = files[:300]
                    break
        apps = []
        for path in files:
            if path.is_symlink():
                continue
            ident = hashlib.sha256(str(path.resolve()).encode()).hexdigest()[:16]
            record = records.get(ident, {})
            desktop_path, entry = entries.get(str(path.resolve()), (None, {}))
            try:
                arch = architecture(path)
            except (OSError, AppImageError):
                arch = 'unsupported'
            icon = entry.get('Icon', '')
            if not Path(icon).is_absolute() or not Path(icon).is_file():
                icon = ''
            previous = record.get('previous')
            can_restore = bool(previous and self.transaction_path(previous).is_dir())
            apps.append({'id': ident, 'name': entry.get('Name', path.stem), 'path': str(path),
                         'icon': icon, 'version': entry.get('X-AppImage-Version', record.get('version', 'Unknown')),
                         'architecture': arch, 'executable': os.access(path, os.X_OK),
                         'managed': bool(desktop_path), 'canRollback': can_restore,
                         'size': path.stat().st_size, 'desktopId': desktop_path.stem if desktop_path else ''})
        return sorted(apps, key=lambda app: app['name'].casefold())

    def response(self, **extra):
        return {'ok': True, 'apps': self.inventory(), 'warnings': list(dict.fromkeys(self.warnings)), **extra}

    def inspect(self, source, target_id=''):
        path = Path(source).expanduser().resolve(strict=True)
        if not path.is_file() or path.suffix.lower() != '.appimage':
            raise AppImageError('Choose a local .AppImage file.')
        size = path.stat().st_size
        if size < 96 or size > 8 * 1024 ** 3:
            raise AppImageError('The AppImage is empty or exceeds the 8 GiB size limit.')
        arch = architecture(path)
        apps = self.inventory()
        target = next((app for app in apps if app['id'] == target_id), None)
        if target_id and target is None:
            raise AppImageError('This installed application is no longer available. Refresh and try again.')
        candidate = {'token': '', 'path': str(path), 'name': path.stem, 'version': 'Unknown',
                     'architecture': arch, 'compatible': arch == self.machine, 'icon': '',
                     'targetId': target_id, 'targetPath': target['path'] if target else '',
                     'operation': 'update' if target else 'install', 'size': size,
                     'desktopId': '', 'metadataAvailable': False, 'errorMessage': ''}
        if arch != self.machine:
            candidate['errorMessage'] = f'This image is for {arch}; your computer needs {self.machine}.'
            return self.response(candidate=candidate)
        filesystem = SquashFS(path)
        try:
            desktop_id, entry, icon = filesystem.metadata_files()
        finally:
            filesystem.close()
        if target and target['desktopId'] and target['desktopId'] != desktop_id:
            raise AppImageError('This AppImage belongs to a different application. Choose the matching update.')
        same = next((app for app in apps if app.get('desktopId') == desktop_id and app['id'] != target_id), None)
        if same:
            raise AppImageError('This app is already installed elsewhere. Use its Update button instead.')
        if not target:
            executable = desktop_id.rsplit('.', 1)[-1]
            executable = re.sub(r'[^a-z0-9_-]', '-', executable.lower()).strip('-')
            if not executable:
                raise AppImageError('The AppImage does not provide a usable application name.')
            destination = self.programs / 'AppImages' / (executable + '.AppImage')
            if destination.exists():
                raise AppImageError('An AppImage already uses that filename. Use its Update button instead.')
            target_id = hashlib.sha256(str(destination).encode()).hexdigest()[:16]
        else:
            destination = self.checked_target(target['path'])
        if path == destination and (not target or target['managed']):
            raise AppImageError('Choose a different downloaded file to update this application.')
        candidate.update(name=entry['Name'], version=entry.get('X-AppImage-Version', 'Unknown'),
                         targetId=target_id, targetPath=str(destination), desktopId=desktop_id,
                         metadataAvailable=True)
        token = uuid.uuid4().hex
        self.cache.mkdir(parents=True, exist_ok=True, mode=0o700)
        if icon:
            preview = self.cache / (token + '.png')
            atomic(preview, icon)
            candidate['icon'] = str(preview)
        elif target and target['icon']:
            candidate['icon'] = target['icon']
            self.warnings.append('No supported embedded PNG icon was found; the existing icon will be kept.')
        else:
            self.warnings.append('No supported embedded PNG icon was found; a standard application icon will be used.')
        candidate['token'] = token
        payload = {'candidate': candidate, 'created': time.time(), 'source': fingerprint(path),
                   'target': fingerprint(destination) if destination.exists() else None,
                   'desktop': entry, 'icon': base64.b64encode(icon).decode() if icon else None}
        json_write(self.cache / (token + '.json'), payload)
        self.clean_cache()
        return self.response(candidate=candidate)

    def clean_cache(self):
        retained = []
        for path in self.cache.glob('*'):
            if re.fullmatch(r'[a-f0-9]{32}\.(json|png)', path.name):
                with contextlib.suppress(OSError):
                    if time.time() - path.stat().st_mtime > 3600:
                        path.unlink()
                    else:
                        retained.append(path)
        for path in sorted(retained, key=lambda item: item.stat().st_mtime, reverse=True)[80:]:
            path.unlink(missing_ok=True)

    def transaction_path(self, ident):
        if not re.fullmatch(r'[a-f0-9]{32}', ident):
            raise AppImageError('The saved AppImage backup is invalid.')
        return self.state / 'transactions' / ident

    def allowed_write(self, path):
        path = Path(path)
        if path.is_symlink():
            raise AppImageError('A managed destination was replaced by a symbolic link.')
        resolved = path.resolve()
        if (resolved.is_relative_to(self.programs) and resolved.suffix.lower() == '.appimage'):
            return
        if resolved.parent in (self.applications, self.icons) and re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]{0,160}\.(desktop|png)', resolved.name):
            return
        if resolved == self.records_path:
            return
        raise AppImageError('The saved AppImage transaction contains an invalid path.')

    def snapshot(self, paths):
        ident = uuid.uuid4().hex
        directory = self.transaction_path(ident)
        directory.mkdir(parents=True, mode=0o700)
        entries = []
        try:
            for index, path in enumerate(paths):
                self.allowed_write(path)
                entry = {'path': str(path), 'exists': path.exists(), 'backup': str(index)}
                if path.exists():
                    entry['mode'] = stat.S_IMODE(path.stat().st_mode)
                    shutil.copyfile(path, directory / str(index))
                entries.append(entry)
            json_write(directory / 'snapshot.json', entries)
        except BaseException:
            shutil.rmtree(directory, ignore_errors=True)
            raise
        return ident

    def restore_snapshot(self, ident, include_records=True):
        directory = self.transaction_path(ident)
        entries = read_json(directory / 'snapshot.json', None)
        if not isinstance(entries, list) or len(entries) > 8:
            raise AppImageError('The saved AppImage recovery data is invalid.')
        for entry in entries:
            path = Path(entry['path'])
            self.allowed_write(path)
            if path == self.records_path and not include_records:
                continue
            if entry['exists']:
                backup = directory / entry['backup']
                if backup.parent != directory or not backup.is_file():
                    raise AppImageError('An AppImage backup file is missing.')
                self.copy_replace(backup, path, entry['mode'])
            else:
                path.unlink(missing_ok=True)

    def recover(self):
        journal = read_json(self.journal, None)
        if journal:
            self.restore_snapshot(journal['snapshot'])
            self.journal.unlink()
            shutil.rmtree(self.transaction_path(journal['snapshot']), ignore_errors=True)
            self.warnings.append('An interrupted AppImage change was safely rolled back.')

    def copy_replace(self, source, target, mode=0o755):
        target.parent.mkdir(parents=True, exist_ok=True)
        fd, temporary = tempfile.mkstemp(prefix='.' + target.name + '.', dir=target.parent)
        try:
            with os.fdopen(fd, 'wb') as output, source.open('rb') as original:
                shutil.copyfileobj(original, output, 1024 * 1024)
                output.flush()
                os.fsync(output.fileno())
            os.chmod(temporary, mode)
            os.replace(temporary, target)
        finally:
            with contextlib.suppress(FileNotFoundError):
                os.unlink(temporary)

    def desktop_text(self, entry, desktop_id, target, icon_path, old=None):
        selected = {}
        for key, value in entry.items():
            if key in ('Name', 'GenericName', 'Comment', 'StartupWMClass', 'Categories', 'MimeType',
                       'Keywords', 'X-AppImage-Version') or re.fullmatch(r'(Name|GenericName|Comment|Keywords)\[[A-Za-z0-9_@.-]+\]', key):
                if any(ord(character) < 32 for character in value):
                    continue
                selected[key] = value
        if old:
            for key, value in old.items():
                if '[' in key and key not in selected:
                    selected[key] = value
        command = (old or entry).get('Exec', '')
        try:
            arguments = shlex.split(command)
        except ValueError as exception:
            raise AppImageError('The application launch arguments are invalid.') from exception
        if not arguments:
            raise AppImageError('The AppImage has no application launch command.')

        def quote(value):
            if any(ord(character) < 32 for character in value):
                raise AppImageError('The application launch arguments contain unsupported control characters.')
            escaped = value.replace('\\', '\\\\').replace('"', '\\"').replace('`', '\\`').replace('$', '\\$').replace('%', '%%')
            return '"' + escaped + '"'

        launch = [quote(str(target))]
        for argument in arguments[1:]:
            if re.fullmatch(r'%[fFuUick]', argument):
                launch.append(argument)
            else:
                # Desktop field codes embedded in arguments have undefined
                # semantics. Preserve static arguments, reject ambiguous ones.
                if re.search(r'%(?!%)', argument.replace('%%', '')):
                    raise AppImageError('The application uses unsupported embedded launch placeholders.')
                launch.append(quote(argument.replace('%%', '%')))
        result = {'Type': 'Application', **selected, 'Exec': ' '.join(launch),
                  'TryExec': str(target), 'Icon': str(icon_path) if icon_path else 'application-x-executable',
                  'Terminal': 'false', 'StartupNotify': 'true'}
        return ('[Desktop Entry]\n' + ''.join(key + '=' + value + '\n' for key, value in result.items())).encode()

    def validate_desktop(self, data):
        validator = shutil.which('desktop-file-validate')
        if not validator:
            self.warnings.append('Desktop validation tool was unavailable; the entry was checked internally.')
            return
        self.cache.mkdir(parents=True, exist_ok=True)
        fd, temporary = tempfile.mkstemp(suffix='.desktop', dir=self.cache)
        try:
            with os.fdopen(fd, 'wb') as stream:
                stream.write(data)
            result = subprocess.run([validator, temporary], capture_output=True, text=True, timeout=10)
            if result.returncode:
                raise AppImageError('The AppImage desktop metadata did not pass validation.')
        finally:
            Path(temporary).unlink(missing_ok=True)

    def update_database(self):
        command = shutil.which('update-desktop-database')
        if command:
            try:
                result = subprocess.run([command, str(self.applications)], capture_output=True, timeout=15)
                if result.returncode:
                    self.warnings.append('The app was saved, but the desktop MIME database could not be refreshed.')
            except (OSError, subprocess.TimeoutExpired):
                self.warnings.append('The app was saved, but the desktop MIME database could not be refreshed.')

    def apply(self, token):
        if not re.fullmatch(r'[a-f0-9]{32}', token):
            raise AppImageError('Choose an AppImage again before applying it.')
        payload = read_json(self.cache / (token + '.json'), None)
        if not payload or time.time() - payload['created'] > 600:
            raise AppImageError('This preview expired. Choose the AppImage again.')
        candidate = payload['candidate']
        source = Path(candidate['path'])
        destination = self.checked_target(candidate['targetPath'])
        if fingerprint(source) != payload['source'] or architecture(source) != self.machine:
            raise AppImageError('The downloaded AppImage changed. Choose it again before applying.')
        actual_target = fingerprint(destination) if destination.exists() else None
        if actual_target != payload['target']:
            raise AppImageError('The installed AppImage changed. Refresh and choose the update again.')
        desktop_id = candidate['desktopId']
        desktop = self.applications / (desktop_id + '.desktop')
        icon = self.icons / (desktop_id + '.png')
        for path in (desktop, icon):
            self.allowed_write(path)
        old_entry = parse_desktop(desktop.read_bytes()) if desktop.exists() else None
        if old_entry:
            try:
                previous_path = Path(shlex.split(old_entry.get('Exec', ''))[0]).resolve()
            except (IndexError, ValueError):
                previous_path = None
            if previous_path != destination:
                raise AppImageError('Another launcher already uses this application identifier.')
        embedded_icon = base64.b64decode(payload['icon'], validate=True) if payload['icon'] else None
        chosen_icon = icon if embedded_icon else (Path(old_entry['Icon']) if old_entry and Path(old_entry.get('Icon', '')).is_absolute() and Path(old_entry['Icon']).is_file() else None)
        text = self.desktop_text(payload['desktop'], desktop_id, destination, chosen_icon, old_entry)
        self.validate_desktop(text)
        paths = [destination, desktop, self.records_path]
        if embedded_icon:
            paths.insert(2, icon)
        snapshot = self.snapshot(paths)
        records = self.records()
        previous_record = records.get(candidate['targetId'], {})
        record = {'path': str(destination), 'desktopId': desktop_id, 'name': candidate['name'],
                  'version': candidate['version'], 'previous': snapshot if payload['target'] else None}
        record['installed'] = {str(destination): payload['source']['sha256'],
                               str(desktop): hashlib.sha256(text).hexdigest()}
        if embedded_icon:
            record['installed'][str(icon)] = hashlib.sha256(embedded_icon).hexdigest()
        records[candidate['targetId']] = record
        json_write(self.journal, {'snapshot': snapshot})
        try:
            self.copy_replace(source, destination)
            if sha(destination) != payload['source']['sha256']:
                raise AppImageError('The AppImage copy could not be verified.')
            if embedded_icon:
                atomic(icon, embedded_icon, 0o644)
            atomic(desktop, text, 0o644)
            json_write(self.records_path, records)
            self.journal.unlink()
        except BaseException:
            self.restore_snapshot(snapshot)
            self.journal.unlink(missing_ok=True)
            shutil.rmtree(self.transaction_path(snapshot), ignore_errors=True)
            raise
        # One previous version is retained; do not remove it until commit succeeds.
        older = previous_record.get('previous')
        if older and older != snapshot:
            shutil.rmtree(self.transaction_path(older), ignore_errors=True)
        if not payload['target']:
            shutil.rmtree(self.transaction_path(snapshot), ignore_errors=True)
        (self.cache / (token + '.json')).unlink(missing_ok=True)
        (self.cache / (token + '.png')).unlink(missing_ok=True)
        self.update_database()
        if not embedded_icon:
            self.warnings.append('No supported embedded PNG icon was found; the previous icon was kept when available.')
        return self.response(message=candidate['name'] + (' updated. Reopen the app to use the new version.' if payload['target'] else ' added to the launcher.'))

    def restore(self, ident):
        records = self.records()
        record = records.get(ident)
        if not record or not record.get('previous'):
            raise AppImageError('There is no previous version available for this app.')
        prior = record['previous']
        for path, expected in record.get('installed', {}).items():
            target = Path(path)
            self.allowed_write(target)
            if not target.exists() or sha(target) != expected:
                raise AppImageError('The installed app or its launcher changed after the update; its previous version was not restored.')
        directory = self.transaction_path(prior)
        entries = read_json(directory / 'snapshot.json', None)
        if not entries:
            raise AppImageError('The previous AppImage backup is missing.')
        safety = self.snapshot([Path(entry['path']) for entry in entries])
        json_write(self.journal, {'snapshot': safety})
        try:
            self.restore_snapshot(prior, include_records=False)
            # A per-app rollback must not revert records for unrelated apps.
            restored = records.copy()
            previous_records = {}
            for entry in entries:
                if Path(entry['path']) == self.records_path and entry['exists']:
                    previous_records = read_json(directory / entry['backup'], {})
            current_record = previous_records.get(ident, {'path': record['path'], 'name': record['name'],
                                                        'desktopId': record['desktopId'], 'version': 'Unknown'})
            current_record['previous'] = None
            current_record.pop('installed', None)
            restored[ident] = current_record
            json_write(self.records_path, restored)
            self.journal.unlink()
        except BaseException:
            self.restore_snapshot(safety)
            self.journal.unlink(missing_ok=True)
            shutil.rmtree(self.transaction_path(safety), ignore_errors=True)
            raise
        shutil.rmtree(directory, ignore_errors=True)
        shutil.rmtree(self.transaction_path(safety), ignore_errors=True)
        self.update_database()
        return self.response(message='Previous version restored. Reopen the app to use it.')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('command', choices=('list', 'inspect', 'apply', 'restore'))
    parser.add_argument('argument', nargs='?', default='')
    parser.add_argument('target', nargs='?', default='')
    arguments = parser.parse_args()
    manager = Manager()
    try:
        with manager.locked():
            if arguments.command == 'list':
                response = manager.response()
            elif arguments.command == 'inspect':
                response = manager.inspect(arguments.argument, arguments.target)
            elif arguments.command == 'apply':
                response = manager.apply(arguments.argument)
            else:
                response = manager.restore(arguments.argument)
        print(json.dumps(response, ensure_ascii=False))
    except Exception as exception:
        print(json.dumps({'ok': False, 'error': str(exception) or 'The AppImage operation failed.'}, ensure_ascii=False))
        raise SystemExit(1)


if __name__ == '__main__':
    main()
