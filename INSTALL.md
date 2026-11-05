# Installation

## Compatibility

This snapshot was prepared from **Hyprland 0.57.1**, **Quickshell 0.3.2** and
**Qt 6.12** on Arch Linux. It uses Hyprland's Lua configuration and Scrolling
layout. Releases expecting only `hyprland.conf` cannot use these files directly.

The user configuration expects `~/.config`, `~/.local/share` and
`~/Pictures/Wallpapers`. Arbitrary alternative XDG configuration locations are
not supported throughout the desktop. The public keyboard default is US. Review
monitor scaling and keyboard layout in `.config/hypr/modules/monitors.lua` and
`input.lua` for your device.

## Copy with backups

```sh
./install.sh --check
./install.sh --dry-run
./install.sh
```

Use your normal desktop account, without sudo. The installer verifies the
configuration checksums built into its script before copying. Existing files are backed up, and unrelated
files inside destination directories are retained. Editor appearance settings are
merged with existing settings. JSONC comments and formatting are normalized;
the exact original remains in the backup. The printed backup path can be used to restore:

```sh
./install.sh --restore /path/printed/by/the/installer
```

The default install does not start programs, change services, install packages,
alter GRUB or copy optional system-wide SDDM files. It adds a generated neutral
PNG to each theme collection; your personal wallpaper collection is not bundled.
Existing desktop programs may notice their configuration changing when copied.

## Dependencies

`./install.sh --check` checks local command availability. Install missing packages
using your distribution's package manager. Match the Hyprland/Quickshell versions
and modules above before trying to start this desktop.

| Area | Components |
| --- | --- |
| Shell | Hyprland, Quickshell, QtQuick/Controls/Layouts/Effects/FolderListModel, Qt SVG support |
| Connections | NetworkManager (`nmcli`, `nmtui`), BlueZ (`bluetoothctl`), a PolicyKit authentication agent |
| Sound and brightness | PipeWire, WirePlumber (`wpctl`), `brightnessctl` |
| Wallpaper | `awww`, `awww-daemon` |
| Screenshots and clipboard | `hyprshot`, `hyprpicker`, `wl-copy`, `wl-paste`, system Python with Pillow |
| Lock and session | `hyprlock`, `hypridle`, `loginctl`; `hyprshutdown` for the logout UI |
| Terminal and tools | Kitty, Fish, Starship, Fastfetch, Python 3, Bash, Coreutils, XDG-Utils, Nautilus |
| Fonts | Inter, Material Symbols Rounded, JetBrainsMono Nerd Font Mono/Propo; a color emoji font |
| Optional | Tailscale, TLP, VSCodium, XSettingsd, Playerctl, GNOME System Monitor, Qt GTK platform bridge |

Quickshell provides the notification server. Run a single notification daemon;
stop another provider such as SwayNC, Mako or Dunst before enabling this one.
No notification history or daemon preferences from the original machine are
included. A per-user D-Bus activation override starts the shell instead of
relaunching SwayNC; it assumes the Arch Quickshell executable at `/usr/bin/qs`.
Tailscale needs a separate account setup on the target machine.

Some legacy battery-detail fallbacks use `BAT0`; update those references if your
device uses a different battery name. Current status panels also use detected
devices/UPower. System permissions for brightness, Bluetooth, suspend and power
actions belong to the target system's session and PolicyKit setup.

## Material Python environment

Create the environment on the target machine; copied virtual environments are
deliberately excluded. From this export folder:

```sh
python3 -m venv "$HOME/.config/quickshell/material-runtime"
"$HOME/.config/quickshell/material-runtime/bin/python" -m pip install -r requirements-material.txt
```

This is an explicit download step. It is not run by the copy installer. The
requirements are the versions used by the source setup and require Python 3.12
or newer. Material colors, wallpaper thumbnails and profile-photo conversion use
this environment. The screenshot editor additionally requires Pillow in system
Python; install your distribution's Python Pillow package.

## Icons and fonts

Icon and font packages are installed separately. The shell uses Inter and
Material Symbols Rounded, and terminal symbols require Nerd Fonts. The configured
cursor fallback is Bibata-Modern-Ice; another installed cursor can be selected
under Settings → Personalization → Appearance.

For automatic folder colors, install **Colloid-Dark** and **Colloid-Light** from
the [Colloid icon theme](https://github.com/vinceliuice/Colloid-icon-theme), retaining
its license files. The code expects local base themes and generates its own
colored overlay. Without Colloid, icon lookup uses the available fallback themes.
No icons or font binaries are embedded in this export.

## Wallpapers and profile photo

The installer prepares these folders with `notch-default.png`:

```text
~/Pictures/Wallpapers/
  Gruvbox/         Tokyo-Night/     Catppuccin/      Kanagawa/
  Everforest/      Nord/            Rose-Pine/       Dracula/
  Solarized-Dark/  Material/
```

Add your own PNG/JPEG/WebP/BMP images to the collections. Material derives colors
from its selected wallpaper. The theme switcher lists Material first; Appearance
settings let you choose the transition. The initial transition is a diagonal wipe.

Choose a profile photo in Settings → Personalization → Appearance. No original
photo or selected-photo state is supplied. Legacy automatic photo lookup uses a
local Pictures/Profile Pictures folder, if present. The chosen photo is normalized
for the lock screen. Optional SDDM synchronization publishes a readable copy to
its shared data folder, when that integration is configured.

## Start the desktop

After installing dependencies and reviewing the hardware settings, select the
Hyprland session through your usual session manager. The supplied autostart starts
Quickshell, the wallpaper daemon, idle helper and saved cursor configuration.
Avoid adding duplicate autostarts for the same programs.

For an already running compatible session, reload Hyprland through your normal
desktop controls. Quickshell watches its configuration. The exported desktop
entries for Settings, Task Manager and Quick Notes use the running shell's IPC.

## Optional system-wide extras

- `extras/sddm/` contains the login theme and neutral fallback. Its README describes
  installing it separately and configuring the shared appearance data directory.
- `extras/hyprshutdown/` contains the custom logout sources and license. Build on
  the target system, or use the distribution's installed `hyprshutdown` fallback.

No package binaries, Office/AppImage programs, desktop accounts, system boot
configuration or credentials are installed by the copy script.
