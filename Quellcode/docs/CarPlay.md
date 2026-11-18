# CarPlay und AirPlay für TV+

## Was eingebaut ist
- **CarPlay-Oberfläche** (`CarPlayCoordinator.swift`, `App/CarPlaySceneDelegate.swift`): Tabs Favoriten, Zuletzt, Kategorien und «Läuft» (`CPNowPlayingTemplate`), nur mit Apple-Templates. Auswahl startet den Sender über die vorhandene Player-Pipeline (`LiveTVViewModel.play(_:in:presenting: false)`), ohne das Fenster auf dem iPhone zu öffnen.
- **Video-Hinweis an CarPlay** (iOS 26.4 und neuer): Jede Senderzeile trägt eine `CPPlaybackConfiguration` mit Präsentation `.video`, wenn `CPSessionConfiguration.supportsVideoPlayback` wahr ist, sonst `.audio`. Live-Sender melden die Dauer 0 (unbekannt).
- **Zustände** (`CarPlayVideoState`): nicht verbunden, verbunden ohne Video, verbunden mit Videounterstützung. Ob das Fahrzeug Video im Moment zeigen darf, entscheidet das System (Wiedergaberichtlinie, z. B. Fahrzeug in Bewegung). Dafür gibt es keine App-API, die App schaltet das nicht um und umgeht nichts.
- **Läuft gerade** (`NowPlayingPublisher.swift`): Sendername, aktuelle Sendung, Live-Kennzeichnung; Vor/Zurück wechselt den Sender, Play/Pause bedient den AVPlayer.
- **AirPlay**: `AVRoutePickerView` in der Kopfleiste des iPhone-Players. Die Zielwahl trifft immer der Nutzer.
- **Hintergrund**: `UIBackgroundModes` = `audio`.

## Fahrerablenkung (Richtlinien)
- Nur Apples Templates, keine eigenen Bedienelemente, nichts am iPhone nötig: Der Sender startet über CarPlay, das iPhone-Fenster bleibt unberührt.
- Listen höchstens 12 Zeilen und nie mehr als das System erlaubt (`CPListTemplate.maximumItemCount`). Meldet das Fahrzeug eingeschränkte Listen (`limitedUserInterfaces`), baut die App die Listen neu auf.
- Texte werden auf 36 Zeichen gekürzt, ein Untertitel pro Zeile. Logos in der vom System vorgegebenen Bildgrösse.
- Kein Video bei Fahrt: Das entscheidet das System. Die App blendet nichts ein, was es sperrt.
- Alle Menüs liegen in Tabs auf einer Ebene (Favoriten, Zuletzt, Kategorien, Läuft), Kategorien öffnen höchstens eine zweite Ebene.

## Grenzen
- Video über CarPlay oder AirPlay gelingt nur für Sender, die der **AVPlayer** abspielt (HLS, MP4). Sender, die nur VLCKit (TS, MKV) abspielt, gehen nicht ins Fahrzeug-Video; dort bleibt Ton auf dem iPhone.
- Nicht im Code erzwingbar: Anzeige auf dem Fahrzeugdisplay. Das System präsentiert Video nur bei freigegebener Sitzung.

## Apple-Freigaben (noch offen, nicht eingetragen)
`App/ARJOTV-CarPlay.entitlements` enthält `com.apple.developer.carplay-audio` und `com.apple.developer.carplay-video`. Die Datei ist **nicht** im Build. Sie erst in `CODE_SIGN_ENTITLEMENTS` eintragen, wenn Apple die Berechtigungen für `ch.arjo.iptelevision` freigegeben hat und das Provisioning Profile sie enthält, sonst schlägt die Signierung fehl. Ohne Freigabe verbindet sich CarPlay nie mit der App.
Antrag: developer.apple.com → CarPlay-Berechtigung anfordern (Kategorie Audio bzw. Video). Ob Apple ein Video-Entitlement für diese App freigibt, ist offen.

## Mercedes-Benz GLC (MBUX)
Das Fahrzeug braucht CarPlay mit Videounterstützung. Welche Modelljahre und MBUX-Softwarestände das haben, ist hier nicht belegt: Modelljahr und Softwarestand des Fahrzeugs und die Angabe des Herstellers prüfen. Ohne Videounterstützung läuft die App stabil im Audiomodus.

## Test im Fahrzeug
1. App mit freigegebenen Entitlements signieren und auf dem iPhone installieren.
2. Fahrzeug mit CarPlay verbinden (Kabel oder drahtlos), App-Symbol «TV+» im CarPlay-Menü öffnen.
3. Sender aus «Favoriten» wählen: Ton muss starten, bei Videounterstützung erscheint das Bild, solange das System es erlaubt.
4. Sender wechseln (Kategorien oder Vor/Zurück). Netz kurz trennen: Wiedergabe baut sich wieder auf.
5. CarPlay trennen: Wiedergabe läuft auf dem iPhone weiter. AirPlay-Taste im iPhone-Player: Ziel wählen.

## Simulator
Der CarPlay-Simulator (Xcode → I/O → External Displays → CarPlay) startet nur mit freigegebenen Entitlements. Hier nicht durchgeführt.
