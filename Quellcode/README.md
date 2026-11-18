# ARJO TV

IPTV-Player für Apple TV, iPhone und iPad. Die App ist nur ein Player und liefert **keine Sender oder Inhalte** mit; der Nutzer gibt seine eigenen Zugangsdaten ein (Xtream Codes oder M3U-Playlist). Keine Werbung, keine Tracker, keine Analyse.

## Aufbau

Ein Multiplattform-Target («ARJO TV») und fünf lokale Swift Packages. Abhängigkeiten zeigen nach unten: App → UI → Core; Network, Data und Player kennen sich nicht untereinander.

| Package | Inhalt |
|---|---|
| `ARJOCore` | Modelle, Protokolle (Repositories, Player-Engine), reines Swift |
| `ARJONetwork` | Xtream-Client, M3U-Streaming-Parser, XMLTV-Parser, gzip, Playlist-Quelle |
| `ARJOData` | SwiftData-Speicher (Katalog, EPG, Film-/Serienlisten, Nutzerdaten), Keychain (Zugangsdaten, PIN) |
| `ARJOPlayer` | `PlaybackController` (Reconnect), AVPlayer-Engine, VLC-Fallback, Oberflächen für das Bild |
| `ARJOUI` | SwiftUI-Ansichten und View-Models (MVVM) |
| `App/` | `ARJOTVApp`, `AppEnvironment` (verdrahtet alles), Entitlements, Info.plist, Privacy-Manifest, Top-Shelf-Erweiterung |

## Xcode-Projekt

`ARJOTV.xcodeproj` liegt bereit: öffnen, unter Signing & Capabilities das eigene Team wählen, starten. Das Projekt wird aus `project.yml` erzeugt (`brew install xcodegen`, dann `xcodegen generate`); Änderungen an Zielen, Einstellungen oder Dateien gehören in `project.yml`, nicht ins Projekt.

- Neue Texte im Code ergänzt `python3 Tools/generate_localizations.py App/Localizable.xcstrings` (englische Übersetzung in der Tabelle `EN` im Skript nachtragen).
- iCloud einschalten: `docs/ICLOUD-SYNC.md`. App Group, Hintergrundmodi und Top Shelf: `docs/TestFlight-Checkliste.md`.
- Beim ersten Build lädt Xcode das ca. 780 MB grosse VLCKit-Binary (Fallback-Engine).
- Das Logo-Intro (`App/Resources/ArjoIntro.mp4`) läuft bei jedem Start einmal; ein Tipp überspringt es.

## Tests

```bash
for p in ARJOCore ARJONetwork ARJOData ARJOPlayer ARJOUI; do (cd Packages/$p && swift test); done
```

Die Tests laufen auf dem Mac. Alles, was Bild und Ton oder die echten Server betrifft, muss auf Gerät oder Simulator mit einem Testkonto geprüft werden.

## Funktionen

- **Quellen:** Xtream (Server, Benutzer, Passwort), M3U per URL oder Datei (iOS), mehrere Quellen, Umschalten und Entfernen in den Einstellungen, automatische Aktualisierung (24 h). Zugangsdaten nur in der Keychain (optional iCloud-Schlüsselbund). M3U-Playlists liefern auch Filme und Serien: Einträge mit `/movie/`- oder `/series/`-Pfad bzw. Aufnahme-Endung (`.mkv`, `.mp4` …) werden erkannt, Episoden aus Namen wie `Show S01E02` zu Staffeln gruppiert.
- **Live TV:** Gruppen als Reihen (in eigener Reihenfolge), Favoriten und eigene Ordner, Ausblenden und Umbenennen von Sendern und Gruppen, «Zuletzt gesehen», Senderliste im Player, Wischen hoch/runter wechselt den Sender (Apple TV), optional Fortsetzen beim Start.
- **Catch-up/Timeshift:** Bei Sendern mit Archiv (Xtream `tv_archive`, M3U `catchup`) zeigt der Programmführer «Aufnahme ansehen» bzw. «Von Anfang ansehen»; im Player «Von Anfang» und «Live». Adressen: Xtream `/timeshift/…` in der Serverzeit, M3U-Arten `default`/`append`/`shift`/`flussonic` mit den üblichen Platzhaltern.
- **Multiview:** bis zu vier Sender gleichzeitig (Symbol oben rechts in Live TV oder «Im Multiview ansehen» im Kontextmenü eines Senders). Nur ein Bild hat Ton, die anderen laufen stumm und mit begrenzter Bitrate.
- **EPG:** XMLTV (Xtream `xmltv.php`, M3U `url-tvg`, auch gzip), Jetzt/Danach auf Kacheln und im Player, Programmführer-Raster (3-Stunden-Fenster), Zeitversatz und Zeitzone einstellbar.
- **Filme und Serien:** Raster nach Kategorien, Details, Staffeln und Episoden, Weiterschauen mit Fortschritt, Gesehen-Markierung, automatisch die nächste Episode (mit Ankündigung, abbrechbar).
- **Player:** AVPlayer, bei MKV/AVI/TS/AC3 oder Fehlern automatisch VLCKit (mit Audio-/Untertitelwahl, Spulen, Zeitleiste), automatischer Reconnect mit Wiederaufnahme an der letzten Position, Bild-in-Bild (iOS), Seitenverhältnis (auch bei VLC) und Puffer einstellbar, Audio- und Untertitelwahl bei beiden Engines (bei Live TV auf Apple TV in der Senderliste).
- **Suche:** über Sender, Filme, Serien und Sendungen der nächsten 48 Stunden, Diktat über die Systemtastatur bzw. Siri Remote.
- **Kindersicherung:** PIN (4–6 Ziffern, Hash in der Keychain), gesperrte Gruppen erscheinen nirgends (Reihen, Suche, Weiterschauen, Top Shelf), 10 Minuten freigegeben nach richtiger PIN, Sperre nach fünf Fehlversuchen.
- **Sync und Backup:** CloudKit (private Datenbank) für Profile, Einstellungen, Favoriten, Ordner, Wiedergabestand und zuletzt gesehenen Sender inkl. Timeshift-Stelle (Kompilierflag `ICLOUD_SYNC`, Architektur, Konfliktregel und Einrichtung: `docs/ICLOUD-SYNC.md`). Status, Schalter und «Wiedergabeverlauf löschen» unter Einstellungen › iCloud. Backup/Restore als JSON-Datei (iOS, Mac), ohne Zugangsdaten und PIN.
- **Sprachen:** Deutsch (Schweiz) und Englisch über einen String Catalog; die App folgt der Systemsprache.
- **Startseite:** grosses Titelbild (Weiterschauen, sonst zuletzt gesehener Sender, sonst Favorit), Reihen «Weiterschauen», «Zuletzt gesehen», «Favoriten», eigene Ordner, «Neue Filme/Serien» (zuletzt hinzugefügt); Live-Karten zeigen die laufende Sendung. Gesperrte und ausgeblendete Inhalte fehlen.
- **Apple-TV-Stil:** dunkles Design (Navy/Gold, Akzentfarbe wählbar), Fokus-Effekt, unscharfer Hintergrund aus dem fokussierten Inhalt, Top Shelf mit «Weiterschauen».

## Manuell testen

1. Starten, anmelden (Xtream oder M3U). Beim ersten Start wird die Senderliste geladen (bei grossen Listen einige Sekunden), danach im Hintergrund das EPG.
2. Live TV: Sender anwählen, im Player wischen (Apple TV) bzw. die Liste öffnen (iOS), WLAN kurz trennen → «Verbindung wird neu aufgebaut».
3. Lange auf einen Sender drücken: Favorit, Ordner, Umbenennen, Ausblenden. Verwaltung unter Einstellungen › Favoriten & Ordner.
4. Filme/Serien: Poster öffnen, abspielen, nach über 10 Sekunden schliessen → «Fortsetzen ab …» und Startseite › Weiterschauen.
5. MKV-Film abspielen → VLC-Bedienelemente (Audiospur, Untertitel, ±10 s).
6. Suche: Begriff eintippen oder diktieren.
7. Einstellungen › Kindersicherung: PIN setzen, Gruppe sperren, Reihe zeigt «Gesperrt», Entsperren mit PIN.
8. Einstellungen › Backup (iOS): exportieren, App-Daten ändern, wiederherstellen.
9. Zwei Geräte mit demselben iCloud-Konto (mit `ICLOUD_SYNC`): Favorit auf dem einen setzen, auf dem anderen App öffnen.
10. Catch-up: Im Programmführer eine vergangene Sendung eines Senders mit Archiv wählen → «Aufnahme ansehen». Im Live-Player «Von Anfang» und zurück mit «Live».
11. Multiview: zwei bis vier Sender hinzufügen, Bild anwählen setzt den Ton dorthin, langes Drücken ersetzt oder entfernt ein Bild.
12. Serie bis zum Ende einer Episode ansehen → «Als Nächstes» erscheint und startet nach 8 Sekunden.
13. Gerätesprache auf Englisch stellen: alle Texte erscheinen englisch.

## Bekannte Lücken

- **Nicht umgesetzt:** Aufnahmen auf dem Gerät (die App spielt nur ab, was der Anbieter als Archiv bereithält), gleichzeitiges Verschieben ganzer Gruppen per Ziehen (Reihenfolge ändert sich per Menü «Nach oben/unten»), weitere Sprachen als Deutsch und Englisch.
- **Nur auf Geräten prüfbar:** Wiedergabe, Siri-Remote-Bedienung, Bild-in-Bild, Multiview-Leistung (vier Streams gleichzeitig), Top Shelf, CloudKit-Sync, VLC-Verhalten mit echten Streams, Catch-up-Adressen mit echten Anbietern (Anbieter weichen bei Zeitzone und Format ab).
- **M3U-Filme und -Serien:** Handlung, Besetzung und Bewertung fehlen (die Playlist enthält sie nicht); die Erkennung beruht auf Pfad, Dateiendung und Namensmuster und kann bei ungewöhnlichen Playlists danebenliegen.
- **Speicher:** Die Xtream-Senderliste wird vor dem Import komplett dekodiert; M3U-Playlists werden dagegen gestreamt. Der EPG-Import puffert Sendungen im Arbeitsspeicher (Zeitfenster und Sender-Filter begrenzen das).
- **tvOS-Speicher:** Das System darf lokale Dateien auf Apple TV löschen. Kataloge werden dann neu geladen; Profile kommen mit iCloud-Sync zurück.
