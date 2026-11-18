// Tests für MainPlayer (player.js) mit simuliertem Samsung AVPlay und eigener Uhr: Puffer, Wiederholungen, Stillstand,
// Senderwechsel, veraltete Callbacks, nur eine Anbieter-Verbindung. Ausführen: node SamsungTV/tests/player.test.js
"use strict";
const assert = require("assert"), fs = require("fs"), path = require("path"), vm = require("vm");
const JS = path.join(__dirname, "../wgt/js/");
let passed = 0;
function test(name, fn) { try { fn(); passed++; } catch (e) { console.error("FEHLER: " + name + "\n  " + (e.stack || e.message)); process.exitCode = 1; } }

/** Umgebung: Uhr, Timer, localStorage, AVPlay-Attrappe. */
function env(opts) {
  opts = opts || {};
  let now = 1000000, seq = 0; const timers = new Map();
  const clock = {
    setTimeout: (fn, ms) => { const id = ++seq; timers.set(id, { at: now + (ms || 0), fn, every: 0 }); return id; },
    setInterval: (fn, ms) => { const id = ++seq; timers.set(id, { at: now + ms, fn, every: ms }); return id; },
    clearTimeout: id => timers.delete(id), clearInterval: id => timers.delete(id),
    advance(ms) {
      const end = now + ms;
      for (;;) {
        let next = null; for (const [id, t] of timers) if (t.at <= end && (!next || t.at < next[1].at)) next = [id, t];
        if (!next) break;
        now = next[1].at; if (next[1].every) next[1].at += next[1].every; else timers.delete(next[0]);
        next[1].fn();
      }
      now = end;
    }
  };
  const FakeDate = { now: () => now };
  const store = {};
  const av = {
    log: [], state: "NONE", listener: null, prepareOk: null, prepareErr: null, openCount: 0, connections: 0, maxConnections: 0, buffer: [],
    open(url) { this.openCount++; this.connections++; this.maxConnections = Math.max(this.maxConnections, this.connections); this.state = "IDLE"; this.log.push("open"); this.url = url; },
    close() { if (this.state !== "NONE") this.connections--; this.state = "NONE"; this.log.push("close"); },
    stop() { if (this.state === "PLAYING" || this.state === "PAUSED" || this.state === "READY") this.state = "IDLE"; },
    setDisplayRect() {}, setDisplayMethod() {}, setSilentSubtitle() {}, seekTo() {},
    setBufferingParam(o, u, n) { if (opts.bufferThrows) throw { name: "InvalidValuesError" }; if (n < 4) throw { name: "InvalidValuesError" }; this.buffer.push([o, n]); },
    setListener(l) { this.listener = l; },
    prepareAsync(ok, err) { this.prepareOk = ok; this.prepareErr = err; },
    play() { this.state = "PLAYING"; }, pause() { this.state = "PAUSED"; },
    getState() { return this.state; }, getCurrentTime() { return 0; }, getDuration() { return 0; },
    // Hilfen für Tests
    ready() { const ok = this.prepareOk; this.prepareOk = null; this.state = "READY"; ok(); },
    fail(code) { const l = this.listener; l.onerror(code); },
    tick(ms) { this.listener.oncurrentplaytime(ms); }
  };
  const ctx = { webapis: { avplay: av }, localStorage: { getItem: k => store[k] || null, setItem: (k, v) => { store[k] = v; } },
    console: { info() {} }, Date: FakeDate, setTimeout: clock.setTimeout, clearTimeout: clock.clearTimeout, setInterval: clock.setInterval, clearInterval: clock.clearInterval,
    JSON, Math, String, Array, Number };
  vm.createContext(ctx);
  vm.runInContext(fs.readFileSync(JS + "core.js", "utf8"), ctx);
  vm.runInContext(fs.readFileSync(JS + "player.js", "utf8"), ctx);
  const video = { style: {}, pause() {}, removeAttribute() {}, load() {} };
  const events = [];
  const cb = { busy: b => events.push("busy:" + b), status: t => t && events.push("status"), started: () => events.push("started"), ended: () => events.push("ended"), error: (c, k) => events.push("error:" + k) };
  return { av, clock, store, events, cb, Players: ctx.Players, player: new ctx.Players.MainPlayer(video, null) };
}
const LIVE = "http://anbieter.test/u/p/1.ts", OTHER = "http://anbieter.test/u/p/2.ts";

test("Puffer: gültige Werte (≥ 4 s) für Live und VOD", () => {
  const e = env(); e.player.play(LIVE, 0, true, e.cb); e.clock.advance(0);
  assert.deepStrictEqual(e.av.buffer, [["PLAYER_BUFFER_FOR_PLAY", 4], ["PLAYER_BUFFER_FOR_RESUME", 8]]);
});
test("Puffer: verworfene Einstellung wird in der Diagnose sichtbar, ohne Adresse", () => {
  const e = env({ bufferThrows: true }); e.player.play(LIVE, 0, true, e.cb); e.clock.advance(0);
  const d = e.Players.Diag.dump().filter(x => x.ev === "buffer-config-failed");
  assert.strictEqual(d.length, 2); assert.strictEqual(d[0].seconds, 4);
  const all = JSON.stringify(e.Players.Diag.dump()); assert(!all.includes("anbieter.test") && !all.includes("/u/p/"), "keine URL in der Diagnose");
});
test("Fehlerklassen: Verbindung, fehlender Stream, Format", () => {
  const c = env().Players.classify;
  assert.strictEqual(c("PLAYER_ERROR_CONNECTION_FAILED"), "connection"); assert.strictEqual(c("PLAYER_ERROR_GENEREIC"), "connection");
  assert.strictEqual(c("PLAYER_ERROR_NO_SUCH_FILE"), "unavailable");
  assert.strictEqual(c("PLAYER_ERROR_NOT_SUPPORTED_FORMAT"), "format"); assert.strictEqual(c("PLAYER_ERROR_INVALID_URI"), "format");
});
test("Retry-Grenze: 2 Wiederholungen nach 6 und 12 s, dann Fehler; auch wenn jeder Versuch kurz startet", () => {
  const e = env(); e.player.play(LIVE, 0, true, e.cb); e.clock.advance(0);
  for (let i = 0; i < 3; i++) {
    e.av.ready(); e.clock.advance(1000); e.av.fail("PLAYER_ERROR_CONNECTION_FAILED");
    if (i === 0) { e.clock.advance(5999); assert.strictEqual(e.av.openCount, 1, "nicht vor 6 s"); e.clock.advance(1); }
    else e.clock.advance(12000);
  }
  assert.strictEqual(e.av.openCount, 3, "Erstversuch + 2 Wiederholungen");
  assert(e.events.includes("error:connection"));
  e.clock.advance(60000); assert.strictEqual(e.av.openCount, 3, "danach keine weiteren Versuche");
});
test("Nach Verbindungsfehler gilt der Mindestabstand von 4 s auch beim Senderwechsel", () => {
  const e = env(); e.player.play(LIVE, 0, true, e.cb); e.clock.advance(0); e.av.ready();
  e.av.fail("PLAYER_ERROR_CONNECTION_FAILED"); e.clock.advance(100);
  e.player.play(OTHER, 0, true, e.cb); e.clock.advance(3800); assert.strictEqual(e.av.openCount, 1);
  e.clock.advance(200); assert.strictEqual(e.av.openCount, 2);
});
test("Format-Fehler: anderes Format einmal, danach keine Wiederholung", () => {
  const e = env(); e.player.play(LIVE, 0, true, e.cb); e.clock.advance(0); e.av.fail("PLAYER_ERROR_NOT_SUPPORTED_FORMAT");
  e.clock.advance(1000); assert(e.av.url.endsWith("/live/u/p/1.m3u8")); e.av.fail("PLAYER_ERROR_NOT_SUPPORTED_FORMAT");
  e.clock.advance(60000); assert.strictEqual(e.av.openCount, 2); assert(e.events.includes("error:format"));
});
test("TS scheitert vor dem ersten Bild mit GENEREIC: HLS wird probiert und gemerkt", () => {
  const e = env(); e.player.play(LIVE, 0, true, e.cb); e.clock.advance(0);
  assert(e.av.url.endsWith("/live/u/p/1.ts"));
  e.av.fail("PLAYER_ERROR_GENEREIC"); e.clock.advance(1000);
  assert(e.av.url.endsWith("/live/u/p/1.m3u8"), "HLS"); e.av.ready();
  assert.strictEqual(e.store["iptv.liveFormat"], "m3u8");
  e.player.play(OTHER, 0, true, e.cb); e.clock.advance(5000);
  assert(e.av.url.endsWith("/live/u/p/2.m3u8"), "nächster Sender gleich in HLS");
  assert.strictEqual(e.av.maxConnections, 1);
});
test("GENEREIC nach dem ersten Bild: gleiches Format wiederholen, kein Formatwechsel", () => {
  const e = env(); e.player.play(LIVE, 0, true, e.cb); e.clock.advance(0); e.av.ready();
  e.av.fail("PLAYER_ERROR_GENEREIC"); e.clock.advance(7000);
  assert.strictEqual(e.av.openCount, 2); assert(e.av.url.endsWith(".ts"));
});
test("Formatwechsel endet: beide Formate scheitern -> Meldung, keine Schleife", () => {
  const e = env(); e.player.play(LIVE, 0, true, e.cb); e.clock.advance(0);
  e.av.fail("PLAYER_ERROR_GENEREIC"); e.clock.advance(1000);
  for (let i = 0; i < 3; i++) { e.av.fail("PLAYER_ERROR_GENEREIC"); e.clock.advance(12000); }
  e.clock.advance(120000);
  assert(e.events.some(x => x.startsWith("error:"))); assert(e.av.openCount <= 4, "begrenzt: " + e.av.openCount);
});

test("Stillstand: Neustart nach 20 s ohne Fortschritt, höchstens 2-mal, dann Meldung", () => {
  const e = env(); e.player.play(LIVE, 0, true, e.cb); e.clock.advance(0); e.av.ready();
  e.av.tick(1000); e.clock.advance(19000); assert.strictEqual(e.av.openCount, 1, "läuft noch");
  e.clock.advance(4000); e.clock.advance(1000); assert.strictEqual(e.av.openCount, 2, "1. Neustart");
  e.av.ready(); e.clock.advance(25000); assert.strictEqual(e.av.openCount, 3, "2. Neustart");
  e.av.ready(); e.clock.advance(25000); assert.strictEqual(e.av.openCount, 3, "kein 3. Neustart");
  assert(e.events.includes("error:stalled")); assert.strictEqual(e.av.connections, 0, "Verbindung geschlossen");
  e.clock.advance(120000); assert.strictEqual(e.av.openCount, 3, "keine Endlosschleife");
});
test("Stillstand: Fortschritt verhindert Neustart", () => {
  const e = env(); e.player.play(LIVE, 0, true, e.cb); e.clock.advance(0); e.av.ready();
  for (let t = 1; t <= 60; t++) { e.clock.advance(1000); e.av.tick(t * 1000); }
  assert.strictEqual(e.av.openCount, 1);
});
test("Stillstand: kein Neustart während Pause und Vorbereitung", () => {
  const e = env(); e.player.play(LIVE, 0, true, e.cb); e.clock.advance(60000);
  assert.strictEqual(e.av.openCount, 1, "Vorbereitung ohne Antwort: kein Neustart");
  e.av.ready(); e.player.setPlaying(false); e.clock.advance(120000); assert.strictEqual(e.av.openCount, 1, "pausiert");
  e.player.setPlaying(true); e.clock.advance(19000); assert.strictEqual(e.av.openCount, 1, "Fortsetzen startet die Frist neu");
});
test("Stillstand: VOD wird nicht automatisch neu gestartet", () => {
  const e = env(); e.player.play(LIVE, 0, false, e.cb); e.clock.advance(0); e.av.ready(); e.clock.advance(120000);
  assert.strictEqual(e.av.openCount, 1);
});
test("Senderwechsel: veraltete Callbacks des alten Senders wirken nicht", () => {
  const e = env(); e.player.play(LIVE, 0, true, e.cb); e.clock.advance(0);
  const oldListener = e.av.listener, oldReady = e.av.prepareOk;
  e.player.play(OTHER, 0, true, e.cb); e.clock.advance(1000);
  const before = e.events.length;
  oldReady(); oldListener.onerror("PLAYER_ERROR_CONNECTION_FAILED"); oldListener.onbufferingstart(); oldListener.oncurrentplaytime(5);
  assert.strictEqual(e.events.length, before, "keine Ereignisse vom alten Sender");
  e.clock.advance(60000); assert.strictEqual(e.av.openCount, 2, "kein Retry vom alten Sender");
});
test("Schnelles Zappen: nur der letzte Sender wird geöffnet, nie zwei Verbindungen", () => {
  const e = env(); e.player.play(LIVE, 0, true, e.cb); e.clock.advance(0); e.av.ready();
  for (let i = 0; i < 5; i++) { e.player.play("http://anbieter.test/u/p/" + (10 + i) + ".ts", 0, true, e.cb); e.clock.advance(100); }
  e.clock.advance(1000);
  assert.strictEqual(e.av.openCount, 2); assert(e.av.url.endsWith("/14.ts")); assert.strictEqual(e.av.maxConnections, 1);
});
test("Stopp beendet Überwachung und Wiederholungen", () => {
  const e = env(); e.player.play(LIVE, 0, true, e.cb); e.clock.advance(0); e.av.ready(); e.player.stop();
  e.clock.advance(300000); assert.strictEqual(e.av.openCount, 1);
});
test("Nutzer-Wiederholung setzt die Grenzen zurück", () => {
  const e = env(); e.player.play(LIVE, 0, true, e.cb); e.clock.advance(0);
  for (let i = 0; i < 3; i++) { e.av.fail("PLAYER_ERROR_CONNECTION_FAILED"); e.clock.advance(12000); }
  assert.strictEqual(e.av.openCount, 3);
  e.player.retryNow(0); e.clock.advance(5000); assert.strictEqual(e.av.openCount, 4);
});

console.log(passed + " Player-Tests bestanden" + (process.exitCode ? ", siehe Fehler" : ""));
