# ARJO TV – Übergabe an Grok

Sprache: Deutsch, Schweizer Schreibweise (kein «ß»), Du-Form. Code, Befehle und Dateinamen bleiben im Original.

## Projekt
ARJO TV ist ein IPTV-Player (Xtream, M3U) für iPhone, Apple TV und Mac. Ein Multiplattform-Xcode-Target «ARJO TV» (Bundle-ID `ch.arjo.iptelevision`, Team `D752V8XA4G`) und fünf lokale Swift Packages. Der Player liefert keine Inhalte. Aufbau und Funktionen: `Quellcode/README.md`.

## Ordnerstruktur
- `Quellcode/` – Xcode-Projekt: `ARJOTV.xcodeproj` (erzeugt aus `project.yml` mit `xcodegen generate`), `App/`, `Packages/` (ARJOCore, ARJONetwork, ARJOData, ARJOPlayer, ARJOUI), `Tools/`, `docs/`.
- `Quellcode/ARJOTV-RELEASE/` – `scripts/build.sh`, `INSTALLATION.md`, `BUILD-REPORT.md`, `website/`.
- `Websitedownload Arjo TV/` – fertige Upload-Dateien: `IPTelevision-Mac.dmg` (Developer ID signiert, notarisiert), Prüfsumme, Anleitung, Website-Text.

## Befehle
- Tests (auf dem Mac): `for p in ARJONetwork ARJOData ARJOPlayer ARJOUI; do (cd Quellcode/Packages/$p && swift test); done`
- Mac-Release signieren und notarisieren (aus `Quellcode/ARJOTV-RELEASE`):
  `ARJO_ONLY_MAC=1 ARJO_DEVID="Developer ID Application: ARIJAN VRANJA (D752V8XA4G)" ARJO_NOTARY_PROFILE=arjo-notary ./scripts/build.sh`
  Ergebnis: `downloads/ARJOTV-macOS.dmg`, danach nach `Websitedownload Arjo TV/IPTelevision-Mac.dmg` kopieren und `shasum -a 256` neu erzeugen. Alte Download-Dateien immer löschen.
- Projekt neu erzeugen: `cd Quellcode && xcodegen generate`

## Stand
- macOS-Ziel ergänzt (`project.yml`), Wiedergabe mit AVPlayer und VLCKit, Multiview, echtes Vollbild im Player, Keychain ohne iCloud-Sync auf macOS.
- UI nach TV+ tvOS-Brandguide V1 (`Quellcode/docs/TV-Plus_tvOS-Brandguide_v1.pdf`, Kurzfassung in `Quellcode/docs/DESIGN-RICHTLINIEN.md`). Farben und Masse in `Packages/ARJOUI/Sources/ARJOUI/Theme.swift`.
- Mac-App ist notarisiert (Apple: Accepted). Zugang: Keychain-Profil `arjo-notary` (nicht im Repo, nie Passwörter ausgeben).

## Offen
- Wiedergabetest der DMG mit echtem VLC-Stream (TS/MKV) unter Hardened Runtime.
- iPhone/Apple TV: TestFlight oder Ad-hoc mit dem bezahlten Account vorbereiten.
- GitHub-Upload (Repo-Name und Sichtbarkeit offen; öffentlich nötig für Kunden-Downloads).

## Regeln
- Nichts pushen, hochladen, löschen oder bezahlen ohne ausdrückliche Freigabe.
- Keine Passwörter, Tokens oder Schlüssel in Dateien oder Ausgaben.
- Kleinste mögliche Änderung, nach jeder Änderung bauen oder testen, nichts als erledigt melden, was nicht geprüft ist.
- Projektablage: Dieses Repo liegt in `~/Developer/IPTelevision-plus` (eigenständig, nicht Teil von TV+ oder dem Launcher). Design, Marketing und Releases liegen in iCloud Drive › `Projektelab/01_Apps/IPTelevision+/` (Regeln: `Projektelab/MAIN.md`).
- Jeder neue Build kommt in einen neuen Ordner `Projektelab/01_Apps/IPTelevision+/Releases/<Datum>_v<X.Y.Z>/Dateien/{macOS,iOS,Android}` (`./update.sh` legt ihn an). Alte Release-Ordner nie überschreiben.
- Vor jeder UI-Änderung `Quellcode/docs/DESIGN-RICHTLINIEN.md` lesen (Apple HIG: Prinzipien, Layout, Farbe, Materialien; Fokus und Auswahl).

## Releases

- Release immer mit `tools/release.sh` aus der Repo-Wurzel. Nur den Zielordner anzeigen, ohne zu bauen: `tools/release.sh --pfad`.
- Das Skript ruft das bestehende `./update.sh` auf und reicht alle Optionen weiter (`--version`, `--only mac|ios|android`, `--skip-tests`, `--dry-run`). `update.sh` ersetzt die Dateien in `Download-macOS/`, `Download-iOS/` und `Download-GoogleTV/`.
- Ziel: iCloud Drive › `Projektelab/01_Apps/IPTelevision+/Releases/<JJJJ-MM-TT>_v<X.Y.Z>/Dateien/<Plattform>` (Version auf drei Stellen ergänzt, z. B. 1.5 → v1.5.0). Gibt es den Ordner schon, hängt das Skript `_2`, `_3` … an. In `Releases/` nie etwas überschreiben, umbenennen oder löschen. Nach einem Release `Release.md` aus `Projektelab/99_Vorlagen/Release.md` anlegen.
- Ablage: Dieses Repo liegt ausserhalb von iCloud in `~/Developer/IPTelevision-plus` (seit 2026-11-13). Design, Marketing und Releases liegen in iCloud Drive › `Projektelab/01_Apps/IPTelevision+/`. Regeln: `Projektelab/MAIN.md`.
- Das Skript findet den Release-Ordner über einen festen Pfad (überschreibbar mit `PROJEKTELAB_RELEASES`) und bricht ab, wenn er fehlt. Nach einem Umzug `tools/release.sh --pfad` prüfen.
- Nichts committen, pushen, hochladen oder im Store einreichen ohne ausdrücklichen Auftrag.

## Ablage ausserhalb des Repos

Design, Marketing und Releases liegen ausserhalb dieses Repos (lokaler Ordner `Projektelab/01_Apps/IPTelevision+/` in iCloud Drive). Dafür gelten die lokalen Ablageregeln des Besitzers, sie gehören nicht ins öffentliche Repo.
