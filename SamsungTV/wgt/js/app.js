/* Ablauf der App: 1:1 aus MainActivity.java (Anmeldung, Laden mit Zwischenspeicher, TV-Modus, Favoriten, Verlauf, Menüs). */
(function (root) {
  "use strict";
  var h = UI.h, button = UI.button, Prefs = Store.Prefs, Vault = Store.Vault, CatalogCache = Store.CatalogCache, NumberStore = Store.NumberStore, Catalog = Store.Catalog;
  var App = root.App = { VERSION: "1.0.0" };
  var cache = {}, generation = 0, source = null, previousSource = null, kind = "home", loginMode = "xtream", library = null;
  var favorites = {}, lists = null, current = [], history = [], autoStarted = false, player = null, multiview = null;
  var screen = document.getElementById("screen");

  function setScreen(el) { UI.clearFocus(); screen.innerHTML = ""; screen.appendChild(el); }
  function scopeKey(name) { return name + ":" + source.scope(); }

  // ---------- Start ----------
  function start() {
    registerKeys();
    var waiting = h("div", "waiting"); waiting.appendChild(h("div", "spinner big")); setScreen(waiting);
    var restored = null, failed = false;
    try {
      restored = Vault.load();
      var preset = root.IPTV_CONFIG && (root.IPTV_CONFIG.preset || root.IPTV_CONFIG.playlistUrl) || "";
      var selected = Core.choosePreset(restored, preset, Prefs.get("appliedPreset", ""));
      if (selected !== restored) { Vault.save(selected); Prefs.set("appliedPreset", selected.scope()); }
      restored = selected;
    } catch (e) { failed = true; restored = null; }
    if (!restored) { login(failed ? "Gespeicherter Zugang nicht lesbar. Bitte erneut anmelden." : ""); return; }
    source = restored; history = Vault.history(source.scope());
    NumberStore.preload(source.scope()).then(function () { readFavorites(); showLibrary(); load(); });
  }
  function registerKeys() {
    try {
      ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "PreCh", "ChannelUp", "ChannelDown", "MediaPlayPause", "MediaPlay", "MediaPause", "MediaStop",
        "MediaFastForward", "MediaRewind", "Info", "Tools"].forEach(function (k) { try { root.tizen.tvinputdevice.registerKey(k); } catch (e) {} });
    } catch (e) {}
  }

  // ---------- Anmeldung ----------
  function field(form, hint, secret) {
    var f = h("input", "field f login-field"); f.type = secret ? "password" : "text"; f.placeholder = hint; f.setAttribute("autocomplete", "off"); f.spellcheck = false;
    form.appendChild(f); return f;
  }
  function login(message) {
    generation++; library = null;
    var rootEl = h("div", "login screen"), form = h("div", "login-form");
    var mark = h("img", "login-mark"); mark.src = "img/lockup.png"; mark.alt = "IPTelevision+"; form.appendChild(mark);
    var modes = h("div", "segmented");
    var xtream = button("Xtream", function () { loginMode = "xtream"; login(""); }, { selected: loginMode === "xtream" });
    var m3u = button("M3U-Playlist", function () { loginMode = "m3u"; login(""); }, { selected: loginMode === "m3u" });
    modes.appendChild(xtream); modes.appendChild(m3u); form.appendChild(modes);
    form.appendChild(h("div", "t-body secondary center login-note", loginMode === "xtream" ? "Mit Xtream-Zugangsdaten anmelden" : "Adresse Deiner M3U-Playlist"));
    var address = field(form, loginMode === "xtream" ? "Server (z. B. https://anbieter.example:8080)" : "Playlist-Adresse (https://…)", false);
    var user = loginMode === "xtream" ? field(form, "Benutzername", false) : null, password = loginMode === "xtream" ? field(form, "Passwort", true) : null;
    var error = h("div", "t-small secondary center login-error", message); error.style.display = message ? "" : "none"; form.appendChild(error);
    var connect = button("Anmelden", null, { primary: true, cls: "wide tall" }); form.appendChild(connect);
    connect._click = function () {
      var candidate;
      try { candidate = new Core.Source(loginMode, address.value, user ? user.value : "", password ? password.value : ""); }
      catch (e) { error.textContent = "Bitte HTTP-/HTTPS-Adresse und Zugang vollständig prüfen."; error.style.display = ""; return; }
      UI.setEnabled(connect, false); error.textContent = "Quelle wird geprüft …"; error.style.display = ""; var ticket = ++generation;
      var catalog = new Catalog(candidate), list;
      NumberStore.preload(candidate.scope()).then(function () { return catalog.authenticate(); }).then(function () { return catalog.load("live"); }).then(function (l) {
        list = l; NumberStore.apply(candidate.scope(), list, true);
        if (!list.length && candidate.mode === "m3u") throw new Error();
        CatalogCache.save(candidate.scope(), candidate.mode === "xtream" ? "live" : "playlist", list);
        if (ticket !== generation) return;
        try { Vault.save(candidate); } catch (e) { UI.setEnabled(connect, true); error.textContent = "Der Zugang konnte nicht sicher gespeichert werden. Bitte erneut versuchen."; return; }
        source = candidate; previousSource = null; cache = {}; cache[candidate.mode === "xtream" ? "live" : "playlist"] = list; kind = "home"; history = Vault.history(candidate.scope());
        readFavorites(); showLibrary(); load();
      }).catch(function () {
        if (ticket !== generation) return;
        UI.setEnabled(connect, true); error.textContent = "Verbindung fehlgeschlagen. Adresse, Zugang und Netzwerk prüfen."; UI.focus(connect);
      });
    };
    if (previousSource) form.appendChild(button("Abbrechen", function () { generation++; source = previousSource; previousSource = null; NumberStore.preload(source.scope()).then(function () { showLibrary(); load(); }); }, { cls: "wide" }));
    form.appendChild(h("div", "t-small secondary center login-privacy", "Nur Player · Keine Inhalte enthalten · Zugang nur auf diesem Fernseher gespeichert"));
    rootEl.appendChild(form); setScreen(rootEl);
    UI.focus(address);
  }

  // ---------- Mediathek ----------
  function readFavorites() {
    favorites = {}; Prefs.get(scopeKey("favorites"), []).forEach(function (id) { favorites[id] = true; });
    lists = new Core.Lists(Prefs, source.scope()); if (library) library.setLists(lists);
  }
  function favoriteList() { return Object.keys(favorites); }
  function toggleFavorite(e) { if (favorites[e.id]) delete favorites[e.id]; else favorites[e.id] = true; Prefs.set(scopeKey("favorites"), favoriteList()); }
  function progressKey(e) { return Core.hash(source.scope() + "|" + e.id); }
  function position(e) { return Prefs.get("p:" + progressKey(e), 0); }
  function fraction(e) { var d = Prefs.get("pd:" + progressKey(e), 0); return d > 0 ? Math.min(0.999, position(e) / d) : 0; }
  function showLibrary() {
    library = new Library.LibraryView({
      navigate: function (next) { generation++; kind = next; library.activate(kind); load(); },
      open: function (e) { open(e); }, play: function (e) { play(e); }, menu: function (e) { menu(e); },
      search: function (q) { if (library) library.filter(q); }, action: function (a) { action(a); }
    }, { position: position, fraction: fraction });
    if (lists) library.setLists(lists);
    setScreen(library.el); library.activate(kind); library.initialFocus();
  }
  function load() {
    if (!source || !library) return;
    var ticket = ++generation, loadingKind = kind, loadingSource = source;
    library.setStatus("Inhalte werden geladen …");
    if (kind === "settings") { library.setStatus("IPTelevision+ · Deine Quellen bleiben auf diesem Gerät."); library.setData(current, favoriteList(), history); return; }
    // Nach der Anmeldung liegt die Senderliste schon im Speicher: sofort starten statt auf Filme und Serien zu warten.
    if (!autoStarted && (cache.live || cache.playlist)) { current = entriesFor(kind); library.setData(current, favoriteList(), history); maybeAutoStart(); }
    var existing = Object.assign({}, cache), updated = Object.assign({}, existing), failed = false, stale = [], catalog = new Catalog(loadingSource);
    var keys = loadingSource.mode === "m3u" ? ["playlist"] : (loadingKind === "home" || loadingKind === "search" || loadingKind === "favorites") ? ["live", "movie", "series"] : [loadingKind];
    var chain = Promise.resolve();
    keys.forEach(function (k) {
      if (updated[k]) return;
      chain = chain.then(function () {
        return obtain(loadingSource, k, k === "playlist" ? "live" : k, catalog, stale).then(function (list) { updated[k] = list; if (k === "live" || k === "playlist") startEarly(ticket, k, list); })
          .catch(function () { failed = true; });
      });
    });
    // Kontostatus nur beim ersten Laden und nach «Aktualisieren» prüfen, nicht bei jedem Tabwechsel.
    var check = Object.keys(existing).length === 0, expiry = 0, problem = null;
    chain.then(function () {
      if (!check) return;
      return catalog.authenticate().then(function (x) { expiry = x; }, function (e) { problem = e && e.message ? e.message : "Anbieter nicht erreichbar."; })
        .then(function () { if (problem === null && failed) problem = "Einige Inhalte konnten nicht geladen werden."; });
    }).then(function () {
      if (ticket !== generation || !library) return;
      if (check) library.setHealth(problem === null ? 1 : -1, problem, expiry);
      cache = updated; current = entriesFor(loadingKind);
      library.setData(current, favoriteList(), history); maybeAutoStart();
      library.setStatus(failed ? "Einige Inhalte konnten nicht geladen werden. Unter Einstellungen erneut laden." : current.length + " Inhalte · OK: öffnen · OK halten: Favoriten");
      if (stale.length) refreshInBackground(loadingSource, stale);
    });
  }
  /** Fernsehen zuerst: Sobald die Senderliste da ist (meist aus dem Zwischenspeicher), läuft der Autostart sofort. */
  function startEarly(ticket, key, live) {
    if (autoStarted || !live || !live.length) return;
    if (ticket !== generation || !library) return;
    cache[key] = live; current = entriesFor(kind); library.setData(current, favoriteList(), history); maybeAutoStart();
  }
  /** Katalogteil aus dem lokalen Zwischenspeicher, sonst aus dem Netz (und dann gespeichert). Alte Stände werden in stale gemerkt. */
  function obtain(s, key, apiKind, catalog, stale) {
    return CatalogCache.load(s.scope(), key).then(function (hit) {
      if (hit) { if (apiKind === "live") NumberStore.apply(s.scope(), hit.entries, true); if (hit.stale()) stale.push(key); return hit.entries; }
      return catalog.load(apiKind).then(function (loaded) {
        if (apiKind === "live") NumberStore.apply(s.scope(), loaded, true);
        if (loaded.length) CatalogCache.save(s.scope(), key, loaded);
        return loaded;
      });
    });
  }
  /** Lädt veraltete Teile still nach und speichert sie. Die Ansicht bleibt unverändert (kein Fokussprung). */
  function refreshInBackground(s, keys) {
    var catalog = new Catalog(s), fresh = {};
    keys.reduce(function (p, key) {
      return p.then(function () {
        var api = key === "playlist" ? "live" : key;
        return catalog.load(api).then(function (loaded) { if (api === "live") NumberStore.apply(s.scope(), loaded, true); if (loaded.length) { CatalogCache.save(s.scope(), key, loaded); fresh[key] = loaded; } });
      });
    }, Promise.resolve()).then(function () { if (source === s) Object.keys(fresh).forEach(function (k) { cache[k] = fresh[k]; }); }, function () {});
  }
  /** Alle geladenen Einträge, auch die in «Meine Listen» ausgeblendeten. */
  function allEntries() {
    if (source.mode === "m3u") return (cache.playlist || []).slice();
    return [].concat(cache.live || [], cache.movie || [], cache.series || []);
  }
  function entriesFor(screenKind) {
    var all = lists ? lists.visible(allEntries()) : allEntries();
    return all.filter(function (e) {
      if (screenKind === "home" || screenKind === "search" || screenKind === "settings" || screenKind === "favorites") return screenKind !== "favorites" || favorites[e.id];
      return screenKind === "series" ? e.kind === "series" || e.kind === "episode" : e.kind === screenKind;
    });
  }
  function open(e) {
    if (e.kind === "live") { play(e); return; }
    library.showDetail(e); var ticket = ++generation;
    if (source.mode === "m3u" || e.kind === "episode") { library.detailInfo(e, {}); return; }
    var c = new Catalog(source);
    c.detail(e).then(function (details) {
      var episodes = e.kind === "series" ? c.episodes(details) : [];
      if (ticket !== generation || !library) return;
      library.detailInfo(e, details); if (e.kind === "series") library.episodes(e, episodes);
    }).catch(function () { if (ticket === generation && library) library.detailError(e); });
  }
  function resolved(e) {
    if (source.mode !== "xtream" || e.kind === "series") return e;
    try {
      var id = e.id.slice(e.id.indexOf(":") + 1), path = Core.parseUrl(e.url).path, ext = path.slice(path.lastIndexOf(".") + 1);
      var r = Object.assign({}, e); r.url = source.stream(e.kind === "episode" ? "series" : e.kind === "movie" ? "movie" : "live", id, ext); return r;
    } catch (x) { return e; }
  }
  function play(entry) {
    var e = resolved(entry); if (!Core.isWeb(e.url) || player) return;
    remember(e);
    var live = e.kind === "live";
    player = new Screens.PlayerScreen({
      entry: e, live: live, key: progressKey(e), scope: source.scope(),
      queue: live ? new Core.PlaybackQueue(entriesFor("live"), e, source.scope(), liveGroupOrder()) : null,
      onZap: function (next) { remember(next); },
      onClose: function () {
        player = null;
        if (source && library) { UI.toast("Menü · Zurück: Fernsehen"); library.setData(current, favoriteList(), history); if (!UI.current() || !UI.current().isConnected) library.initialFocus(); }
      }
    });
  }
  /** Gruppen der sichtbaren Live-Sender in eigener Reihenfolge (Meine Listen). */
  function liveGroupOrder() { var g = [], seen = {}; entriesFor("live").forEach(function (e) { if (!seen[e.group]) { seen[e.group] = true; g.push(e.group); } }); return lists ? lists.ordered("live", g) : g; }
  /** Fernsehen zuerst: nach dem Laden läuft Kanal 1 (kleinste Nummer) oder, wenn gewählt, der zuletzt gesehene Sender. */
  function maybeAutoStart() {
    if (autoStarted || !source) return;
    var s = tvEntry(Prefs.get("startLast", false)); if (!s) return;
    autoStarted = true; play(s);
  }
  function tvEntry(preferLast) {
    var live = entriesFor("live"); if (!live.length) return null;
    if (preferLast) for (var i = 0; i < history.length; i++) if (history[i].kind === "live") for (var j = 0; j < live.length; j++) if (live[j].id === history[i].id) return live[j];
    var first = null; live.forEach(function (e) { if (e.number > 0 && (!first || e.number < first.number)) first = e; });
    return first || live[0];
  }
  function remember(e) {
    history = history.filter(function (x) { return x.id !== e.id; }); history.unshift(e); if (history.length > 30) history = history.slice(0, 30);
    try { Vault.saveHistory(source.scope(), history); } catch (x) { UI.toast("Verlauf konnte nicht gespeichert werden."); }
  }
  function menu(entry) {
    var favorite = !!favorites[entry.id], live = entry.kind === "live";
    var items = [entry.kind === "series" ? "Episoden öffnen" : live ? "Abspielen" : "Details öffnen", favorite ? "Aus Favoriten entfernen" : "Zu Favoriten hinzufügen"];
    if (live) items.push("Im Multiview ansehen", "Ausblenden");
    UI.dialog({ title: lists.name(entry), items: items, onItem: function (i) {
      if (i === 0) open(entry);
      else if (i === 1) { toggleFavorite(entry); library.setData(current, favoriteList(), history); }
      else if (i === 2) openMultiview(entry);
      else { lists.setHidden(entry, true); current = entriesFor(kind); library.setData(current, favoriteList(), history); UI.toast("Ausgeblendet. Wieder einblenden unter Einstellungen › Meine Listen.", true); }
    }, buttons: [{ label: "Schliessen" }] });
  }
  /** Öffnet das Multiview mit den sichtbaren Sendern (Adressen nur im Arbeitsspeicher). */
  function openMultiview(first) {
    if (!source) return;
    var live = entriesFor("live").map(resolved).filter(function (e) { return Core.isWeb(e.url); });
    if (!live.length) { UI.toast("Noch keine Sender geladen."); return; }
    multiview = new Screens.MultiviewScreen({ catalog: live, lists: lists, favorites: favorites, first: first ? first.id : null, onClose: function () { multiview = null; if (library) library.initialFocus(); } });
  }
  function editLists(page) {
    library.showPanel(new Library.ListEditor(lists, page, {
      all: allEntries, favorites: function () { return favorites; }, toggleFavorite: toggleFavorite,
      changed: function () { current = entriesFor(kind); library.setData(current, favoriteList(), history); },
      close: function () { library.closeDetail(); }
    }).el);
  }
  function action(a) {
    if (a === "back") { onBack(); return; }
    if (a === "lists") { editLists(kind === "live" ? "channels" : "categories"); return; }
    if (a === "multiview") { openMultiview(null); return; }
    if (a === "startmode") { var last = !Prefs.get("startLast", false); Prefs.set("startLast", last); UI.toast(last ? "Beim Start: zuletzt gesehener Kanal" : "Beim Start: Kanal 1"); return; }
    if (a === "reload") { cache = {}; CatalogCache.clear(); if (kind === "settings") { kind = "home"; library.activate(kind); } load(); return; }
    if (a === "choose") { chooseSource(); return; }
    if (a === "source") { previousSource = source; login(""); return; }
    if (a === "forget") UI.dialog({ message: "Gespeicherten Zugang und Verlauf von diesem Fernseher entfernen?", buttons: [
      { label: "Entfernen", primary: true, action: function () { generation++; Vault.forget(); CatalogCache.clear(); source = null; previousSource = null; cache = {}; history = []; login(""); } },
      { label: "Abbrechen" }] });
    if (a === "info") UI.dialog({ title: "IPTelevision+ · Samsung TV · " + App.VERSION,
      message: "Design der Apple-Version mit Logo-Kacheln, grosser Startseite, Filmplakaten und Detailansichten; für Fernbedienung angepasst.\n\nXtream/M3U, Live TV, Filme, Serien/Episoden, Suche, Favoriten, Weiterschauen, Meine Listen (Ausblenden, Umbenennen, Reihenfolge, Aufbau der Startseite) und Multiview mit bis zu vier Sendern.\n\nNoch nicht enthalten: EPG, Catch-up, Kindersicherung, iCloud-Sync und VLC-Fallback. Codec-Unterstützung hängt vom Fernseher ab.\n\nKeine Inhalte, Werbung oder Analyse. Bilder und Streams kommen von Deiner Quelle. HTTPS nach Möglichkeit verwenden.",
      buttons: [{ label: "Schliessen" }] });
  }
  function onBack() {
    if (UI.isEditing()) { UI.stopEditing(); return; }
    if (library && library.hasDetail()) { generation++; library.closeDetail(); return; }
    if (previousSource) { generation++; source = previousSource; previousSource = null; showLibrary(); load(); return; }
    if (library && kind !== "home") { kind = "home"; library.activate(kind); load(); UI.focus(library.tabs.home); return; }
    var tv = source ? tvEntry(true) : null; if (tv) { autoStarted = true; play(tv); return; }
    UI.dialog({ message: "IPTelevision+ beenden?", buttons: [{ label: "Beenden", primary: true, action: exit }, { label: "Bleiben" }] });
  }
  /** Eingebaute, benannte Quellen (z. B. «Durim», «Standard»); die erste ist die Voreinstellung. */
  function builtInSources() {
    var list = root.IPTV_CONFIG && root.IPTV_CONFIG.playlists || [];
    var out = [];
    list.forEach(function (p) { try { if (p && p.name) out.push({ name: p.name, source: p.mode ? Core.Source.from(p) : new Core.Source("m3u", p.url, "", "") }); } catch (e) {} });
    return out;
  }
  App.sourceName = function () {
    if (!source) return "";
    var hit = builtInSources().filter(function (p) { return p.source.scope() === source.scope(); })[0];
    return hit ? hit.name : "";
  };
  App.hasChoice = function () { return builtInSources().length > 1; };
  function chooseSource() {
    var list = builtInSources(), currentName = App.sourceName();
    UI.dialog({ title: "Quelle wählen", items: list.map(function (p) { return (p.name === currentName ? "✓ " : "") + p.name; }), onItem: function (i) {
      var next = list[i].source;
      if (source && next.scope() === source.scope()) return;
      try { Vault.save(next); } catch (e) { UI.toast("Der Zugang konnte nicht gespeichert werden."); return; }
      generation++; if (player) player.close(); source = next; previousSource = null; cache = {}; kind = "home"; autoStarted = false; history = Vault.history(source.scope());
      NumberStore.preload(source.scope()).then(function () { readFavorites(); showLibrary(); load(); UI.toast("Quelle: " + list[i].name); });
    }, buttons: [{ label: "Abbrechen" }] });
  }
  function exit() { try { root.tizen.application.getCurrentApplication().exit(); } catch (e) { try { window.close(); } catch (x) {} } }
  UI.onBack = onBack;

  // Wie onStop/onStart auf Android: im Hintergrund (Home-Taste) Wiedergabe anhalten und Stand sichern, danach fortsetzen.
  document.addEventListener("visibilitychange", function () {
    if (player) { if (document.hidden) player.suspend(); else player.resume(); }
    if (multiview) { if (document.hidden) multiview.suspend(); else multiview.resume(); }
  });

  App.start = start;
  start();
})(this);
