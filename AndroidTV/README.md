# ARJO TV für Google TV / Android TV

Separate Android-Kopie im Ordner `AndroidTV/`. Die Apple-Version in `../Quellcode/` bleibt unverändert. Version 2.1.0 übernimmt das Redesign der Apple-Version (Logo-Kacheln, Meine Listen, Multiview) in einer für Fernbedienung angepassten Android-Oberfläche. Sie ist eine Privat-/Testversion, keine vollständige Funktionskopie und kein Play-Store-Release.

Die vom Nutzer gelieferte Dropbox-M3U ist in der aktuellen Installationsdatei voreingestellt. Beim ersten Start bzw. beim ersten Update auf diese Voreinstellung wird sie direkt geladen. Danach bleiben bewusst gewechselte Quellen und Abmeldungen erhalten. Die Quelle wird weiterhin über «Einstellungen» verwaltet.

Für eigene Neubauten liegt die Voreinstellung in der nicht versionierten `playlist.local.properties` (`playlistUrl=…`); alternativ kann `ARJO_DEFAULT_PLAYLIST_URL` gesetzt werden. Der private Freigabelink wird nicht in der Dokumentation oder im versionierten Quellcode wiederholt. Nur der Release-Build enthält die Voreinstellung, Debug-Builds bleiben für isolierte Tests ohne externe Quelle.

## Enthalten

- Original-ARJO-Logo und Markenfarben, grosse Startseite mit Titelbild, horizontalen Senderreihen, Filmplakaten und Wiedergabefortschritt.
- Navigation wie im Original: Startseite, Live TV, Filme, Serien, Suche, Einstellungen; Kategorien, Favoritenfilter und Detailseiten mit Staffelauswahl.
- Google-TV-Startbildschirm, Querformat, Bedienung mit Richtungstasten und OK; sichtbarer Fokus und skalierbare Schrift.
- Xtream-Anmeldung: Serveradresse, Benutzername und Passwort.
- M3U per HTTP-/HTTPS-URL, Gruppen und Erkennung von Filmen/Episoden; relative Streamadressen und gzip-Übertragung werden unterstützt.
- Live TV, Filme, Serien; bei Xtream mit Staffeln und Episoden.
- Kategorien, globale Suche über Sender/Filme/Serien, Favoriten (OK gedrückt halten).
- Senderkacheln: Logo gross auf einer 16:9-Fläche, Fokusring in Glut nur um die Bildfläche. Name darunter abschaltbar (dann erscheint er nur bei Fokus), Kachelgrösse Kompakt/Normal/Gross.
- Meine Listen (Einstellungen oder «Listen bearbeiten» in Live TV): Kategorien und Sender ein-/ausblenden, umbenennen, Kategorien verschieben, Reihen der Startseite ein-/ausblenden und ordnen. Pro Quelle gespeichert; ausgeblendete Einträge fehlen überall.
- Multiview: bis zu vier Sender, nur so viele Felder wie laufende Sender (3 = 2 oben, 1 unten), Anordnungen Raster, Fokus, Bühne, Reihe und Bild in Bild. OK auf einem Bild setzt den Ton, OK halten bzw. Menü-Taste: ersetzen oder entfernen. Stumme Bilder laufen mit höchstens 2,5 Mbit/s.
- Media3/ExoPlayer mit HLS, DASH und progressiven Streams (z. B. TS, MP4, MKV). Tatsächliche Bild-/Tonunterstützung hängt vom Decoder des Fernsehers ab. Kein VLC-Fallback. Wie viele Multiview-Bilder gleichzeitig laufen, hängt von den Hardware-Decodern des Fernsehers ab.
- Vollbild, Pause, Spulen bei abrufbaren Inhalten, vom Stream angebotene Audio-/Untertitelspuren über das Player-Menü, Wiedergabestand für Filme/Episoden.
- Senderlogos und Filmplakate aus der Quelle, bei Xtream auch Beschreibung/Besetzung/Regie soweit vorhanden. Artwork nur in einem begrenzten Arbeitsspeicher-Cache.
- Ein lokal verschlüsselt gespeicherter Zugang und Verlauf mit bis zu 30 Einträgen (AES-GCM, Android Keystore); keine Zugangsdaten im Klartext in den App-Einstellungen. Backups und Geräteübertragung ausgeschlossen. Keine Analyse oder Werbung.

## Fernbedienung im Player

- Live TV: Hoch bzw. P+ zum nächsten Sender, Runter bzw. P− zum vorherigen Sender innerhalb derselben Gruppe. Am Ende/Anfang wird umgebrochen.
- Filme und Serienepisoden: Links/Rechts um 10 Sekunden zurück/vor; bei längerem Halten 30-Sekunden-Schritte. Gespult wird nur bei spulbaren Streams, begrenzt auf Anfang und Ende.
- OK öffnet die Player-Bedienelemente. Dort bleiben Richtungstasten für Fokus, Ton und Untertitel verfügbar. Zurück schliesst zuerst das Menü und anschliessend den Player.
- Android-Drehrad-/Scroll-Ereignisse werden ebenfalls ausgewertet: Senderwechsel bei Live TV bzw. Spulen bei Filmen/Episoden. Die Fernbedienung muss solche Ereignisse an die App weitergeben; physisches Drehen ohne Android-Eingabesignal kann die App nicht erkennen.
- Gedrückthalten wird gedrosselt; ein Tastendruck wird beim Loslassen nicht doppelt ausgeführt. Ein nicht erreichbarer Live-Sender blockiert das weitere Umschalten nicht mit einem Dialog.

## Grenzen gegenüber der Apple-Version

Noch nicht umgesetzt: EPG/Programmführer, Catch-up/Timeshift, PIN/Kindersicherung, mehrere gleichzeitig gespeicherte Quellen, Cloud-Sync/Backup, eigene Ordner, automatische nächste Episode und Englisch. M3U-Episoden werden als einzelne Einträge angezeigt; Staffelstruktur gibt es bei Xtream. Erweiterte M3U-Optionen wie `#EXTVLCOPT`, benutzerdefinierte HTTP-Header, DRM, lokale Playlistdateien und RTSP werden nicht ausgewertet. Die Quelle muss eine unterstützte, unverschlüsselte IPTV-Wiedergabe erlauben. Die App liefert keine Inhalte.

Beim Start wird der aktuelle Katalog neu geladen; ein Offline-Katalog ist nicht enthalten. Grosse Xtream-Antworten sind auf 48 MiB begrenzt. HTTP wird für vorhandene IPTV-Anbieter zugelassen; bei HTTP sind Zugang und Streams auf dem Transportweg nicht verschlüsselt. HTTPS nach Möglichkeit verwenden. Abgelaufene/abgelehnte Zugänge werden nicht gespeichert. Fehlermeldungen und App-Logs zeigen keine Provider-URLs oder Passwörter an.

## Installation und Prüfung

Siehe `INSTALLATION.md`, `BUILD-REPORT.md` und den Designabgleich in `DESIGN.md`. Gerenderte Android-Ansichten mit künstlichen Testdaten liegen unter `Vorschau/`. Mindestversion: Android TV 8 (API 26). Ein bereits verbundenes TCL-Gerät wurde lesend als Android 14 erkannt. Es wurde im Rahmen der Erstellung noch nichts darauf installiert, gestartet oder mit einem echten Anbieter abgespielt.

## Bauen

JDK 17, Android SDK Platform 36 / Build Tools 35.0.0 und Internet für Gradle-Abhängigkeiten. Gradle 8.13 und Android Gradle Plugin 8.13.2 sind festgelegt. Media3 ist auf 1.9.4 festgelegt.

```bash
cd AndroidTV
./scripts/build.sh
```

Das Skript führt Tests und Android Lint aus und erstellt danach `Installation/IPTelevision-GoogleTV-1.2.0.apk` mit SHA-256-Prüfsumme. Alternativ dieses Verzeichnis in Android Studio öffnen. Eigene SDK-Pfade über `ANDROID_HOME` oder eine nicht versionierte `local.properties` angeben.

Die APK ist nicht debuggable, wird für die private Installation aber mit dem lokalen Android-Debug-Zertifikat signiert. Keine Schlüsseldatei liegt im Projekt. Updates benötigen dasselbe Zertifikat; den lokalen Android-Schlüsselspeicher auf diesem Mac erhalten. Für eine öffentliche Veröffentlichung ist eine eigene Release-Signatur nötig. Das Build-Skript lädt nichts hoch und verbindet sich mit keinem Fernseher.

## Quellen

- [Android: TV-App und Fernbedienungsbedienung](https://developer.android.com/training/tv/get-started/create)
- [Android: Media3 PlayerView](https://developer.android.com/media/media3/ui/playerview)
- [Android: Media3-Versionshinweise](https://developer.android.com/jetpack/androidx/releases/media3)

## TV-Modus (siehe `../docs/TV-MODUS-SPEZIFIKATION.md`)
- Start direkt im Live-Player auf Kanal 1 (Einstellungen › «Beim Start» wechselt zu «zuletzt gesehen»). Zurück im Fernsehbild öffnet das Menü, nochmals Zurück das Fernsehbild; Home-Taste verlässt die App.
- Feste Kanalnummern (`tvg-chno`, Xtream `num`, sonst fortlaufend) in `NumberStore`, Logik in `ChannelNumbers` und `ChannelNavigator`.
- Live-Bild: Hoch/Runter oder P+/P− Kanal, Links/Rechts Gruppe, Ziffern wählen eine Nummer, OK kurz Banner, OK lang Zahlenfeld, Info/Menü öffnet Ton und Untertitel.
