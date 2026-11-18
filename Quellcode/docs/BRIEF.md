# TV+ (ARJO TV+)

IPTV-Player für Mac, iPhone, Apple TV und Google TV. Zeigt die eigenen Sender, Filme und Serien des Nutzers (Xtream oder M3U) ruhig auf dem grossen Bildschirm.

## Ersetzt
Fremde IPTV-Player mit Werbung und lautem Design. Haltung laut TV-App-Guide V1.0: «Zurücklehnen. Nicht suchen.»

## Hauptaufgaben
1. Live TV schauen, Sender per Fernbedienung wechseln, Favoriten.
2. Filme und Serien finden und fortsetzen («Weiterschauen»).
3. Suchen (Sender, Filme, Serien) mit Bildschirmtastatur und Fernbedienung.

## Daten
- Quelle: Server, Benutzer, Passwort (Keychain) oder M3U-Adresse.
- Sender, Gruppen, Filme, Serien, EPG (lokal zwischengespeichert), Wiedergabestand, Favoriten.

## Form
- Mac, iPhone, Apple TV: ein SwiftUI-Projekt (`Quellcode/`), macOS 15+, iOS/tvOS 18+.
- Google TV (TCL): getrennte Android-App (`AndroidTV/`, Java, Media3), Android TV 8+.
- Lokale Daten, keine Konten, kein Tracking. Netz nur zum eigenen Anbieter.

## System-Anbindung
Top Shelf (tvOS), Deep Link `arjotv://`, Vollbild und Multiview auf dem Mac, Menü, Fernbedienung (Hoch, Runter, Links, Rechts, OK, Zurück).

## Referenz
`ARJO-LAB_TV-App-Guide_V1.0.pdf` (massgeblich ab 31.10.2026, gilt bei Widerspruch zu anderen Guides) und `ARJO-TVplus_AppIcon_v3.svg`.

## Look
Eigene Marke, auf Plattform-Komponenten aufgebaut: Dark ist Standard (`#090A0A`), Raised `#1A1B1D`, Elevated `#2A2C2C`, Text `#FDFDFC`. Glut `#FC5F39` nur für Fokusring, Fortschritt und Punkt. Schrift Geist Medium/Regular, Geist Mono für Micro. Kachel-Radius 12 px, Fokus: Ring 4 px plus Skalierung 1.06, Bewegung 200–400 ms, Text mindestens 24 px bei 1080p, 5 % Title-safe-Rand. Name in der App «TV+», im Store «ARJO TV+», Absender «Ein Produkt von ARJO LAB».

## Icon
Unverändert aus `ARJO-TVplus_AppIcon_v3.svg` (flaches Master-Bild, 1024 × 1024). Nicht neu zeichnen, nicht umfärben.

## Nicht in Version 1
- Eigene Bildschirmtastatur auf Apple TV (System-Tastatur), Hero-Vorschau mit Bewegtbild.
- Mehrere Quellen und PIN auf Google TV, EPG und Catch-up auf Google TV.
- Geschichtetes tvOS-Icon (Ebenen-Master fehlt).
