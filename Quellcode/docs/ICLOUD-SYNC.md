# iCloud-Sync (Wiedergabestand, Weiterschauen, Live TV)

Stand: 07.11.2026. **Eingeschaltet** (`ICLOUD_SYNC` in `project.yml`, Team `D752V8XA4G`). Container `iCloud.ch.arjo.iptelevision` per Xcode (automatische Signierung) registriert und der App-ID zugewiesen; Mac-Entwicklungsprofil und Developer-ID-Profil enthalten den Container. Code mit Unit-Tests und Test-Doubles geprüft; **echter Abgleich zwischen Geräten ist noch nicht geprüft**.

Noch offen (siehe Abschnitt «Einschalten»): CarPlay-Berechtigung an der App-ID, iPhone/Apple TV registrieren, CloudKit-Schema nach Production, Geräteprüfung.

## Architektur

- **Framework:** SwiftData mit `ModelConfiguration(cloudKitDatabase: .private("iCloud.ch.arjo.iptelevision"))`. Intern ist das `NSPersistentCloudKitContainer`: Er übernimmt Hochladen, Abrufen, stille Push-Benachrichtigungen, Wiederholung mit Backoff, Offline-Warteschlange und das Verhalten beim Kontowechsel. Kein eigener CloudKit-Code für den Datentransport, keine zusätzliche Abhängigkeit. `CKSyncEngine` wäre möglich (ab iOS/tvOS 17, macOS 14), hätte aber eine zweite Persistenzschicht neben SwiftData bedeutet.
- **Datenbank:** nur die **private** Datenbank des angemeldeten iCloud-Kontos. Keine öffentliche Datenbank, keine Freigaben.
- **Container:** `iCloud.ch.arjo.iptelevision` für iPhone, iPad, Apple TV und Mac (eine Bundle-ID `ch.arjo.iptelevision`, Team `D752V8XA4G`).
- **Was synchronisiert wird** (Speicher «UserData»): Profile (Name, Art, Fingerabdruck der Quelle), Wiedergabestand, zuletzt gesehener Sender mit Timeshift-Stelle, Favoriten, Ordner, ausgeblendete/umbenannte Sender, Einstellungen.
- **Was nie synchronisiert wird:** Zugangsdaten und PIN (Keychain; auf iPhone/Apple TV optional iCloud-Schlüsselbund), Stream-Adressen, Senderlisten, EPG, Film-/Serienkataloge (lokal, neu ladbar), Mediendateien.

### Inhaltskennungen (`ContentIdentity`)

| Inhalt | Kennung | Warum |
|---|---|---|
| Xtream-Film/Episode/Sender | Stream-ID des Anbieters | stabil pro Server |
| Playlist-Film/Episode | Hash des «Fundorts»: bei `/movie/<Benutzer>/<Passwort>/<ID>.mkv` nur `movie/<ID>`, sonst Host + Pfad ohne Token-Parameter (`token`, `expires`, `password` …) | wechselnde Tokens und Passwörter ändern die Kennung nicht; keine Zugangsdaten in iCloud |
| Playlist-Sender | `m3u-<Hash des Fundorts>` | früher die ganze Adresse (mit Zugangsdaten) |
| Serie aus Playlist | Hash von `series:<Name>` | unverändert |
| Quelle (Profil) | `SourceFingerprint`: SHA-256 aus Server + Benutzername (Xtream) bzw. Playlist-Fundort ohne Passwort | dieselbe Quelle auf zwei Geräten ergibt ein Profil |

Gleichnamige Inhalte bleiben getrennt, weil die Kennung nie aus dem Titel entsteht. Nicht mehr vorhandene Inhalte werden nicht geraten: Ein Sender, den es in der Liste nicht mehr gibt, wird nicht fortgesetzt; Weiterschauen eines Playlist-Titels ohne Katalogeintrag meldet einen Fehler statt eine falsche Adresse zu spielen.

### Konfliktregel Wiedergabestand

1. Jedes Gerät schreibt **seinen eigenen Datensatz** pro Inhalt (`deviceID`, zufällige Installations-ID, keine Hardware-Kennung). Ein verspäteter Upload kann deshalb nie den Datensatz eines anderen Geräts überschreiben.
2. Gelesen wird pro Inhalt der Datensatz mit der neuesten **Ereigniszeit**; bei Gleichstand entscheidet die Gerätekennung (alle Geräte wählen denselben Gewinner).
3. Die Ereigniszeit ist eine **hybride Uhr**: nie früher als alle bereits bekannten Einträge (+1 ms). Eine vorgehende Uhr eines anderen Geräts kann eine spätere bewusste Aktion (Zurückspulen, «Gesehen», neu Anschauen) nicht verdrängen.
4. **Verlauf löschen** setzt eine Löschmarke am Profil. Ältere Einträge (auch die eines Geräts, das offline war) zählen danach nicht mehr; neue Wiedergabe zählt wieder.
5. Beschädigte oder unvollständige Datensätze (unbekannte Art, Schlüssel passt nicht) werden ignoriert.

Der zuletzt gesehene Sender liegt am Profil (ein Datensatz, letzter Schreiber gewinnt, ebenfalls mit hybrider Uhr und serieller Warteschlange).

### Speichern

- Lokal zuerst (SwiftData); CloudKit gleicht im Hintergrund ab und bündelt Schreibvorgänge.
- Während der Wiedergabe höchstens alle **30 s**; **sofort** bei Pause, Spulen, Schliessen, Episodenwechsel, Ende, Wechsel in den Hintergrund/Unterbrechung, Senderwechsel. Beim harten Beenden geht höchstens der Stand der letzten 30 s verloren.
- Live TV: Senderwechsel sofort. Timeshift/Catch-up: Startstelle sofort, danach wie oben; die Stelle wird als **echte Uhrzeit beim Anbieter** gespeichert (unabhängig vom EPG-Versatz).

### Fortsetzen auf einem anderen Gerät

- Film/Episode: «Weiterschauen» auf der Startseite und «Fortsetzen ab …» in den Details zeigen den neuesten Stand aller Geräte. Aktualisierung beim Start, beim Wechsel in den Vordergrund und sobald CloudKit Änderungen importiert.
- Live TV ohne Archiv: derselbe Sender **live**.
- Live TV mit Archiv (Xtream `tv_archive`, M3U `catchup`): an der gespeicherten Stelle, **nur wenn** sie noch mindestens 5 Minuten im Archivfenster liegt und mindestens 1 Minute hinter live; sonst live. Sender ohne Archiv bekommen nie eine Timeshift-Stelle.

### Konten und Fehler

- Status in Einstellungen › iCloud: aktuell, wird abgeglichen, nicht angemeldet, gesperrt, vorübergehend nicht verfügbar, keine Verbindung, iCloud-Speicher voll, ausgelastet (Rate Limit), Konto geändert. Die App funktioniert in jedem Zustand lokal weiter.
- Kontowechsel: Erwartet wird, dass `NSPersistentCloudKitContainer` den lokalen Spiegel beim Kontowechsel zurücksetzt, damit Daten zweier Konten nicht gemischt werden (**nicht selbst verifiziert**, im Unit-Test nicht nachstellbar, siehe Geräteprüfung Punkt 9). Die App meldet den Wechsel (`CKAccountChanged`) und liest danach alle Nutzerdaten neu.
- Schalter «Mit iCloud abgleichen» (pro Gerät, wirkt nach Neustart). Ausgeschaltet bleiben die Daten lokal.
- Doppelte Quellen (vor dem ersten Abgleich auf zwei Geräten angemeldet) werden über den Fingerabdruck zusammengeführt; es bleibt die kleinste Profil-ID, damit jedes Gerät unabhängig dasselbe Ergebnis erhält.

### Migration älterer Daten

Beim ersten Start mit dieser Version: Sender-Kennungen in Favoriten, Ordnern und «Zuletzt gesehen» werden umgestellt, Wiedergabestände von Playlist-Titeln bekommen die neue Kennung, gespeicherte Stream-Adressen werden gelöscht, Playlist-Kataloge werden einmal neu geladen. Die Migration läuft bei jedem Start erneut (idempotent), damit Daten älterer App-Versionen anderer Geräte ebenfalls umgestellt werden. **Alle Geräte sollten dieselbe Version nutzen**; ältere Versionen schreiben weiterhin alte Kennungen.

## Einschalten: Stand und restliche Schritte

Erledigt (07.11.2026):
- Container `iCloud.ch.arjo.iptelevision` angelegt und der App-ID `ch.arjo.iptelevision` zugewiesen (über `xcodebuild -allowProvisioningUpdates`).
- `project.yml`: Flag `ICLOUD_SYNC`, Entitlements je Plattform, `DEVELOPMENT_TEAM: D752V8XA4G`, Hardened Runtime für den Mac.
- `App/Info.plist`: `remote-notification` unter `UIBackgroundModes`.
- `ARJOTV-RELEASE/scripts/build.sh`: Mit `ARJO_DEVID` wird der Mac jetzt archiviert und als «developer-id» exportiert (Profil mit iCloud eingebettet, Hardened Runtime), danach wie bisher notarisiert. Unsignierte Builds (ad-hoc, Simulator) bauen ohne `ICLOUD_SYNC`, weil CloudKit ohne Berechtigung die App beenden würde.
- Geprüft: signierter Mac-Debug-Build und Developer-ID-Export (Signatur gültig, Hardened Runtime, Container im Profil). Nicht notarisiert.
- iPhone «Iphone Ari» registriert, iOS-Entwicklungsprofil mit iCloud erzeugt, Debug-Build installiert und gestartet (07.11.2026). Wegen fehlender CarPlay-Freigabe mit temporären Entitlements ohne CarPlay gebaut; das Projekt selbst ist unverändert.
- CarPlay Video war an der App-ID bereits aktiv; der frühere Signierfehler kam vom fehlenden registrierten Gerät. Vollständiger iOS-Build (CarPlay + iCloud) auf dem iPhone installiert.
- Abgleich vom iPhone bestätigt: CloudKit hat in Development `CD_ProfileRecord`, `CD_PreferenceRecord`, `CD_SettingsRecord`, `CD_WatchProgressRecord` angelegt. Schema am 07.11.2026 nach **Production** übernommen (diese vier Typen).
- **Offen:** `CD_FolderRecord` fehlt noch in Production. Sobald auf einem Debug-Gerät ein Ordner angelegt und hochgeladen ist, erneut «Deploy Schema Changes…». Bis dahin werden Ordner in Production-Builds (Developer-ID-Mac, TestFlight, App Store) nicht abgeglichen.

Noch zu tun (braucht dich oder Geräte):
1. **CarPlay:** Die iOS-Signierung scheitert mit «Entitlement com.apple.developer.carplay-video not found». Die freigegebene CarPlay-Berechtigung (Case-ID 23249073) muss im Portal unter Identifiers › `ch.arjo.iptelevision` › «Additional Capabilities» aktiviert werden. Das betraf schon den bisherigen Stand.
2. **Geräte registrieren:** Für Entwicklungsprofile braucht das Team mindestens ein registriertes iPhone/iPad und Apple TV (Gerät per USB/Netzwerk mit Xcode verbinden oder UDID im Portal eintragen). Danach `xcodebuild … -allowProvisioningUpdates` oder in Xcode starten.
3. **Schema:** Einen Debug-Build auf einem Gerät mit iCloud starten und etwas abspielen, damit das Schema in **Development** entsteht. Danach in der CloudKit Console (icloud.developer.apple.com) › Schema › «Deploy Schema Changes…» nach **Production** übernehmen, bevor TestFlight, App Store oder die Developer-ID-Mac-App ausgeliefert wird. Achtung: Der Developer-ID-Mac nutzt immer **Production**; vor dem Deploy schlägt dort jeder Abgleich fehl.
4. Neue Felder ab dann nur optional hinzufügen (Kommentare an den `@Model`-Klassen).
5. **Downgrade:** Die neuen Felder ändern den lokalen Speicher. Eine ältere installierte Version (≤ 2.1.0) öffnet ihn danach möglicherweise nicht mehr; nicht zurück auf eine alte Version wechseln.

## Prüfen auf echten Geräten (noch offen)

Mit demselben iCloud-Konto auf mindestens zwei Geräten (z. B. Apple TV + iPhone, iPad + Mac):

1. Film auf Gerät A bis 43:25, Player schliessen → Gerät B öffnen: «Weiterschauen» zeigt den Film, «Fortsetzen ab 43:25».
2. Serie S2E5 auf A, auf B öffnen → genau diese Episode; S2E4 behält seinen Stand.
3. Live-Sender auf A → auf B «Zuletzt gesehen» öffnet denselben Sender live.
4. Catch-up eines Senders mit Archiv auf A, bei Minute 20 pausieren → auf B an derselben Stelle; Stelle älter als das Archiv → live.
5. Flugmodus auf A, Film weiterschauen, Verbindung wieder an → Stand erscheint auf B.
6. Gleichzeitig auf A und B denselben Film → der zuletzt bewegte Stand gewinnt, keiner springt zurück.
7. Auf A «Gesehen» setzen, auf B (offline) weiter schauen, B online → «Gesehen» bleibt nur, wenn es die spätere Aktion war.
8. Einstellungen › iCloud › «Wiedergabeverlauf löschen» auf A → auf B nach dem Abgleich leer.
9. iCloud abmelden bzw. Konto wechseln → Status «Nicht bei iCloud angemeldet»/«Konto prüfen», keine Daten des alten Kontos sichtbar.
10. iCloud-Speicher voll (Testkonto) → Status «iCloud-Speicher ist voll», lokal geht nichts verloren.
11. Schalter «Mit iCloud abgleichen» aus, App neu starten, etwas ändern, Schalter an, neu starten → Änderung erscheint auf dem zweiten Gerät (prüft, dass der lokal geöffnete Speicher danach wieder abgleicht).
