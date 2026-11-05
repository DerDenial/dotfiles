#!/usr/bin/env python3
"""Update supported native ChatGPT desktop appearance settings only."""
import json
import os
from pathlib import Path
import re
import sys
import tomllib


def inline(value):
    if isinstance(value, dict):
        return '{ ' + ', '.join(json.dumps(k) + ' = ' + inline(v) for k, v in value.items()) + ' }'
    if isinstance(value, bool):
        return 'true' if value else 'false'
    return json.dumps(value, ensure_ascii=False)


def sync(palette, config_path):
    appearance = {
        'appearanceTheme': 'dark',
        'appearanceDarkChromeTheme': {
            'accent': palette.get('accent', palette['aqua']),
            'accentSource': 'custom',
            'contrast': 60,
            'fonts': {'ui': 'Inter', 'content': 'Inter', 'code': 'JetBrainsMono Nerd Font'},
            'ink': palette['text'],
            'surface': palette['bg0'],
            'opaqueWindows': False,
            'semanticColors': {'diffAdded': palette['green'], 'diffRemoved': palette['red'], 'skill': palette.get('accent', palette['aqua'])},
        },
    }
    text = config_path.read_text()
    parsed = tomllib.loads(text)
    sections = re.split(r'(?m)(?=^\s*\[[^\n]+\]\s*(?:#.*)?$)', text)
    retained = []
    found = False
    for section in sections:
        header = re.match(r'^\s*\[([^\n]+)\]\s*(?:#.*)?\n', section)
        if header and header.group(1).strip().startswith('desktop.appearanceDarkChromeTheme'):
            continue
        if header and header.group(1).strip() == 'desktop':
            found = True
            section = re.sub(r'(?m)^\s*(?:appearanceTheme|appearanceDarkChromeTheme)\s*=.*\n?', '', section)
            section = section.rstrip() + '\n' + ''.join(k + ' = ' + inline(v) + '\n' for k, v in appearance.items()) + '\n'
        retained.append(section)
    text = ''.join(retained)
    if not found:
        text = text.rstrip() + '\n\n[desktop]\n' + ''.join(k + ' = ' + inline(v) + '\n' for k, v in appearance.items())
    check = tomllib.loads(text)
    assert check['desktop']['appearanceDarkChromeTheme'] == appearance['appearanceDarkChromeTheme']
    for key, value in parsed.items():
        if key != 'desktop':
            assert check[key] == value
    for key, value in parsed.get('desktop', {}).items():
        if key not in appearance:
            assert check['desktop'][key] == value
    if text != config_path.read_text():
        temp = config_path.with_suffix('.theme-tmp')
        temp.write_text(text)
        temp.chmod(config_path.stat().st_mode & 0o777)
        os.replace(temp, config_path)


if __name__ == '__main__':
    sync(json.loads(sys.argv[1]), Path.home() / '.codex/config.toml')
