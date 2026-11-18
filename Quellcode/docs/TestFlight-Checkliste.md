# ARJO TV: Checkliste für TestFlight und App Store

Stand: Oktober 2026. Die Punkte mit ☐ sind noch offen; sie lassen sich nicht aus dem Code erledigen.

## 1. Vor dem ersten Archiv

**Konto und Kennungen**
- ☐ Apple-Developer-Konto (Organisation oder Einzelperson) mit gültiger Mitgliedschaft.
- ☐ Bundle-ID festlegen (Vorschlag: `ch.arjo.iptelevision`) und im Projekt für iPhone/iPad/Apple TV setzen. Eine Bundle-ID für alle drei Plattformen (universeller Kauf).
- ☐ Team unter *Signing & Capabilities* wählen, automatisches Signing einschalten.

**Capabilities (Xcode › Signing & Capabilities)**
- ☐ *iCloud › CloudKit*, Container `iCloud.ch.arjo.iptelevision` anlegen und einschalten: Schritt für Schritt in `docs/ICLOUD-SYNC.md`. Ohne Flag `ICLOUD_SYNC` läuft die App rein lokal.
- ☐ *App Groups* `group.ch.arjo.iptelevision` (App und Top-Shelf-Erweiterung).
- ☐ iOS-Target: *Background Modes › Audio, AirPlay, and Picture in Picture* (Ton im Hintergrund und Bild-in-Bild) und *Remote notifications* (CloudKit-Sync).
- ☐ Dateien `App/ARJOTV.entitlements`, `App/Info.plist`, `App/PrivacyInfo.xcprivacy` ins Target aufnehmen (Info.plist-Pfad in den Build Settings eintragen).
- ☐ CloudKit-Schema im *CloudKit Dashboard* von «Development» nach «Production» übernehmen, **bevor** die App im Store erscheint.

**Top-Shelf-Erweiterung (nur tvOS)**
- ☐ Neues Target: *tvOS › TV Top Shelf Extension*. `App/TopShelf/ContentProvider.swift` verwenden, Pakete `ARJOCore` und `ARJOData` verknüpfen, dieselbe App Group einstellen.
- ☐ Top-Shelf-Bilder in den Asset Catalog (Brand Assets) legen, falls die Erweiterung ausfällt.

**Grafiken**
- App-Symbole iOS (1024 × 1024) und tvOS (mehrschichtig, Large/Small) sind in `App/Assets.xcassets` angelegt; Logo und Farben vor der Einreichung prüfen.
- ☐ Top Shelf Image (1920 × 720 bzw. Wide 2320 × 720).
- ☐ Launch-Bild für tvOS.
- ☐ Sprachen: `App/Localizable.xcstrings` im Target, *English* unter Localizations hinzugefügt. Screenshots und Beschreibung in Deutsch **und** Englisch einreichen.

**Prüfen**
- ☐ `swift test` in allen Packages (siehe README) und ein Lauf auf einem echten Apple TV, iPhone und iPad.
- ☐ Auf einem Gerät testen: Anmeldung, Live-TV-Wiedergabe, Umschalten, Reconnect (WLAN kurz trennen), MKV-Film (VLC-Fallback), Fortsetzen, Programmführer, Suche mit Diktat, Kindersicherung, Backup/Restore (iOS), iCloud-Sync zwischen zwei Geräten.
- ☐ Xcode-Datenschutzbericht erzeugen (*Product › Archive › Generate Privacy Report*) und mit `PrivacyInfo.xcprivacy` abgleichen; VLCKit liefert eventuell ein eigenes Manifest mit.
- ☐ Multiview mit vier HD-Sendern auf einem echten Apple TV und iPad prüfen (Hitze, Speicher, Bildruckeln); bei Bedarf `MultiviewModel.backgroundBitRate` senken.
- ☐ Instruments: Speicherverbrauch beim Import einer 50'000-Sender-Playlist und beim Scrollen durch Poster prüfen.

## 2. App Store Connect: Eintrag anlegen

- ☐ App anlegen (Name «ARJO TV», Primärsprache Deutsch (Schweiz)), SKU, Bundle-ID.
- ☐ **Datenschutzerklärung (URL, Pflicht)**: Die App sammelt keine Daten, es gibt keine Werbung, keine Tracker und keine Analyse. Zugangsdaten bleiben in der Keychain (optional iCloud-Schlüsselbund); Einstellungen, Favoriten und Wiedergabestand liegen lokal und optional in der privaten iCloud des Nutzers.
- ☐ *App-Datenschutz* («Privacy Nutrition Label»): «Daten werden nicht erfasst» wählen (nur zutreffend, solange keine Analyse/Werbung dazukommt).
- ☐ Support-URL und Marketing-URL.
- ☐ Altersfreigabe: Der Nutzer bestimmt die Inhalte selbst. Fragebogen ehrlich ausfüllen (uneingeschränkter Zugriff auf Medien aus dem Internet); realistisch **17+**.
- ☐ Kategorie: Unterhaltung (oder Foto & Video).
- ☐ Exportbestimmungen: `ITSAppUsesNonExemptEncryption = NO` ist in `Info.plist` gesetzt; Fragen in App Store Connect entsprechend beantworten.
- ☐ Screenshots: iPhone 6,9", iPad 13", Apple TV 1920 × 1080. **Keine** Bilder mit urheberrechtlich geschützten Sendern, Logos oder Filmen verwenden; Testinhalte mit freien Lizenzen (z. B. Blender-Filme) nehmen.
- ☐ Beschreibung und Schlagwörter: klar sagen, dass die App **keine Sender oder Inhalte mitliefert** und dass der Nutzer eigene, rechtmässig erhaltene Zugangsdaten verwendet. Keine Werbung mit «IPTV-Abo», «gratis Sender» o. Ä.

## 3. Hinweise für die App-Prüfung (App Review)

Das ist bei IPTV-Playern der heikelste Teil. Alles in das Feld *Hinweise für die Prüfung* schreiben:

- ☐ Die App ist ein reiner Player (wie VLC oder Infuse). Sie enthält und vermittelt keine Inhalte, bietet keine Anbieter-Suche und keine Voreinstellungen.
- ☐ **Zugang für die Prüfer:** Entweder eine M3U-Playlist-URL mit rechtmässigen Testinhalten (z. B. Big Buck Bunny/Sintel als HLS) oder ein Xtream-Testkonto auf einem eigenen Server angeben. Ohne funktionierenden Zugang wird die App abgelehnt (Richtlinie 2.1).
- ☐ Erklären, warum App Transport Security gelockert ist: Nutzer geben eigene Server ein, viele davon ohne TLS; die Adresse ist vorab unbekannt (Richtlinie 2.5.x / ATS-Begründung in App Store Connect).
- ☐ Erklären, wozu Hintergrund-Audio und Bild-in-Bild dienen (Wiedergabe weiterlaufen lassen).
- ☐ Richtlinie 5.2 (geistiges Eigentum): Die App ermöglicht keine Umgehung von Schutzmassnahmen, enthält keine Inhalte und verweist auf keine Quellen.
- ☐ Kindersicherung mit PIN ist vorhanden (hilfreich für die Altersfreigabe).

## 4. Rechtliches und Lizenzen

- ☐ **VLCKit (LGPL 2.1):** Lizenztext und Quellhinweis in der App aufnehmen (Einstellungen › Über zeigt den Hinweis; vollständigen Lizenztext zusätzlich in die Beschreibung oder auf die Support-Seite stellen). VLCKit wird dynamisch gelinkt, damit Nutzer die Bibliothek austauschen können. Prüfen, ob das Community-Binary (`tylerjonesio/vlckit-spm` 3.6.0) für den Store-Betrieb in Ordnung ist; alternativ VLCKit selbst aus dem offiziellen Quellcode bauen (`generate.sh` im Paket).
- ☐ Marken: Der Name «ARJO TV» auf bestehende Marken prüfen lassen.
- ☐ Impressum/Anbieterkennzeichnung gemäss Schweizer Recht auf der Support-Seite.

## 5. TestFlight

1. ☐ *Product › Archive* für iOS und tvOS (Release-Konfiguration). Bei jeder Einreichung die Build-Nummer erhöhen.
2. ☐ *Distribute App › App Store Connect › Upload*.
3. ☐ In App Store Connect › TestFlight: Export-Compliance beantworten, «Test-Informationen» ausfüllen (inkl. Testzugang aus Abschnitt 3).
4. ☐ **Interne Tests** (bis 100 Mitglieder des Teams): sofort verfügbar, keine Prüfung.
5. ☐ **Externe Tests**: Beta-App-Prüfung durch Apple (meist 1–2 Tage); öffentlichen Link oder E-Mail-Einladungen verwenden.
6. ☐ Feedback über TestFlight sammeln; Abstürze unter *Xcode › Organizer › Crashes* auswerten.
7. ☐ Wenn stabil: Build für die Store-Einreichung auswählen, Altersfreigabe/Datenschutz prüfen und «Zur Prüfung einreichen».

## 6. Nach dem Start

- ☐ CloudKit-Production-Schema nicht mehr ohne Migration ändern (neue Felder nur optional/mit Standardwert hinzufügen).
- ☐ Bekannte Lücken (siehe README) priorisieren: weitere Sprachen, Verhalten von Catch-up bei einzelnen Anbietern, M3U-Erkennung für Filme und Serien verfeinern.
