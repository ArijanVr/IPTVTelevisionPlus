# Originaldesign → Google TV

Version 0.2.1 übernimmt die visuelle Struktur aus den vorhandenen SwiftUI-Ansichten. Der Abgleich basiert auf dem Quellcode der Mac-App; ein Pixelvergleich mit einer laufenden Mac-Instanz wurde nicht durchgeführt.

| Original in `../Quellcode/Packages/ARJOUI/Sources/ARJOUI/` | Umsetzung auf Android |
| --- | --- |
| `Theme.swift` | Konzept «IP Television+»: Black `#090A0A`, Off-White `#FDFDFC`, Graphite `#2A2C2C`, Raised `#1A1B1D`, Text2 `#D9DAD8`, Control-Rand `#6B6E6D`; einziger Akzent Glut `#FC5F39` nur für Fortschritt, Live-/Status-Punkt, Fehler-Icon, «+» der Wortmarke und Fokusring |
| `LoginView.swift` | Originalmarke, zentrierte Anmeldung, segmentierte Quellenwahl, gerundete Felder und orange Anmeldetaste |
| `ProfileSession.swift` / `MainTabView` | Startseite, Live TV, Filme, Serien, Suche und Einstellungen; am Fernseher als erreichbare Navigation oben |
| `HomeView.swift` | Grosses Titelbild mit Verlauf, Titel und Wiedergabeaktion, Weiterschauen, zuletzt gesehener Sender, Favoriten, neue Filme/Serien |
| `LiveTVView.swift` / `ChannelTile.swift` | Horizontale Senderreihen nach Kategorie, Logos, abgerundete Karten; Sender-/Kategorienauswahl und Favoritenfilter |
| `VODBrowseView.swift` / `PosterCard.swift` | Horizontale Reihen mit Filmplakaten im 2:3-Format, Titel und Anbietermetadaten darunter |
| `MovieDetailView.swift` / `SeriesDetailView.swift` | Poster links, Titel/Beschreibung/Besetzung rechts, Wiedergabeaktion, Staffelauswahl und Episoden |

Das obere Menüband ist in Version 0.2.1 relativ zur gesamten Bildschirmbreite zentriert. Das links angeordnete Logo verschiebt die Mitte nicht. Der Layouttest prüft die tatsächlichen Grenzen des Menübands bei 960 und 1280 Pixel Breite.

## TV-Anpassungen

Grössere Schrift und Bedienelemente, sichtbarer Fokusrahmen, kurze Fokus-Anhebung bei aktivierten Systemanimationen, Richtungstasten für Reihen/Navigation, OK zum Öffnen und langes OK für Favoriten. Die Navigation bleibt bei grösserer Systemschrift horizontal erreichbar; Kartenreihen und Titelbild erhalten zusätzlichen vertikalen Platz. Android-Systemschrift statt nicht vorhandener Geist-Schriften oder Apple-Schriftdateien. Es wird der dunkle ARJO-Stil verwendet.

Die abgerundeten, teilweise transparenten Kontrollflächen nähern die Originaloptik an. Apples Liquid Glass/SwiftUI und die macOS-Fensterbedienung werden auf Android nicht ausgeführt. Sichtbare Daten stammen aus der eigenen Quelle; es gibt keine mitgelieferten Programme oder erfundenen Programmdaten. Ohne verfügbare Logos/Poster erscheinen neutrale Platzhalter.

Gemessene Kontraste: ARJO White auf Black 19.48:1; sekundärer Text `#B7BAB7` auf Graphite 7.17:1; Black auf der orangen Haupttaste 5.90:1. Der dunkle Tastentext verbessert die Lesbarkeit auf dem Fernseher.

## Vorschau und Prüfung

Die sieben PNG-Dateien unter `Vorschau/` zeigen tatsächlich gerenderte Android-Ansichten bei 960 × 540 mit künstlichen Testdaten und neutralen Bildplatzhaltern. Sie sind keine Fotografien/Screenshots des TCL und keine blossen Designentwürfe. Der reale Katalog ersetzt Namen, Bilder und Metadaten nach der Anmeldung.

Robolectric prüft die Navigationsziele, Kartenfokus, Fokuswechsel nach rechts, Fokus beim Wechsel der Senderansicht, Favoritenaktion, Suche, Filmwiedergabeaktion und Staffel-/Episodenansicht. Der TV-Eingabemodus wird im Test explizit gesetzt, da Robolectric standardmässig Touch-Eingabe annimmt. Die vollständige Fernbedienungsbedienung und Bild-/Tonwiedergabe müssen auf dem TCL geprüft werden.

Die noch fehlenden Funktionen der Apple-Version (u. a. EPG, Catch-up und Multiview) sind unter `README.md` aufgeführt; dafür werden keine funktionslosen Schaltflächen angezeigt.
