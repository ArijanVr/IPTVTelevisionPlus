# ARJO TV

| Ordner / Datei | Inhalt |
|---|---|
| `Websitedownload Arjo TV/` | **Das lädst du auf die Website hoch:** `IPTelevision-Mac.dmg` (signiert und von Apple notarisiert), Prüfsumme, `1-UPLOAD-ANLEITUNG.txt`, `2-TEXT-FUER-DIE-WEBSITE.txt` |
| `Quellcode/` | Vollständiges Xcode-Projekt (iOS, tvOS, macOS): `ARJOTV.xcodeproj`, `App/`, `Packages/`, `project.yml`, `Tools/`, `docs/`, `README.md` |
| `Quellcode/ARJOTV-RELEASE/scripts/build.sh` | Baut alles neu (Mac, iPhone, Simulator), signiert, notarisiert und baut die DMG |
| `Quellcode/ARJOTV-RELEASE/INSTALLATION.md`, `BUILD-REPORT.md` | Installationsanleitung und letzter Build-Bericht |
| `Quellcode/ARJOTV-RELEASE/website/` | Statische Download-Seite (Daten werden von `build.sh` erzeugt) |

## Neue Version bauen und signieren
```bash
cd Quellcode/ARJOTV-RELEASE
ARJO_ONLY_MAC=1 ARJO_DEVID="Developer ID Application: ARIJAN VRANJA (D752V8XA4G)" ARJO_NOTARY_PROFILE=arjo-notary ./scripts/build.sh
```
Ergebnis: `Quellcode/ARJOTV-RELEASE/downloads/ARJOTV-macOS.dmg`. Diese Datei nach `Websitedownload Arjo TV/IPTelevision-Mac.dmg` kopieren (alte ersetzen) und die Prüfsumme mit `shasum -a 256` neu erzeugen.
Voraussetzung: Zertifikat «Developer ID Application» in der Keychain und das Keychain-Profil `arjo-notary` (`xcrun notarytool store-credentials`).
