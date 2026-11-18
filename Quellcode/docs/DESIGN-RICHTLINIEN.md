# Design-Richtlinien TV+

Verbindlich für jede UI-Änderung an TV+ (Mac, iPhone, iPad, Apple TV). Grundlage sind die Apple Human Interface Guidelines und der ARJO-Brandguide (Farben in `Packages/ARJOUI/Sources/ARJOUI/Theme.swift`). Bei Widerspruch: Bedienbarkeit und Barrierefreiheit vor Markenwirkung.

## Quellen (Apple HIG)

- Design-Prinzipien: https://developer.apple.com/design/human-interface-guidelines/design-principles
- Layout: https://developer.apple.com/design/human-interface-guidelines/layout
- Farbe: https://developer.apple.com/design/human-interface-guidelines/color
- Materialien: https://developer.apple.com/design/human-interface-guidelines/materials

Vor grösseren Änderungen die betroffene Seite neu lesen; Apple passt die Texte laufend an.

## Kernregeln für TV+

### Prinzipien

- Inhalt zuerst: Senderlogos, Bilder und Sendungen tragen die Oberfläche. Bedienelemente treten zurück.
- Hierarchie über Grösse, Gewicht und Abstand, nicht über zusätzliche Farbe oder Rahmen.
- Konsistent mit dem System: Systemkomponenten (Seitenleiste, Tab-Leiste, Picker, Blätter) bevorzugen und nur gezielt einfärben.
- Rückmeldung bei jeder Interaktion (Zeiger, Fokus, Drücken), aber ruhig und kurz.

### Layout

- Ränder und Abstände aus einem festen Raster; Elemente an gemeinsamen Kanten ausrichten.
- Sichere Bereiche (Safe Area, Title-safe auf Apple TV) einhalten. Inhalte dürfen unter Seitenleiste und Leisten laufen (`backgroundExtensionEffect`), Bedienelemente nicht.
- Anpassungsfähig bleiben: Fenstergrössen auf dem Mac, Size Classes auf iPad, Dynamic Type.
- Mindest-Trefferflächen: 44 × 44 pt (iPhone, iPad), 28 × 28 pt (Mac).

### Farbe

- Glut (`Theme.glut`, `#FC5F39`) sparsam: Fokus, Fortschritt, Live-Punkt, Titelpunkt. Gesamtanteil am Bildschirm höchstens 5 %.
- Farbe nie als einziges Unterscheidungsmerkmal (zusätzlich Symbol, Text oder Form).
- Kontrast: Text mindestens 4.5 : 1, grosser Text 3 : 1. Für Text in Glut im hellen Modus `Theme.glutText` verwenden.
- Jede Farbe für hellen und dunklen Modus und für «Kontrast erhöhen» prüfen.

### Materialien

- Liquid Glass / Materialien nur für schwebende Bedienebenen (Leisten, Seitenleiste, Taste über Inhalt), nicht für Inhaltsflächen.
- Keine Materialien stapeln (Glas auf Glas). Text auf Material mit ausreichender Lebendigkeit/Kontrast.
- «Transparenz reduzieren» respektieren: Systemmaterialien erledigen das selbst, eigene Unschärfe-Effekte nicht.

## TV+ tvOS-Brandguide V1 (verbindlich ab 2026-11-05)

Quelle: `Quellcode/docs/TV-Plus_tvOS-Brandguide_v1.pdf` (22 Seiten). Gilt für alle TV+-Apps; auf Mac, iPhone, iPad und Google TV mit denselben Tokens, Grössen pro Gerät angepasst. Umsetzung in `Packages/ARJOUI/Sources/ARJOUI/Theme.swift` und `AndroidTV/.../TvStyle.java`.

| Token | Dunkel | Hell | Rolle |
|---|---|---|---|
| color.bg | `#090A0A` | `#FDFDFC` | Bildschirmgrund |
| color.surface | `#2A2C2C` | `#D9DAD8` | Taste ruhend, Platzhalter |
| color.text | `#FDFDFC` | `#090A0A` | Text |
| color.text.2 | `#D9DAD8` | `#6B6E6D` | Sekundärtext |
| color.focus.bg | `#FDFDFC` | `#090A0A` | fokussierte Taste (invertiert) |
| color.accent | `#FC5F39` | `#FC5F39` | Fortschritt, Live-Punkt, Titelpunkt, Fehler-Icon |
| color.accent.text | `#FC5F39` | `#B8391A` | Glut als Text |

- Apple TV: Safe Area 80/60 pt, Raster 40 pt horizontal, 5er 16:9 (320 pt), 6er Poster (260 pt), Reihentitel 24 pt, Tasten 66 pt hoch als Kapsel, Kacheln 14 pt Radius, Schrift Geist 76/57/48/38/29/25/24 pt.
- Bewegung: 120 / 200 / 320 / 400 ms, Kurven ease-ui `(0.2, 0, 0, 1)` und ease-out `(0.16, 1, 0.3, 1)`.
- Tabs: Jetzt · Filme · Serien · Live · Mediathek, dazu Suche und Profil. Mediathek = Weiterschauen, Zuletzt gesehen, Favoriten, eigene Ordner.
- Hell/Dunkel folgt dem System. Keine Einstellungen «Erscheinungsbild» und «Akzentfarbe» in der App (Werte bleiben nur für ältere Backups lesbar).
- ARJO Signal `#FF4A1C` erscheint nie in der TV+-Oberfläche.

## Auswahl und Fokus (Entscheid 2026-11-05, ersetzt den Glut-Schein)

- Fokus nie mit Orange und nie nur mit Farbe: Anheben (`Theme.focusScale`, Apple TV ≈ 1.09) und neutraler Schatten (`FocusLift`).
- Tasten invertieren bei Fokus: hell auf dunkel bzw. dunkel auf hell. Hauptaktion zeigt immer die invertierte Fläche.
- «Kontrast erhöhen»: zusätzlich eine Kontur in Textfarbe.
- Ausgewählt (z. B. Ton in Multiview): neutral hell, nicht Glut.
- Seitenleiste und Tab-Leiste zeichnet das System; Tönung monochrom (`Theme.monochrome`).
- Google TV: gleicher Grundsatz (Skalierung 1.09, neutraler Schatten, Tasten invertiert, kein Glut-Rahmen).
