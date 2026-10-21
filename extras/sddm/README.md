# Optionales SDDM-Theme

Die QML-Oberfläche liegt in `notch-minimal/`. Sie enthält keinen vorbelegten Benutzernamen,
kein persönliches Wallpaper und keine eingebetteten Schriftdateien. Inter und
Material Symbols Rounded müssen systemweit installiert und für den Greeter lesbar sein.
Der mitgelieferte SVG-Hintergrund ist eine neutrale, neu erstellte Farbfläche.

Das Theme braucht SDDM mit Qt 6, QtQuick Controls, Layouts, Effects, QtCore und SVG-Unterstützung.
Kopiere `notch-minimal/` bei Bedarf nach `/usr/share/sddm/themes/` und setze in einer
SDDM-Konfigurationsdatei `[Theme]` / `Current=notch-minimal`. Sichere vorhandene Dateien zuerst.
Die neue Oberfläche wird beim nächsten regulären Start des Greeters verwendet.

Für die optionale Synchronisierung liest der Greeter `/var/lib/quickshell-sddm/theme.ini`.
`theme.ini.example` zeigt die erwartete Struktur. Der Shell-Helfer
`~/.config/quickshell/sync-sddm.py --current` schreibt dort nur Farbwerte und eine
lesbare Wallpaper-Kopie hinein. Er benötigt einen passend eingerichteten Datenordner
mit Schreibrecht für den Desktop-Benutzer und Leserecht für SDDM. Der Export setzt
keine Systemrechte oder Dienstkonfigurationen automatisch.

Eine eigene Wallpaper-Kopie in diesem gemeinsamen Datenordner ist für den Greeter
lesbar; verwende dafür ein Bild, das keine privaten Informationen enthält.
