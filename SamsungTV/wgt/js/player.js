/* Wiedergabe: Samsung AVPlay auf der TV (wie ExoPlayer auf Google TV), HTML5-Video als Rückfall (Browser, Multiview).
   Auf der TV gemessen (08.11.2026, alte Tizen-Version): Der Anbieter gibt eine Verbindung erst verzögert frei.
   Neuer Stream sofort nach dem Stoppen -> PLAYER_ERROR_CONNECTION_FAILED, mit 4 s Abstand klappt jeder Wechsel.
   Deshalb: Der Abstand ist zuerst kurz (schnelles Zappen). Meldet der Anbieter einmal einen Verbindungsfehler, gilt für den Rest
   der Sitzung der Mindestabstand von 4 s. Höchstens 2 langsame Wiederholungen je Stream; der Zähler gilt erst nach 30 s stabiler
   Wiedergabe als zurückgesetzt. Schnelles Zappen startet nur den zuletzt gewählten Sender. */
(function (root) {
  "use strict";
  var av = root.webapis && root.webapis.avplay ? root.webapis.avplay : null;
  var MIN_GAP = 4000, ZAP_GAP = 400, RETRY_WAIT = [6000, 12000];
  // Samsung AVPlay: setBufferingParam braucht mindestens 4 s (Doku avplay-api, Stand 11/2026) und gilt nur im Zustand IDLE.
  // Live: 4 s bis zum ersten Bild (Minimum, schnelles Zappen), 8 s nach einem Aussetzer (mehr Reserve gegen erneutes Stocken).
  var BUFFER = { live: { play: 4, resume: 8 }, vod: { play: 4, resume: 8 } };
  // Stillstand: läuft Live über 20 s ohne Fortschritt, wird derselbe Sender neu geöffnet; höchstens 2-mal innerhalb von 10 min.
  var STALL_MS = 20000, WATCH_MS = 2000, MAX_RECOVERIES = 2, RECOVERY_WINDOW_MS = 600000, STABLE_MS = 30000;

  /** Fehlerklassen: "connection" (vorübergehend, Wiederholung sinnvoll), "unavailable" (Stream fehlt), "format" (nicht abspielbar). */
  function classify(msg) {
    var m = String(msg);
    if (/NOT_SUPPORTED|INVALID_URI|INVALID_PARAMETER|MEDIA_ERROR/i.test(m)) return "format";
    if (/NO_SUCH_FILE/i.test(m)) return "unavailable";
    return "connection"; // CONNECTION_FAILED, NETWORK, TIMEOUT, GENEREIC, InvalidAccess und Unbekanntes
  }
  function isConnError(msg) { return classify(msg) === "connection"; }
  function lang(info) {
    try { var x = typeof info.extra_info === "string" ? JSON.parse(info.extra_info) : info.extra_info || {}; return x.language || x.track_lang || x.lang || ""; } catch (e) { return ""; }
  }

  /** Lokale Diagnose (Ringpuffer, 200 Einträge, localStorage «iptv.diag»). Nie Adressen, Zugangsdaten oder Pfade, nur Codes und Zeiten. */
  var Diag = (function () {
    var KEY = "iptv.diag", MAX = 200, list = [], dirty = false;
    try { list = JSON.parse(root.localStorage.getItem(KEY) || "[]"); if (!Array.isArray(list)) list = []; } catch (e) { list = []; }
    function flush() { if (!dirty) return; dirty = false; try { root.localStorage.setItem(KEY, JSON.stringify(list)); } catch (e) {} }
    return {
      log: function (ev, data) {
        var item = { t: Date.now(), ev: ev };
        if (data) for (var k in data) if (data.hasOwnProperty(k) && (typeof data[k] === "number" || typeof data[k] === "boolean" || (typeof data[k] === "string" && data[k].length <= 64 && !/[\/?=&@]/.test(data[k])))) item[k] = data[k];
        list.push(item); if (list.length > MAX) list.splice(0, list.length - MAX);
        if (!dirty) { dirty = true; setTimeout(flush, 5000); }
        try { if (root.console && root.console.info) root.console.info("[IPTV]", ev, JSON.stringify(item)); } catch (e) {}
      },
      flush: flush,
      dump: function () { return list.slice(); }
    };
  })();

  /** Zuletzt funktionierendes Live-Format ("ts" oder "m3u8"), damit der nächste Sender gleich im richtigen Format startet. */
  var FORMAT_KEY = "iptv.liveFormat";
  function preferredFormat() { try { return root.localStorage.getItem(FORMAT_KEY) || ""; } catch (e) { return ""; } }
  function rememberFormat(url) { var m = /\.(ts|m3u8)$/.exec(url); if (!m) return; try { if (preferredFormat() !== m[1]) { root.localStorage.setItem(FORMAT_KEY, m[1]); Diag.log("format-preferred", { format: m[1] }); } } catch (e) {} }

  /** Haupt-Player (Vollbild). cb: busy(bool), started(), ended(), error(msg, kind), status(text), subtitle(text) */
  function MainPlayer(videoEl, objectEl) {
    this.vid = videoEl; this.obj = objectEl; this.native = !!av;
    this.gen = 0; this.gap = ZAP_GAP; this.timer = null; this.watch = null; this.open = false; this.lastClose = 0; this.cb = {}; this.url = ""; this.retry = 0; this.startAt = 0; this.live = false;
    this.recoveries = []; this.paused = false; this.playing = false; this.lastProgressAt = 0; this.lastTime = -1; this.startedAt = 0; this.streamId = ""; this.lastPlayCall = -Infinity;
  }
  MainPlayer.prototype.closeAv = function () {
    if (av) { try { av.stop(); } catch (e) {} try { av.close(); } catch (e) {} }
    if (this.open) this.lastClose = Date.now();
    this.open = false;
  };
  MainPlayer.prototype.stopWatch = function () { clearInterval(this.watch); this.watch = null; this.playing = false; };
  MainPlayer.prototype.play = function (url, startMs, live, callbacks) {
    this.gen++; clearTimeout(this.timer); this.stopWatch(); this.closeAv(); this.stopVideo();
    // Live-Xtream: Liste der Formate (TS, HLS); sonst eine Adresse.
    this.urls = live && root.Core ? root.Core.streamVariants(url, preferredFormat()) : [url]; this.uIdx = 0; this.baseUrl = url;
    this.cb = callbacks || {}; this.url = this.urls[0]; this.retry = 0; this.recoveries = []; this.paused = false; this.startAt = startMs || 0; this.live = !!live;
    this.streamId = root.Core ? root.Core.hash(String(url).replace(/\.(ts|m3u8)$/, "")).slice(0, 6) : "";
    Diag.log("select", { live: this.live, id: this.streamId, gap: this.gap });
    this.cb.busy && this.cb.busy(true);
    // Senderwechsel kurz hintereinander (Taste gehalten): erst nach 400 ms Ruhe öffnen, damit keine Zwischen-Sender Verbindungen belegen.
    var now = Date.now(), zapping = now - this.lastPlayCall < 1500; this.lastPlayCall = now;
    this.schedule(zapping ? ZAP_GAP : 0);
  };
  MainPlayer.prototype.schedule = function (extra) {
    var self = this, g = this.gen; clearTimeout(this.timer);
    var wait = Math.max(extra || 0, this.lastClose + this.gap - Date.now(), 0);
    if (!av) wait = extra || 0;
    this.timer = setTimeout(function () { if (g === self.gen) self.attempt(); }, wait);
  };
  MainPlayer.prototype.setBuffer = function () {
    var b = this.live ? BUFFER.live : BUFFER.vod;
    [["PLAYER_BUFFER_FOR_PLAY", b.play], ["PLAYER_BUFFER_FOR_RESUME", b.resume]].forEach(function (o) {
      try { av.setBufferingParam(o[0], "PLAYER_BUFFER_SIZE_IN_SECOND", o[1]); }
      catch (e) { Diag.log("buffer-config-failed", { option: o[0], seconds: o[1], code: String(e && (e.name || e.message) || e).slice(0, 60) }); }
    });
  };
  MainPlayer.prototype.attempt = function () {
    var self = this, g = this.gen, done = false, cb = this.cb, started = false;
    function failed(msg) {
      if (done || g !== self.gen) return; done = true;
      var kind = av ? classify(msg) : "format", code = String(msg).slice(0, 60);
      self.stopWatch(); self.closeAv();
      Diag.log("error", { code: code, kind: kind, retry: self.retry, live: self.live, format: (/\.(ts|m3u8)$/.exec(self.url) || ["", ""])[1], started: started });
      // Anderes Format probieren, wenn der Start scheitert (Formatfehler oder unbestimmter Fehler vor dem ersten Bild).
      var tryOther = kind === "format" || kind === "unavailable" || (!started && /GENEREIC/i.test(code));
      if (av && tryOther && self.uIdx + 1 < self.urls.length) {
        self.url = self.urls[++self.uIdx]; self.retry = 0;
        Diag.log("variant", { format: (/\.(ts|m3u8)$/.exec(self.url) || ["", ""])[1] });
        self.schedule(0); return;
      }
      if (kind === "connection") self.gap = MIN_GAP;
      if (kind === "connection" && self.retry < RETRY_WAIT.length) {
        var w = RETRY_WAIT[self.retry++];
        Diag.log("retry", { attempt: self.retry, waitMs: w });
        cb.status && cb.status("Keine Verbindung, neuer Versuch in " + Math.round(w / 1000) + " s …");
        self.schedule(w); return;
      }
      cb.busy && cb.busy(false);
      cb.error && cb.error(code, kind);
    }
    Diag.log("attempt", { id: this.streamId, retry: this.retry });
    if (!av) return this.openVideo(failed, g);
    try {
      av.open(this.url); this.open = true;
      try { av.setDisplayRect(0, 0, 1920, 1080); } catch (e) {}
      try { av.setDisplayMethod("PLAYER_DISPLAY_MODE_LETTER_BOX"); } catch (e) {}
      this.setBuffer();
      av.setListener({
        onbufferingstart: function () { if (g !== self.gen) return; Diag.log("buffering-start", { pos: self.lastTime }); cb.busy && cb.busy(true); },
        onbufferingcomplete: function () { if (g !== self.gen) return; Diag.log("buffering-complete", { pos: self.lastTime }); cb.busy && cb.busy(false); },
        onstreamcompleted: function () { if (g !== self.gen) return; Diag.log("completed", {}); self.stopWatch(); cb.ended && cb.ended(); },
        onerror: function (e) { failed(e); },
        onsubtitlechange: function (duration, text) { if (g === self.gen) cb.subtitle && cb.subtitle(text, duration); },
        oncurrentplaytime: function (ms) { if (g === self.gen) self.progress(ms); }
      });
      av.prepareAsync(function () {
        if (g !== self.gen || done) return;
        if (self.startAt > 0) { try { av.seekTo(self.startAt); } catch (e) {} }
        try { av.setSilentSubtitle(true); } catch (e) {}
        av.play(); started = true;
        if (self.live && self.urls.length > 1) rememberFormat(self.url);
        Diag.log("playing", { live: self.live, retry: self.retry, format: (/\.(ts|m3u8)$/.exec(self.url) || ["", ""])[1] });
        self.startWatch(g);
        cb.busy && cb.busy(false); cb.status && cb.status(""); cb.started && cb.started();
      }, function (e) { failed(e && (e.name || e.message) || e); });
    } catch (e) { failed(e.name || e.message || String(e)); }
  };
  /** Fortschritt aus oncurrentplaytime. Erst nach 30 s stabiler Wiedergabe gelten die Wiederholungen wieder als verbraucht-frei. */
  MainPlayer.prototype.progress = function (ms) {
    var now = Date.now();
    if (ms !== this.lastTime) { this.lastTime = ms; this.lastProgressAt = now; }
    if (this.retry > 0 && now - this.startedAt >= STABLE_MS) { Diag.log("stable", { afterRetries: this.retry }); this.retry = 0; }
  };
  MainPlayer.prototype.startWatch = function (g) {
    var self = this;
    clearInterval(this.watch); this.playing = true; this.startedAt = this.lastProgressAt = Date.now(); this.lastTime = -1;
    if (!this.live || !av) return; // Fortschritt kommt nur von AVPlay (oncurrentplaytime)
    this.watch = setInterval(function () { if (g === self.gen) self.checkStall(g); else clearInterval(self.watch); }, WATCH_MS);
  };
  /** Live hängt: läuft (nicht pausiert), aber seit STALL_MS kein Fortschritt. Neustart desselben Senders, begrenzt. */
  MainPlayer.prototype.checkStall = function (g) {
    if (!this.playing || this.paused || g !== this.gen) return;
    var state = this.state();
    if (state !== "PLAYING") return;
    var now = Date.now();
    if (now - this.lastProgressAt < STALL_MS) return;
    this.recoveries = this.recoveries.filter(function (t) { return now - t < RECOVERY_WINDOW_MS; });
    Diag.log("stall", { stalledMs: now - this.lastProgressAt, pos: this.lastTime, recoveries: this.recoveries.length });
    if (this.recoveries.length >= MAX_RECOVERIES) {
      this.stopWatch(); this.gen++; clearTimeout(this.timer); this.closeAv();
      Diag.log("stall-giveup", {});
      this.cb.busy && this.cb.busy(false);
      this.cb.error && this.cb.error("STALLED", "stalled");
      return;
    }
    this.recoveries.push(now);
    this.restart("stall");
  };
  /** Öffnet denselben Stream neu (eine Verbindung: erst schliessen, dann nach dem Mindestabstand öffnen). */
  MainPlayer.prototype.restart = function (reason) {
    this.gen++; clearTimeout(this.timer); this.stopWatch(); this.closeAv();
    Diag.log("recover", { reason: reason, attempt: this.recoveries.length });
    this.startAt = this.live ? 0 : this.startAt;
    this.cb.busy && this.cb.busy(true);
    this.cb.status && this.cb.status("Bild hängt, Sender wird neu geladen …");
    this.schedule(0);
  };
  MainPlayer.prototype.openVideo = function (failed, g) {
    var v = this.vid, self = this, cb = this.cb;
    v.style.display = "block"; v.src = this.url;
    v.onwaiting = function () { if (g === self.gen) cb.busy && cb.busy(true); };
    v.onplaying = function () { if (g === self.gen) { cb.busy && cb.busy(false); cb.started && cb.started(); } };
    v.onended = function () { if (g === self.gen) cb.ended && cb.ended(); };
    v.onerror = function () { failed("MEDIA_ERROR"); };
    v.onloadedmetadata = function () { if (self.startAt > 0) v.currentTime = self.startAt / 1000; };
    var p = v.play(); if (p && p.catch) p.catch(function () {});
  };
  MainPlayer.prototype.stopVideo = function () {
    var v = this.vid; v.onerror = null; v.pause(); v.removeAttribute("src"); try { v.load(); } catch (e) {} v.style.display = "none";
  };
  MainPlayer.prototype.stop = function () { this.gen++; clearTimeout(this.timer); this.stopWatch(); this.closeAv(); this.stopVideo(); Diag.flush(); };
  /** Gezielter neuer Versuch durch den Nutzer: setzt alle Grenzen zurück. */
  MainPlayer.prototype.retryNow = function (startMs) { var cb = this.cb; Diag.log("user-retry", {}); this.play(this.baseUrl, startMs || 0, this.live, cb); };
  MainPlayer.prototype.state = function () { if (av) { try { return av.getState(); } catch (e) { return "NONE"; } } return this.vid.paused ? "PAUSED" : "PLAYING"; };
  MainPlayer.prototype.isPlaying = function () { return this.state() === "PLAYING"; };
  MainPlayer.prototype.setPlaying = function (on) {
    this.paused = !on; if (on) this.lastProgressAt = Date.now();
    Diag.log(on ? "resume" : "pause", {});
    if (av) { try { if (on) av.play(); else av.pause(); } catch (e) {} return; }
    if (on) { var p = this.vid.play(); if (p && p.catch) p.catch(function () {}); } else this.vid.pause();
  };
  MainPlayer.prototype.position = function () { if (av) { try { return av.getCurrentTime(); } catch (e) { return 0; } } return Math.round(this.vid.currentTime * 1000) || 0; };
  MainPlayer.prototype.duration = function () {
    if (av) { try { var d = av.getDuration(); return d > 0 ? d : -1; } catch (e) { return -1; } }
    return isFinite(this.vid.duration) && this.vid.duration > 0 ? Math.round(this.vid.duration * 1000) : -1;
  };
  MainPlayer.prototype.seekable = function () { return !this.live && this.duration() > 0; };
  MainPlayer.prototype.seekTo = function (ms) {
    if (av) { try { av.seekTo(Math.max(0, Math.round(ms))); } catch (e) {} return; }
    this.vid.currentTime = Math.max(0, ms / 1000);
  };
  /** Vom Stream angebotene Spuren: type "AUDIO" oder "TEXT". */
  MainPlayer.prototype.tracks = function (type) {
    var out = [];
    if (av) {
      try { (av.getTotalTrackInfo() || []).forEach(function (t, n) { if (t.type === type) out.push({ index: t.index, label: lang(t) || (type === "AUDIO" ? "Tonspur " : "Untertitel ") + (out.length + 1) }); }); } catch (e) {}
      return out;
    }
    var list = type === "AUDIO" ? this.vid.audioTracks : this.vid.textTracks;
    if (list) for (var i = 0; i < list.length; i++) out.push({ index: i, label: list[i].label || list[i].language || (type === "AUDIO" ? "Tonspur " : "Untertitel ") + (i + 1) });
    return out;
  };
  MainPlayer.prototype.selectTrack = function (type, index) {
    if (av) {
      try { if (type === "TEXT") { if (index < 0) { av.setSilentSubtitle(true); return; } av.setSilentSubtitle(false); } av.setSelectTrack(type, index); } catch (e) {}
      return;
    }
    var list = type === "AUDIO" ? this.vid.audioTracks : this.vid.textTracks; if (!list) return;
    for (var i = 0; i < list.length; i++) { if (type === "AUDIO") list[i].enabled = i === index; else list[i].mode = i === index ? "showing" : "disabled"; }
  };

  /** Multiview-Bild: HTML5-Video. AVPlay zeigt auf Tizen nur ein Videobild gleichzeitig (AVPlayStore dient laut Samsung nur dem
      parallelen Vorpuffern). Wie viele Bilder wirklich laufen, entscheiden die Decoder des Fernsehers. */
  function TilePlayer(videoEl) { this.vid = videoEl; }
  TilePlayer.prototype.play = function (url, onError) {
    var v = this.vid; v.onerror = function () { onError && onError(); }; v.src = url; v.muted = true;
    var p = v.play(); if (p && p.catch) p.catch(function () {});
  };
  TilePlayer.prototype.setSound = function (on) { this.vid.muted = !on; };
  TilePlayer.prototype.stop = function () { var v = this.vid; v.onerror = null; v.pause(); v.removeAttribute("src"); try { v.load(); } catch (e) {} };

  root.Players = { MainPlayer: MainPlayer, TilePlayer: TilePlayer, native: !!av, Diag: Diag, classify: classify,
    LIMITS: { MIN_GAP: MIN_GAP, ZAP_GAP: ZAP_GAP, RETRY_WAIT: RETRY_WAIT, BUFFER: BUFFER, STALL_MS: STALL_MS, MAX_RECOVERIES: MAX_RECOVERIES, STABLE_MS: STABLE_MS } };
})(this);
