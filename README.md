# IPTVTelevisionPlus

Öffentliche Release-Ablage für **IP Television+**, den IPTV-Player für Mac, iPhone, iPad, Apple TV und Google TV. Der Quellcode liegt nicht hier.

Die App liefert keine Sender und keine Inhalte. Quellen (Xtream Codes oder M3U) gibt die nutzende Person selbst ein. Keine Werbung, keine Tracker.

## Downloads

Alle Dateien stehen unter [Releases](../../releases/latest):

| Plattform | Datei |
|---|---|
| macOS 15+ | `IPTelevisionPlus-<Version>-macOS.zip` |
| Google TV / Android TV | `IPTelevisionPlus-<Version>-GoogleTV.apk` |

iPhone, iPad und Apple TV: Installation über TestFlight oder Xcode, die App meldet dort nur, dass ein Update bereitliegt.

## Automatische Updates

Die App fragt beim Start `releases/latest` dieses Repos ab.

- **macOS:** Sparkle lädt `appcast.xml` und das ZIP aus dem neuesten Release, prüft die EdDSA-Signatur und installiert das Update.
- **Google TV:** Die App lädt die APK aus dem neuesten Release und öffnet den Android-Installer. Android verlangt dafür einmalig die Erlaubnis «Aus dieser Quelle installieren».
- **iPhone, iPad, Apple TV:** Die App zeigt einen Hinweis mit Link auf die Release-Seite. Apple erlaubt keine Selbstinstallation.
