# Build-Bericht · 29. Oktober 2026 · Version 0.2.2

## Ergebnis

Aktuelle Installationsdatei: `Installation/ARJOTV-GoogleTV-0.2.2.apk` (ca. 4.9 MiB).

- App-ID `ch.arjo.tv.android`; Version 0.2.2, Build 4; Android TV ab Android 8/API 26, Ziel API 35, gebaut mit SDK 36.
- Separater Android-Quellcode. Apple-Quellcode und bestehende Mac-Downloads unverändert.
- Originaldesign anhand der SwiftUI-Ansichten übernommen: siehe `DESIGN.md` für Quellen, Anpassungen und Grenzen.
- Release-Build ohne Debugging, lokal mit dem Android-Debug-Zertifikat für private Installation signiert; kein öffentlicher Store-Release und keine Schlüsseldatei im Projekt.

## Erfolgreich geprüft

`./scripts/build.sh` abgeschlossen:

- `:app:testDebugUnitTest`: **43 Tests**, 0 Fehler, 0 übersprungen.
- `:app:lintDebug`: **0 Fehler**, 22 Hinweise. Hinweise betreffen unter anderem neuere Bibliotheksversionen, feste TV-Ausrichtung, deutsche Texte im Code sowie API-Opt-in in Testcode; keine Fehler ausgeblendet und keine Lint-Baseline eingerichtet.
- `:app:assembleRelease`: erfolgreich.
- Ausgelieferte APK mit `apksigner verify --verbose` geprüft: gültige v2-Signatur.
- SHA-256-Datei erzeugt und mit `shasum -a 256 -c` geprüft: übereinstimmend.
- Paketversion/TV-Launcher und Mindestversion aus der APK geprüft.

Testumfang: URL-Kodierung, Quellenkennungen, ungültige Adressen, M3U-Metadaten und Bildadressen, Xtream-Anmeldung und IDs, Episodensortierung, bereinigte Fehlermeldungen, Artwork-Download und Speicher-Cache, Originalstruktur der sechs Navigationsziele, Kartenfokus/Fokuswechsel, Favoritenaktionen, globale Suche, Filme/Detailaktionen, Staffelauswahl und Anmeldung.

Sieben Android-Ansichten unter Robolectric mit nativer Grafik gerendert und visuell geprüft: Anmeldung, Startseite, Live TV, Kategorien, Filme, Filmdetails und Seriendetails. Künstliche Testdaten, keine echten Anbieterzugänge. Die PNGs liegen unter `Vorschau/`.

## Änderung und M3U-Prüfung in 0.2.1

- Nur das obere Menüband geometrisch zentriert; restlicher Designaufbau beibehalten. Test bei 960 und 1280 Pixel Bildschirmbreite bestanden, neu gerenderte Vorschau visuell geprüft.
- Bereitgestellte Dropbox-Quelle als Voreinstellung im Release-Build eingebunden. Automatische einmalige Übernahme, danach bleiben spätere Nutzerentscheidungen erhalten; fünf Tests prüfen diese Auswahlregeln.
- Dropbox-Abruf: HTTP 200 und gültiger M3U-Kopf. Vollständiger Import mit dem produktiven Java-Parser direkt aus dem Netzwerk, ohne lokale Speicherung oder Ausgabe der Streamadressen: **132’654 Einträge, 57 Gruppen**; erkannt als 1’817 Live-Einträge, 15’018 Filme und 115’819 Episoden. Erkennung nach bestehenden M3U-Regeln, keine redaktionelle Einzelprüfung.
- SHA-256-Erzeugung für Eintragskennungen ohne Formatter pro Byte umgesetzt; Ergebnisformat unverändert. Abruf und Parsing auf dem Mac in der Stichprobe rund zwei Sekunden. Dies ist kein Geschwindigkeitsnachweis für den Fernseher.
- Link aus lokaler, Git-ignorierter Konfiguration; im Release-Paket enthalten, nicht im versionierten Quellcode. Debug-Tests kontaktieren die private Quelle nicht.

## Fernbedienung in 0.2.2

- Live-Senderwechsel per Hoch/Runter, P+/P− und von Android gemeldeter Radbewegung. Sendergruppe und Katalogreihenfolge bleiben erhalten, Enden werden umgebrochen.
- Links/Rechts sowie Vor-/Rückspultasten für Filme/Episoden: 10 Sekunden; beim Halten ab der fünften Wiederholung 30 Sekunden, mit Drosselung und Begrenzung auf Streamanfang/-ende. Nicht spulbare Streams werden abgefangen.
- OK öffnet das Player-Menü; Richtungsnavigation darin wird nicht durch Direktkürzel blockiert. Zurück schliesst zuerst das Menü. Android-Lautstärke-/Home-/Zurück-Ereignisse werden nicht als Wiedergabekürzel konsumiert.
- Senderliste verbleibt im Arbeitsspeicher, statt Tausende URLs im Activity-Aufruf zu übergeben. Nach einem Prozessverlust wird die Gruppe bei Bedarf aus der gespeicherten Quelle neu geladen; aktuelle Senderkennung wird im Activity-Zustand erhalten. Nach Rückkehr zur Hauptansicht wird der zuletzt umgeschaltete Sender im verschlüsselten Verlauf aktualisiert.
- Zwölf Eingabe-Tests decken Tastendruck/Loslassen, Halten/Drosselung, Menümodus, Dreh-/Scrollsignale, Richtungen und Seek-Grenzen ab. Vier Queue-Tests decken Filter/Reihenfolge, Umbruch, Wiederherstellung und Session-Kennungen ab.
- Vier Tests der tatsächlichen PlayerActivity mit einem aufzeichnenden Player prüfen neuen Stream beim Zappen, Seek ohne Streamwechsel, Anfang/Ende/nicht spulbare Streams sowie gespeicherte Senderidentität. Diese Tests starten keine externen Streams oder Hardwaredecoder.
- Abschliessender Build, 43 Tests und Android Lint erfolgreich; 0 Lint-Fehler, 22 Hinweise. Signatur und SHA-256 der ausgelieferten APK erneut bestätigt.

## Gerätetest noch offen

In der vorherigen Vorbereitung wurde ein verbundenes Gerät lesend als TCL mit Android 14 erkannt. Diese Version wurde nicht auf den Fernseher übertragen oder dort gestartet.

Noch zu prüfen: tatsächliche Richtungs-/P+/P−-Signale und etwaige Drehrad-Signale der TCL-Fernbedienung, Direktspulen und Menübedienung mit echten Streams, Wiederherstellung nach Prozessverlust, echte Fernbedienungsnavigation über alle Reihen, reale Anmeldung, Android-Keystore inklusive verschlüsseltem Verlauf, Start mit echten Logos/Postern, Bild/Ton für HLS/TS/MKV, Audio-/Untertitelwahl, Weiterschauen nach App-Neustart und Netzwerkunterbruch. Android-View-Rendering und Robolectric ersetzen diese Gerätetests nicht.

EPG, Catch-up, Multiview, Kindersicherung, iCloud-Sync und weitere in `README.md` genannte Funktionen sind weiterhin nicht umgesetzt.
