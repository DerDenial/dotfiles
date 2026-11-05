# Notch Desktop

An Arch Linux desktop built around Hyprland and a Quickshell notch, with shared
Material colors, compact panels and keyboard navigation.

## Install

Run these commands from this folder as your normal desktop user:

```sh
./install.sh --check
./install.sh --dry-run
./install.sh
```

The installer copies the included configuration, backs up files it replaces,
and installs a neutral starter wallpaper. It does not install packages, change
your login manager, restart the session or download anything. Missing dependencies
and the Python environment are covered in [INSTALL.md](INSTALL.md).

## Included

- Animated notch with five workspace indicators, clock, Wi-Fi, battery and tray.
- App launcher with favorites, file search and calculator; emoji picker.
- Floating window switcher with previews, pinning and edge-to-edge taskbar mode.
- Native notifications, Quick Settings, notes, clipboard history and file shelf.
- Settings for devices, windows, cursors, profile photos and wallpaper transitions.
- Hardware and network panels, connection checks, speed test and Task Manager.
- Screenshot selection with frozen screen, editor, copy and save.
- Wallpaper-derived Material colors, preview cache, Kitty, Fish, Starship and Fastfetch.
- Hyprlock/Hypridle integration; optional SDDM and custom logout sources.

Personal content, saved sessions, caches and private images are not included.

## Shortcuts

| Shortcut | Action |
| --- | --- |
| Super + Space | App launcher |
| Super + Tab | Open windows |
| Super + Shift + T | Themes and wallpapers |
| Super + Shift + R | Random wallpaper from the current theme |
| Super + Q / I | Quick Settings / Settings |
| Super + T | Notification center |
| Super + N | Quick notes |
| Super + . | Emoji picker |
| Super + Alt + V | Clipboard history |
| Ctrl + Shift + Esc | Task Manager |
| Super + H | CPU, GPU and battery panel |
| Super + Shift + N | Network panel and connection check |
| Super + Alt + S | Speed test |
| Super + Esc | Power menu |
| Super + L | Lock |
| Super + E / Return | File manager / Terminal |
| Super + D | Show desktop / restore windows |
| Super + Up / Down | Expand column, edge mode / restore |
| Super + Left / Right | Focus adjacent window; cycle windows in edge mode |
| Print | Select screenshot region, then edit, copy or save |
| Hold Super | Shortcut overview |

External components and retained licenses are listed in [CREDITS.md](CREDITS.md).
