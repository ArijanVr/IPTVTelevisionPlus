# IPTVTelevisionPlus

Öffentliche Release-Ablage für **IP Television+**, den IPTV-Player für Mac, iPhone, iPad, Apple TV und Google TV. Der Quellcode liegt nicht hier.

Die App liefert keine Sender und keine Inhalte. Quellen (Xtream Codes oder M3U) gibt die nutzende Person selbst ein. Keine Werbung, keine Tracker.

## Downloads

Alle Dateien stehen unter [Releases](../../releases/latest):

| Plattform | Datei |
|---|---|
| macOS 15+ | `IPTelevisionPlus-<Version>-macOS.dmg` |
| Google TV / Android TV | `IPTelevisionPlus-<Version>-GoogleTV.apk` |

iPhone, iPad und Apple TV: Installation über TestFlight oder Xcode, die App meldet dort nur, dass ein Update bereitliegt.

## Automatische Updates

Die App fragt beim Start `releases/latest` dieses Repos ab.

- **macOS:** Sparkle lädt `appcast.xml` und die DMG aus dem neuesten Release, prüft die EdDSA-Signatur und installiert das Update.
- **Google TV:** Die App lädt die APK aus dem neuesten Release und öffnet den Android-Installer. Android verlangt dafür einmalig die Erlaubnis «Aus dieser Quelle installieren».
- **iPhone, iPad, Apple TV:** Die App zeigt einen Hinweis mit Link auf die Release-Seite. Apple erlaubt keine Selbstinstallation.

---

# IPTelevision+

IPTV-Player für Mac, iPhone und Apple TV (Xtream Codes oder M3U-Playlist). Die App liefert **keine Sender oder Inhalte**; du gibst eigene Zugangsdaten ein. Keine Werbung, keine Tracker. Version 1.0.0 (Build 1) (Design nach TV+ tvOS-Brandguide V1), App-Name «TV+», Bundle-ID `ch.arjo.iptelevision`.

Mac: macOS 15 oder neuer, Apple Silicon und Intel, Developer ID signiert und von Apple notarisiert.

## Struktur

| Ordner | Inhalt |
| --- | --- |
| `Websitedownload Arjo TV/` | Fertige Datei für Kunden und Website: `IPTelevision-Mac.dmg`, Prüfsumme, Upload-Anleitung, Website-Text |
| `Quellcode/` | Xcode-Projekt (`ARJOTV.xcodeproj` aus `project.yml`), `App/`, Packages (ARJOCore, ARJONetwork, ARJOData, ARJOPlayer, ARJOUI), `Tools/`, `docs/` |
| `Quellcode/ARJOTV-RELEASE/` | `scripts/build.sh`, `INSTALLATION.md`, `BUILD-REPORT.md`, statische Download-Seite unter `website/` |

Funktionen, Tests auf dem Gerät und bekannte Lücken: `Quellcode/README.md`.

## Installation (Kunden, Mac)

1. `IPTelevision-Mac.dmg` öffnen.
2. **IPTelevision+** auf den Ordner «Programme» ziehen.
3. Aus «Programme» starten. Beim ersten Start einmal «Öffnen» wählen.

Prüfsumme:

```sh
cd "Websitedownload Arjo TV"
shasum -a 256 -c IPTelevision-Mac.dmg.sha256
```

iPhone und Apple TV: siehe `Quellcode/ARJOTV-RELEASE/INSTALLATION.md`. Für TestFlight oder Ad-hoc braucht es den bezahlten Apple-Developer-Account.

## Neu bauen (Entwickler)

Projekt aus der Spezifikation erzeugen:

```sh
cd Quellcode && xcodegen generate
```

Mac-Release signieren, notarisieren und DMG bauen (Zertifikat «Developer ID Application» in der Keychain, Keychain-Profil `arjo-notary`):

```sh
cd Quellcode/ARJOTV-RELEASE
ARJO_ONLY_MAC=1 ARJO_DEVID="Developer ID Application: ARIJAN VRANJA (D752V8XA4G)" ARJO_NOTARY_PROFILE=arjo-notary ./scripts/build.sh
```

Ergebnis: `Quellcode/ARJOTV-RELEASE/downloads/ARJOTV-macOS.dmg`. Datei nach `Websitedownload Arjo TV/IPTelevision-Mac.dmg` kopieren (alte ersetzen) und die Prüfsumme neu erzeugen:

```sh
cd "Websitedownload Arjo TV"
shasum -a 256 IPTelevision-Mac.dmg > IPTelevision-Mac.dmg.sha256
```

## Tests

```sh
for p in ARJONetwork ARJOData ARJOPlayer ARJOUI; do (cd Quellcode/Packages/$p && swift test); done
```

Wiedergabe, Siri Remote, Multiview und VLC mit echten Streams nur auf Gerät oder Simulator prüfen.
