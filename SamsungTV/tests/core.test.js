// Tests der Kernlogik, übertragen aus den Android-Unit-Tests (CatalogTest, ChannelNumbersTest, ListsTest, MultiviewLayoutTest, TvModeTest, PresetSourceTest).
// Ausführen: node SamsungTV/tests/core.test.js
"use strict";
const assert = require("assert");
const C = require("../wgt/js/core.js");
let passed = 0;
function test(name, fn) { try { fn(); passed++; } catch (e) { console.error("FEHLER: " + name + "\n  " + e.message); process.exitCode = 1; } }
const eq = assert.deepStrictEqual;

// Catalog / Source
test("Zugangsdaten werden in Abfrage und Pfad kodiert", () => {
  const s = new C.Source("xtream", "https://example.test:8080/path", "user +&", "test /+&?");
  eq(s.api("get_live_streams"), "https://example.test:8080/player_api.php?username=user%20%2B%26&password=test%20%2F%2B%26%3F&action=get_live_streams");
  eq(s.stream("live", "12", "ts"), "https://example.test:8080/live/user%20%2B%26/test%20%2F%2B%26%3F/12.ts");
});
test("Quellkennung ignoriert Passwortwechsel", () => {
  eq(new C.Source("xtream", "https://example.test", "user", "one").scope(), new C.Source("xtream", "https://example.test/", "user", "two").scope());
  assert.notStrictEqual(new C.Source("xtream", "https://example.test", "user", "one").scope(), new C.Source("xtream", "https://example.test", "other", "one").scope());
});
test("Ungültige Adressen und eingebettete Zugangsdaten werden abgelehnt", () => {
  for (const url of ["file:///etc/passwd", "javascript:alert(1)", "https://user:pass@example.test", "not a url", "https://example.test/#secret"])
    assert.throws(() => new C.Source("m3u", url, "", ""), url);
  assert.throws(() => new C.Source("xtream", "https://example.test", "", "x"));
});
test("Playlist: BOM, Kommas in Anführungszeichen, relative Adressen, Arten", () => {
  const fixture = "﻿#EXTM3U\n#EXTINF:-1 tvg-name=\"News\" group-title=\"Schweiz, DE\",News, HD\n/live/1.ts\n"
    + "#EXTINF:-1 group-title=\"Kino\",Film\n/movie/2.mkv\n#EXTINF:-1,Show S01E02\n/series/3.mp4\n#EXTINF:-1,Bad\nfile:///bad\n";
  const rows = C.parseM3u(fixture, "https://example.test/list.m3u");
  eq(rows.length, 3); eq(rows[0].name, "News, HD"); eq(rows[0].group, "Schweiz, DE");
  eq(rows[0].url, "https://example.test/live/1.ts"); eq(rows[0].kind, "live"); eq(rows[1].kind, "movie"); eq(rows[2].kind, "episode");
});
test("Playlist: Metadaten zurückgesetzt, EXTGRP, CRLF", () => {
  const rows = C.parseM3u("#EXTM3U\r\n#EXTINF:-1,First\r\n#EXTGRP:Sport\r\nhttps://example.test/1\r\nhttps://example.test/2\r\n", "https://example.test/list");
  eq(rows[0].group, "Sport"); eq(rows[1].group, "Ohne Gruppe"); eq(rows[1].name, "Eintrag 2"); eq(rows[0].url, "https://example.test/1");
});
test("Playlist: Logo aufgelöst, nie im nächsten Eintrag; tvg-chno", () => {
  const list = C.parseM3u("#EXTM3U\n#EXTINF:-1 tvg-chno=\"7\" tvg-logo=\"/logo.png\",Sender\n/stream.ts\n#EXTINF:-1 tvg-chno=\"x\",Anderer\n../other.ts\n", "https://example.test/a/playlist.m3u");
  eq(list[0].image, "https://example.test/logo.png"); eq(list[1].image, ""); eq(list[0].sourceNumber, 7); eq(list[1].sourceNumber, 0);
  eq(list[1].url, "https://example.test/other.ts");
});
test("Xtream: gemischte IDs, Gruppen, Streamadressen", () => {
  const s = new C.Source("xtream", "https://example.test/", "fixture", "fixture");
  const list = C.xtreamEntries(s, "live", [{ category_id: 1, category_name: "Schweiz" }], [{ stream_id: 42, name: "Testkanal", category_id: "1", num: 5 }, { stream_id: "../bad" }]);
  eq(list.length, 1); eq(list[0].group, "Schweiz"); assert(list[0].url.endsWith("/live/fixture/fixture/42.ts")); eq(list[0].sourceNumber, 5);
});
test("Xtream: Staffeln und Episoden numerisch sortiert", () => {
  const s = new C.Source("xtream", "https://example.test/", "fixture", "fixture");
  const list = C.xtreamEpisodes(s, { episodes: { "10": [{ id: 7, episode_num: 1, title: "Finale", container_extension: "mkv" }], "2": [{ id: 5, episode_num: 2 }, { id: 4, episode_num: 1 }] } });
  eq(list.length, 3); eq(list[0].id, "episode:4"); eq(list[1].id, "episode:5"); eq(list[2].group, "Staffel 10"); assert(list[2].url.endsWith("/series/fixture/fixture/7.mkv"));
});
test("Xtream: Anmeldung, Ablauf und Fehler ohne Adressen", () => {
  eq(C.xtreamAuth({ user_info: { auth: 1, status: "Active", exp_date: "4102444800" } }, Date.now()), 4102444800);
  assert.throws(() => C.xtreamAuth({ user_info: { auth: 0 } }, Date.now()), /abgelehnt/);
  assert.throws(() => C.xtreamAuth({ user_info: { auth: 1, exp_date: "1000" } }, Date.now()), /abgelaufen/);
});
test("Xtream-get.php (m3u_plus, mpegts): Live ohne Endung, Filme, Serien", () => {
  const base = "http://anbieter.test:80/get.php?username=u&password=p&type=m3u_plus&output=mpegts";
  const text = "#EXTM3U\n#EXTINF:-1 tvg-id=\"srf1.ch\" tvg-name=\"CH: SRF 1 HD\" tvg-logo=\"http://anbieter.test/logo/srf.png\" group-title=\"CH | Schweiz\",CH: SRF 1 HD\nhttp://anbieter.test:80/u/p/12345\n"
    + "#EXTINF:-1 tvg-name=\"Film (2024)\" group-title=\"VOD | Neu\",Film (2024)\nhttp://anbieter.test:80/movie/u/p/678.mkv\n"
    + "#EXTINF:-1 tvg-name=\"Serie S02 E03\" group-title=\"SERIEN\",Serie S02 E03\nhttp://anbieter.test:80/series/u/p/910.mp4\n";
  const rows = C.parseM3u(text, base);
  eq(rows.map(r => r.kind), ["live", "movie", "episode"]);
  eq(rows[0].name, "CH: SRF 1 HD"); eq(rows[0].group, "CH | Schweiz"); eq(rows[0].image, "http://anbieter.test/logo/srf.png");
  assert(new C.Source("m3u", base, "", "").scope());
});
test("Live-Formate: TS zuerst, HLS bei Vorliebe; fremde Adressen unverändert", () => {
  eq(C.streamVariants("http://h.test:80/live/u/p/42.ts"), ["http://h.test:80/live/u/p/42.ts", "http://h.test:80/live/u/p/42.m3u8"]);
  eq(C.streamVariants("http://h.test:80/u/p/42", "m3u8"), ["http://h.test:80/live/u/p/42.m3u8", "http://h.test:80/live/u/p/42.ts"]);
  eq(C.streamVariants("https://cdn.test/stream/index.m3u8"), ["https://cdn.test/stream/index.m3u8"]);
});
test("Dropbox-Link wird auf den Download-Host umgeschrieben", () => {
  eq(C.Source.transport("https://www.dropbox.com/scl/fi/abc/list.m3u?rlkey=x&dl=0"), "https://dl.dropboxusercontent.com/scl/fi/abc/list.m3u?rlkey=x&dl=1");
  eq(C.Source.transport("https://example.test/a.m3u"), "https://example.test/a.m3u");
});
test("Voreinstellung wird nur einmal übernommen", () => {
  const saved = new C.Source("xtream", "https://example.test", "u", "p");
  const first = C.choosePreset(saved, "https://example.test/list.m3u", "");
  eq(first.mode, "m3u");
  eq(C.choosePreset(saved, "https://example.test/list.m3u", first.scope()), saved);
  eq(C.choosePreset(null, "", ""), null);
  const x = C.choosePreset(null, { mode: "xtream", address: "http://anbieter.test:80", user: "u", password: "p" }, "");
  eq(x.mode, "xtream"); eq(x.api("get_live_streams"), "http://anbieter.test:80/player_api.php?username=u&password=p&action=get_live_streams");
  eq(C.choosePreset(x, { mode: "xtream", address: "http://anbieter.test:80", user: "u", password: "p" }, x.scope()), x);
});

// ChannelNumbers
const none = {};
test("N1 fortlaufend ab 1", () => eq(C.assignNumbers(["a", "b", "c"], [0, 0, 0], none, none).numbers, { a: 1, b: 2, c: 3 }));
test("N2 Nummern der Quelle gewinnen", () => eq(C.assignNumbers(["a", "b", "c", "d"], [0, 1, 5, 0], none, none).numbers, { b: 1, c: 5, a: 2, d: 3 }));
test("N3 doppelte Quellnummer: erster behält", () => { const r = C.assignNumbers(["a", "b", "c"], [7, 7, 0], none, none); eq(r.numbers, { a: 7, b: 1, c: 2 }); eq(r.duplicates, 1); });
test("N4 Aktualisierung behält bisherige", () => eq(C.assignNumbers(["n", "c", "a"], [0, 0, 0], { a: 1, b: 2, c: 3 }, none).numbers, { a: 1, c: 3, n: 4 }));
test("N5 bisherige schlägt andere Quelle", () => { const n = C.assignNumbers(["x", "a"], [2, 0], { a: 2 }, none).numbers; eq(n.a, 2); assert.notStrictEqual(n.x, 2); });
test("N6 fest gewählte schlägt bisherige", () => { const n = C.assignNumbers(["a", "b"], [0, 0], { a: 1, b: 2 }, { b: 1 }).numbers; eq(n.b, 1); assert.notStrictEqual(n.a, 1); eq(new Set(Object.values(n)).size, 2); });
test("N7 ungültige ignoriert, doppelte IDs eine Nummer", () => eq(C.assignNumbers(["a", "a", "b"], [0, 0, -3], none, none).numbers, { a: 1, b: 2 }));
test("Viele Sender eindeutig", () => {
  const ids = [], s = []; for (let i = 0; i < 5000; i++) { ids.push("id" + i); s.push(i % 7 === 0 ? 3 : 0); }
  const n = C.assignNumbers(ids, s, none, none).numbers; eq(Object.keys(n).length, 5000); eq(new Set(Object.values(n)).size, 5000);
});

// Lists
function prefs() { const m = {}; return { get: (k, d) => (k in m ? JSON.parse(m[k]) : d), set: (k, v) => { m[k] = JSON.stringify(v); } }; }
const a = C.entry("live:1", "SRF 1", "Schweiz", "https://example.test/1.ts", "live"), b = C.entry("live:2", "Arte", "Doku", "https://example.test/2.ts", "live"), film = C.entry("movie:1", "Film", "Doku", "https://example.test/m.mp4", "movie");
test("Ausblenden je Bereich und je Quelle", () => {
  const p = prefs(), lists = new C.Lists(p, "quelle-1");
  lists.setHidden(a, true); eq(lists.visible([a, b, film]), [b, film]);
  lists.setGroupHidden("live", "Doku", true); eq(lists.visible([a, b, film]), [film]);
  eq(new C.Lists(p, "quelle-2").visible([a, b]).length, 2);
  lists.setHidden(a, false); lists.setGroupHidden("live", "Doku", false); eq(lists.visible([a, b, film]).length, 3);
});
test("Umbenennen und zurücksetzen", () => {
  const lists = new C.Lists(prefs(), "q"); lists.rename(a, "  Schweiz 1 "); eq(lists.name(a), "Schweiz 1"); lists.rename(a, ""); eq(lists.name(a), "SRF 1");
  lists.renameGroup("live", "Doku", "Wissen"); eq(lists.groupName("live", "Doku"), "Wissen"); eq(lists.groupName("movie", "Doku"), "Doku");
});
test("Gruppenreihenfolge, unbekannte in Anbieterreihenfolge", () => {
  const lists = new C.Lists(prefs(), "q"), groups = ["A", "B", "C", "D"];
  lists.move("live", groups, "C", -2); eq(lists.ordered("live", groups), ["C", "A", "B", "D"]);
  lists.move("live", groups, "C", -1); eq(lists.ordered("live", groups), ["C", "A", "B", "D"]);
  eq(lists.ordered("live", ["A", "B", "C", "D", "E"]), ["C", "A", "B", "D", "E"]);
  eq(lists.ordered("movie", groups), groups); lists.resetOrder("live"); eq(lists.ordered("live", groups), groups);
});
test("Startseite und Kacheln", () => {
  const p = prefs(), lists = new C.Lists(p, "q"); eq(lists.visibleSections(), C.Lists.SECTIONS);
  lists.moveSection("favorites", -3); lists.setSectionHidden("hero", true);
  eq(lists.visibleSections()[0], "favorites"); assert(!lists.visibleSections().includes("hero"));
  lists.resetHome(); eq(lists.visibleSections(), C.Lists.SECTIONS);
  assert(lists.showNames()); lists.setShowNames(false); assert(!new C.Lists(p, "andere").showNames());
  lists.setTileSize(9); eq(lists.tileSize(), 2); eq(lists.tileWidth(), 236);
});

// MultiviewLayout
const ML = C.MultiviewLayout;
test("Alle Anordnungen ausser Bild in Bild füllen die Fläche ohne Überlappung", () => {
  for (const key of ML.KEYS) { if (ML.overlaps(key)) continue;
    for (let count = 1; count <= 4; count++) { const f = ML.frames(key, count, 1200, 600, count - 1);
      eq(f.length, count); assert(Math.abs(f.reduce((s, r) => s + r[2] * r[3], 0) - 720000) < 1, key + count);
      for (let i = 0; i < f.length; i++) for (let j = i + 1; j < f.length; j++) {
        const w = Math.min(f[i][0] + f[i][2], f[j][0] + f[j][2]) - Math.max(f[i][0], f[j][0]), h = Math.min(f[i][1] + f[i][3], f[j][1] + f[j][3]) - Math.max(f[i][1], f[j][1]);
        assert(w <= 0.5 || h <= 0.5, key + " overlap"); } } }
});
test("Raster mit drei: letztes Bild über die ganze Breite", () => eq(ML.frames("grid", 3, 1200, 600, 0), [[0, 0, 600, 300], [600, 0, 600, 300], [0, 300, 1200, 300]]));
test("Bild in Bild: Hauptbild voll, kleine Bilder in der Ecke", () => {
  const f = ML.frames("pip", 3, 1600, 900, 1); eq(f[1], [0, 0, 1600, 900]);
  for (const i of [0, 2]) { assert(f[i][0] > 800 && f[i][0] + f[i][2] <= 1600 && f[i][1] >= 0 && f[i][1] + f[i][3] <= 900); assert(Math.abs(f[i][2] / f[i][3] - 16 / 9) < 0.01); }
  assert(f[0][1] >= f[2][1] + f[2][3] || f[2][1] >= f[0][1] + f[0][3]); eq(ML.label("unbekannt"), "Raster");
});

// TV-Modus
function live(id, group, number) { const e = C.entry(id, id, group, "https://example.test/" + id + ".ts", "live"); e.number = number; return e; }
test("Warteschlange: Gruppe beginnt bei kleinster Nummer, globaler Sprung", () => {
  const all = [live("a", "Schweiz", 3), live("b", "Schweiz", 1), live("c", "Sport", 20), live("d", "Sport", 10)];
  const q = new C.PlaybackQueue(all, all[0], "scope", ["Schweiz", "Sport"]);
  eq(q.groups(), ["Schweiz", "Sport"]); eq(q.move(-1).id, "b"); eq(q.move(-1).id, "a");
  eq(q.neighbourGroup("Schweiz", 1), { name: "Sport", position: 2, count: 2 });
  eq(q.startGroup("Sport").id, "d"); eq(q.jump(q.byNumber(1)).id, "b"); eq(q.byNumber(99), null); eq(q.previous().id, "d");
});
test("Feste Nummern bleiben über Neuladen", () => {
  const first = [live("a", "G", 0), live("b", "G", 0)];
  const saved = C.applyNumbers(first, {}, {}); eq(first[0].number, 1); eq(first[1].number, 2);
  const second = [live("n", "G", 0), live("b", "G", 0), live("a", "G", 0)];
  C.applyNumbers(second, saved, {}); eq(second[0].number, 3); eq(second[1].number, 2); eq(second[2].number, 1);
});
test("Zifferneingabe: höchstens 4 Ziffern, keine führende 0", () => {
  const n = new C.ChannelNavigator(); n.enter(0, 0); assert(!n.hasPendingDigits());
  [1, 2, 3, 4, 5].forEach(d => n.enter(d, 1)); eq(n.digits(), "1234"); eq(n.commitDigits(), 1234); assert(!n.hasPendingDigits());
});
test("Spulen begrenzt auf Anfang und Ende", () => { eq(C.seekTarget(5000, 60000, -10000), 0); eq(C.seekTarget(55000, 60000, 10000), 60000); eq(C.seekTarget(1000, -1, 10000), 11000); });
test("Relative Adressen", () => {
  eq(C.resolveUrl("https://h.test/a/b/list.m3u?x=1", "c.ts"), "https://h.test/a/b/c.ts");
  eq(C.resolveUrl("https://h.test/a/b/list.m3u", "//cdn.test/x"), "https://cdn.test/x");
  eq(C.resolveUrl("https://h.test/a/b/list.m3u", "https://o.test/y"), "https://o.test/y");
});

console.log(passed + " Tests bestanden" + (process.exitCode ? ", siehe Fehler" : ""));
