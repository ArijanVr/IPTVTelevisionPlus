# IPTelevision+ auf Deinem TCL installieren

Datei: `Installation/IPTelevision-GoogleTV-0.3.0.apk` · Version 0.3.0 · Android TV/Google TV ab Android 8.

Die Mac-App und ihre Downloads bleiben erhalten. Diese APK ist eine separat signierte Privat-/Testversion. Sie ist noch nicht auf Deinem Fernseher mit echten Streams getestet. Sie enthält keine Sender oder Anbieterzugänge.

## Mit USB-Stick

1. Kopiere die APK auf einen USB-Stick und stecke ihn am Fernseher ein.
2. Öffne die Datei mit einem Android-TV-Dateimanager. Die normale Foto-/Medienansicht zeigt APK-Dateien möglicherweise nicht an.
3. Falls Google TV nachfragt, erlaube diesem Dateimanager unter «Unbekannte Apps installieren» die Installation. Die Menünamen unterscheiden sich je nach TCL-Version.
4. Wähle «Installieren», danach «Öffnen». ARJO TV hat einen eigenen Eintrag im TV-App-Menü.
5. Deaktiviere die Installationsfreigabe für den Dateimanager danach wieder, wenn Du sie nicht mehr brauchst.

## Direkt vom Mac

Ist der Fernseher für die Android-Geräteverbindung freigegeben und im selben Netzwerk, kann die APK vom Mac installiert werden. Eine Installation oder Übertragung durch den Assistenten erfolgt erst nach Deiner ausdrücklichen Freigabe gemäss `../AGENTS.md`.

Für die manuelle Installation mit bereits verbundenem Fernseher (die Geräteadresse erhältst Du aus `adb devices`):

```bash
adb -s DEINE_GERAETEADRESSE install -r Installation/IPTelevision-GoogleTV-0.3.0.apk
```

Du brauchst keinen Play-Store-Upload und kein kostenpflichtiges Entwicklerkonto. Bei einer Signatur-Kollision die vorhandene App nicht vorschnell entfernen: Eine Deinstallation löscht deren lokal gespeicherte Daten. Erst klären, welche Version installiert ist.

## Direkt starten

Die aktuelle APK enthält Deine bereitgestellte Dropbox-M3U als Voreinstellung. Nach der Installation lädt sie diese Quelle direkt, ohne dass Du die URL eintippen musst. Bei einem Update wird diese neue Voreinstellung einmalig übernommen. Später bewusst gewählte Quellen werden beim nächsten Start beibehalten. Für den Download ist Internet nötig; die Playlist ist nicht als Kopie in der APK enthalten.

Der Import der bereitgestellten Playlist wurde mit dem produktiven M3U-Parser auf dem Mac geprüft: 132’654 Einträge in 57 Gruppen. Einzelne Streams und die Ladezeit auf dem Fernseher sind dadurch noch nicht geprüft.

## Eigene Quelle einrichten (optional)

- **Xtream:** Serveradresse einschliesslich `https://` bzw. `http://` und Port eingeben, dann Deinen Benutzernamen und Dein Passwort. Es wird der Xtream-Endpunkt `/player_api.php` verwendet.
- **M3U:** Die vollständige Playlist-URL eingeben. Zugangsdaten innerhalb einer URL werden zusammen mit der Quelle verschlüsselt gespeichert.
- «Verbinden» prüft die Quelle und lädt Inhalte. Zum Tippen erscheint die TV-Tastatur. Bitte Zugangsdaten direkt am Fernseher eingeben, nicht im Chat senden.

## Bedienung

- Richtungstasten: zwischen Rubriken, Suche, Gruppen und Einträgen wechseln.
- OK auf einer Gruppe: filtern und zur Eintragsliste wechseln.
- OK auf einem Sender: starten. OK auf einem Film: Detailseite mit «Abspielen»/«Fortsetzen». OK auf einer Serie: Detailseite mit Staffeln/Episoden.
- OK auf einem Eintrag gedrückt halten: Favorit hinzufügen/entfernen.
- Im Live-Player: Hoch/P+ nächster Sender, Runter/P− vorheriger Sender innerhalb der aktuellen Gruppe; am Rand geht es wieder zum anderen Ende.
- Bei Filmen/Serienepisoden: Links 10 Sekunden zurück, Rechts 10 Sekunden vor. Länger halten: 30-Sekunden-Schritte. Der Stream muss Spulen erlauben.
- Ein von Android erkanntes Drehrad/Scrollrad schaltet Live-Sender bzw. spult Filme/Episoden. Der Navigationsring mit vier Richtungstasten funktioniert über dieselben Tastenkürzel.
- Im Player OK: Bedienelemente für Pause, Ton und Untertitel. Solange dieses Menü offen ist, dienen die Pfeiltasten der Menübedienung. Zurück schliesst zuerst das Menü, danach den Player.
- Zurück im Player: zur Liste. Zurück in einer Serie: zur Übersicht.
- «Einstellungen»: neu laden, Zugang wechseln oder nach Bestätigung Zugang und Verlauf vom Fernseher entfernen.
- «Startseite»: grosses Titelbild, Weiterschauen, zuletzt gesehener Sender, Favoriten und neue Filme/Serien.
- «Suche»: Sender, Filme und Serien durchsuchen.

## Erster Gerätetest

1. Prüfe, ob ARJO TV im App-Menü erscheint und alle Schaltflächen per Fernbedienung erreichbar sind.
2. Verbinde Deine Quelle und starte einen Live-Sender. Bild und Ton prüfen.
3. Prüfe bei Bedarf einen HLS-Stream sowie TS/MKV und die gewünschten Audiospuren. Unterstützung hängt vom Fernseher und Stream ab.
4. Öffne einen Film, spule etwas vor, gehe zurück und öffne ihn wieder: Wiedergabestand prüfen.
5. Prüfe eine Serie, Kategorien, Suche und Favoriten, anschliessend einen Neustart der App.
6. Live TV: Hoch/Runter und P+/P− testen; die Auswahl bleibt in der Sendergruppe. Nach dem Zurückkehren zur Startseite «Zuletzt gesehen» prüfen.
7. Film und Serienepisode: Links/Rechts, längeres Halten, Anfang/Ende und – falls vorhanden – echtes Drehen am Rad testen. Danach mit OK Ton-/Untertitelmenü öffnen und die Pfeilnavigation prüfen.
8. Trenne kurz das Netzwerk. Prüfe die Fehlermeldung und «Erneut versuchen».

Bei schwarzem Bild oder fehlendem Ton einen anderen Stream prüfen. Diese erste Android-Version besitzt keinen VLC-Ersatzdecoder. EPG, Multiview und weitere noch fehlende Funktionen sind in `README.md` aufgeführt.
