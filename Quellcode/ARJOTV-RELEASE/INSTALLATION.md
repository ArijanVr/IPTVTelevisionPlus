# ARJO TV installieren

## Mac (DMG aus `Websitedownload Arjo TV/`)
1. DMG öffnen, **ARJO TV** auf «Programme» ziehen, starten. Beim ersten Start einmal «Öffnen» bestätigen.
2. Mit Developer ID signiert, von Apple notarisiert und angeheftet (kein Terminal-Befehl nötig).
3. Universal (Apple Silicon + Intel). Wiedergabe: AVPlayer, für MKV/AVI/TS automatisch VLC. Zugangsdaten liegen in der lokalen Keychain (kein iCloud-Sync).

## iPhone
Das iPhone-IPA (`downloads/ARJOTV-iOS.ipa`, entsteht mit `build.sh`) ist mit dem kostenlosen Personal Team (Entwicklungs-Signierung) erstellt:
- läuft nur auf den im Profil eingetragenen Geräten (siehe BUILD-REPORT.md), nicht auf Geräten von Freunden;
- das Profil läuft nach 7 Tagen ab, dann muss neu gebaut/installiert werden.

Installation auf dem eigenen iPhone: Xcode → Window → Devices and Simulators → iPhone wählen → IPA hineinziehen. Oder Projekt in Xcode öffnen, Team wählen, iPhone als Ziel, Run.

**Freunde:** Ein kostenloser Account kann keine Apps dauerhaft verteilen. Nötig ist das bezahlte Apple Developer Program (99 USD/Jahr): dann TestFlight oder Ad-hoc (bis 100 registrierte Geräte).

## Apple TV
Keine installierbare Datei: Für tvOS existiert kein Provisioning Profile (der Apple TV ist nicht als Gerät registriert). Der tvOS-Build wurde nur im Simulator geprüft. Zum Installieren: Apple TV in Xcode koppeln (Window → Devices), Team wählen, Run.

## Simulator-Builds (`simulator-builds/`, entstehen mit `build.sh`)
**Nur für den Xcode-Simulator, auf keinem echten Gerät installierbar.**
`xcrun simctl install booted <App.app>` (zuvor ZIP entpacken).

## Später mit bezahltem Account
```bash
ARJO_TEAM_ID=DEINTEAMID ARJO_EXPORT_METHOD=release-testing ARJOTV-RELEASE/scripts/build.sh   # Ad-hoc
ARJO_EXPORT_METHOD=app-store-connect ARJOTV-RELEASE/scripts/build.sh                          # TestFlight
```
Für den Mac zusätzlich «Developer ID Application» und Notarisierung (`xcrun notarytool`), damit Gatekeeper ohne Warnung öffnet.

## Hosting
`website/` und `downloads/` als Geschwisterordner hochladen (die Seite verlinkt `../downloads/…`).
