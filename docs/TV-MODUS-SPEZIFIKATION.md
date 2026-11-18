# TV-Modus: gemeinsame Spezifikation (Apple, Android TV, Tizen)

Referenz ist die Apple-Fassung (`ChannelNumbering`, `ChannelNavigator` in `Quellcode/Packages/ARJOCore`). Jede Fassung baut die Logik in ihrer eigenen Sprache nach; die Testfälle unten müssen überall dasselbe ergeben. Keine gemeinsamen Dateien.

## Verhalten
- Start: direkt Live-Wiedergabe auf Kanal 1 (kleinste Nummer; ausgeblendete/gesperrte Gruppen zählen nicht). Einstellung «Beim Start»: «Kanal 1» (Standard) oder «Zuletzt gesehener Kanal».
- Kanalnummer: eine feste Nummer pro Kanal, in jeder Gruppe gleich. Quelle der Nummer: Nutzer → `tvg-chno`/`num` → fortlaufend ab 1. Stabil über Aktualisierungen.
- Hoch/runter (P+/P−): Kanal in der Gruppe, am Ende rundum. Links/rechts: Gruppe (eigene Reihenfolge, ausgeblendete/gesperrte übersprungen, rundum), startet den ersten Kanal der neuen Gruppe, Banner oben ca. 2 s «Name · n von m». Schnelles Mehrfachdrücken startet nur die zuletzt gewählte Gruppe (250 ms Entprellung).
- Ziffern: bis 4 Stellen, führende 0 zählt nicht, nach 2 s ohne Ziffer oder mit Enter/OK gilt die Eingabe, Esc/Zurück bricht ab. Unbekannte Nummer: «Kanal N nicht vorhanden», aktueller Kanal bleibt. Nummern springen global; liegt der Kanal in der laufenden Liste, bleibt sie, sonst gilt seine Gruppe.
- Kanal-Banner unten ca. 4 s: Nummer, Logo, Name (mit EPG: Jetzt/Danach, Fortschritt).
- Einmal Zurück im Fernsehbild: Menü (Filme, Serien, …) mit «Zurück zum Fernsehen»; nochmals Zurück: Fernsehen. Live-Stream endet beim Film und wird danach auf demselben Kanal wieder aufgenommen. App verlassen: Home-Taste.
- Ohne Zifferntasten: langes OK öffnet ein 3×4-Zahlenfeld.

## Nummernvergabe (Algorithmus)
Eingabe: Kandidaten in Playlist-Reihenfolge `(id, sourceNumber?)`, `existing: id→Nummer`, `pinned: id→Nummer`.
1. `pinned`, dann `existing`: Nummer behalten, falls ≥ 1 und frei.
2. Quellnummer (≥ 1): frei → nehmen; sonst «Duplikat», Kanal wartet.
3. Wartende und Kanäle ohne Nummer in Reihenfolge: nächste freie Nummer, Start 1 (wenn `existing` und `pinned` leer) sonst höchste vergebene + 1. Doppelte IDs bekommen nur eine Nummer.

## Testfälle (Eingabe → Ergebnis)
| # | Eingabe | Ergebnis |
|---|---|---|
| N1 | `[a,b,c]` | a1 b2 c3 |
| N2 | `[a, b(1), c(5), d]` | b1 c5 a2 d3 |
| N3 | `[a(7), b(7), c]` | a7 b1 c2, 1 Duplikat |
| N4 | `[n,c,a]`, existing a1 b2 c3 | a1 c3 n4, b weg |
| N5 | `[x(2), a]`, existing a2 | a2, x ≠ 2 |
| N6 | `[a,b]`, existing a1 b2, pinned b1 | b1, a ≠ 1, 2 verschiedene |
| N7 | `[a(0), a, b(-3)]` | a1 b2 |
| Z1 | Gruppen `[Schweiz,Sport,Kino]`, Kanäle `[3,1,2]` | sortiert 1,2,3, Start 1 |
| Z2 | hoch −1 / +1 von 1 | 3 / 1 / 2 (rundum) |
| Z3 | Gruppe +1 / −1 von Schweiz | Sport 2 von 3 / Kino 3 von 3 |
| Z4 | Gruppen ohne ausgeblendete `[Schweiz,Kino]`, +1 | Kino |
| Z5 | Ziffern `1` bei t0, `2` bei t0+1 s | Frist t0+3 s, Ergebnis 12 |
| Z6 | `0`, dann `1 2 3 4 5` | 1234 (führende 0 ignoriert, 5. Ziffer ignoriert) |
| Z7 | Abbruch nach `7` | keine Nummer, keine Frist |
| Z8 | zap +1, +1, dann «letzter» | zurück zum vorherigen Kanal, nochmals: wieder zum anderen |
| Z9 | «letzter» ohne Verlauf | nichts |
