"""Erzeugt App/Localizable.xcstrings aus allen Texten im Code (Deutsch) und der Übersetzungstabelle EN unten.

Aufruf im Ordner ARJOTV/:  python3 Tools/generate_localizations.py App/Localizable.xcstrings
Neue deutsche Texte im Code erscheinen als «ohne Übersetzung»; dann hier in EN ergänzen und neu erzeugen.
"""
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from extract_keys import extract

EN = {
'Kanalnummern':'Channel numbers','Kanalnummer':'Channel number','Nummer':'Number','Speichern':'Save',
'Ist eine Nummer vergeben, tauschen beide Sender ihre Nummern.':'If a number is taken, both channels swap numbers.',
'Neu nummerieren nach Gruppen':'Renumber by groups','Alle Sender werden ab 1 neu nummeriert, Gruppe für Gruppe in deiner Reihenfolge.':'All channels are renumbered from 1, group by group in your order.',
'Alle Sender neu nummerieren?':'Renumber all channels?','Neu nummerieren':'Renumber','Eigene Nummern gehen verloren.':'Your own numbers will be lost.','Neu nummeriert.':'Renumbered.',
'Beim Start':'At launch','Kanal 1':'Channel 1','Zuletzt gesehener Kanal':'Last watched channel',
'Zurück zum Fernsehen':'Back to TV','Kanalnummer eingeben':'Enter channel number','Abbrechen':'Cancel','Bestätigen':'Confirm',
'Kanal %lld nicht vorhanden':'Channel %lld not available','Kanal %lld':'Channel %lld','Kanalnummer %@':'Channel number %@',
'%lld von %lld':'%lld of %lld','Gruppe %@, %lld von %lld':'Group %@, %lld of %lld','Jetzt: %@':'Now: %@','Danach: %@':'Next: %@',
'Auge: Sender ein- oder ausblenden. Stern: Favorit. Zum Ordnen eine Zeile ziehen – oder in den Reihen eine Kachel auf eine andere ziehen.':'Eye: show or hide a channel. Star: favourite. Drag a row to reorder – or drag one tile onto another in the rows.',
'Einstellungen, Quelle %@':'Settings, source %@','%@ live ansehen':'Watch %@ live',
'Alle Sender dieser Kategorie einblenden':'Show all channels in this category','Alles an einem Ort':'Everything in one place',
'Auge: Reihe ein- oder ausblenden. Reihenfolge über das Menü «…».':'Eye: show or hide a row. Reorder with the «…» menu.',
'Auge: Reihe ein- oder ausblenden. Zum Ordnen eine Zeile ziehen.':'Eye: show or hide a row. Drag a row to reorder.',
'Auge: ein- oder ausblenden. Reihenfolge über das Menü «…».':'Eye: show or hide. Reorder with the «…» menu.',
'Auge: ein- oder ausblenden. Zum Ordnen eine Zeile ziehen.':'Eye: show or hide. Drag a row to reorder.',
'Auge: Sender ein- oder ausblenden. Stern: Favorit. Ausgeblendete Sender fehlen überall in der App.':'Eye: show or hide a channel. Star: favourite. Hidden channels disappear everywhere in the app.',
'Bereich':'Section','Bild in Bild':'Picture in Picture','Bis zu vier Bilder. Nur eines hat Ton – wähle es mit einem Klick.':'Up to four pictures. Only one has sound – pick it with a click.',
'Eigene Ordner':'My folders','Fertig':'Done','Gross':'Large','Kachelgrösse':'Tile size','Kompakt':'Compact','Liste':'List','Listen bearbeiten':'Edit lists',
'Mehrere Sender gleichzeitig':'Several channels at once','Meine Listen':'My lists','Meine Listen und Startseite':'My lists and home screen',
'Noch keine Kategorien geladen.':'No categories loaded yet.','Normal':'Regular','Ohne Namen erscheint der Name nur, wenn eine Kachel ausgewählt ist.':'Without names, the name only appears when a tile is selected.',
'Reihen der Startseite':'Home screen rows','Sender suchen':'Search channels','Sender umbenennen':'Rename channel','Senderkacheln':'Channel tiles',
'Sendernamen unter den Kacheln':'Channel names below tiles','Standard-Aufbau wiederherstellen':'Restore default layout','Startseite anpassen':'Customise home screen',
'Titelbild':'Featured','Umbenennen …':'Rename …','Sender hinzufügen':'Add channel','Sender ersetzen':'Replace channel','Sender wählen':'Choose channel',
'Keine Sender in dieser Auswahl.':'No channels in this selection.','Kein Sender gefunden.':'No channel found.','Ton hier':'Sound here',
'Noch keine Favoriten. Markiere Sender mit dem Stern.':'No favourites yet. Mark channels with the star.','Keine Sender in dieser Kategorie.':'No channels in this category.',
'Nach oben':'Move up','Nach unten':'Move down','Reihenfolge des Anbieters wiederherstellen':"Restore provider's order",
'%lld von %lld Sendern':'%lld of %lld channels','%lld von %lld sichtbar':'%lld of %lld visible',
'Bühne':'Stage',
'Raster':'Grid','Fokus':'Focus','Reihe':'Row','Anordnung':'Layout',
'Sendungen':'Programmes',
'Alles':'All','Zuletzt gesucht':'Recent searches','Löschen':'Clear',
'Kategorien':'Categories',
'Erscheinungsbild':'Appearance','System':'System','Hell':'Light','Dunkel':'Dark',
'Jetzt im TV':'On TV now','Keine Sendungsdaten':'No programme data','Nächstes Titelbild':'Next featured item','Aus Favoriten entfernen':'Remove from favourites','Zu Favoriten':'Add to favourites',
'Die Startseite konnte nicht geladen werden.':'The home screen could not be loaded.',
'Hier erscheinen zuletzt gesehene Sender, Favoriten und angefangene Filme.':'Recently watched channels, favourites and films you started will appear here.',
'Neue Filme':'New films','Neue Serien':'New series','Fortsetzen':'Resume','Live ansehen':'Watch live','Favorit':'Favourite',
'10 Sekunden vor':'Forward 10 seconds','10 Sekunden zurück':'Back 10 seconds','3 Stunden vor':'Forward 3 hours','3 Stunden zurück':'Back 3 hours',
'4 bis 6 Ziffern.':'4 to 6 digits.',
'IPTelevision+ ist nur ein Player und liefert keine Sender oder Inhalte mit. Du verwendest deine eigenen Zugangsdaten. Für Formate, die Apple nicht abspielt, nutzt die App VLCKit (LGPL 2.1, © VideoLAN).':'IPTelevision+ is only a player and does not include any channels or content. You use your own credentials. For formats Apple cannot play, the app uses VLCKit (LGPL 2.1, © VideoLAN).',
'Abbrechen':'Cancel','Abmelden':'Sign out','Abmelden ist fehlgeschlagen.':'Signing out failed.','Abspielen':'Play','Adresse deiner M3U-Playlist':'Address of your M3U playlist',
'Aktionen':'Actions','Aktive Quelle entfernen':'Remove active source','Aktualisieren fehlgeschlagen':'Update failed','Akzentfarbe':'Accent colour',
'Als Nächstes':'Up next','Als gesehen markieren':'Mark as watched','Als nicht gesehen markieren':'Mark as unwatched','Anderen Sender wählen …':'Choose another channel …',
'Anmelden':'Sign in','Anmeldung fehlgeschlagen.':'Sign-in failed.','Ansicht':'View','Audiospur':'Audio track',
'Auf Apple TV werden Favoriten, Ordner, Einstellungen und Wiedergabestand über iCloud mit deinen anderen Geräten abgeglichen. Ein Backup als Datei erstellst du auf iPhone oder iPad.':'On Apple TV, favourites, folders, settings and watch progress are synced with your other devices through iCloud. You can create a backup file on iPhone or iPad.',
'Aufnahme ansehen':'Watch recording','Aufnahme verfügbar':'Recording available','Aus':'Off','Aus Favoriten entfernen':'Remove from favourites','Aus Ordner entfernen':'Remove from folder',
'Ausblenden':'Hide','Ausgeblendet':'Hidden','Backup':'Backup','Backup exportieren …':'Export backup …','Backup wiederherstellen …':'Restore backup …','Benutzername':'Username',
'Benutzername oder Passwort sind falsch.':'Username or password is incorrect.','Blau':'Blue','Cache leeren':'Clear cache','Darstellung':'Appearance',
'Das Backup enthält Einstellungen, Favoriten, Ordner und Wiedergabestand, aber keine Zugangsdaten und keine PIN. Speichere die Datei z. B. in iCloud Drive.':'The backup contains settings, favourites, folders and watch progress, but no credentials and no PIN. Save the file in iCloud Drive, for example.',
'Das Backup konnte nicht erstellt werden.':'The backup could not be created.','Das Backup konnte nicht gelesen werden.':'The backup could not be read.','Das Backup konnte nicht gespeichert werden.':'The backup could not be saved.',
'Das Backup stammt von einer neueren Version der App.':'The backup comes from a newer version of the app.','Das Profil konnte nicht gespeichert werden.':'The profile could not be saved.',
'Daten':'Data','Dein Anbieter liefert hier keine Inhalte.':'Your provider does not deliver any content here.',
'Der Ordner konnte nicht gelöscht werden.':'The folder could not be deleted.','Der Ordner konnte nicht gespeichert werden.':'The folder could not be saved.',
'Der Programmführer konnte nicht geladen werden.':'The programme guide could not be loaded.','Der Programmführer konnte nicht gelesen werden.':'The programme guide could not be read.',
'Der Sender ist nicht erreichbar.':'The channel cannot be reached.','Der Server antwortet nicht (Zeitüberschreitung).':'The server is not responding (timeout).',
'Der Server hat keine gültige Xtream-Antwort geliefert. Prüfe die Adresse.':'The server did not return a valid Xtream response. Check the address.',
'Der Server ist nicht erreichbar.':'The server cannot be reached.','Der Server wurde nicht gefunden. Prüfe die Adresse.':'The server was not found. Check the address.',
'Der Zeitversatz verschiebt alle Sendezeiten, falls dein Anbieter in einer anderen Zeitzone sendet.':'The offset shifts all broadcast times in case your provider broadcasts in a different time zone.',
'Die Adresse der Aufnahme konnte nicht gebildet werden.':'The address of the recording could not be built.','Die Datei ist kein gültiges IPTelevision+-Backup.':'The file is not a valid IPTelevision+ backup.',
'Die Datei ist keine gültige M3U-Playlist.':'The file is not a valid M3U playlist.','Die Datei konnte nicht gelesen werden.':'The file could not be read.',
'Die Einstellungen konnten nicht gelesen werden. Es gelten die Standardwerte.':'The settings could not be read. Defaults apply.','Die Einstellungen konnten nicht gespeichert werden.':'The settings could not be saved.',
'Die Inhalte dieser Gruppe konnten nicht geladen werden.':'The content of this group could not be loaded.','Die Inhalte konnten nicht geladen werden.':'The content could not be loaded.',
'Die Kindersicherung ist durch eine PIN geschützt.':'Parental controls are protected by a PIN.','Die PIN konnte nicht entfernt werden.':'The PIN could not be removed.',
'Die PIN konnte nicht geprüft werden.':'The PIN could not be checked.','Die PIN konnte nicht gespeichert werden.':'The PIN could not be saved.','Die PIN muss 4 bis 6 Ziffern haben.':'The PIN must have 4 to 6 digits.',
'Die PINs stimmen nicht überein.':'The PINs do not match.','Die Playlist ist nicht erreichbar.':'The playlist cannot be reached.','Die Playlist nennt keine EPG-Quelle.':'The playlist does not name an EPG source.',
'Die Playlist-Adresse ist ungültig.':'The playlist address is invalid.','Die Reihenfolge konnte nicht gespeichert werden.':'The order could not be saved.',
'Die Sender dieser Gruppe konnten nicht geladen werden.':'The channels of this group could not be loaded.','Die Sender konnten nicht geladen werden.':'The channels could not be loaded.',
'Die Senderliste konnte nicht geladen werden.':'The channel list could not be loaded.','Die Server-Adresse ist ungültig.':'The server address is invalid.',
'Die Stream-Adresse konnte nicht ermittelt werden.':'The stream address could not be determined.','Die Zugangsdaten konnten nicht sicher gespeichert werden.':'The credentials could not be stored securely.',
'Die Zugangsdaten wurden nicht gefunden. Bitte neu anmelden.':'The credentials were not found. Please sign in again.','Die gespeicherten Profile konnten nicht gelesen werden.':'The saved profiles could not be read.',
'Die lokalen Daten konnten nicht gelöscht werden.':'The local data could not be deleted.','Die Änderung konnte nicht gespeichert werden.':'The change could not be saved.',
'Diese Quelle enthält keine Filme und Serien.':'This source does not contain movies and series.','Dieser Sender bietet keine Aufnahmen zum Zurückspulen an.':'This channel does not offer recordings to rewind to.',
'Dieser Sender läuft schon im Multiview.':'This channel is already playing in Multiview.','EPG-Zeitversatz':'EPG time offset','Einblenden':'Show','Einige Ergebnisse konnten nicht geladen werden.':'Some results could not be loaded.',
'Einpassen':'Fit','Einstellungen':'Settings','Entfernen':'Remove','Entsperren':'Unlock','Erneut versuchen':'Try again','Falsche PIN.':'Wrong PIN.','Favoriten':'Favourites',
'Favoriten & Ordner':'Favourites & folders','Favoriten und Ordner konnten nicht gelesen werden.':'Favourites and folders could not be read.','Fehler':'Error','Filme':'Movies',
'Filme werden geladen …':'Loading movies …','Füllen':'Fill','Für diese Serie sind keine Episoden vorhanden.':'There are no episodes for this series.','Gesehen':'Watched','Gesperrt':'Locked',
'Monochrom':'Monochrome','Gross (8 s)':'Large (8 s)','Gruppe':'Group','Gruppe ausblenden':'Hide group','Gruppe umbenennen …':'Rename group …','Gruppen':'Groups','Grün':'Green',
'Hier erscheinen Filme und Serien, die du angefangen hast.':"Movies and series you have started will appear here.",'Hinweis':'Notice','Im Multiview ansehen':'Watch in Multiview',
'Jetzt':'Now','Jetzt abspielen':'Play now','Jetzt ansehen':'Watch now','Kein Versatz':'No offset','Keine Gruppen geladen.':'No groups loaded.','Keine Internetverbindung.':'No internet connection.',
'Keine passende Quelle gefunden.':'No matching source found.','Kindersicherung':'Parental controls','Kindersicherung ist aktiv.':'Parental controls are on.','Klein (1,5 s)':'Small (1.5 s)',
'Leer lassen, um den Originalnamen wiederherzustellen.':'Leave empty to restore the original name.','Leer. Halte einen Sender gedrückt und wähle «Zu Ordner hinzufügen».':'Empty. Press and hold a channel and choose “Add to folder”.',
'Letzten Sender beim Start fortsetzen':'Resume last channel at launch','Liste aktualisieren':'Update list','Listen automatisch aktualisieren':'Update lists automatically','Live':'Live','Live TV':'Live TV',
'Lokale Daten löschen?':'Delete local data?','Läuft jetzt':'On now','Löschen fehlgeschlagen':'Deletion failed','Löschen und neu laden':'Delete and reload','M3U-Datei wählen …':'Choose M3U file …',
'Mit Xtream-Zugangsdaten anmelden':'Sign in with Xtream credentials','Mit einer PIN kannst du ausgewählte Kategorien für Kinder sperren.':'With a PIN you can lock selected categories for children.',
'Mit einer PIN lassen sich Kategorien sperren.':'A PIN lets you lock categories.','Multiview':'Multiview','Multiview wird auf diesem System nicht unterstützt.':'Multiview is not supported on this system.',
'Nach oben':'Move up','Nach oben schieben':'Move up','Nach unten':'Move down','Nach unten schieben':'Move down','Name':'Name','Name (optional)':'Name (optional)','Neue PIN':'New PIN',
'Neuer Ordner':'New folder','Ordner anlegen …':'Create folder …','Nichts ausgeblendet.':'Nothing hidden.',
'Noch keine Favoriten. Halte einen Sender gedrückt (Apple TV: lange auf die Mitte des Touch-Pads drücken) und wähle «Zu Favoriten».':'No favourites yet. Press and hold a channel (Apple TV: press and hold the centre of the touch surface) and choose “Add to favourites”.',
'Normal (4 s)':'Normal (4 s)','Nächste Episode automatisch abspielen':'Play next episode automatically','OK':'OK','Orange':'Orange','Ordner':'Folders','Ordner löschen':'Delete folder','Ordner umbenennen …':'Rename folder …',
'PIN':'PIN','PIN eingeben':'Enter PIN','PIN entfernen':'Remove PIN','PIN festlegen':'Set PIN','PIN wiederholen':'Repeat PIN','PIN ändern':'Change PIN','Passwort':'Password',
'Playlist-Adresse (http://…)':'Playlist address (http://…)','Programmführer':'Programme guide','Programmführer aktualisieren':'Update programme guide','Programmführer nicht verfügbar':'Programme guide unavailable',
'Puffer':'Buffer','Quelle':'Source','Quelle entfernen?':'Remove source?','Quelle hinzufügen':'Add source','Quellen':'Sources','Reihenfolge des Anbieters wiederherstellen':"Restore the provider's order",
'Rot':'Red','Schliessen':'Close','Sehr gross (15 s)':'Very large (15 s)','Seitenverhältnis':'Aspect ratio','Sender':'Channels','Sender hinzufügen':'Add channel','Sender wählen':'Choose channel',
'Sender öffnen':'Open channel','Sender öffnen, die Sendung läuft später':'Open channel, the programme is on later','Sender, Filme, Serien, Sendungen':'Channels, movies, series, programmes','Senderliste':'Channel list',
'Senderliste aktualisieren':'Update channel list','Senderliste wird geladen …':'Loading channel list …',
'Senderlisten, Filme, Serien, Programmführer und Bilder werden gelöscht und neu geladen. Zugangsdaten, Favoriten und Wiedergabestand bleiben erhalten.':'Channel lists, movies, series, programme guide and images will be deleted and reloaded. Credentials, favourites and watch progress are kept.',
'Serien':'Series','Serien werden geladen …':'Loading series …','Server (z. B. http://beispiel.ch:8080)':'Server (e.g. http://example.com:8080)','Sichern':'Save','Sprache':'Language','Staffel':'Season',
'Startseite':'Home','Suche':'Search',
'Suche nach Sendern, Filmen, Serien und Sendungen. Tippe oder diktiere über die Mikrofon-Taste der Tastatur bzw. der Siri Remote.':'Search for channels, movies, series and programmes. Type, or dictate with the microphone key on the keyboard or the Siri Remote.',
'Tippe auf eine Quelle, um zu ihr zu wechseln.':'Tap a source to switch to it.','Ton hier':'Sound here','Umbenennen':'Rename','Sender umbenennen …':'Rename channel …','Untertitel':'Subtitles','Version':'Version',
'Violett':'Purple','Von Anfang':'From start','Von Anfang ansehen':'Watch from the start','Weiterschauen':'Continue watching','Wiedergabe':'Playback','Wiedergabe wird auf diesem System nicht unterstützt.':'Playback is not supported on this system.',
'Zeitzone':'Time zone','Zu Favoriten':'Add to favourites','Zu Ordner hinzufügen':'Add to folder','Zu viele Versuche. Bitte warte kurz.':'Too many attempts. Please wait a moment.',
'Zugangsdaten, Listen und Wiedergabestand dieser Quelle werden von diesem Gerät gelöscht.':'Credentials, lists and watch progress of this source will be deleted from this device.',
'Zuletzt gesehen':'Recently watched','«Weiterschauen» im Top Shelf':'“Continue watching” in Top Shelf','«Weiterschauen» konnte nicht geladen werden.':'“Continue watching” could not be loaded.','Über IPTelevision+':'About IPTelevision+','Ein Produkt von':'A product by','Ein Produkt von ARJO LAB':'A product by ARJO LAB','Nichts gefunden. Versuch ein anderes Wort.':'Nothing found. Try another word.','Glut':'Ember',
# interpolierte Schlüssel
'Aufnahme: %@':'Recording: %@','Besetzung: %@':'Cast: %@','Danach: %@':'Next: %@','Das Konto ist nicht aktiv (Status: %@).':'The account is not active (status: %@).',
'Der Server hat mit Fehler %lld geantwortet.':'The server responded with error %lld.','Details nicht verfügbar: %@':'Details unavailable: %@',
'Die Wiedergabe ist fehlgeschlagen. Das Format (%@) wird möglicherweise noch nicht unterstützt.':'Playback failed. The format (%@) may not be supported.',
'Es sind höchstens %lld Bilder gleichzeitig möglich.':'At most %lld pictures are possible at the same time.','Fortsetzen ab %@':'Resume from %@','Gerät (%@)':'Device (%@)','Jetzt: %@':'Now: %@',
'Keine Treffer für «%@».':'No results for “%@”.','Reihenfolge: %@':'Order: %@','Staffel %lld':'Season %lld','Verbindung wird neu aufgebaut (Versuch %lld)':'Reconnecting (attempt %lld)',
'Wiederhergestellt für: %@.':'Restored for: %@.',' Nicht übernommen (Quelle fehlt auf diesem Gerät): %@.':' Not applied (source missing on this device): %@.',
'%@, Ton an':'%@, sound on','%@, stumm':'%@, muted','%@%lld Std.':'%@%lld h','%@%lld Std. %lld Min.':'%@%lld h %lld min','«%@» entfernen':'Remove “%@”',
# iCloud-Sync (docs/ICLOUD-SYNC.md)
'Abgleich fehlgeschlagen':'Sync failed','Aktuell':'Up to date','Ausgeschaltet':'Off',
'Bis iCloud wieder verfügbar ist, wird alles auf diesem Gerät gespeichert und danach abgeglichen.':'Until iCloud is available again, everything is saved on this device and synced afterwards.',
'Das iCloud-Konto wurde geändert oder ist abgemeldet. Daten verschiedener Konten werden nicht vermischt.':'The iCloud account has changed or is signed out. Data from different accounts is never mixed.',
'Der Abgleich wird später automatisch wiederholt.':'Syncing will be retried automatically later.',
'Der iCloud-Status ist unbekannt.':'The iCloud status is unknown.',
'Die Änderung wirkt nach dem nächsten Start der App.':'The change takes effect the next time the app starts.',
'Durch Einschränkungen gesperrt':'Blocked by restrictions',
'Ein Backup als Datei erstellst du auf iPhone, iPad oder Mac.':'Create a backup file on iPhone, iPad or Mac.',
'Fortschritt, «Weiterschauen» und der zuletzt gesehene Sender dieser Quelle werden auf allen Geräten mit derselben iCloud entfernt.':'Progress, «Continue Watching» and the last channel of this source are removed on all devices using the same iCloud.',
'Gib iCloud-Speicher frei, damit neue Änderungen abgeglichen werden. Auf diesem Gerät bleibt alles gespeichert.':'Free up iCloud storage so new changes can sync. Everything stays saved on this device.',
'In dieser Version nicht verfügbar':'Not available in this version','Keine Verbindung zu iCloud':'No connection to iCloud',
'Melde dich in den Systemeinstellungen bei iCloud an, um auf deinen Geräten weiterzuschauen. Bis dahin bleibt alles auf diesem Gerät.':'Sign in to iCloud in Settings to continue watching across your devices. Until then, everything stays on this device.',
'Mit iCloud abgleichen':'Sync with iCloud','Nicht bei iCloud angemeldet':'Not signed in to iCloud','Status':'Status',
'Verlauf löschen':'Clear history',
'Wiedergabestand, Favoriten und Einstellungen bleiben auf diesem Gerät.':'Playback progress, favourites and settings stay on this device.',
'Wiedergabestand, «Weiterschauen», zuletzt gesehener Sender, Favoriten, Ordner und Einstellungen liegen in deiner privaten iCloud. Zugangsdaten und PIN werden darüber nicht übertragen.':'Playback progress, «Continue Watching», the last channel, favourites, folders and settings are kept in your private iCloud. Login details and PIN are never transferred this way.',
'Wiedergabeverlauf löschen':'Clear watch history','Wiedergabeverlauf löschen?':'Clear watch history?',
'Wird abgeglichen …':'Syncing …','Wird geprüft …':'Checking …','Zeitversetzt':'Time-shifted','Zuletzt abgeglichen':'Last synced',
'iCloud ist ausgelastet':'iCloud is busy','iCloud vorübergehend nicht verfügbar':'iCloud temporarily unavailable',
'iCloud-Konto prüfen':'Check iCloud account','iCloud-Speicher ist voll':'iCloud storage is full',
'Änderungen werden gespeichert und abgeglichen, sobald wieder eine Verbindung besteht.':'Changes are saved and synced as soon as a connection is available again.',
# Bisher ohne Übersetzung
'AirPlay':'AirPlay','Läuft':'Playing','Mediathek':'Library','Nichts hier. Starte einen Sender auf dem iPhone.':'Nothing here. Start a channel on your iPhone.',
'Noch nichts gemerkt.':'Nothing saved yet.','Profil und Einstellungen':'Profile and settings','Zuletzt':'Recent',
}

# Schlüssel, die nicht übersetzt werden müssen (Eigennamen, Zahlen, Trenner)
SAME = {'ARJO TV','ARJO LAB','IPTelevision+','OK','PIN','Name','Orange','Signal','Server','Version','Live','Live TV','Multiview','iCloud','Normal (4 s)','%@ · %@ – %@','%@ · %@ – %@'}

def fix_key(k):
    # Swift-Interpolationen -> Formatplatzhalter
    manual = {
        '\\(group.position) von \\(group.count)':'%lld von %lld',
        'Kanalnummer \\(model.numberEntry)':'Kanalnummer %@','Kanalnummer \\(text)':'Kanalnummer %@',
        'Gruppe \\(name), \\(group.position) von \\(group.count)':'Gruppe %@, %lld von %lld',
        'Kanal \\(number)':'Kanal %lld','Kanal \\(number) nicht vorhanden':'Kanal %lld nicht vorhanden',
        'Aufnahme: \\(recording.title)':'Aufnahme: %@','Besetzung: \\(cast)':'Besetzung: %@','Danach: \\(next.title)':'Danach: %@',
        'Das Konto ist nicht aktiv (Status: \\(status)).':'Das Konto ist nicht aktiv (Status: %@).',
        'Der Server hat mit Fehler \\(code) geantwortet.':'Der Server hat mit Fehler %lld geantwortet.',
        'Details nicht verfügbar: \\(message)':'Details nicht verfügbar: %@',
        'Die Wiedergabe ist fehlgeschlagen. Das Format (\\(target.containerExtension)) wird möglicherweise noch nicht unterstützt.':'Die Wiedergabe ist fehlgeschlagen. Das Format (%@) wird möglicherweise noch nicht unterstützt.',
        'Es sind höchstens \\(Self.maxSlots) Bilder gleichzeitig möglich.':'Es sind höchstens %lld Bilder gleichzeitig möglich.',
        'Fortsetzen ab \\(Formatting.clock($0))':'Fortsetzen ab %@','Gerät (\\(TimeZone.current.identifier))':'Gerät (%@)','Jetzt: \\(now.title)':'Jetzt: %@',
        'Keine Treffer für «\\(model.trimmedQuery)».':'Keine Treffer für «%@».','Reihenfolge: \\(area.title)':'Reihenfolge: %@','Staffel \\(season.number)':'Staffel %lld',
        'Verbindung wird neu aufgebaut (Versuch \\(attempt))':'Verbindung wird neu aufgebaut (Versuch %lld)',
        '\\(organization.name(for: slot.channel)), Ton an':'%@, Ton an','\\(organization.name(for: slot.channel)), stumm':'%@, stumm',
        '\\(sign)\\(absolute / 60) Std.':'%@%lld Std.','\\(sign)\\(absolute / 60) Std. \\(absolute % 60) Min.':'%@%lld Std. %lld Min.',
        '«\\(profile.name)» entfernen':'«%@» entfernen',
        'Einstellungen, Quelle \\(profile.name)':'Einstellungen, Quelle %@',
        '\\(organization.name(for: channel)) live ansehen':'%@ live ansehen',
        '\\(model.slots.count) von \\(MultiviewModel.maxSlots) Sendern':'%lld von %lld Sendern',
        '\\(ordered.count - hiddenCount) von \\(ordered.count) sichtbar':'%lld von %lld sichtbar',
        '\\(shown.count - hidden) von \\(shown.count) sichtbar':'%lld von %lld sichtbar',
    }
    if k in manual: return manual[k]
    if k.startswith('Wiederhergestellt für: \\('): return 'Wiederhergestellt für: %@.'
    if k.startswith(' Nicht übernommen (Quelle fehlt auf diesem Gerät): \\('): return ' Nicht übernommen (Quelle fehlt auf diesem Gerät): %@.'
    return k

keys = extract()
catalog = {}
skipped_interp = []
for raw in keys:
    if raw == '' or re.fullmatch(r'[a-z0-9._\-]+', raw) or raw.startswith('%') or raw == '–': continue
    key = fix_key(raw)
    if '\\(' in key:
        skipped_interp.append(key)   # reine Platzhalter-Texte wie "\(episode.episodeNumber)" brauchen keinen Eintrag
        continue
    catalog[key] = EN.get(key)

missing = sorted(k for k,v in catalog.items() if v is None and k not in SAME and not re.fullmatch(r'[%@ ·–lld]+', k))
print('Schlüssel:', len(catalog), '| ohne Übersetzung:', missing, '| ignoriert:', skipped_interp)

strings = {}
for key in sorted(catalog):
    value = catalog[key]
    entry = {'extractionState': 'manual', 'localizations': {'de': {'stringUnit': {'state': 'translated', 'value': key}}}}
    if value is not None:
        entry['localizations']['en'] = {'stringUnit': {'state': 'translated', 'value': value}}
    strings[key] = entry
doc = {'sourceLanguage': 'de', 'strings': strings, 'version': '1.0'}
out = sys.argv[1]
open(out, 'w').write(json.dumps(doc, ensure_ascii=False, indent=2, sort_keys=True) + '\n')
