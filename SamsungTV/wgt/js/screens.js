/* Player (PlayerActivity + RemoteInput) und Multiview (MultiviewActivity) der Google-TV-App. */
(function (root) {
  "use strict";
  var h = UI.h, button = UI.button, K = UI.K;
  function clock(ms) { var s = Math.max(0, Math.floor(ms / 1000)); return Math.floor(s / 60) + ":" + ("0" + (s % 60)).slice(-2); }
  function longClock(ms) { var s = Math.max(0, Math.floor(ms / 1000)), hh = Math.floor(s / 3600), m = Math.floor(s / 60) % 60; return (hh ? hh + ":" + ("0" + m).slice(-2) : m) + ":" + ("0" + (s % 60)).slice(-2); }

  // ---------- Player ----------
  /** p: {entry, live, key, scope, queue, onClose(entryId), progress} */
  function PlayerScreen(p) {
    var self = this;
    this.p = p; this.entry = p.entry; this.live = p.live; this.key = p.key; this.queue = p.queue; this.digits = new Core.ChannelNavigator();
    this.currentNumber = p.queue ? p.queue.current().number : p.entry.number || 0;
    this.menuMode = false; this.timers = {}; this.lastAction = -Infinity; this.lastGroup = -Infinity; this.repeat = {}; this.longDone = false; this.okDown = false;
    var el = this.el = h("div", "player-layer");
    this.video = h("video", "player-video"); this.video.setAttribute("playsinline", ""); el.appendChild(this.video);
    this.spinner = h("div", "spinner"); el.appendChild(this.spinner);
    this.subtitle = h("div", "subtitle"); el.appendChild(this.subtitle);
    this.groupBanner = h("div", "group-banner t-title32"); el.appendChild(this.groupBanner);
    this.channelBanner = h("div", "channel-banner"); this.channelNumber = h("div", "t-title72"); this.channelName = h("div", "t-title32");
    this.channelBanner.appendChild(this.channelNumber); this.channelBanner.appendChild(this.channelName); el.appendChild(this.channelBanner);
    this.entryView = h("div", "entry-view t-title72"); el.appendChild(this.entryView);
    this.buildController();
    [this.groupBanner, this.channelBanner, this.entryView, this.controller].forEach(function (v) { v.style.display = "none"; });
    document.getElementById("overlay").appendChild(el);
    document.documentElement.classList.add("playing");
    UI.pushLayer(el, { onBack: function () { self.back(); } });
    this.keyHandler = function (e, phase) { return self.onKey(e, phase); };
    UI.addKeyHandler(this.keyHandler);
    this.player = new Players.MainPlayer(this.video, null);
    var start = this.live ? 0 : Store.Prefs.get("p:" + this.key, 0);
    this.start(start);
    this.saveTimer = setInterval(function () { self.save(); }, 15000);
  }
  var PS = PlayerScreen.prototype;
  PS.start = function (startMs) {
    var self = this, e = this.entry;
    this.subtitle.textContent = "";
    this.player.play(e.url, startMs, this.live, {
      busy: function (on) { self.spinner.style.display = on ? "block" : "none"; },
      status: function (t) { if (t) self.message(t); },
      started: function () {},
      subtitle: function (text, duration) { self.subtitle.innerHTML = ""; self.subtitle.textContent = String(text || "").replace(/<[^>]*>/g, ""); clearTimeout(self.timers.sub); self.timers.sub = setTimeout(function () { self.subtitle.textContent = ""; }, Math.max(500, +duration || 3000)); },
      ended: function () { if (!self.live) { Store.Prefs.remove("p:" + self.key); self.ended = true; } },
      error: function (code, kind) { self.failed(kind); }
    });
  };
  /** kind: "connection" (Versuche ausgeschöpft), "stalled" (Bild hing wiederholt), "unavailable", "format". */
  PS.failed = function (kind) {
    var self = this;
    if (this.closed) return;
    if (this.live && (kind === "format" || kind === "unavailable")) { this.message("Sender momentan nicht verfügbar. Mit Hoch/Runter einen anderen Sender wählen."); return; }
    if (this.error) return;
    var message = kind === "stalled" ? "Das Bild ist mehrmals stehen geblieben. Prüfe die Verbindung des Fernsehers oder versuche es erneut."
      : kind === "connection" ? "Keine Verbindung zum Stream nach mehreren Versuchen. Dein Zugang erlaubt eventuell nur eine Verbindung gleichzeitig: andere Geräte und Apps schliessen und erneut versuchen."
      : "Stream oder Format ist momentan nicht verfügbar. Einige Ton-/Bildformate werden vom Fernseher möglicherweise nicht unterstützt.";
    this.error = UI.dialog({ title: this.live ? "Sender nicht verfügbar" : "Wiedergabe unterbrochen", message: message,
      buttons: [{ label: "Erneut versuchen", primary: true, action: function () { self.error = null; self.player.retryNow(self.live ? 0 : self.lastPosition || 0); } },
                { label: this.live ? "Schliessen" : "Zurück", action: function () { self.error = null; if (!self.live) self.close(); } }],
      onClose: function () { self.error = null; } });
  };
  PS.buildController = function () {
    var self = this, c = this.controller = h("div", "controller");
    this.ctlTitle = h("div", "t-title40 ellipsis", ""); c.appendChild(this.ctlTitle);
    var prog = this.ctlProgress = h("div", "ctl-progress");
    this.ctlPos = h("div", "t-small", "0:00"); this.ctlBar = h("div", "ctl-bar"); this.ctlFill = h("i"); this.ctlBar.appendChild(this.ctlFill); this.ctlDur = h("div", "t-small", "");
    prog.appendChild(this.ctlPos); prog.appendChild(this.ctlBar); prog.appendChild(this.ctlDur); c.appendChild(prog);
    var row = h("div", "ctl-buttons");
    this.btnBack = button("−10 s", function () { self.seekBy(-10000); }); this.btnPlay = button("Pause", function () { self.togglePlay(); }, { primary: true }); this.btnFwd = button("+10 s", function () { self.seekBy(10000); });
    this.btnAudio = button("Ton", function () { self.chooseTrack("AUDIO"); }); this.btnSubs = button("Untertitel", function () { self.chooseTrack("TEXT"); });
    [this.btnBack, this.btnPlay, this.btnFwd, this.btnAudio, this.btnSubs].forEach(function (b) { row.appendChild(b); });
    c.appendChild(row); this.el.appendChild(c);
  };
  PS.openMenu = function () {
    this.menuMode = true; this.controller.style.display = "";
    this.ctlTitle.textContent = this.entry.name || "";
    this.btnBack.style.display = this.btnFwd.style.display = this.ctlProgress.style.display = this.live ? "none" : "";
    this.updateController(); UI.focus(this.btnPlay); this.touchMenu();
    var self = this; clearInterval(this.timers.ctl); this.timers.ctl = setInterval(function () { self.updateController(); }, 500);
  };
  PS.touchMenu = function () { var self = this; clearTimeout(this.timers.hideMenu); this.timers.hideMenu = setTimeout(function () { if (!UI.topLayer() || UI.topLayer() === self.el) self.hideMenu(); }, 5000); };
  PS.hideMenu = function () { this.menuMode = false; this.controller.style.display = "none"; clearInterval(this.timers.ctl); UI.clearFocus(); };
  PS.updateController = function () {
    var pos = this.player.position(), dur = this.player.duration();
    this.btnPlay.textContent = this.player.isPlaying() ? "Pause" : "Wiedergabe";
    this.ctlPos.textContent = longClock(pos); this.ctlDur.textContent = dur > 0 ? longClock(dur) : "";
    this.ctlFill.style.width = dur > 0 ? Math.min(100, pos / dur * 100) + "%" : "0";
  };
  PS.togglePlay = function () { this.player.setPlaying(!this.player.isPlaying()); var self = this; setTimeout(function () { self.updateController(); }, 150); };
  PS.chooseTrack = function (type) {
    var self = this, tracks = this.player.tracks(type);
    if (!tracks.length) { this.message(type === "AUDIO" ? "Dieser Stream bietet keine weiteren Tonspuren." : "Dieser Stream bietet keine Untertitel."); return; }
    var items = tracks.map(function (t) { return t.label; }); if (type === "TEXT") items.unshift("Aus");
    UI.dialog({ title: type === "AUDIO" ? "Tonspur" : "Untertitel", items: items, onItem: function (n) {
      if (type === "TEXT") { if (n === 0) { self.player.selectTrack("TEXT", -1); self.subtitle.textContent = ""; } else self.player.selectTrack("TEXT", tracks[n - 1].index); }
      else self.player.selectTrack("AUDIO", tracks[n].index);
    }, buttons: [{ label: "Abbrechen" }] });
  };
  /** Fernbedienung wie RemoteInput.java. */
  PS.onKey = function (e, phase) {
    var k = e.keyCode, live = this.live, menu = this.menuMode, now = Date.now();
    var center = k === K.ENTER;
    if (UI.topLayer() !== this.el) {
      // Dialog oder Zahlenfeld offen: Tastenzustand beim Loslassen trotzdem zurücksetzen, sonst geht danach kurzes OK verloren.
      if (phase === "up") { delete this.repeat[k]; if (center) { this.okDown = false; clearTimeout(this.timers.ok); } }
      return false;
    }
    if (phase === "up") {
      var was = this.repeat[k] !== undefined; delete this.repeat[k];
      if (center && this.okDown) { this.okDown = false; clearTimeout(this.timers.ok); if (live && !menu && !this.longDone) { if (this.digits.hasPendingDigits()) this.commitDigits(); else this.showBanner(); } return true; }
      return was && !menu;
    }
    var rep = this.repeat[k] === undefined ? 0 : this.repeat[k] + 1; this.repeat[k] = rep;
    if (menu) this.touchMenu();
    if (k === K.PLAYPAUSE || k === K.PLAY || k === K.PAUSE) { if (rep === 0) { if (k === K.PLAY) this.player.setPlaying(true); else if (k === K.PAUSE) this.player.setPlaying(false); else this.togglePlay(); } return true; }
    if (k === K.STOP) { this.close(); return true; }
    if (live && !menu) {
      var d = UI.digitOf(k);
      if (d >= 0) { if (rep === 0) this.enterDigit(d); return true; }
      if (k === K.PRECH) { if (rep === 0) this.recallPrevious(); return true; }
    }
    if (!menu && (k === K.INFO || k === K.TOOLS || k === K.MENU)) { if (rep === 0) this.openMenu(); return true; }
    if (center && !menu) {
      if (live) {
        // Live: OK kurz = Banner (beim Loslassen), OK lang = Zahlenfeld.
        if (rep === 0) { var self = this; this.okDown = true; this.longDone = false; clearTimeout(this.timers.ok); this.timers.ok = setTimeout(function () { if (self.okDown) { self.longDone = true; self.showNumberPad(); } }, 500); }
        return true;
      }
      if (rep === 0) this.openMenu(); return true;
    }
    var channelKey = k === K.CH_UP || k === K.CH_DOWN, mediaSeek = k === K.FF || k === K.RW;
    if (menu && !channelKey && !mediaSeek) { delete this.repeat[k]; return false; }
    if (live && (k === K.LEFT || k === K.RIGHT)) {
      if (rep === 0 || now - this.lastGroup >= 300) { this.lastGroup = now; this.switchGroup(k === K.RIGHT ? 1 : -1); }
      return true;
    }
    var direction = 0;
    if (live) { if (k === K.UP || k === K.CH_UP) direction = 1; if (k === K.DOWN || k === K.CH_DOWN) direction = -1; }
    else { if (k === K.RIGHT || k === K.FF) direction = 1; if (k === K.LEFT || k === K.RW) direction = -1; }
    if (!direction) { delete this.repeat[k]; return false; }
    var interval = live ? 300 : 150;
    if (rep === 0 || now - this.lastAction >= interval) {
      this.lastAction = now;
      if (live) this.changeChannel(direction); else this.seekBy(direction * (rep >= 5 ? 30000 : 10000));
    }
    return true;
  };
  PS.changeChannel = function (direction) {
    if (!this.queue) { this.message("Senderliste wird geladen …"); return; }
    if (this.queue.size() < 2) { this.message("In dieser Gruppe ist nur ein Sender vorhanden."); return; }
    this.playEntry(this.queue.move(direction));
  };
  PS.playEntry = function (next) {
    this.entry = next; this.currentNumber = next.number; this.key = Core.hash(this.p.scope + "|" + next.id);
    if (this.error) { this.error.close(); this.error = null; }
    if (this.menuMode) this.hideMenu();
    this.start(0); this.result = next.id; this.p.onZap && this.p.onZap(next); this.showBanner();
  };
  /** Links/rechts: Gruppe wechseln. Schnelles Mehrfachdrücken aktualisiert nur das Banner, gestartet wird die letzte Gruppe. */
  PS.switchGroup = function (direction) {
    var self = this;
    if (!this.queue || !this.live) return;
    var target = this.queue.neighbourGroup(this.pendingGroup != null ? this.pendingGroup : this.entry.group, direction);
    if (!target) return;
    this.pendingGroup = target.name; this.groupBanner.textContent = target.name + " · " + target.position + " von " + target.count; this.groupBanner.style.display = "";
    clearTimeout(this.timers.group); this.timers.group = setTimeout(function () { self.groupBanner.style.display = "none"; }, 2000);
    clearTimeout(this.timers.groupStart);
    this.timers.groupStart = setTimeout(function () { var wanted = self.pendingGroup; self.pendingGroup = null; var first = wanted == null || !self.queue ? null : self.queue.startGroup(wanted); if (first) self.playEntry(first); }, 250);
  };
  PS.enterDigit = function (d) {
    var self = this; if (!this.live) return;
    this.digits.enter(d, Date.now()); this.showEntry(this.digits.digits()); if (this.padDisplay) this.padDisplay.textContent = this.digits.digits();
    clearTimeout(this.timers.commit); this.timers.commit = setTimeout(function () { self.commitDigits(); }, Core.ChannelNavigator.DIGIT_WINDOW_MS);
  };
  PS.commitDigits = function () {
    clearTimeout(this.timers.commit);
    var number = this.digits.commitDigits(); this.entryView.style.display = "none"; if (this.padDisplay) this.padDisplay.textContent = "–";
    if (number <= 0 || !this.queue) return;
    var target = this.queue.byNumber(number);
    if (!target) { this.showEntry("Kanal " + number + " nicht vorhanden", 2000); return; }
    if (target.id === this.entry.id) { this.showBanner(); return; }
    this.playEntry(this.queue.jump(target));
  };
  PS.cancelDigits = function () { clearTimeout(this.timers.commit); this.digits.cancelDigits(); this.entryView.style.display = "none"; if (this.padDisplay) this.padDisplay.textContent = "–"; };
  PS.recallPrevious = function () { if (!this.queue) return; var prev = this.queue.previous(); if (prev) this.playEntry(prev); };
  PS.showEntry = function (text, forMs) {
    var self = this; this.entryView.textContent = text; this.entryView.style.display = ""; clearTimeout(this.timers.entry);
    if (forMs) this.timers.entry = setTimeout(function () { self.entryView.style.display = "none"; }, forMs);
  };
  /** Kanal-Banner unten: Nummer und Name (kein EPG wie auf Google TV), nach 4 Sekunden weg. */
  PS.showBanner = function () {
    var self = this; if (!this.live) return;
    this.channelNumber.textContent = this.currentNumber > 0 ? String(this.currentNumber) : ""; this.channelNumber.style.display = this.currentNumber > 0 ? "" : "none";
    this.channelName.textContent = this.entry.name || ""; this.channelBanner.style.display = "";
    clearTimeout(this.timers.banner); this.timers.banner = setTimeout(function () { self.channelBanner.style.display = "none"; }, 4000);
  };
  /** Zahlenfeld 3 × 4 für Fernbedienungen ohne Zifferntasten. */
  PS.showNumberPad = function () {
    var self = this; if (!this.live || this.pad) return;
    var shade = h("div", "dialog-shade"), box = h("div", "dialog pad");
    this.padDisplay = h("div", "t-title72 pad-display", this.digits.hasPendingDigits() ? this.digits.digits() : "–"); box.appendChild(this.padDisplay);
    var grid = h("div", "pad-grid");
    function close() { if (!shade.parentNode) return; shade.parentNode.removeChild(shade); UI.popLayer(shade, true); self.pad = null; self.padDisplay = null; UI.clearFocus(); }
    ["1", "2", "3", "4", "5", "6", "7", "8", "9", "✕", "0", "OK"].forEach(function (label) {
      var action = label === "✕" ? function () { self.cancelDigits(); close(); } : label === "OK" ? function () { self.commitDigits(); close(); } : function () { self.enterDigit(+label); };
      var b = button(label, action, { primary: label === "OK", label: label === "✕" ? "Abbrechen" : label === "OK" ? "Bestätigen" : "Ziffer " + label }); grid.appendChild(b);
    });
    box.appendChild(grid); shade.appendChild(box); document.getElementById("overlay").appendChild(shade);
    this.pad = shade; UI.pushLayer(shade, { onBack: function () { close(); } }); UI.focus(grid.children[0]);
    var padKeys = function (e, phase) { if (UI.topLayer() !== shade) return false; var d = UI.digitOf(e.keyCode); if (d >= 0) { if (phase === "down") self.enterDigit(d); return true; } return false; };
    UI.addKeyHandler(padKeys); var oldClose = close; close = function () { UI.removeKeyHandler(padKeys); oldClose(); };
  };
  PS.seekBy = function (delta) {
    if (this.live) return;
    if (!this.player.seekable()) { this.message("Dieser Stream lässt sich momentan nicht spulen."); return; }
    var target = Core.seekTarget(this.player.position(), this.player.duration(), delta); this.player.seekTo(target);
    this.message((delta > 0 ? "+" : "−") + Math.abs(delta) / 1000 + " s · " + clock(target));
  };
  PS.message = function (text) { UI.toast(text); };
  PS.save = function () {
    if (this.live || this.closed && this.saved) return;
    var dur = this.player.duration(), pos = this.player.position();
    if (this.ended || (dur > 0 && dur - pos < 10000)) pos = 0;
    this.lastPosition = pos;
    if (pos > 0) Store.Prefs.set("p:" + this.key, pos); else Store.Prefs.remove("p:" + this.key);
    if (dur > 0) Store.Prefs.set("pd:" + this.key, dur);
  };
  PS.suspend = function () { if (this.closed || this.suspended) return; this.save(); this.resumeAt = this.live ? 0 : this.lastPosition || 0; this.suspended = true; this.player.stop(); };
  PS.resume = function () { if (this.closed || !this.suspended) return; this.suspended = false; this.start(this.resumeAt); };
  PS.back = function () {
    if (this.digits.hasPendingDigits()) { this.cancelDigits(); return; }
    if (this.menuMode) { this.hideMenu(); return; }
    this.close();
  };
  PS.close = function () {
    if (this.closed) return;
    if (this.player.duration() > 0 || this.player.position() > 0) this.save();
    this.closed = true; this.saved = true;
    clearInterval(this.saveTimer); for (var t in this.timers) { clearTimeout(this.timers[t]); clearInterval(this.timers[t]); }
    this.player.stop(); UI.removeKeyHandler(this.keyHandler);
    if (this.error) this.error.close();
    if (this.el.parentNode) this.el.parentNode.removeChild(this.el);
    document.documentElement.classList.remove("playing");
    UI.popLayer(this.el, true);
    this.p.onClose && this.p.onClose(this.result || null);
  };

  // ---------- Multiview ----------
  /** Bis zu vier Sender gleichzeitig. Nur ein Bild hat Ton, die anderen laufen stumm. */
  function MultiviewScreen(o) {
    var self = this;
    this.catalog = o.catalog; this.lists = o.lists; this.favorites = o.favorites; this.onClose = o.onClose;
    this.slots = []; this.audio = null; this.layout = Store.Prefs.get("multiview:layout", "grid"); this.picker = null;
    var root = this.el = h("div", "multiview");
    this.grid = h("div", "mv-grid"); root.appendChild(this.grid);
    this.buildBar(); this.buildEmpty();
    document.getElementById("overlay").appendChild(root); document.documentElement.classList.add("multiview-on");
    UI.pushLayer(root, { onBack: function () { self.back(); } });
    this.keyHandler = function (e, phase) { return self.onKey(e, phase); }; UI.addKeyHandler(this.keyHandler);
    if (o.first) for (var i = 0; i < this.catalog.length; i++) if (this.catalog[i].id === o.first) { this.slots.push(this.slot(this.catalog[i])); break; }
    if (this.slots.length) this.audio = this.slots[0];
    this.refresh();
    UI.focus(this.slots.length ? this.slots[0].tile : this.emptyButton);
  }
  var MV = MultiviewScreen.prototype;
  MV.buildBar = function () {
    var self = this, bar = this.bar = h("div", "mv-bar");
    var words = h("div", "mv-words"); words.appendChild(h("div", "eyebrow small", "MULTIVIEW")); this.count = h("div", "t-small medium"); words.appendChild(this.count); bar.appendChild(words);
    this.add = button("+ Sender hinzufügen", function () { self.pick(-1); }, { primary: true }); bar.appendChild(this.add);
    this.arrange = button("", function () { self.chooseLayout(); }); bar.appendChild(this.arrange);
    bar.appendChild(button("Schliessen", function () { self.close(); }));
    this.el.appendChild(bar);
  };
  MV.buildEmpty = function () {
    var self = this, e = this.empty = h("div", "mv-empty");
    var t = h("div", "t-title52"); t.appendChild(UI.dotted("Mehrere Sender gleichzeitig.")); e.appendChild(t);
    e.appendChild(h("div", "t-body secondary mv-note", "Bis zu vier Bilder. Nur eines hat Ton – wähle es mit OK."));
    this.emptyButton = button("+ Sender wählen", function () { self.pick(-1); }, { primary: true }); e.appendChild(this.emptyButton);
    this.el.appendChild(e);
  };
  MV.slot = function (entry) {
    var self = this, s = { entry: entry };
    s.tile = h("div", "mv-tile f"); s.video = h("video"); s.video.setAttribute("playsinline", ""); s.tile.appendChild(s.video);
    s.label = h("div", "mv-label t-small medium"); s.tile.appendChild(s.label);
    s.tile._click = function () { self.setAudio(s); self.reveal(); };
    s.tile._long = function () { self.menu(s); };
    this.grid.appendChild(s.tile);
    this.start(s);
    return s;
  };
  MV.start = function (s) {
    var self = this; s.player = new Players.TilePlayer(s.video);
    s.player.play(s.entry.url, function () { if (s.player) s.label.textContent = self.lists.name(s.entry) + " · nicht verfügbar"; });
  };
  MV.stop = function (s) { if (s.player) { s.player.stop(); s.player = null; } };
  MV.setAudio = function (s) { this.audio = s; this.refresh(); };
  MV.refresh = function () {
    var self = this;
    this.slots.forEach(function (s) {
      var sound = s === self.audio;
      if (s.player) s.player.setSound(sound);
      if (s.label.textContent.indexOf("nicht verfügbar") < 0) s.label.textContent = (sound ? "🔊  " : "") + self.lists.name(s.entry);
      s.label.classList.toggle("secondary", !sound);
      s.tile.setAttribute("aria-label", self.lists.name(s.entry) + (sound ? ", Ton an" : ", stumm"));
    });
    this.count.textContent = this.slots.length + " von " + Core.MultiviewLayout.MAX + " Sendern";
    UI.setEnabled(this.add, this.slots.length < Core.MultiviewLayout.MAX);
    this.arrange.textContent = "Anordnung: " + Core.MultiviewLayout.label(this.layout) + " ⌄"; UI.setEnabled(this.arrange, this.slots.length > 1);
    this.empty.style.display = this.slots.length ? "none" : "";
    this.arrangeTiles(); this.reveal();
  };
  /** Legt die Bilder nach der gewählten Anordnung über die ganze Fläche; nur so viele Felder wie laufende Sender. */
  MV.arrangeTiles = function () {
    var w = 1920, hh = 1080, focus = Math.max(0, this.slots.indexOf(this.audio));
    var frames = Core.MultiviewLayout.frames(this.layout, this.slots.length, w, hh, focus), single = this.slots.length === 1, pip = Core.MultiviewLayout.overlaps(this.layout);
    this.slots.forEach(function (s, i) {
      var f = frames[i], floating = pip && i !== focus, full = single || (pip && !floating), gap = full ? 0 : 4, st = s.tile.style;
      st.left = Math.round(f[0]) + gap + "px"; st.top = Math.round(f[1]) + gap + "px"; st.width = Math.round(f[2]) - 2 * gap + "px"; st.height = Math.round(f[3]) - 2 * gap + "px";
      s.tile.classList.toggle("rounded", !full); s.tile.classList.toggle("floating", floating);
    });
  };
  MV.chooseLayout = function () {
    var self = this;
    UI.dialog({ title: "Anordnung", items: Core.MultiviewLayout.LABELS, onItem: function (n) { self.layout = Core.MultiviewLayout.KEYS[n]; Store.Prefs.set("multiview:layout", self.layout); self.refresh(); }, buttons: [{ label: "Abbrechen" }] });
  };
  MV.menu = function (s) {
    var self = this;
    UI.dialog({ title: this.lists.name(s.entry), items: ["Ton hier", "Anderen Sender wählen …", "Entfernen"], onItem: function (n) {
      if (n === 0) self.setAudio(s); else if (n === 1) self.pick(self.slots.indexOf(s)); else self.remove(s);
    }, buttons: [{ label: "Schliessen" }] });
  };
  MV.remove = function (s) {
    this.stop(s); this.grid.removeChild(s.tile); this.slots.splice(this.slots.indexOf(s), 1);
    if (this.audio === s) this.audio = this.slots.length ? this.slots[0] : null;
    this.refresh(); UI.focus(this.slots.length ? this.slots[0].tile : this.emptyButton);
  };
  MV.choose = function (e, replace) {
    this.closePicker();
    for (var i = 0; i < this.slots.length; i++) if (this.slots[i].entry.id === e.id) { UI.toast("Dieser Sender läuft schon im Multiview."); return; }
    if (replace >= 0 && replace < this.slots.length) { var r = this.slots[replace]; this.stop(r); r.entry = e; r.label.textContent = ""; this.start(r); this.refresh(); UI.focus(r.tile); return; }
    if (this.slots.length >= Core.MultiviewLayout.MAX) { UI.toast("Es sind höchstens " + Core.MultiviewLayout.MAX + " Bilder gleichzeitig möglich."); return; }
    var s = this.slot(e); this.slots.push(s); if (!this.audio) this.audio = s; this.refresh(); UI.focus(s.tile);
  };
  // Senderwahl: Quellen links (Favoriten, Kategorien), Logo-Raster rechts.
  MV.pick = function (replace) {
    var self = this, lists = this.lists; this.closePicker();
    var all = lists.visible(this.catalog), groups = {}, order = [], fav = [];
    all.forEach(function (e) { if (self.favorites[e.id]) fav.push(e); if (!groups[e.group]) { groups[e.group] = []; order.push(e.group); } groups[e.group].push(e); });
    var names = [], contents = [];
    if (fav.length) { names.push("★ Favoriten"); contents.push(fav); }
    lists.ordered("live", order).forEach(function (g) { names.push(lists.groupName("live", g)); contents.push(groups[g]); });
    var panel = this.picker = h("div", "mv-picker"), side = h("div", "mv-side");
    side.appendChild(h("div", "t-title32 mv-heading", replace >= 0 ? "Sender ersetzen" : "Sender hinzufügen"));
    var sources = h("div", "mv-sources scroller"); side.appendChild(sources); panel.appendChild(side);
    var tiles = h("div", "mv-tiles scroller"); panel.appendChild(tiles);
    var buttons = [];
    function show(list, focusFirst) {
      tiles.innerHTML = ""; tiles.scrollTop = 0;
      // Bei sehr grossen Gruppen nur die ersten 400 Logos (Fernseher-Speicher); die Gruppe bleibt über «Sender ersetzen» erreichbar.
      list.slice(0, 400).forEach(function (e) {
        var running = self.slots.some(function (s) { return s.entry.id === e.id; });
        var card = h("div", "mv-card f"), frame = h("div", "mv-frame"); frame.appendChild(Library.img(e.image, true)); card.appendChild(frame);
        card.appendChild(h("div", "t-small medium ellipsis mv-name", (running ? "✓ " : "") + lists.name(e)));
        if (running) card.style.opacity = ".5";
        card.setAttribute("aria-label", lists.name(e) + (running ? ", läuft schon" : ""));
        card._click = function () { self.choose(e, replace); };
        tiles.appendChild(card);
      });
      if (focusFirst && tiles.firstChild) UI.focus(tiles.firstChild);
    }
    names.forEach(function (n, i) {
      var b = button(n, null, { cls: "wide" });
      b._click = function () { buttons.forEach(function (o) { o.classList.toggle("selected", o === b); }); show(contents[i], true); };
      sources.appendChild(b); buttons.push(b);
    });
    if (!names.length) side.appendChild(h("div", "t-body", "Keine Sender verfügbar."));
    else { buttons[0].classList.add("selected"); show(contents[0], false); }
    this.el.appendChild(panel);
    UI.pushLayer(panel, { onBack: function () { self.closePicker(); if (self.slots.length) UI.focus(self.slots[0].tile); } });
    if (buttons.length) UI.focus(buttons[0]);
    clearTimeout(this.hideTimer);
  };
  MV.closePicker = function () { if (this.picker) { var p = this.picker; this.picker = null; p.parentNode.removeChild(p); UI.popLayer(p, true); this.reveal(); } };
  /** Die Leiste blendet sich nach 3 s aus (ausser ohne Bilder oder während der Senderwahl); der Fokus geht dann aufs Bild mit Ton. */
  MV.setControls = function (visible) {
    if (!visible && (!this.slots.length || this.picker)) return;
    var cur = UI.current();
    if (!visible && cur && this.bar.contains(cur)) UI.focus(this.slots[Math.max(0, this.slots.indexOf(this.audio))].tile);
    this.bar.style.visibility = visible ? "visible" : "hidden";
  };
  MV.reveal = function () { var self = this; this.setControls(true); clearTimeout(this.hideTimer); this.hideTimer = setTimeout(function () { self.setControls(false); }, 3000); };
  MV.onKey = function (e, phase) {
    if (UI.topLayer() !== this.el || phase !== "down") return false;
    var k = e.keyCode;
    if (UI.isBack(k)) return false;
    var hidden = this.bar.style.visibility === "hidden"; this.reveal();
    if (hidden && k === K.UP) return true;
    // Ein Bild über die ganze Fläche liegt unter der Leiste: Hoch führt dann direkt in die Leiste.
    if (k === K.UP && UI.current() && UI.current().classList.contains("mv-tile") && !UI.move("up")) {
      var first = UI.focusables(this.bar)[0]; if (first) UI.focus(first); return true;
    }
    if (k === K.TOOLS || k === K.MENU) { var cur = UI.current(); for (var i = 0; i < this.slots.length; i++) if (this.slots[i].tile === cur) { this.menu(this.slots[i]); return true; } }
    return false;
  };
  MV.suspend = function () { var self = this; this.slots.forEach(function (s) { self.stop(s); }); };
  MV.resume = function () { var self = this; this.slots.forEach(function (s) { if (!s.player) self.start(s); }); this.refresh(); };
  MV.back = function () { this.close(); };
  MV.close = function () {
    var self = this; clearTimeout(this.hideTimer);
    this.slots.forEach(function (s) { self.stop(s); });
    UI.removeKeyHandler(this.keyHandler);
    if (this.el.parentNode) this.el.parentNode.removeChild(this.el);
    document.documentElement.classList.remove("multiview-on");
    UI.popLayer(this.el); this.onClose && this.onClose();
  };

  root.Screens = { PlayerScreen: PlayerScreen, MultiviewScreen: MultiviewScreen };
})(this);
