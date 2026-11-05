#!/usr/bin/env python3
"""Validated live input settings with atomic, readable Hyprland persistence."""
import concurrent.futures
import json
import math
import os
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parent
STATE = ROOT / 'input-preferences.json'
LUA = ROOT / 'input-overrides.lua'
OPTIONS = {
    'naturalScroll': ('input:touchpad:natural_scroll', 'touchpad', 'natural_scroll', bool, 0, 1),
    'tapToClick': ('input:touchpad:tap-to-click', 'touchpad', 'tap-to-click', bool, 0, 1),
    'disableWhileTyping': ('input:touchpad:disable_while_typing', 'touchpad', 'disable_while_typing', bool, 0, 1),
    'sensitivity': ('input:sensitivity', '', 'sensitivity', float, -1, 1),
    'repeatRate': ('input:repeat_rate', '', 'repeat_rate', int, 1, 80),
    'repeatDelay': ('input:repeat_delay', '', 'repeat_delay', int, 100, 1000),
    'followMouse': ('input:follow_mouse', '', 'follow_mouse', int, 0, 3),
}

def run(arguments):
    result = subprocess.run(arguments, capture_output=True, text=True, timeout=4)
    if result.returncode:
        raise RuntimeError((result.stderr or result.stdout).strip()[:200] or 'The compositor did not accept the setting.')
    return result.stdout.strip()

def read_option(key):
    try:
        info = json.loads(run(['hyprctl', '-j', 'getoption', OPTIONS[key][0]]))
        kind = OPTIONS[key][3]
        value = info.get('float') if kind is float else info.get('bool', info.get('int')) if kind is bool else info.get('int')
        if value is None:
            raise ValueError('Option unavailable')
        return key, bool(value) if kind is bool else kind(value)
    except (RuntimeError, ValueError, subprocess.TimeoutExpired, OSError):
        return key, None

def load():
    try:
        data = json.loads(STATE.read_text())
        return {'values': {k: v for k,v in data.get('values', {}).items() if k in OPTIONS},
                'original': {k: v for k,v in data.get('original', {}).items() if k in OPTIONS}}
    except (OSError, ValueError, TypeError):
        return {'values': {}, 'original': {}}

def lua_for(values):
    groups = {}
    for key, value in values.items():
        _, group, field, kind, low, high = OPTIONS[key]
        if kind is bool:
            if not isinstance(value, bool):
                raise ValueError('Expected an on/off value.')
            encoded = 'true' if value else 'false'
        else:
            if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value) or not low <= value <= high:
                raise ValueError('The value is outside its supported range.')
            encoded = str(round(value, 3) if kind is float else int(value))
        groups.setdefault(group, []).append(f'[{json.dumps(field)}] = {encoded}')
    fields = groups.pop('', [])
    fields += [group + ' = { ' + ', '.join(entries) + ' }' for group, entries in groups.items()]
    return 'hl.config({ input = { ' + ', '.join(fields) + ' } })'

def apply(values):
    response = run(['hyprctl', 'eval', lua_for(values)])
    if re.search(r'\b(error|invalid|unknown|failed)\b', response, re.I):
        raise RuntimeError(response[:200])

def save(data):
    changes = {
        STATE: json.dumps(data, indent=2) + '\n',
        LUA: '-- Managed by Settings > Input. Reset in Settings to restore previous values.\n' + lua_for(data['values']) + '\n',
    }
    previous = {path: path.read_bytes() if path.exists() else None for path in changes}
    try:
        for path, content in changes.items():
            path.with_name(path.name + '.tmp').write_text(content)
        for path in changes:
            path.with_name(path.name + '.tmp').replace(path)
    except OSError:
        for path, original in previous.items():
            if original is None:
                path.unlink(missing_ok=True)
            else:
                temporary = path.with_name(path.name + '.rollback')
                temporary.write_bytes(original)
                temporary.replace(path)
        raise
    finally:
        for path in changes:
            path.with_name(path.name + '.tmp').unlink(missing_ok=True)

def main():
    action = sys.argv[1] if len(sys.argv) > 1 else 'get'
    data = load()
    if action == 'get':
        with concurrent.futures.ThreadPoolExecutor(max_workers=4) as executor:
            values = dict(executor.map(read_option, OPTIONS))
        return {'values': values, 'changed': len(data['values']), 'available': any(v is not None for v in values.values())}
    if action == 'set':
        key, value = sys.argv[2], json.loads(sys.argv[3])
        if key not in OPTIONS:
            raise ValueError('Unknown preference.')
        lua_for({key: value})
        _, previous = read_option(key)
        if previous is None:
            raise RuntimeError('This setting is not available from the running compositor.')
        apply({key: value})
        data['original'].setdefault(key, previous)
        data['values'][key] = value
        try:
            save(data)
        except OSError:
            apply({key: previous})
            raise
        return {'ok': True}
    if action == 'reset':
        current = dict(read_option(key) for key in data['original'])
        if data['original']:
            apply(data['original'])
        try:
            save({'values': {}, 'original': {}})
        except OSError:
            apply({key: value for key, value in current.items() if value is not None})
            raise
        return {'ok': True}
    raise ValueError('Unknown action.')

if __name__ == '__main__':
    try:
        print(json.dumps(main()))
    except (OSError, ValueError, RuntimeError, subprocess.TimeoutExpired, IndexError) as error:
        print(json.dumps({'error': str(error)[:220]}))
        sys.exit(1)
