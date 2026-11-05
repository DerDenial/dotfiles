"""Generate native application themes from Quickshell's semantic palette."""
import configparser
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess


def write(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_suffix(path.suffix + '.tmp')
    temp.write_text(text, encoding='utf-8')
    temp.replace(path)


def apply_icon_theme(icon_name, config, notify=True):
    """Select an already complete icon theme without restarting applications."""
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.-]*', icon_name):
        raise ValueError('invalid icon theme name')
    config = Path(config)
    for version in (3, 4):
        path = config / f'gtk-{version}.0/settings.ini'
        settings = configparser.ConfigParser(interpolation=None)
        settings.optionxform = str
        if path.exists():
            settings.read(path, encoding='utf-8')
        if 'Settings' not in settings:
            settings['Settings'] = {}
        if settings['Settings'].get('gtk-icon-theme-name') != icon_name:
            settings['Settings']['gtk-icon-theme-name'] = icon_name
            from io import StringIO
            out = StringIO()
            settings.write(out)
            write(path, out.getvalue())

    def set_line(path, expression, replacement):
        old = path.read_text(encoding='utf-8') if path.exists() else ''
        if re.search(expression, old, re.M):
            new = re.sub(expression, lambda match: replacement, old, flags=re.M)
        else:
            new = old.rstrip() + '\n' + replacement + '\n'
        if new != old:
            write(path, new)

    gtk2_line = 'gtk-icon-theme-name="' + icon_name + '"'
    set_line(config / 'gtk-2.0/gtkrc', r'^\s*gtk-icon-theme-name\s*=.*$', gtk2_line)
    legacy = Path.home() / '.gtkrc-2.0'
    if legacy.exists():
        set_line(legacy, r'^\s*gtk-icon-theme-name\s*=.*$', gtk2_line)
    set_line(config / 'xsettingsd/xsettingsd.conf', r'^Net/IconThemeName\s+.*$',
             'Net/IconThemeName "' + icon_name + '"')

    if notify:
        try:
            if shutil.which('gsettings'):
                subprocess.run(['gsettings', 'set', 'org.gnome.desktop.interface', 'icon-theme', icon_name], check=True, timeout=10)
        finally:
            if shutil.which('pgrep') and shutil.which('pkill'):
                if subprocess.run(['pgrep', '-x', 'xsettingsd'], stdout=subprocess.DEVNULL).returncode == 0:
                    subprocess.run(['pkill', '-HUP', '-x', 'xsettingsd'], check=False)


def apply_gtk_palette(p, theme_id, config, icon_name=None):
    p = {**p, 'accent': p.get('accent', p['aqua']), 'onAccent': p.get('onAccent', p['bg0']), 'onError': p.get('onError', p['bg0'])}
    aliases = {
        'theme_bg_color': 'bg0', 'theme_fg_color': 'text',
        'theme_base_color': 'surface', 'theme_text_color': 'text',
        'theme_selected_bg_color': 'accent', 'theme_selected_fg_color': 'onAccent',
        'theme_unfocused_bg_color': 'bg0', 'theme_unfocused_fg_color': 'muted',
        'theme_unfocused_base_color': 'surface', 'theme_unfocused_text_color': 'text',
        'theme_unfocused_selected_bg_color': 'surfaceRaised',
        'theme_unfocused_selected_fg_color': 'text',
        'insensitive_bg_color': 'surfaceAlt', 'insensitive_fg_color': 'mutedStrong',
        'insensitive_base_color': 'surface', 'borders': 'border',
        'unfocused_borders': 'border', 'warning_color': 'yellow',
        'error_color': 'red', 'success_color': 'green',
        'accent_color': 'accent', 'accent_bg_color': 'accent', 'accent_fg_color': 'onAccent',
        'destructive_color': 'red', 'destructive_bg_color': 'red', 'destructive_fg_color': 'onError',
        'window_bg_color': 'bg0', 'window_fg_color': 'text',
        'view_bg_color': 'surface', 'view_fg_color': 'text',
        'headerbar_bg_color': 'surface', 'headerbar_fg_color': 'text',
        'headerbar_backdrop_color': 'bg0', 'headerbar_border_color': 'border',
        'popover_bg_color': 'surfaceAlt', 'popover_fg_color': 'text',
        'dialog_bg_color': 'surface', 'dialog_fg_color': 'text',
        'card_bg_color': 'surfaceAlt', 'card_fg_color': 'text',
        'sidebar_bg_color': 'bg0', 'sidebar_fg_color': 'text',
        'sidebar_backdrop_color': 'bg0', 'sidebar_border_color': 'border',
        'secondary_sidebar_bg_color': 'surface', 'secondary_sidebar_fg_color': 'text',
        'secondary_sidebar_backdrop_color': 'bg0', 'secondary_sidebar_border_color': 'border',
        'thumbnail_bg_color': 'surface', 'thumbnail_fg_color': 'text',
        'shade_color': 'bgDim', 'scrollbar_outline_color': 'border',
    }
    definitions = ''.join(f'@define-color {name} {p[role]};\n' for name, role in aliases.items())
    # Cover complete widget states rather than painting over a Gruvbox base theme.
    rules = '''
window, .background, dialog, messagedialog { background-color: @window_bg_color; color: @window_fg_color; }
window:backdrop, .background:backdrop { background-color: @window_bg_color; color: @window_fg_color; }
headerbar, .titlebar, toolbar, menubar, .toolbar { background-image: none; background-color: @headerbar_bg_color; color: @headerbar_fg_color; border-color: @borders; box-shadow: none; }
headerbar:backdrop, .titlebar:backdrop { background-color: @headerbar_backdrop_color; color: @theme_unfocused_fg_color; }
.view, .view:backdrop, treeview, treeview:backdrop, iconview, textview, textview text, entry, spinbutton, .view text, list, listview, gridview { background-color: @view_bg_color; color: @view_fg_color; }
entry, spinbutton { background-image: none; border-color: @borders; box-shadow: none; caret-color: @accent_color; }
entry:focus, spinbutton:focus { border-color: @accent_color; box-shadow: inset 0 0 0 1px @accent_color; }
button, button:backdrop { background-image: none; background-color: @card_bg_color; color: @card_fg_color; border-color: @borders; border-radius: 9px; box-shadow: none; text-shadow: none; }
button:hover { background-color: @theme_unfocused_selected_bg_color; }
button:checked, button:active, button.suggested-action { background-image: none; background-color: @accent_bg_color; color: @accent_fg_color; border-color: @accent_bg_color; }
button.suggested-action:hover { background-color: shade(@accent_bg_color, 1.12); }
button.destructive-action, button.destructive-action:backdrop { background-image: none; background-color: @destructive_bg_color; color: @destructive_fg_color; border-color: @destructive_bg_color; box-shadow: none; text-shadow: none; }
button.destructive-action:hover { background-color: shade(@destructive_bg_color, 1.12); }
button.destructive-action:active { background-color: shade(@destructive_bg_color, 0.85); }
button:disabled, button.suggested-action:disabled, button.destructive-action:disabled, entry:disabled, spinbutton:disabled { background-color: @insensitive_bg_color; color: @insensitive_fg_color; border-color: @borders; }
button.flat { background-color: transparent; border-color: transparent; }
button.flat:hover { background-color: @card_bg_color; }
*:selected, selection, .view:selected, .view:selected:focus, row:selected { background-color: @theme_selected_bg_color; color: @theme_selected_fg_color; }
*:selected:backdrop, .view:selected:backdrop { background-color: @theme_unfocused_selected_bg_color; color: @theme_unfocused_selected_fg_color; }
menu, menu:backdrop, popover { background-image: none; background-color: @popover_bg_color; color: @popover_fg_color; border-color: @borders; }
menuitem, modelbutton { background-image: none; color: @popover_fg_color; }
menuitem:hover, modelbutton:hover { background-color: @theme_unfocused_selected_bg_color; }
menuitem:disabled, modelbutton:disabled { color: @insensitive_fg_color; }
tooltip, tooltip.background { background-color: @popover_bg_color; color: @popover_fg_color; border-color: @borders; }
check, radio { background-image: none; background-color: @view_bg_color; color: @view_fg_color; border-color: @borders; box-shadow: none; }
check:checked, radio:checked, check:indeterminate { background-color: @accent_bg_color; color: @accent_fg_color; border-color: @accent_bg_color; }
check:disabled, radio:disabled { background-color: @insensitive_bg_color; color: @insensitive_fg_color; }
switch { background-image: none; background-color: @card_bg_color; border-color: @borders; }
switch:checked { background-color: @accent_bg_color; border-color: @accent_bg_color; }
switch slider { background-image: none; background-color: @window_fg_color; border-color: @borders; box-shadow: none; }
scale trough, progressbar trough, levelbar trough { background-color: @card_bg_color; border-color: @borders; }
scale highlight, progressbar progress, levelbar block.filled { background-image: none; background-color: @accent_bg_color; border-color: @accent_bg_color; }
scale slider { background-image: none; background-color: @accent_bg_color; border-color: @accent_bg_color; box-shadow: none; }
scrollbar { background-color: transparent; }
scrollbar slider { background-color: @insensitive_fg_color; border-color: transparent; }
scrollbar slider:hover { background-color: @theme_unfocused_fg_color; }
.sidebar, .navigation-sidebar, placessidebar, placessidebar list { background-color: @sidebar_bg_color; color: @sidebar_fg_color; }
.sidebar row, placessidebar row { background-color: transparent; color: @sidebar_fg_color; }
.sidebar row:selected, placessidebar row:selected { background-color: @theme_unfocused_selected_bg_color; color: @window_fg_color; }
notebook > header, notebook > header tabs, notebook > header tabs tab { background-color: @headerbar_bg_color; color: @headerbar_fg_color; border-color: @borders; }
notebook > header tabs tab:checked { background-color: @view_bg_color; border-color: @accent_bg_color; }
separator, frame > border { border-color: @borders; }
separator { background-color: @borders; }
.dim-label, .subtitle { color: @theme_unfocused_fg_color; }
label.error, .error { color: @error_color; }
label.warning, .warning { color: @warning_color; }
label.success, .success { color: @success_color; }
label.link, link, :link, :visited { color: @accent_color; }
'''
    gtk3 = definitions + rules
    # Libadwaita 1.6+ also uses CSS variables instead of only named colors.
    variables = ':root {\n' + ''.join(f'  --{name.replace("_", "-")}: {p[role]};\n' for name, role in aliases.items() if name.endswith('_color')) + '}\n'
    gtk4 = definitions + variables + rules + '\n/* GTK4 paints the menu on contents; keep its outer popup transparent. */\npopover, popover.background, popover.menu, popover.context-menu {\n    background: transparent;\n    border: none;\n    box-shadow: none;\n}\npopover > contents {\n    background-image: none;\n    background-color: @popover_bg_color;\n    color: @popover_fg_color;\n    border: 1px solid @borders;\n    border-radius: 14px;\n}\npopover > arrow { background-color: @popover_bg_color; border-color: @borders; }\n'
    digest = hashlib.sha256((gtk3 + gtk4).encode()).hexdigest()[:8]
    name = 'Quickshell-' + re.sub(r'[^A-Za-z0-9_-]', '', theme_id) + '-' + digest
    data = Path(os.environ.get('XDG_DATA_HOME', Path.home() / '.local/share'))
    theme = data / 'themes' / name
    imports = {3: 'Adwaita/gtk-contained-dark.css', 4: 'Default/Default-dark.css'}
    for version, css in ((3, gtk3), (4, gtk4)):
        body = f'@import url("resource:///org/gtk/libgtk/theme/{imports[version]}");\n' + css
        for variant in ('gtk.css', 'gtk-dark.css'):
            write(theme / f'gtk-{version}.0' / variant, body)
        ini = config / f'gtk-{version}.0/settings.ini'
        settings = configparser.ConfigParser(interpolation=None)
        settings.optionxform = str
        if ini.exists(): settings.read(ini)
        if 'Settings' not in settings: settings['Settings'] = {}
        settings['Settings']['gtk-theme-name'] = name
        settings['Settings']['gtk-application-prefer-dark-theme'] = '1'
        settings['Settings']['gtk-font-name'] = 'Inter 11'
        from io import StringIO
        out = StringIO(); settings.write(out)
        write(ini, out.getvalue())
    # GTK3 loads the named theme on every theme change. User CSS is loaded only once,
    # so remove its stale palette override; GTK4's Libadwaita needs user overrides.
    write(config / 'gtk-3.0/gtk.css', '/* Palette lives in the generated Quickshell GTK theme. */\n')
    write(config / 'gtk-4.0/gtk.css', '/* Generated by Quickshell; Libadwaita overrides. */\n' + gtk4)
    effective_icon = icon_name or settings.get('Settings', 'gtk-icon-theme-name', fallback=None)
    icon_line = 'gtk-icon-theme-name="' + effective_icon + '"\n' if effective_icon and re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.-]*', effective_icon) else ''
    # Keep the cursor choice when a wallpaper rebuilds the GTK palette.
    cursor_name = settings.get('Settings', 'gtk-cursor-theme-name', fallback='')
    cursor_size = settings.get('Settings', 'gtk-cursor-theme-size', fallback='')
    cursor_lines = ('gtk-cursor-theme-name=' + json.dumps(cursor_name, ensure_ascii=False) + '\n') if cursor_name else ''
    if cursor_size.isdigit() and 1 <= int(cursor_size) <= 256:
        cursor_lines += 'gtk-cursor-theme-size=' + str(int(cursor_size)) + '\n'
    gtk2 = 'gtk-theme-name="' + name + '"\ngtk-font-name="Inter 11"\n' + icon_line + cursor_lines + 'style "quickshell" {\n'
    for state in ('NORMAL', 'PRELIGHT', 'ACTIVE', 'SELECTED', 'INSENSITIVE'):
        bg = p['accent'] if state == 'SELECTED' else p['surfaceRaised'] if state in ('PRELIGHT', 'ACTIVE') else p['bg0']
        fg = p['onAccent'] if state == 'SELECTED' else p['mutedStrong'] if state == 'INSENSITIVE' else p['text']
        gtk2 += f'  bg[{state}] = "{bg}"\n  base[{state}] = "{bg if state == "SELECTED" else p["surface"]}"\n  fg[{state}] = "{fg}"\n  text[{state}] = "{fg}"\n'
    gtk2 += '}\nclass "*" style "quickshell"\n'
    write(config / 'gtk-2.0/gtkrc', gtk2)
    write(theme / 'gtk-2.0/gtkrc', gtk2)
    xsettings = config / 'xsettingsd/xsettingsd.conf'
    text = xsettings.read_text() if xsettings.exists() else ''
    text = re.sub(r'^Net/ThemeName\s+.*$', 'Net/ThemeName "' + name + '"', text, flags=re.M)
    if not re.search(r'^Net/ThemeName\s', text, re.M): text += '\nNet/ThemeName "' + name + '"\n'
    text = re.sub(r'^Gtk/FontName\s+.*$', 'Gtk/FontName "Inter 11"', text, flags=re.M)
    if not re.search(r'^Gtk/FontName\s', text, re.M): text += 'Gtk/FontName "Inter 11"\n'
    write(xsettings, text)
    if icon_name:
        apply_icon_theme(icon_name, config, notify=False)
    if shutil.which('gsettings'):
        native_settings = [('gtk-theme', name), ('color-scheme', 'prefer-dark'), ('font-name', 'Inter 11')]
        if icon_name:
            native_settings.append(('icon-theme', icon_name))
        for key, value in native_settings:
            subprocess.run(['gsettings', 'set', 'org.gnome.desktop.interface', key, value], check=False, timeout=10)
    if shutil.which('pgrep') and shutil.which('pkill'):
        if subprocess.run(['pgrep', '-x', 'xsettingsd'], stdout=subprocess.DEVNULL).returncode == 0:
            subprocess.run(['pkill', '-HUP', '-x', 'xsettingsd'], check=False)
    return name
