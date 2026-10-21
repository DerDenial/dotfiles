# Exportbericht

Stand: 21. Oktober 2026.

Umfang: 149 öffentliche Dateien, alle als Text lesbar.
Datenschutzcheck: 149 Dateien, 0 Verdachtsfunde, 0 Abweichungen vom Exportmanifest.

Der Export wurde aus einzeln ausgewählten Konfigurations- und Quelldateien erstellt.
Enthalten sind Quickshell, Hyprland, Terminal/Prompt, Fastfetch, Benachrichtigungen,
GTK, kosmetische VSCodium-Einstellungen sowie optionale SDDM- und Logout-Quellen.

## Durchsicht

- Persönliche Pfade, feste Benutzerwerte und Geräte-Vorgaben wurden bereinigt.
- Keine privaten Laufzeitdatenbanken oder Sitzungsdateien wurden übernommen.
- Keine Symlinks, Schrift-/Icon-Pakete, AppImages, Binärprogramme oder alte Git-Metadaten enthalten.
- Der SDDM-Hintergrund ist ein neutraler SVG; kein persönliches Bild wurde kopiert.
- Die Dateien wurden auf auffällige Zugangsdaten, Home-Pfade, E-Mail-, IP- und MAC-Werte durchgesehen.
- Eine unabhängige zweite statische Durchsicht fand keine Datenschutzblocker.
- Die ausdrückliche Dateiliste in `.gitignore` schützt vor versehentlich ergänzten Dateien.
- Das Manifest enthält relative Dateinamen und SHA-256-Prüfsummen, keine ursprünglichen Home-Pfade.

## Grenzen

Der Export wurde nicht auf einem zweiten Rechner installiert oder funktional getestet.
Abhängigkeiten, eigene Wallpaper und gerätespezifische Einstellungen sind gemäß
`INSTALL.md` lokal einzurichten. Die Prüfung erkennt nicht jedes beliebige Geheimnisformat;
Änderungen an später freigegebenen Dateien oder einer neuen Git-Historie sind gesondert durchzusehen.

Ein ausführbarer, rein lesender Datenschutzcheck liegt unter `scripts/check-public.py`.
