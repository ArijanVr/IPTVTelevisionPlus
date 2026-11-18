# IPTelevision+

IPTV-Player für iPhone, Apple TV und Mac. Projekt, Befehle und Regeln: `AGENTS.md`. Deutsch, Schweizer Schreibweise (kein «ß»), Du-Form.

## Releases

- Release immer mit `tools/release.sh` aus der Repo-Wurzel. Nur den Zielordner anzeigen, ohne zu bauen: `tools/release.sh --pfad`.
- Das Skript ruft das bestehende `./update.sh` auf und reicht alle Optionen weiter (`--version`, `--only mac|ios|android`, `--skip-tests`, `--dry-run`). `update.sh` ersetzt die Dateien in `Download-macOS/`, `Download-iOS/` und `Download-GoogleTV/`.
- Ziel: iCloud Drive › `Projektelab/01_Apps/IPTelevision+/Releases/<JJJJ-MM-TT>_v<X.Y.Z>/Dateien/<Plattform>` (Version auf drei Stellen ergänzt, z. B. 1.5 → v1.5.0). Gibt es den Ordner schon, hängt das Skript `_2`, `_3` … an. In `Releases/` nie etwas überschreiben, umbenennen oder löschen. Nach einem Release `Release.md` aus `Projektelab/99_Vorlagen/Release.md` anlegen.
- Ablage: Dieses Repo liegt ausserhalb von iCloud in `~/Developer/IPTelevision-plus` (seit 2026-11-13). Design, Marketing und Releases liegen in iCloud Drive › `Projektelab/01_Apps/IPTelevision+/`. Regeln: `Projektelab/MAIN.md`.
- Das Skript findet den Release-Ordner über einen festen Pfad (überschreibbar mit `PROJEKTELAB_RELEASES`) und bricht ab, wenn er fehlt. Nach einem Umzug `tools/release.sh --pfad` prüfen.
- Nichts committen, pushen, hochladen oder im Store einreichen ohne ausdrücklichen Auftrag.

## Remote

- `origin` ist das öffentliche Repo `ArijanVr/IPTVTelevisionPlus` (Quellcode und Releases). Nur dorthin pushen. `privat` (`IPTelevision-plus`) ist das alte Archiv mit der vollen Historie (Branch `archive-privat`), dort nicht mehr pushen.
- Öffentlich ist alles, was committet wird: keine Playlist-Adressen, Zugangsdaten, IPAs, APKs oder DMGs einchecken (`Download-*/` ist ignoriert).

## Auto-Update

- Updates kommen aus der öffentlichen Ablage `ArijanVr/IPTVTelevisionPlus` (nur Releases, kein Quellcode). Veröffentlichen: erst `tools/release.sh --version X.Y.Z`, dann `tools/publish-update.sh --notes "…"` (ohne `--publish` nur Testlauf, mit `--publish` wird hochgeladen).
- Mac: Sparkle (`Packages/ARJOUpdate`, Schlüssel `SUPublicEDKey` in `App/Info.plist`, privater Schlüssel im Login-Schlüsselbund; ohne ihn keine Updates mehr signierbar, Sicherung erstellen). Google TV: `Updater.java` lädt die APK aus dem Release. iPhone, iPad, Apple TV: `UpdateChecker` zeigt nur einen Hinweis.
- Die öffentliche Google-TV-APK baut `publish-update.sh` mit `-PpublicBuild`, damit keine Playlist-Adresse aus `playlist.local.properties` im Release landet. Nie die APK aus `Download-GoogleTV/` hochladen.
- Google-TV-Updates brauchen dieselbe Signatur wie die installierte App (aktuell der Debug-Schlüssel dieses Macs).

## Ablage ausserhalb des Repos

Design, Marketing und Releases liegen ausserhalb dieses Repos (lokaler Ordner `Projektelab/01_Apps/IPTelevision+/` in iCloud Drive). Dafür gelten die lokalen Ablageregeln des Besitzers, sie gehören nicht ins öffentliche Repo.
