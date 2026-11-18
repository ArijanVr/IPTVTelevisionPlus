# IPTelevision+ für Samsung TV (Tizen)

Tizen-Web-App (`.wgt`, App-ID `IPTVplusTV.IPTelevision`, Version 1.0.0). Sie überträgt die Google-TV-App 1.0.0 (`AndroidTV/`, Stand Commit `0308d7e`) Funktion für Funktion: gleiche Bildschirme, Texte, Farben, Abläufe und Fernbedienungslogik. Andere Builds (Apple, alte Tizen-Version) sind nicht die Vorlage.

## Zuordnung Android → Tizen

| Google TV (`ch/arjo/tv/android`) | Tizen (`wgt/js`) |
| --- | --- |
| `Source`, `Entry`, `PresetSource`, `M3u`, `Catalog` (Auswertung), `ChannelNumbers`, `ChannelNavigator`, `PlaybackQueue`, `Lists`, `MultiviewLayout` | `core.js` |
| `Catalog` (Netz), `CatalogCache`, `Vault`, `NumberStore`, SharedPreferences | `store.js` |
| `TvStyle`, Fokussuche, `AlertDialog`, `Toast` | `ui.js`, `css/style.css` |
| `LibraryView`, `ListEditor` | `library.js` |
| `PlayerActivity`, `RemoteInput`, `MultiviewActivity` | `screens.js`, `player.js` |
| `MainActivity` | `app.js` |

## Was technisch anders ist (Plattform, nicht Funktion)

- Wiedergabe mit Samsung AVPlay statt ExoPlayer. Zwischen zwei Streams liegen mindestens 4 s, bei Verbindungsfehlern höchstens 2 Wiederholungen: auf dieser TV gemessen (alte Tizen-Version, 08.11.2026), der Anbieter gibt eine Verbindung sonst nicht frei.
- Multiview nutzt HTML5-Video, weil AVPlay auf Tizen nur ein Bild gleichzeitig zeigt. Wie viele Bilder wirklich laufen, entscheiden die Decoder der TV.
- Zugang und Verlauf liegen im privaten App-Speicher (localStorage), Katalog und Kanalnummern in IndexedDB. Tizen hat keinen Android Keystore; die Daten sind deshalb nicht zusätzlich verschlüsselt, aber für andere Apps nicht lesbar.
- Interne Kennungen nutzen einen schnellen 53-Bit-Hash statt SHA-256 (130 000 Einträge wären auf der TV sonst zu langsam). Sichtbar ist das nicht.
- Dropbox-Links werden auf `dl.dropboxusercontent.com` umgeschrieben (die TV erhält unter `www.dropbox.com` sonst eine Webseite).
- Wiedergabestabilität: AVPlay-Puffer 4 s Start / 8 s nach Aussetzern (Samsung-Minimum 4 s). Live-Bild ohne Fortschritt über 20 s wird höchstens 2-mal in 10 min neu geladen, danach Meldung mit «Erneut versuchen». Verbindungsfehler: 2 Wiederholungen (6 s, 12 s), Formatfehler ohne Wiederholung. Schnelles Zappen öffnet nur den letzten Sender.
- Diagnose: die letzten 200 Wiedergabe-Ereignisse (Puffer, Fehlercodes, Neustarts, Pausen) in `localStorage` unter `iptv.diag` und in der Konsole (`[IPTV]`), ohne Adressen oder Zugangsdaten. Auslesen über den Web Inspector von Tizen Studio: `Players.Diag.dump()`.
- Zusatz: Steht im Multiview nur ein Bild über die ganze Fläche, führt «Hoch» in die Bedienleiste.

## Fernbedienung

Wie Google TV: Live ↑/↓ bzw. P+/P− Sender, ←/→ Gruppe, Ziffern wählen eine Nummer, OK kurz Banner, OK lang Zahlenfeld, «PreCh» letzter Kanal, Info/Tools Ton und Untertitel. Filme/Episoden: ←/→ 10 s (gehalten 30 s), OK Bedienleiste. In Listen: OK öffnen, OK halten (oder Tools) Menü mit Favoriten. Zurück wie auf Google TV; die App verlässt man mit der Home-Taste oder über «Beenden».

## Bauen

```bash
PROFILE=Arjo ./build.sh
```

Prüft die Syntax, führt `node tests/core.test.js` aus und legt `Installation/IPTelevision-SamsungTV-1.0.0.wgt` mit Prüfsumme an. Braucht Tizen Studio unter `~/tizen-studio` und das Samsung-Zertifikatsprofil. Eingebaute Quelle: «Durim» aus der nicht versionierten `playlist.Durim.local.properties` (`playlistUrl=…`). Weitere Dateien `playlist.<Name>.local.properties` ergeben weitere benannte Quellen; bei mehreren erscheint unter Profil «Quelle: … ⌄». Die Dateien enthalten Zugangsdaten: nicht weitergeben, nicht committen.

Installieren (TV im Entwicklermodus, gleiches Netz): `PROFILE=Arjo INSTALL=1 TV_IP=192.168.1.85 ./build.sh`.

## Geprüft

- `node tests/core.test.js` (übertragen aus den Android-Unit-Tests) und `node tests/player.test.js` (simuliertes AVPlay: Retry-Grenzen, Stillstand, Senderwechsel, veraltete Callbacks).
- Im Browser mit künstlicher Playlist: Autostart Kanal 1, Zappen, Gruppenwechsel, Zifferneingabe, Mediathek, Reihen, Detail, Film mit Spulen und Bedienleiste, Menü «OK halten», Multiview mit zwei Bildern, Meine Listen, Anmeldung.
- Noch nicht auf der Samsung-TV installiert oder mit echtem Anbieter abgespielt.
