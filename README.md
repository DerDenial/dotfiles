# Notch Desktop

Ein bereinigtes Arch-Linux-Setup mit Hyprland, Quickshell und einer animierten Notch.

## Enthalten

- Notch mit Workspaces, Uhr, WLAN, Akku und System-Tray.
- App-Launcher, Theme- und Wallpaper-Auswahl sowie Quick Settings.
- Settings-App, Clipboard-Oberfläche und Schnellnotizen.
- Material-Farben aus dem Wallpaper und gemeinsame Farben für Terminal, GTK, Editor und Benachrichtigungen.
- Hyprlock, Hypridle, Kitty, Fish, Starship und Fastfetch.
- Optionale Quelltexte für SDDM und den angepassten Abmeldebildschirm.

## Aufbau

| Pfad | Inhalt |
| --- | --- |
| `.config/quickshell` | Oberfläche, Helfer und Farbexport |
| `.config/hypr` | Lua-Konfiguration, Hotkeys, Sperren und Leerlauf |
| `.config/kitty`, `.config/fish`, `.config/starship.toml` | Terminal und Prompt |
| `.config/swaync`, `.config/gtk-*`, `.config/xsettingsd` | Benachrichtigungen und Toolkit-Farben |
| `.config/VSCodium/User/settings.json` | Ausschließlich Erscheinungs-Einstellungen |
| `.local/share/applications` | Launcher-Einträge für Settings und Notizen |
| `extras` | Optionale SDDM- und Hyprshutdown-Quellen |

## Einrichten

Siehe [INSTALL.md](INSTALL.md). Das Setup benötigt eine Hyprland-Version mit Lua-Konfiguration und dem Scrolling-Layout. Es ist kein universelles Installationsskript für beliebige Hyprland-Versionen.

Eigene Wallpaper, Schriftdateien, Icon-Pakete, Programme und die Python-Umgebung werden separat eingerichtet. Der Export enthält keine persönliche Wallpaper-Sammlung und keine vorgebauten Programme.

## Hotkeys

| Taste | Funktion |
| --- | --- |
| Super + Leertaste | App-Launcher |
| Super + Umschalt + T | Themes und Wallpaper |
| Super + Umschalt + R | Zufälliges Wallpaper im aktuellen Theme |
| Super + Q | Quick Settings |
| Super + I | Settings |
| Super + T | Benachrichtigungen |
| Super + N | Schnellnotizen |
| Super + Alt + V | Clipboard-Verlauf |
| Super + L | Sperren |
| Super + E | Dateimanager |
| Super + D | Desktop anzeigen / Fenster zurückholen |
| Super + Pfeil hoch / runter | Aktive Spalte vergrößern / zurücksetzen |
| Druck | Screenshot-Bereich in die Zwischenablage |

## Öffentlich teilen

Dieser Ordner ist eine neue, getrennte Auswahl von Textdateien und einem neutralen SVG. Er enthält keine alte Git-Historie. Die `.gitignore` erlaubt ausdrücklich nur die ausgewählten Exportdateien; neue Dateien werden zunächst ignoriert.

Vor dem Veröffentlichen aus diesem Ordner ausführen:

```sh
python3 scripts/check-public.py
```

Der Check untersucht nur den Export und gibt bei Verdachtsfällen Dateiname und Zeilennummer aus. Seine Grenzen und die ausgelassenen Daten sind in [PRIVACY.md](PRIVACY.md) beschrieben.

Herkunft externer Komponenten: [CREDITS.md](CREDITS.md).
