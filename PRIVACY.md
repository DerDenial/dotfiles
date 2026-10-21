# Umfang der Bereinigung

## Vorgehen

Der Export wurde aus einer ausdrücklichen Auswahl von Konfigurations- und Quelldateien aufgebaut. Er ist keine Kopie des Home-Verzeichnisses. Symlinks wurden nicht verfolgt, alte Git-Metadaten nicht übernommen und private Datenbanken nicht geöffnet.

## Ausgelassen

- Clipboard-Daten und -Bilder unter `$XDG_STATE_HOME/quickshell-clipboard`.
- Notiztexte und Datenbank unter `$XDG_STATE_HOME/quickshell-notes`.
- Quickshell-Theme-Zustand, zuletzt verwendete Programme, angepinnte Apps und gespeicherter Bluetooth-Zustand.
- Automatisch erzeugte Eingabe-Einstellungen und generierte Wallpaper-Links.
- VSCodium-Cookies, Sitzungen, Kontodaten, Backups, History, GlobalStorage und WorkspaceStorage.
- GTK-Lesezeichen, Shell-Verlauf, Logs, Caches, virtuelle Umgebungen und Python-Bytecode.
- SSH-/GPG-/Cloud-Zugangsdaten, VPN-Zustand und NetworkManager-Verbindungsprofile.
- Persönliche Wallpaper und Screenshots, installierte AppImages, Icon-Pakete, Schriftdateien und vorgebaute Programme.
- Alle alten Git-, Codex- und Arbeitsordner-Metadaten.

Die Clipboard- und Notiz-Pythondateien im Export sind Programmcode. Die eigentlichen gespeicherten Inhalte liegen in anderen, ausgelassenen Verzeichnissen.

## Anpassungen

- Feste persönliche Home-Verzeichnisse durch die passende HOME-Auflösung ersetzt.
- Den voreingestellten SDDM-Benutzernamen geleert.
- Editor-Einstellungen auf Erscheinung und Schriften beschränkt.
- Gerätespezifische Monitor-/Beispielgeräte-Vorgaben und den persönlichen Storage-Anzeigenamen entfernt.
- Generierte GTK-Theme-/Icon-Namen durch allgemeine Ausgangswerte ersetzt.
- SDDM-Schriftdateien und Hintergrundbild durch Systemschriften und einen neutralen SVG-Hintergrund ersetzt.
- Kitty auf aktive Konfiguration reduziert; einen vorhandenen Schreibfehler bei `input_delay` in der Exportkopie korrigiert.
- Einen alten Hotkey zu einem nicht exportierten Waybar-Skript ausgelassen.

## Weiteres Teilen

`.gitignore` verwendet eine ausdrückliche Dateiliste. Neue Dateien müssen bewusst freigegeben werden. Das verhindert nicht, dass später Geheimnisse in eine bereits freigegebene Datei geschrieben werden.

`scripts/check-public.py` vergleicht die Dateien mit dem Exportmanifest und sucht nach offensichtlichen Tokenformaten, privaten Schlüsselblöcken, Zugangsdaten in URLs, fest eingetragenen Geheimnissen, MAC-Adressen und persönlichen Home-Pfaden. Verdächtige Werte werden nicht ausgegeben. Geänderte Dateien werden zur manuellen Durchsicht aufgelistet.

Die Prüfung ist eine Hilfestellung, keine Garantie. Sie erkennt insbesondere nicht jedes beliebige Passwort, persönliche Informationen in freiem Text oder Geheimnisse in einer später hinzugefügten Git-Historie. Kontrolliere vor einem Commit die tatsächlich ausgewählten Änderungen und die gewünschte öffentliche Git-Autoridentität; Commits enthalten auch Autorname und E-Mail-Adresse. `.gitignore` entfernt keine bereits eingecheckten Dateien oder früheren Commits.

In diesem Ausgangsexport wurden keine offensichtlichen Zugangsdaten gefunden. Private Laufzeitdaten wurden durch die Dateiauswahl ausgeschlossen.
