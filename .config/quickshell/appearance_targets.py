"""Small appearance adapters shared by the desktop theme writer."""
import colorsys
import json
from pathlib import Path
import re


def load_jsonc(path):
    return _decode_jsonc(Path(path).read_text(encoding='utf-8'))


def _decode_jsonc(text):
    # Preserve quoted strings (including URL slashes) while stripping comments.
    text = re.sub(r'"(?:\\.|[^"\\])*"|//[^\n]*|/\*[\s\S]*?\*/',
                  lambda m: m[0] if m[0].startswith('"') else ' ', text)
    text = re.sub(r'("(?:\\.|[^"\\])*")|,\s*(?=[}\]])',
                  lambda m: m[1] or '', text)
    return json.loads(text)


def nearest_native_accent(color):
    rgb = [int(color[i:i + 2], 16) / 255 for i in (1, 3, 5)]
    hue, lightness, saturation = colorsys.rgb_to_hls(*rgb)
    if saturation < 0.12:
        return 'slate'
    hues = {'red': 0, 'orange': 30, 'yellow': 55, 'green': 125,
            'teal': 180, 'blue': 220, 'purple': 280, 'pink': 330}
    angle = hue * 360
    return min(hues, key=lambda name: abs((angle - hues[name] + 180) % 360 - 180))


def apply_fastfetch(palette, config, write):
    path = config / 'fastfetch/config.jsonc'
    template = config / 'quickshell/templates/fastfetch.jsonc.template'
    if template.exists():
        # Render the complete native config so inline section/format colors and
        # logo slots follow exactly the same palette as ordinary module keys.
        # Replace only double-braced color roles; Fastfetch's {name} and {#...}
        # format fields remain untouched.
        source = template.read_text(encoding='utf-8')

        def color_token(match):
            role = match[1]
            color = palette.get(role)
            if not isinstance(color, str) or not re.fullmatch(r'#[0-9A-Fa-f]{6}', color):
                raise ValueError(f'Invalid or unknown Fastfetch palette role: {role}')
            return color

        source = re.sub(r'\{\{\s*([A-Za-z][A-Za-z0-9_]*)\s*\}\}', color_token, source)
        if '{{' in source:
            raise ValueError('Unresolved Fastfetch template placeholder')
        data = _decode_jsonc(source)
        if not isinstance(data, dict):
            raise ValueError('Fastfetch template must contain a JSON object')
        # Parsing and role validation complete before touching the active config.
        write(path, json.dumps(data, ensure_ascii=False, indent=2) + '\n')
        return

    if not path.exists():
        return
    data = load_jsonc(path)
    display = data.setdefault('display', {})
    colors = display.setdefault('color', {})
    colors.update(keys=palette['accent'], title=palette['accent'], output=palette['text'])
    logo = data.get('logo')
    if isinstance(logo, dict):
        mapping = logo.setdefault('color', {})
        logo_roles = {'1': 'accent', '2': 'textBright', '3': 'muted',
                      '4': 'aqua', '5': 'purple'}
        for key, role in logo_roles.items():
            if key in mapping or key in {'1', '2'}:
                mapping[key] = palette.get(role, palette['text'])
    write(path, json.dumps(data, ensure_ascii=False, indent=2) + '\n')
