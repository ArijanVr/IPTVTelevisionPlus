# IPTelevision+ 1.0.0 (Build 1): Redesign-Bericht

Branch `redesign/iptelevision-1.0` (Git-Worktree `Quellcode/IPTelevision-plus`). Der alte Stand `Quellcode/ARJO-TV-plus` ist unverändert. Nichts committet, nichts veröffentlicht.

## Identität
- Name «IPTelevision+»: `PRODUCT_NAME`, `CFBundleDisplayName`, `CFBundleName`, Android-Label, Localizable, Info.plist, About-Text, README, Anleitungen.
- ID `ch.arjo.iptelevision` (iOS, macOS, tvOS, Android `applicationId`). Alle Apple-Kennungen mit der alten ID folgen: iCloud-Container `iCloud.ch.arjo.iptelevision`, App Group `group.ch.arjo.iptelevision`, Keychain-Services, UserDefaults-Schlüssel, Logger, URL-Name.
- Version 1.0.0, Build 1 (`MARKETING_VERSION`, `CURRENT_PROJECT_VERSION`, `versionName`, `versionCode`).
- Changelog: «Erstveröffentlichung IPTelevision+ 1.0 mit neuem Design.»
- Annahme: Der Java-Paketname `ch.arjo.tv.android` bleibt (Namespace und R-Klasse). Nur `applicationId` ist neu. Ein Umbenennen ist nicht nötig, ändert aber viele Dateien.
- Annahme: tvOS bleibt als Ziel im Projekt, weil der Code geteilt ist. Es ist gleich benannt und gleich gestaltet.
- Das Skriptziel `ARJOTV` (Modulname, Executable iOS/tvOS) bleibt, das ist kein sichtbarer Name.

## Design
- Tokens: `Theme.swift` (Apple) und `TvStyle.java` (Google TV). Himmel #CFE1F4 / Tief #245483, Flieder #DED6F2 / Tief #5B4B8E, Off-White, Black, Graphite, Light Grey, Signal #FF4A1C nur als Punkt und Fokusring.
- Geist Regular, Medium, Mono. Skala nach Guide S. 7, mit Dynamic Type auf iOS und macOS. Tracking pro Stufe ist nicht umgesetzt (SwiftUI-Font trägt kein Tracking). Annahme: der Unterschied ist gering.
- Radien 14 / 24 / 32 / 44, Pillen. Motion 160 / 240 / 360 / 480 ms, Kurven 0.2 0 0 1 und 0.34 1.3 0.64 1. «Bewegung reduzieren»: Überblenden 160 ms.
- Fokus: Ring Signal 2 pt, Abstand 2 pt, Skala 1.04 (Apple). Android: Ring 3 px bei 1080p (Annahme, bessere Lesbarkeit), Skala 1.04.
- Google TV: Overscan-Rand 5 % in der Hauptansicht, D-Pad unverändert.
- Icon A: iOS hell, dunkel, getönt (1024, ohne Maske). macOS 16 bis 1024 (Superellipse auf 824/1024 mit Schatten, 16 und 32 px vereinfacht). tvOS-Stapel aus Himmel/Flieder-Verlauf und Icon. Android Adaptive Icon (Vektor, Hintergrund Verlauf, Vordergrund Symbol in der 66-dp-Zone) und Banner 640×360 (2× 320×180).
- Wortmarke und Lockup: Image-Sets `IPTelevisionLockup`, `IPTelevisionWortmarke`, `IPTelevisionWortmarkeKlein` (ohne Zusatz, unter 24 px; noch nicht in einer Ansicht eingesetzt). Android: `tv_lockup.png`, `tv_banner.png`.

## Geprüft
- iOS, macOS, tvOS: `xcodebuild` mit `CODE_SIGNING_ALLOWED=NO`, je BUILD SUCCEEDED. Einzige Warnung je Ziel: «Metadata extraction skipped, no AppIntents.framework» (kam schon vorher).
- Swift-Tests ARJONetwork, ARJOData, ARJOPlayer, ARJOUI: 0 Fehler.
- Android: `testDebugUnitTest` 79 Tests, 0 Fehler; `lintDebug` und `assembleRelease` erfolgreich.
- iPhone-Simulator (ad-hoc signiert), Test-Playlist mit erfundenen Sendern auf `localhost`: Anmelden, Jetzt, Live, Filme, Serien, Mehr, Player-Fehlerzustand, hell und dunkel. Screenshots unter `Screenshots/iOS`.
- Google TV: gerenderte Ansichten (Robolectric) unter `Screenshots/GoogleTV`. Die Android-Oberfläche ist nur dunkel (wie vorher).

## Unsicher
- Unsicher: Markenprüfung. «IP Television» (Azero), «IPTV+» und «IPTV Plus» existieren. Keine Registerrecherche (siehe Guide S. 23).
- Unsicher: Daten der alten App werden nicht übernommen. Neue ID heisst neuer Keychain-Bereich, neues Datenverzeichnis, neuer iCloud-Container, neuer Android-Datenspeicher. Playlists, Zugangsdaten, Favoriten, PIN und Verlauf müssen neu eingegeben werden. Es gibt keine Migration. Das Backup der alten App lässt sich in der neuen App importieren (Annahme, nicht getestet; das Dateiformat blieb gleich).
- Unsicher: macOS-Screenshots fehlen. Das Mac-Fenster liess sich in dieser Umgebung nicht zuverlässig aufnehmen. Die Mac-Ansichten teilen den SwiftUI-Code mit iOS. Ein Lauf mit Entwickler-Profil steht aus.
- Unsicher: tvOS und Google TV am echten Gerät (Fokus, Overscan, Banner) ungetestet. Keine Apple-TV-Screenshots.
- Unsicher: Ein macOS-Build mit Signatur braucht das Provisioning-Profil für `ch.arjo.iptelevision` mit iCloud. Ohne Profil startet die App nicht (CloudKit-Container).
- Unsicher: Die Datei `Quellcode/App/Resources/ArjoIntro.mp4` (alte TV+-Animation) ist im Code nicht referenziert und wurde nicht angefasst. Sie liegt aber im App-Paket. Entscheid: entfernen?
- Unsicher: Nicht überarbeitet: Tizen-Projekt, `Download-*`-Ordner (fertige alte Binärdateien), Skriptnamen wie `ARJOTV-GoogleTV-2.1.0.apk` in `AndroidTV/scripts/build.sh`, `update.sh`-Pfade. Sie benennen den alten Stand.
- Unsicher: Das alte Android-Launcher-Bild `arjo_icon.png` wurde im Branch entfernt (ersetzt durch das Adaptive Icon). Es bleibt im Git-Verlauf und im alten Ordner.
- Unsicher: Die Namen «Top Shelf» (tvOS) sind ohne Bild. Wie vorher.
- Rest der Guide-Punkte: Guide S. 22 nennt die Bundle-ID als unverändert. Der Auftrag hat das überstimmt (neue ID).

## Store-Einträge, die du anlegen musst
Apple (App Store Connect / Developer Portal):
1. Neue App-ID `ch.arjo.iptelevision` mit iCloud (CloudKit), App Groups, Push (für stille CloudKit-Pushes) und, falls gewünscht, CarPlay (Berechtigung neu beantragen).
2. iCloud-Container `iCloud.ch.arjo.iptelevision`, App Group `group.ch.arjo.iptelevision`.
3. Provisioning-Profile für iOS, tvOS und macOS (Development, Distribution, Developer ID).
4. App-Eintrag «IPTelevision+» (iOS, tvOS, macOS), Version 1.0.0, Neu in dieser Version: «Erstveröffentlichung IPTelevision+ 1.0 mit neuem Design.» Untertitel, Stichworte, Beschreibung mit klarem Hinweis: nur Player, keine Sender oder Inhalte. Datenschutz-URL, Support-URL, Altersfreigabe, Datenschutz-Angaben (keine Tracker).
5. Screenshots je Plattform (diese Datei liefert Vorlagen, keine fertigen Store-Grössen).
6. Für macOS ausserhalb des Stores: Developer-ID-Zertifikat und Notar-Profil (`arjo-notary`) bleiben gleich. Neue DMG mit dem Namen «IPTelevision+».
Google Play:
7. Neue App «IPTelevision+» mit Paketname `ch.arjo.iptelevision`, Kategorie Video-Player, TV-Formfaktor, TV-Banner, Store-Texte, Datenschutz-Angaben, Inhaltsbewertung.
8. Eigener Upload-Schlüssel (Release ist heute mit dem Debug-Zertifikat signiert) und Play-App-Signing.
