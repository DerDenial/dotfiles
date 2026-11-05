# Herkunft

- [Quickshell](https://quickshell.org/) und [Hyprland](https://hypr.land/) bilden die Grundlage des Desktops. Ihre Programme und Laufzeitbibliotheken sind nicht enthalten.
- [Colloid Icon Theme](https://github.com/vinceliuice/Colloid-icon-theme) von vinceliuice und Mitwirkenden wird separat installiert. Der Ordnerfarben-Helfer verarbeitet eine lokale Installation und übernimmt bei der Erzeugung die dortige GPL-Lizenz. Icon-Assets sind nicht in diesem Export.
- [Material Color Utilities](https://github.com/material-foundation/material-color-utilities), NumPy und Pillow werden separat in der Material-Umgebung installiert.
- Inter, Material Symbols und JetBrains Mono Nerd Fonts werden separat installiert. Schriftdateien sind nicht enthalten.
- `extras/hyprshutdown` enthält den angepassten Quelltext von [Hyprshutdown](https://github.com/hyprwm/hyprshutdown), basierend auf v0.1.1. Die zugehörige BSD-3-Clause-Lizenz liegt im Unterordner.
- Die frühere Discord-Vorlage stammt von [shvedes/discord-gruvbox](https://github.com/shvedes/discord-gruvbox). Sie wurde mangels auffindbarer Lizenz nicht in den Export übernommen.

Die übrigen Konfigurations- und Oberflächendateien stammen aus dem angepassten Desktop-Setup. Der neutrale SDDM-SVG-Hintergrund wurde für diesen Export erstellt.

- Der Emoji-Katalog enthält bearbeitete Unicode-Emoji- und CLDR-Daten unter der Unicode License v3. Herkunft, Änderungen und die vollständige Lizenz stehen in `.config/quickshell/Emoji/`.
- Das neutrale PNG-Wallpaper wurde für diesen Export neu erzeugt; es enthält keine übernommenen Bilddaten oder Metadaten.
