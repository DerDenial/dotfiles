# Einrichtung

## 1. Voraussetzungen

Die Konfiguration stammt von einem Arch-System mit Hyprland-Lua-Konfiguration und Quickshell 0.3.2. Ältere Hyprland-Versionen, die nur `hyprland.conf` erwarten, können diese Lua-Dateien nicht direkt verwenden.

| Bereich | Benötigte Komponenten |
| --- | --- |
| Desktop | Hyprland mit Lua und Scrolling-Layout, Quickshell mit Networking-, Bluetooth-, PipeWire-, UPower-, MPRIS-, SystemTray-, Wayland- und Hyprland-Modulen |
| Qt | Qt 6 / QtQuick, Controls, Layouts, Effects, FolderListModel; GTK-Plattform-Bridge für `QT_QPA_PLATFORMTHEME=gtk3` |
| Verbindungen | NetworkManager mit `nmcli` und `nmtui`, BlueZ mit `bluetoothctl`, ein PolicyKit-Agent für autorisierte Systemaktionen |
| Audio und Helligkeit | PipeWire, WirePlumber / `wpctl`, `brightnessctl` |
| Wallpaper und Benachrichtigungen | `awww` / `awww-daemon`, SwayNC / `swaync-client` |
| Programme und Werkzeuge | Kitty, Nautilus, Fish, Starship, Fastfetch, Python 3, `wl-clipboard`, Hyprshot, Playerctl, UPower, XDG-Utils, Coreutils, Bash, Awk |
| Sperren und Abmelden | Hyprlock, Hypridle, Hyprshutdown; passende PAM- und Sitzungsintegration |
| Optional | Tailscale, TLP, GNOME System Monitor, VSCodium, XSettingsd, Rofi, SDDM |

Die optionalen Komponenten müssen nur eingerichtet werden, wenn die zugehörigen Funktionen verwendet werden. WLAN-/Bluetooth-Autorisierung, Hibernation und Gerätezulassungen sind Systemeinstellungen und werden nicht mit privaten Zugangsdaten exportiert.

## 2. Schriften und Icons

Installiere **Inter**, **Material Symbols Rounded**, **JetBrainsMono Nerd Font Mono** und **JetBrainsMono Nerd Font Propo**. Die Material-Schrift liefert die Google-Icons; die Nerd Fonts liefern Terminal-Symbole. Die Hyprland-Konfiguration verwendet den Cursor `Bibata-Modern-Ice`.

Für die Ordnerfarben wird [Colloid](https://github.com/vinceliuice/Colloid-icon-theme) separat installiert. Benötigt werden **Colloid-Dark und Colloid-Light**: Dark verlinkt auf App-Icons im Light-Paket. Die dynamischen Overlay-Icons erzeugt Quickshell später selbst.

Die vorbereitete Integration basiert auf Commit `ceac6608ecd0e40025cbc2ebbd32bf0e0f4ebc6a`. Im entsprechenden Colloid-Quellordner:

```sh
./install.sh -d "$HOME/.local/share/icons" -s default -t default -notint
install -m 644 LICENSE "$HOME/.local/share/icons/Colloid-Dark/COPYING"
install -m 644 LICENSE "$HOME/.local/share/icons/Colloid-Light/COPYING"
install -m 644 LICENSE "$HOME/.local/share/icons/Colloid/COPYING"
```

Die Lizenzkopien werden vom Ordnerfarben-Generator benötigt. Die Quickshell-Konfiguration wählt für App-Icons ausdrücklich `Colloid-Dark` aus.

## 3. Konfiguration übernehmen

Sichere vorhandene Konfigurationen außerhalb dieses Repositorys. Übernimm anschließend die gewünschten Unterordner aus `.config/` nach `~/.config/` und die beiden Desktop-Dateien aus `.local/share/applications/` nach `~/.local/share/applications/`.

Führe vorhandene Einstellungen bewusst zusammen. Besonders `VSCodium/User/settings.json` enthält hier ausschließlich kosmetische Einstellungen und ersetzt keine vollständige persönliche Editor-Konfiguration.

Danach kann die Desktop-Datenbank aktualisiert werden:

```sh
update-desktop-database "$HOME/.local/share/applications"
```

Die Helfer erwarten die normale Installation unter `~/.config/quickshell`. Ein abweichendes `XDG_CONFIG_HOME` wird nicht durchgängig unterstützt.

## 4. Material-Farben vorbereiten

Erzeuge die virtuelle Python-Umgebung auf dem Zielrechner neu. Die Datei `requirements-material.txt` enthält die Versionen der ursprünglichen Umgebung; sie benötigt Python ab 3.12, ursprünglich wurde Python 3.14 verwendet.

Aus dem Exportordner:

```sh
python3 -m venv "$HOME/.config/quickshell/material-runtime"
"$HOME/.config/quickshell/material-runtime/bin/python" -m pip install -r requirements-material.txt
```

Der Theme-Wechsel erzeugt anschließend die lokalen Farben für GTK, Kitty, Starship, Fastfetch und vorhandene weitere Zielprogramme. Es werden eigene Einstellungen auf dem Zielsystem geschrieben; verwende vorher eine Sicherung.

## 5. Eigene Wallpaper

Lege eigene Bilder unter `~/Pictures/Wallpapers/` in diesen Theme-Unterordnern ab. Für einen direkt funktionierenden ersten Start sind folgende voreingestellte Dateinamen vorgesehen; sie können in `Theme/Theme.qml` angepasst werden.

| Ordner | Voreingestellte Datei |
| --- | --- |
| `Gruvbox` | `Gruvbox_wallpaper.png` |
| `Tokyo-Night` | `arch-black-4k.png` |
| `Catppuccin` | `pexels-eberhardgross-2217366.jpg` |
| `Kanagawa` | `Kanagawa.png` |
| `Everforest` | `Everforest.png` |
| `Nord` | `Nord.png` |
| `Rose-Pine` | `Rose-Pine.png` |
| `Dracula` | `Dracula.png` |
| `Solarized-Dark` | `Solarized-Dark.png` |
| `Material` | `Welcome.jpg` |

Weitere Bilder erscheinen im Wallpaper-Switcher. Die Dateinamen sind lediglich Vorgaben; die zugehörigen Bilder sind nicht Bestandteil des Exports.

## 6. An das Gerät anpassen

- `hypr/modules/monitors.lua` verwendet eine generische Monitorregel. Passe Skalierung und Auflösung an dein Display an.
- Prüfe Tastaturlayout und Eingabegeräte in `hypr/modules/input.lua`.
- Einige ältere Batterie-Komponenten referenzieren `BAT0`; bei anderen Geräten ist der Name anzupassen. Aktuelle Komponenten verwenden auch UPower.
- Tailscale benötigt eine eigene Anmeldung und gegebenenfalls die Operator-Berechtigung für den eigenen Benutzer.
- Der Sperrbildschirm erzeugt seinen Wallpaper-Link lokal über den LockScreen-Helfer; generierte Links sind nicht mitgeliefert.
- Die Hyprland-Konfiguration startet `qs`, Hypridle, SwayNC und den Wallpaper-Dienst. Starte diese nicht zusätzlich ein zweites Mal über einen anderen Autostart.

Die beiden Launcher-Einträge für Settings und Notizen brauchen eine laufende Quickshell-Instanz. Weitere Programme kommen aus den auf dem Zielsystem installierten `.desktop`-Einträgen. Office-AppImages und deren persönliche Installationspfade werden nicht mitgeliefert.

## 7. Optionale Extras

- SDDM: `extras/sddm/README.md` beschreibt Theme und Farbsynchronisierung.
- Angepasster Abmeldebildschirm: `extras/hyprshutdown/README.md` enthält die Quellen und Build-Hinweise. Ohne passenden lokalen Build verwendet der Launcher das installierte Hyprshutdown.
- Die Discord-CSS-Vorlage ist ausgelassen. Der Farbexport überspringt diesen optionalen Teil, solange keine separat bezogene Vorlage vorhanden ist.

Die exportierte Konfiguration wurde für Privatsphäre und Verweise durchgesehen. Auf einem neuen Rechner wurde sie nicht gestartet oder funktional getestet.
