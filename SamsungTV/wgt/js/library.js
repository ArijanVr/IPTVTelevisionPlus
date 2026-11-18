/* Oberfläche der Mediathek: 1:1 aus LibraryView.java und ListEditor.java. Masse: Android-dp × 2 = Pixel bei 1920 × 1080.
   Reihen und Karten werden nur im sichtbaren Bereich gebaut (wie RecyclerView), damit grosse Kataloge flüssig bleiben. */
(function (root) {
  "use strict";
  var h = UI.h, button = UI.button, Lists = Core.Lists;
  var OX = 96;
  function img(src, logo) {
    var i = h("img", "art" + (logo ? " logo" : "")); i.alt = "";
    if (src) { i.onerror = function () { i.style.visibility = "hidden"; }; i.src = src; } else i.style.visibility = "hidden";
    return i;
  }

  // ---------- Shelf: senkrechte Liste von Reihen mit festen Höhen ----------
  function Shelf() {
    var self = this;
    this.el = h("div", "shelf"); this.inner = h("div", "shelf-inner"); this.el.appendChild(this.inner);
    this.rows = []; this.tops = []; this.total = 0; this.scrollY = 0; this.nodes = {}; this.bottomPad = 126;
    this.inner._reveal = function (el) { self.reveal(el); };
  }
  Shelf.prototype.setRows = function (rows, keepScroll) {
    this.rows = rows; this.tops = []; var y = 4;
    for (var i = 0; i < rows.length; i++) { this.tops.push(y); y += rows[i].height; }
    this.total = y;
    for (var k in this.nodes) if (this.nodes[k].parentNode) this.nodes[k].parentNode.removeChild(this.nodes[k]);
    this.nodes = {};
    if (!keepScroll) this.scrollY = 0;
    this.clamp(); this.apply(); this.renderWindow();
  };
  Shelf.prototype.viewH = function () { return this.el.clientHeight || 800; };
  Shelf.prototype.clamp = function () { this.scrollY = Math.max(0, Math.min(this.scrollY, Math.max(0, this.total + this.bottomPad - this.viewH()))); };
  Shelf.prototype.apply = function () { this.inner.style.transform = "translateY(" + (-this.scrollY) + "px)"; };
  Shelf.prototype.renderWindow = function () {
    var top = this.scrollY - 700, bottom = this.scrollY + this.viewH() + 700, cur = UI.current();
    for (var i = 0; i < this.rows.length; i++) {
      var inside = this.tops[i] < bottom && this.tops[i] + this.rows[i].height > top, node = this.nodes[i];
      if (inside && !node) {
        node = h("div", "row"); node.style.top = this.tops[i] + "px"; node.style.height = this.rows[i].height + "px"; node.dataset.row = i;
        this.rows[i].render(node); this.inner.appendChild(node); this.nodes[i] = node;
      } else if (!inside && node && !(cur && node.contains(cur))) { node.parentNode.removeChild(node); delete this.nodes[i]; }
    }
  };
  Shelf.prototype.reveal = function (el) {
    var row = el; while (row && row.parentNode !== this.inner) row = row.parentNode;
    if (!row) return;
    var y = 0; for (var p = el; p && p !== this.inner; p = p.offsetParent) y += p.offsetTop;
    var hgt = el.offsetHeight, pad = 40, view = this.viewH();
    if (y - pad < this.scrollY) this.scrollY = y - pad;
    else if (y + hgt + pad > this.scrollY + view - 60) this.scrollY = y + hgt + pad - view + 60;
    this.clamp(); this.apply(); this.renderWindow();
  };
  Shelf.prototype.node = function (i) { return this.nodes[i] || null; };
  Shelf.prototype.scrollToTop = function () { this.scrollY = 0; this.apply(); this.renderWindow(); };

  // ---------- Horizontale Reihe (Rail) ----------
  /** items: Einträge; step: Kartenabstand; build(entry, index, x) -> Karte. state: {sx, index} bleibt je Reihe erhalten. */
  function Rail(container, items, step, width, build, state) {
    var self = this;
    this.items = items; this.step = step; this.build = build; this.state = state; this.cards = {};
    this.view = h("div", "rail"); this.track = h("div", "track"); this.view.appendChild(this.track); container.appendChild(this.view);
    this.visW = width;
    this.view._reveal = function (card) { self.revealCard(card); };
    this.apply(); this.render();
  }
  Rail.prototype.apply = function () { this.track.style.transform = "translateX(" + (-this.state.sx) + "px)"; };
  Rail.prototype.render = function () {
    var first = Math.max(0, Math.floor(this.state.sx / this.step) - 2), last = Math.min(this.items.length - 1, Math.ceil((this.state.sx + this.visW) / this.step) + 2), cur = UI.current();
    for (var k in this.cards) { var i = +k; if ((i < first || i > last) && !(cur && this.cards[k] === cur)) { this.track.removeChild(this.cards[k]); delete this.cards[k]; } }
    for (var j = first; j <= last; j++) if (!this.cards[j]) { var c = this.build(this.items[j], j, j * this.step); c.dataset.index = j; this.cards[j] = c; this.track.appendChild(c); }
  };
  Rail.prototype.revealCard = function (card) {
    var i = +card.dataset.index, left = i * this.step, s = this.state;
    s.index = i;
    if (left < s.sx) s.sx = left;
    else if (left + this.step > s.sx + this.visW) s.sx = left + this.step - this.visW;
    s.sx = Math.max(0, s.sx); this.apply(); this.render();
  };
  Rail.prototype.card = function (i) { return this.cards[i] || null; };

  // ---------- LibraryView ----------
  function LibraryView(actions, progress) {
    var self = this;
    this.actions = actions; this.progress = progress;
    this.entries = []; this.history = []; this.favorites = {}; this.kind = "home"; this.selectedGroup = "Alle"; this.query = ""; this.mode = "Sender";
    this.favoriteOnly = false; this.detail = null; this.detailView = null; this.heroIndex = 0; this.heroItems = []; this.lists = new Lists(Store.Prefs, "");
    this.sections = []; this.railStates = {}; this.statusText = ""; this.expiryText = ""; this.tabs = {};
    var el = this.el = h("div", "library screen");
    // Kopf: Logo links, Menüband in der Bildschirmmitte, rechts Status-Punkt und Aktualisieren.
    var header = h("div", "header");
    var mark = h("img", "lockup"); mark.src = "img/lockup.png"; mark.alt = "IPTelevision+"; header.appendChild(mark);
    var nav = h("div", "nav");
    var keys = ["home", "live", "movie", "series", "favorites", "search", "settings"], labels = ["Jetzt", "Live", "Filme", "Serien", "Mediathek", "Suche", "Profil"];
    keys.forEach(function (key, i) { var b = button(labels[i], function () { actions.navigate(key); }, { cls: "tab" }); nav.appendChild(b); self.tabs[key] = b; });
    header.appendChild(nav);
    var pstatus = h("div", "pstatus");
    this.healthDot = h("div", "dot"); this.healthDot.setAttribute("aria-label", "Playlist wird geprüft"); pstatus.appendChild(this.healthDot);
    var refresh = button("↻", function () { actions.action("reload"); }, { cls: "tab", label: "Playlist aktualisieren" }); pstatus.appendChild(refresh);
    header.appendChild(pstatus);
    el.appendChild(header);
    this.tools = h("div", "tools"); this.title = h("div", "tools-title t-title", "Jetzt"); this.tools.appendChild(this.title); el.appendChild(this.tools);
    this.search = h("input", "search field f"); this.search.type = "text"; this.search.placeholder = "Sender, Filme und Serien suchen"; this.search.setAttribute("autocomplete", "off");
    var searchTimer = null;
    this.search.addEventListener("input", function () { clearTimeout(searchTimer); searchTimer = setTimeout(function () { self.query = self.search.value; actions.search(self.query); }, 250); });
    el.appendChild(this.search); this.search.style.display = "none";
    this.stage = h("div", "stage"); el.appendChild(this.stage);
    this.shelf = new Shelf(); this.stage.appendChild(this.shelf.el);
    this.status = h("div", "status"); this.stage.appendChild(this.status);
  }
  var P = LibraryView.prototype;
  P.label = function (v) { return { home: "Jetzt", live: "Live", movie: "Filme", series: "Serien", search: "Suche", favorites: "Mediathek" }[v] || "Profil und Einstellungen"; };
  /** @param state 1 = aktiv (grün), -1 = Problem (rot), 0 = unbekannt (grau). @param expirySeconds Ablauf des Abos, 0 = unbekannt. */
  P.setHealth = function (state, problem, expirySeconds) {
    this.healthDot.className = "dot" + (state > 0 ? " ok" : state < 0 ? " bad" : "");
    this.healthDot.setAttribute("aria-label", state > 0 ? "Playlist aktiv" : state < 0 ? "Playlist-Problem: " + problem : "Playlist wird geprüft");
    var left = expirySeconds * 1000 - Date.now();
    if (expirySeconds <= 0) this.expiryText = "";
    else if (left <= 0) this.expiryText = "Abo abgelaufen";
    else { var d = new Date(expirySeconds * 1000); this.expiryText = "Gültig bis " + ("0" + d.getDate()).slice(-2) + "." + ("0" + (d.getMonth() + 1)).slice(-2) + "." + d.getFullYear(); }
    this.setStatus(this.statusText);
  };
  P.setStatus = function (text) { this.statusText = text; this.status.textContent = this.expiryText ? text + " · " + this.expiryText : text; };
  P.setLists = function (lists) { this.lists = lists; this.render(); };
  P.areaOf = function (key) { return key === "movie" || key === "series" ? key : "live"; };
  P.activate = function (next) {
    var self = this;
    if (this.hasDetail()) this.closeDetail(true);
    var changed = this.kind !== next; this.kind = next;
    if (changed) { this.selectedGroup = "Alle"; this.favoriteOnly = false; this.query = ""; this.mode = "Sender"; this.search.value = ""; this.heroIndex = 0; }
    Object.keys(this.tabs).forEach(function (k) { self.tabs[k].classList.toggle("selected", k === self.kind); });
    this.title.textContent = this.label(next);
    this.tools.style.display = next === "home" ? "none" : "";
    this.search.style.display = next === "search" ? "" : "none";
    var cur = UI.current(), focusedTool = cur && this.tools.contains(cur) ? cur.textContent : null;
    while (this.tools.children.length > 1) this.tools.removeChild(this.tools.lastChild);
    function add(b) { self.tools.appendChild(b); return b; }
    if (next === "live") {
      add(button("Sender", function () { self.mode = "Sender"; self.activate(self.kind); self.render(); }, { selected: this.mode === "Sender" }));
      add(button("Kategorien", function () { self.mode = "Kategorien"; self.activate(self.kind); self.render(); }, { selected: this.mode === "Kategorien" }));
      add(button("▦ Multiview", function () { self.actions.action("multiview"); }));
    }
    if (next === "live" || next === "movie" || next === "series") {
      add(button(this.selectedGroup === "Alle" ? "Alle Gruppen ⌄" : this.lists.groupName(this.areaOf(next), this.selectedGroup) + " ⌄", function () { self.chooseGroup(); }));
      add(button(this.favoriteOnly ? "★ Favoriten" : "☆ Favoriten", function () { self.favoriteOnly = !self.favoriteOnly; self.activate(self.kind); self.render(); }, { selected: this.favoriteOnly }));
      add(button("Listen bearbeiten", function () { self.actions.action("lists"); }));
    }
    if (focusedTool !== null) {
      var restored = false;
      for (var i = 1; i < this.tools.children.length; i++) if (this.tools.children[i].textContent === focusedTool) { UI.focus(this.tools.children[i]); restored = true; break; }
      if (!restored && this.tools.children.length > 1) UI.focus(this.tools.children[1]);
    }
    if (changed) this.shelf.scrollToTop();
  };
  P.setData = function (entries, favorites, history) {
    this.entries = entries.slice(); this.favorites = {}; var f = this.favorites; favorites.forEach(function (id) { f[id] = true; }); this.history = history.slice(); this.render();
  };
  P.initialFocus = function () { UI.focus(this.tabs[this.kind]); };
  P.filter = function (text) { this.query = text; this.render(); };
  /** Gruppen in der eigenen Reihenfolge aus «Meine Listen». */
  P.grouped = function (source) {
    var raw = {}, order = [];
    source.forEach(function (e) { if (!raw.hasOwnProperty(e.group)) { raw[e.group] = []; order.push(e.group); } raw[e.group].push(e); });
    return this.lists.ordered(this.areaOf(this.kind), order).map(function (g) { return [g, raw[g]]; });
  };
  P.chooseGroup = function () {
    var self = this, groups = ["Alle"].concat(this.grouped(this.entries).map(function (x) { return x[0]; }));
    UI.dialog({ title: "Kategorie wählen", items: groups.map(function (g, i) { return i === 0 ? "Alle" : self.lists.groupName(self.areaOf(self.kind), g); }),
      onItem: function (i) { self.selectedGroup = groups[i]; self.mode = "Sender"; self.activate(self.kind); self.render(); self.shelf.scrollToTop(); },
      buttons: [{ label: "Abbrechen" }] });
  };
  function ofKind(list, key) { return list.filter(function (e) { return key === "series" ? e.kind === "series" || e.kind === "episode" : e.kind === key; }); }
  function limit(list, n) { return list.slice(0, n); }

  P.render = function () {
    var self = this, sections = [], lists = this.lists, favs = this.favorites;
    function rail(name, list, poster) { if (list.length) sections.push({ type: 0, name: name, list: list, poster: poster }); }
    if (this.kind === "settings") sections.push({ type: 4 });
    else if (this.kind === "home") {
      var resumed = this.history.filter(function (e) { return e.kind !== "live" && self.progress.position(e) > 1000; });
      var visibleHistory = lists.visible(this.history), last = limit(ofKind(visibleHistory, "live"), 1);
      var fav = this.entries.filter(function (e) { return favs[e.id]; });
      resumed = lists.visible(resumed);
      var hero = limit(resumed, 3).concat(last);
      ofKind(fav, "live").forEach(function (e) { if (!hero.some(function (x) { return x.id === e.id; })) hero.push(e); });
      if (!hero.length) hero = limit(ofKind(this.entries, "live"), 4);
      if (!hero.length) hero = limit(this.entries, 4);
      this.heroItems = hero;
      // Reihen in der Reihenfolge aus «Meine Listen»; nur echte Inhalte der Quelle, nie mitgelieferte Beispiele.
      lists.visibleSections().forEach(function (s) {
        if (s === "hero") { if (hero.length) { self.heroIndex = Math.min(self.heroIndex, hero.length - 1); sections.push({ type: 1, entry: hero[self.heroIndex] }); } }
        else if (s === "continue") rail("Weiterschauen", resumed, false);
        else if (s === "last") rail("Zuletzt gesehen", last, false);
        else if (s === "favorites") rail("Favoriten", fav, false);
        else if (s === "live") { if (!fav.length) rail("Live TV", limit(ofKind(self.entries, "live"), 20), false); }
        else if (s === "movies") rail("Neue Filme", limit(ofKind(self.entries, "movie"), 20), true);
        else if (s === "series") rail("Neue Serien", limit(ofKind(self.entries, "series"), 20), true);
      });
    } else {
      var term = this.query.toLowerCase(), g = this.selectedGroup, fo = this.favoriteOnly;
      var filtered = this.entries.filter(function (e) { return (g === "Alle" || e.group === g) && (!fo || favs[e.id]) && (!term || lists.name(e).toLowerCase().indexOf(term) >= 0); });
      if (this.kind === "live" && this.mode === "Kategorien") {
        var cats = this.grouped(filtered);
        for (var i = 0; i < cats.length; i += 3) sections.push({ type: 2, cats: cats.slice(i, i + 3) });
      } else if (this.kind === "search" || this.kind === "favorites") {
        rail("Sender", ofKind(filtered, "live"), false); rail("Filme", ofKind(filtered, "movie"), true); rail("Serien & Episoden", ofKind(filtered, "series"), true);
      } else this.grouped(filtered).forEach(function (x) { rail(x[0], x[1], self.kind !== "live"); });
    }
    if (!sections.length && this.kind === "favorites") sections.push({ type: 3, name: "Noch nichts gemerkt.", description: "Halte OK bei einem Sender, Film oder einer Serie gedrückt und wähle «Favorit». Er erscheint dann hier." });
    if (!sections.length) sections.push({ type: 3, name: this.kind === "search" ? "Keine passenden Inhalte gefunden." : "Hier erscheinen Deine Inhalte.",
      description: this.kind === "home" ? "Füge Favoriten hinzu oder starte einen Sender, Film oder eine Serie." : "Wähle eine andere Kategorie oder lade die Quelle erneut." });
    this.sections = sections; this.refresh();
  };
  /** Baut die Reihen neu; der Fokus bleibt auf derselben Reihe und Position (wie notifyDataSetChanged). */
  P.refresh = function () {
    var self = this, cur = UI.current(), rowIndex = -1, cardIndex = -1, inShelf = cur && this.shelf.inner.contains(cur);
    if (inShelf) { var r = cur; while (r && !r.dataset.row) r = r.parentNode; if (r) rowIndex = +r.dataset.row; if (cur.dataset.index) cardIndex = +cur.dataset.index; if (cur.dataset.slot) cardIndex = +cur.dataset.slot; }
    var rows = this.sections.map(function (s) { return self.rowFor(s); });
    if (inShelf) UI.clearFocus();
    this.shelf.setRows(rows, true);
    if (inShelf && !this.hasDetail()) {
      rowIndex = Math.min(rowIndex, rows.length - 1);
      var node = this.shelf.node(rowIndex), target = null;
      if (node) {
        var list = UI.focusables(node);
        list.forEach(function (c) { if ((c.dataset.index && +c.dataset.index === cardIndex) || (c.dataset.slot && +c.dataset.slot === cardIndex)) target = c; });
        target = target || list[0];
      }
      if (target) UI.focus(target); else { var all = UI.focusables(this.shelf.inner); if (all.length) UI.focus(all[0]); else this.initialFocus(); }
    }
  };
  P.fontRow = function () { return this.lists.showNames(); };
  P.rowFor = function (s) {
    var self = this;
    if (s.type === 1) return { height: 680 + 16, render: function (n) { n.appendChild(self.hero(s.entry)); } };
    if (s.type === 2) return { height: 260, render: function (n) {
      var row = h("div", "catrow");
      s.cats.forEach(function (c, i) {
        var tile = h("div", "cattile f"); tile.dataset.slot = i;
        tile.appendChild(h("div", "t-title28", self.lists.groupName("live", c[0])));
        tile.appendChild(h("div", "t-small secondary", c[1].length + " Sender"));
        tile.setAttribute("aria-label", self.lists.groupName("live", c[0]) + ", " + c[1].length + " Sender");
        tile._click = function () { self.selectedGroup = c[0]; self.mode = "Sender"; self.activate(self.kind); self.render(); };
        row.appendChild(tile);
      });
      n.appendChild(row);
    } };
    if (s.type === 3) return { height: 420, render: function (n) {
      var box = h("div", "empty"); box.appendChild(h("div", "t-title32", s.name)); box.appendChild(h("div", "t-body secondary empty-note", s.description));
      box.appendChild(button("Quelle neu laden", function () { self.actions.action("reload"); })); n.appendChild(box);
    } };
    if (s.type === 4) return { height: App.hasChoice() ? 1280 : 1160, render: function (n) { n.appendChild(self.settingsPanel()); } };
    // Rail
    var live = !s.poster, tw = this.lists.tileWidth(), names = this.lists.showNames();
    var cw = s.poster ? 288 : tw * 2, step = cw + 28, frameH = s.poster ? 396 : Math.round(cw * 9 / 16);
    var railH = s.poster ? 624 : (Math.round(tw * 9 / 16) + (names ? 58 : 0) + 34) * 2;
    var groupRow = this.kind !== "home" && this.kind !== "search" && this.kind !== "favorites";
    var key = this.kind + "|" + s.name + "|" + (s.poster ? 1 : 0);
    var state = this.railStates[key] || (this.railStates[key] = { sx: 0, index: 0 });
    if (state.sx > Math.max(0, s.list.length * step - 1500)) { state.sx = 0; state.index = 0; }
    return { height: 56 + railH, render: function (n) {
      n.appendChild(h("div", "rail-heading t-title28", groupRow ? self.lists.groupName(self.areaOf(self.kind), s.name) : s.name));
      var holder = h("div", "rail-holder"); holder.style.height = railH + "px"; n.appendChild(holder);
      new Rail(holder, s.list, step, 1920 - 32 - 112, function (e, i, x) { return self.card(e, s.poster, x, cw, frameH); }, state);
    } };
  };
  /** Karte: Poster (2:3) oder 16:9-Fläche, bei Sendern mit dem Logo gross in der Mitte. Fokusring nur um die Bildfläche. */
  P.card = function (e, poster, x, cw, frameH) {
    var self = this, lists = this.lists, live = e.kind === "live", names = poster || !live || lists.showNames();
    var title = (live && e.number > 0 ? e.number + "  " : "") + lists.name(e), fav = this.favorites[e.id];
    var card = h("div", "card f" + (poster ? " poster" : "")); card.style.left = x + "px"; card.style.width = cw + "px";
    var frame = h("div", "frame"); frame.style.height = frameH + "px";
    var art = img(e.image, live);
    if (live) { var inset = Math.max(10, lists.tileWidth() / 10) * 2; art.style.padding = Math.round(inset * 3 / 4) + "px " + inset + "px"; }
    frame.appendChild(art);
    var fraction = this.progress.fraction(e);
    if (fraction > 0) { var bar = h("div", "bar"), fill = h("i"); fill.style.width = (fraction * 100) + "%"; bar.appendChild(fill); frame.appendChild(bar); }
    if (!names) frame.appendChild(h("div", "caption", title));
    card.appendChild(frame);
    if (names) {
      var name = h("div", "name" + (poster ? " two" : ""), (fav ? "★ " : "") + title); card.appendChild(name);
      card.appendChild(h("div", "meta", e.subtitle ? e.subtitle : live ? lists.groupName("live", e.group) : ""));
    }
    card.setAttribute("aria-label", title + (fav ? ", Favorit" : ""));
    card._click = function () { self.actions.open(e); };
    card._long = function () { self.actions.menu(e); };
    return card;
  };
  P.hero = function (e) {
    var self = this, lists = this.lists, hero = h("div", "hero");
    var back = img(e.image, false); back.className = "art backdrop"; hero.appendChild(back);
    hero.appendChild(h("div", "hero-h")); hero.appendChild(h("div", "hero-v"));
    if (e.kind === "live") { var logo = img(e.image, true); logo.className = "art hero-logo"; hero.appendChild(logo); }
    var words = h("div", "hero-words"), pos = this.progress.position(e);
    var eyebrow = e.kind !== "live" && pos > 1000 ? "WEITERSCHAUEN" : this.favorites[e.id] ? "FAVORIT" : this.history.some(function (x) { return x.id === e.id; }) ? "ZULETZT GESEHEN" : "LIVE TV";
    words.appendChild(h("div", "eyebrow", eyebrow));
    var headline = h("div", "headline"); headline.appendChild(UI.dotted(lists.name(e) + ".")); words.appendChild(headline);
    words.appendChild(h("div", "hero-sub t-body secondary", e.subtitle ? e.subtitle : e.group));
    var buttons = h("div", "hero-buttons");
    buttons.appendChild(button(e.kind === "live" ? "▶ Live ansehen" : e.kind === "series" ? "Episoden öffnen" : pos > 1000 ? "▶ Fortsetzen" : "▶ Abspielen",
      function () { if (e.kind === "series") self.actions.open(e); else self.actions.play(e); }, { primary: true }));
    buttons.appendChild(button(this.favorites[e.id] ? "★ Favorit" : "☆ Zu Favoriten", function () { self.actions.menu(e); }, { label: "Favorit verwalten: " + lists.name(e) }));
    words.appendChild(buttons); hero.appendChild(words);
    if (this.heroItems.length > 1) {
      var next = button("›", function () { self.heroIndex = (self.heroIndex + 1) % self.heroItems.length; self.render(); }, { cls: "hero-next", label: "Nächstes Titelbild" });
      next.dataset.slot = 9; hero.appendChild(next);
      hero.appendChild(h("div", "hero-dots t-small secondary", (this.heroIndex + 1) + " / " + this.heroItems.length));
    }
    return hero;
  };
  P.settingsPanel = function () {
    var self = this, pane = h("div", "settings");
    pane.appendChild(h("div", "t-title28 settings-heading", "Quelle & Wiedergabe"));
    var keys = ["lists", "multiview", "startmode", "reload", "source", "forget", "info"],
      labels = ["Meine Listen und «Jetzt»", "Multiview", "Beim Start: Kanal 1 oder zuletzt gesehen", "Quelle neu laden", "Anderen Zugang verwenden", "Gespeicherten Zugang entfernen", "Über IPTelevision+ & Funktionsumfang"];
    if (App.hasChoice()) { keys.unshift("choose"); labels.unshift("Quelle: " + (App.sourceName() || "eigene") + " ⌄"); }
    keys.forEach(function (k, i) { var b = button(labels[i], function () { self.actions.action(k); }, { cls: "wide" }); b.dataset.slot = i; pane.appendChild(b); });
    pane.appendChild(h("div", "t-small secondary settings-note", "IPTelevision+ · Samsung TV · " + App.VERSION + "\nKeine Inhalte · Keine Werbung · Keine Analyse"));
    return pane;
  };

  // ---------- Detailseite und eigene Flächen ----------
  P.hasDetail = function () { return !!(this.detail || this.detailView); };
  /** Zeigt eine eigene Fläche (z. B. «Meine Listen») anstelle der Reihen; Zurück schliesst sie wie eine Detailseite. */
  P.showPanel = function (panel) { var cur = UI.current(); this.closeDetail(true); this.returnFocus = cur; this.shelf.el.style.display = "none"; this.detailView = panel; this.stage.insertBefore(panel, this.status); };
  P.closeDetail = function (silent) {
    this.detail = null; this.detailPlot = null; this.episodeHost = null; this.seasons = null;
    if (this.detailView && this.detailView.parentNode) this.detailView.parentNode.removeChild(this.detailView);
    var had = !!this.detailView; this.detailView = null; this.shelf.el.style.display = "";
    var back = this.returnFocus; this.returnFocus = null;
    if (had && !silent) { this.shelf.renderWindow(); if (back && back.isConnected && this.shelf.inner.contains(back)) { UI.focus(back); return; } var l = UI.focusables(this.shelf.inner); if (l.length) UI.focus(l[0]); else this.initialFocus(); }
  };
  P.showDetail = function (e) {
    var self = this, cur = UI.current();
    this.closeDetail(true); this.returnFocus = cur; this.detail = e; this.shelf.el.style.display = "none";
    var scroll = h("div", "detail scroller"), body = h("div", "detail-body"); scroll.appendChild(body);
    this.detailView = scroll; this.stage.insertBefore(scroll, this.status);
    var back = button("‹ Zurück", function () { self.actions.action("back"); }); body.appendChild(back);
    var header = h("div", "detail-header"); body.appendChild(header);
    var poster = h("div", "detail-poster"); poster.appendChild(img(e.image, false)); header.appendChild(poster);
    var info = h("div", "detail-info"); header.appendChild(info);
    info.appendChild(h("div", "t-title40 clamp3", e.name));
    info.appendChild(h("div", "t-body secondary detail-meta", e.subtitle ? e.subtitle : e.group));
    var first = back;
    if (e.kind !== "series") { var play = button(this.progress.position(e) > 1000 ? "▶ Fortsetzen" : "▶ Abspielen", function () { self.actions.play(e); }, { primary: true, cls: "tall" }); info.appendChild(play); first = play; }
    var fav = button(this.favorites[e.id] ? "★ Favorit verwalten" : "☆ Zu Favoriten", function () { self.actions.menu(e); }, { cls: "spaced" }); info.appendChild(fav);
    this.detailPlot = h("div", "t-body secondary detail-plot", e.kind === "episode" ? e.group : "Details werden geladen …"); info.appendChild(this.detailPlot);
    this.episodeHost = h("div", "episodes"); body.appendChild(this.episodeHost);
    UI.focus(first);
  };
  P.detailInfo = function (e, response) {
    if (!this.detail || this.detail.id !== e.id || !this.detailPlot) return;
    var info = response && response.info;
    if (!info || typeof info !== "object") { this.detailPlot.textContent = "Keine weiteren Angaben des Anbieters."; return; }
    var parts = [];
    ["genre", "plot", "cast", "director"].forEach(function (k) { var v = info[k] == null ? "" : String(info[k]); if (v && v !== "null") parts.push((k === "cast" ? "Besetzung: " : k === "director" ? "Regie: " : "") + v); });
    this.detailPlot.textContent = parts.length ? parts.join("\n\n") : "Keine weiteren Angaben des Anbieters.";
  };
  P.detailError = function (e) { if (this.detail && this.detail.id === e.id && this.detailPlot) this.detailPlot.textContent = "Details konnten nicht geladen werden. Die Wiedergabe bleibt verfügbar."; };
  P.episodes = function (e, list) {
    if (!this.detail || this.detail.id !== e.id || !this.episodeHost) return;
    var seasons = this.seasons = {}, order = this.seasonOrder = [];
    list.forEach(function (ep) { if (!seasons[ep.group]) { seasons[ep.group] = []; order.push(ep.group); } seasons[ep.group].push(ep); });
    if (!list.length) { this.episodeHost.appendChild(h("div", "t-body", "Keine Episoden verfügbar.")); return; }
    this.selectedSeason = order[0]; this.renderEpisodes();
  };
  P.renderEpisodes = function () {
    var self = this, host = this.episodeHost; host.innerHTML = "";
    host.appendChild(button(this.selectedSeason + " ⌄", function () {
      UI.dialog({ title: "Staffel wählen", items: self.seasonOrder, onItem: function (n) { self.selectedSeason = self.seasonOrder[n]; self.renderEpisodes(); UI.focus(self.episodeHost.firstChild); }, buttons: [{ label: "Abbrechen" }] });
    }, { cls: "season" }));
    this.seasons[this.selectedSeason].forEach(function (ep, i) {
      var row = h("div", "eprow f");
      row.appendChild(h("div", "epnum t-body28 secondary", String(i + 1)));
      var words = h("div", "epwords"); words.appendChild(h("div", "t-title28 ellipsis", ep.name));
      var resume = self.progress.position(ep);
      words.appendChild(h("div", "t-small secondary", resume > 1000 ? "Fortsetzen ab " + Math.floor(resume / 60000) + " Min." : ep.subtitle));
      row.appendChild(words); row.appendChild(h("div", "t-body28", "▶"));
      row.setAttribute("aria-label", ep.name);
      row._click = function () { self.actions.play(ep); }; row._long = function () { self.actions.menu(ep); };
      host.appendChild(row);
    });
  };

  // ---------- Meine Listen ----------
  /** «Meine Listen»: Kategorien und Sender ein-/ausblenden, umbenennen und ordnen, Aufbau der Startseite und Kacheln. Wirkt sofort. */
  function ListEditor(lists, start, host) {
    var self = this;
    this.lists = lists; this.host = host; this.page = start; this.area = "live"; this.group = null; this.tabs = {};
    var el = this.el = h("div", "editor");
    var top = h("div", "editor-top");
    top.appendChild(button("‹ Zurück", host.close));
    var title = h("div", "t-title40 editor-title"); title.appendChild(UI.dotted("Meine Listen.")); top.appendChild(title);
    [["categories", "Kategorien"], ["channels", "Sender"], ["home", "Jetzt"]].forEach(function (p) {
      var b = button(p[1], function () { self.page = p[0]; self.render(true); }); self.tabs[p[0]] = b; top.appendChild(b);
    });
    el.appendChild(top);
    this.scroll = h("div", "editor-rows scroller"); this.rows = h("div"); this.scroll.appendChild(this.rows); el.appendChild(this.scroll);
    this.render(true);
  }
  var E = ListEditor.prototype;
  E.render = function (focusTab) {
    var self = this, focused = -1, cur = UI.current();
    for (var i = 0; i < this.rows.children.length; i++) if (this.rows.children[i] === cur) focused = i;
    Object.keys(this.tabs).forEach(function (k) { self.tabs[k].classList.toggle("selected", k === self.page); });
    this.rows.innerHTML = "";
    if (this.page === "categories") this.categories(); else if (this.page === "channels") this.channels(); else this.home();
    var self2 = this;
    setTimeout(function () {
      if (!self2.el.isConnected) return;
      if (focusTab) UI.focus(self2.tabs[self2.page]);
      else { var fs = UI.focusables(self2.rows); var idx = Math.max(0, Math.min(focused, self2.rows.children.length - 1)), t = self2.rows.children[idx]; UI.focus(t && t.classList.contains("f") ? t : fs[0] || self2.tabs[self2.page]); }
    }, 0);
  };
  E.changed = function () { this.host.changed(); this.render(false); };
  E.groupsOf = function (area) { var out = [], seen = {}; this.host.all().forEach(function (e) { if (Lists.area(e) === area && !seen[e.group]) { seen[e.group] = true; out.push(e.group); } }); return out; };
  E.categories = function () {
    var self = this, lists = this.lists, area = this.area;
    this.rows.appendChild(this.picker("Bereich: " + Lists.areaLabel(area) + " ⌄", function () { self.choose("Bereich", Lists.AREA_LABELS, function (n) { self.area = Lists.AREAS[n]; self.render(false); }); }));
    var groups = lists.ordered(area, this.groupsOf(area)), hidden = groups.filter(function (g) { return lists.groupHidden(area, g); }).length;
    this.note((groups.length - hidden) + " von " + groups.length + " sichtbar · OK: ein-/ausblenden · OK halten: umbenennen, verschieben");
    groups.forEach(function (g) {
      var off = lists.groupHidden(area, g);
      self.rows.appendChild(self.row(lists.groupName(area, g), off ? "Ausgeblendet" : "Sichtbar", off, function () { lists.setGroupHidden(area, g, !off); self.changed(); }, function () {
        self.choose(lists.groupName(area, g), ["Umbenennen …", "Nach oben", "Nach unten"], function (n) {
          if (n === 0) self.rename(lists.groupName(area, g), function (name) { lists.renameGroup(area, g, name); self.changed(); });
          else { lists.move(area, groups, g, n === 1 ? -1 : 1); self.changed(); }
        });
      }));
    });
    if (!groups.length) this.note("Noch keine Kategorien geladen.");
    if (lists.customOrder(area)) this.rows.appendChild(this.picker("Reihenfolge des Anbieters wiederherstellen", function () { lists.resetOrder(area); self.changed(); }));
  };
  E.channels = function () {
    var self = this, lists = this.lists, favs = this.host.favorites();
    var groups = lists.ordered("live", this.groupsOf("live"));
    if (this.group === null || (this.group !== "" && groups.indexOf(this.group) < 0)) this.group = !Object.keys(favs).length && groups.length ? groups[0] : "";
    var group = this.group;
    this.rows.appendChild(this.picker("Liste: " + (group === "" ? "★ Favoriten" : lists.groupName("live", group)) + " ⌄", function () {
      self.choose("Liste", ["★ Favoriten"].concat(groups.map(function (g) { return lists.groupName("live", g); })), function (n) { self.group = n === 0 ? "" : groups[n - 1]; self.render(false); });
    }));
    var shown = this.host.all().filter(function (e) { return e.kind === "live" && (group === "" ? favs[e.id] : e.group === group); });
    var hidden = shown.filter(function (e) { return lists.channelHidden(e); }).length;
    this.note((shown.length - hidden) + " von " + shown.length + " sichtbar · OK: ein-/ausblenden · OK halten: Favorit, umbenennen");
    shown.forEach(function (e) {
      var off = lists.channelHidden(e), fav = !!favs[e.id];
      self.rows.appendChild(self.row((fav ? "★ " : "") + lists.name(e), off ? "Ausgeblendet" : "Sichtbar", off, function () { lists.setHidden(e, !off); self.changed(); }, function () {
        self.choose(lists.name(e), [fav ? "Aus Favoriten entfernen" : "Zu Favoriten hinzufügen", "Umbenennen …"], function (n) {
          if (n === 0) { self.host.toggleFavorite(e); self.changed(); } else self.rename(lists.name(e), function (name) { lists.rename(e, name); self.changed(); });
        });
      }));
    });
    if (!shown.length) this.note(group === "" ? "Noch keine Favoriten. OK halten auf einem Sender: «Zu Favoriten hinzufügen»." : "Keine Sender in dieser Kategorie.");
  };
  E.home = function () {
    var self = this, lists = this.lists;
    this.rows.appendChild(this.row("Sendernamen unter den Kacheln", lists.showNames() ? "Ein" : "Aus", false, function () { lists.setShowNames(!lists.showNames()); self.changed(); }, null));
    this.rows.appendChild(this.row("Kachelgrösse", Lists.SIZES[lists.tileSize()], false, function () { lists.setTileSize((lists.tileSize() + 1) % 3); self.changed(); }, null));
    this.note("Reihen von «Jetzt» · OK: ein-/ausblenden · OK halten: verschieben");
    lists.homeOrder().forEach(function (s) {
      var off = lists.sectionHidden(s);
      self.rows.appendChild(self.row(Lists.sectionLabel(s), off ? "Ausgeblendet" : "Sichtbar", off, function () { lists.setSectionHidden(s, !off); self.changed(); }, function () {
        self.choose(Lists.sectionLabel(s), ["Nach oben", "Nach unten"], function (n) { lists.moveSection(s, n === 0 ? -1 : 1); self.changed(); });
      }));
    });
    this.rows.appendChild(this.picker("Standard-Aufbau wiederherstellen", function () { lists.resetHome(); self.changed(); }));
  };
  E.row = function (name, value, off, click, hold) {
    var row = h("div", "erow f");
    var eye = h("div", "eye" + (off ? "" : " on"), off ? "○" : "●"); row.appendChild(eye);
    var label = h("div", "t-title28 ellipsis elabel", name); if (off) label.style.opacity = ".55"; row.appendChild(label);
    row.appendChild(h("div", "t-small secondary", value));
    row.setAttribute("aria-label", name + ", " + value);
    row._click = click; if (hold) row._long = hold;
    return row;
  };
  E.picker = function (label, action) { return button(label, action, { cls: "picker" }); };
  E.note = function (text) { this.rows.appendChild(h("div", "t-small secondary enote", text)); };
  E.choose = function (title, items, pick) { UI.dialog({ title: title, items: items, onItem: pick, buttons: [{ label: "Abbrechen" }] }); };
  E.rename = function (current, done) {
    UI.dialog({ title: "Umbenennen", message: "Leer lassen, um den Originalnamen wiederherzustellen.", input: { value: current },
      buttons: [{ label: "Abbrechen" }, { label: "Sichern", primary: true, action: function (v) { done(v); } }] });
  };

  root.Library = { LibraryView: LibraryView, ListEditor: ListEditor, Shelf: Shelf, Rail: Rail, img: img };
})(this);
