/* IPTelevision+ für Samsung Tizen – Kernlogik, 1:1 aus der Google-TV-App (AndroidTV/…/ch/arjo/tv/android) übertragen.
   Ohne DOM und ohne Wiedergabe, damit sie mit Node getestet werden kann (tests/core.test.js).
   Tizen 6.0 hat Chromium 76: kein «?.», kein «??», kein replaceAll. */
(function (root) {
  "use strict";

  // ---------- Hilfen ----------
  /** Schneller, stabiler Hash (53 Bit, hex). Ersetzt SHA-256 der Android-Version: 130 000 Einträge wären sonst auf der TV zu langsam. */
  function hash(str) {
    var h1 = 0xdeadbeef, h2 = 0x41c6ce57;
    for (var i = 0; i < str.length; i++) {
      var ch = str.charCodeAt(i);
      h1 = Math.imul(h1 ^ ch, 2654435761);
      h2 = Math.imul(h2 ^ ch, 1597334677);
    }
    h1 = Math.imul(h1 ^ (h1 >>> 16), 2246822507) ^ Math.imul(h2 ^ (h2 >>> 13), 3266489909);
    h2 = Math.imul(h2 ^ (h2 >>> 16), 2246822507) ^ Math.imul(h1 ^ (h1 >>> 13), 3266489909);
    return ("0000000" + (h2 >>> 0).toString(16)).slice(-8) + ("0000000" + (h1 >>> 0).toString(16)).slice(-8);
  }
  function floorMod(a, n) { return ((a % n) + n) % n; }

  /** Zerlegt eine Adresse wie java.net.URI; null bei ungültiger Adresse. */
  function parseUrl(value) {
    var m = /^([a-zA-Z][a-zA-Z0-9+.-]*):\/\/([^\/?#]*)([^?#]*)(\?[^#]*)?(#.*)?$/.exec(String(value == null ? "" : value).trim());
    if (!m) return null;
    var auth = m[2], at = auth.lastIndexOf("@"), userInfo = at >= 0 ? auth.slice(0, at) : null, hostPort = at >= 0 ? auth.slice(at + 1) : auth;
    var host = hostPort.replace(/:\d*$/, "");
    if (/[\s<>"{}|\\^`]/.test(value)) return null;
    return { scheme: m[1].toLowerCase(), authority: auth, userInfo: userInfo, host: host, path: m[3] || "", query: m[4] || "", fragment: m[5] || null };
  }
  function isWeb(value) {
    var u = parseUrl(value);
    return !!u && (u.scheme === "http" || u.scheme === "https") && u.host.length > 0;
  }
  /** Löst eine relative Adresse gegen die Playlist-Adresse auf (URI.resolve). */
  function resolveUrl(base, ref) {
    ref = String(ref || "").trim();
    if (/^[a-zA-Z][a-zA-Z0-9+.-]*:/.test(ref)) return ref;
    var b = parseUrl(base); if (!b) return ref;
    var origin = b.scheme + "://" + b.authority;
    if (ref.indexOf("//") === 0) return b.scheme + ":" + ref;
    if (ref.charAt(0) === "/") return origin + ref;
    if (ref.charAt(0) === "?") return origin + b.path + ref;
    var dir = b.path.slice(0, b.path.lastIndexOf("/") + 1) || "/";
    var parts = (dir + ref).split("/"), out = [];
    for (var i = 0; i < parts.length; i++) {
      var p = parts[i];
      if (p === "..") { if (out.length > 1) out.pop(); }
      else if (p !== "." || i === parts.length - 1) out.push(p === "." ? "" : p);
    }
    return origin + out.join("/");
  }
  function encode(value) { return encodeURIComponent(value).replace(/[!'()*]/g, function (c) { return "%" + c.charCodeAt(0).toString(16).toUpperCase(); }); }

  // ---------- Source ----------
  function Source(mode, address, user, password) {
    this.mode = mode; this.address = String(address || "").trim(); this.user = String(user || "").trim(); this.password = String(password || "");
    var u = parseUrl(this.address);
    if (!isWeb(this.address) || u.userInfo !== null || u.fragment !== null) throw new Error("Bitte eine gültige HTTP-/HTTPS-Adresse eingeben.");
    if (mode === "xtream" && (!this.user || !this.password)) throw new Error("Benutzername und Passwort fehlen.");
  }
  Source.prototype.base = function () { var u = parseUrl(this.address); return u.scheme + "://" + u.authority; };
  Source.prototype.api = function (action) {
    return this.base() + "/player_api.php?username=" + encode(this.user) + "&password=" + encode(this.password) + (action ? "&action=" + encode(action) : "");
  };
  Source.prototype.stream = function (kind, id, extension) {
    if (!/^[0-9]+$/.test(id) || !/^[A-Za-z0-9]+$/.test(extension)) throw new Error("Ungültiger Stream.");
    return this.base() + "/" + kind + "/" + encode(this.user) + "/" + encode(this.password) + "/" + id + "." + extension;
  };
  Source.prototype.scope = function () { return hash(this.mode + "|" + (this.mode === "xtream" ? this.base() + "|" + this.user : this.address)); };
  Source.prototype.json = function () { return { mode: this.mode, address: this.address, user: this.user, password: this.password }; };
  Source.from = function (j) { return new Source(j.mode, j.address, j.user, j.password); };
  /** Dropbox liefert der TV unter www.dropbox.com eine Webseite statt der Datei (auf der TV gemessen); der Download-Host liefert die Datei. */
  Source.transport = function (url) {
    if (/^https?:\/\/(www\.)?dropbox\.com\//i.test(url))
      return url.replace(/^https?:\/\/(www\.)?dropbox\.com\//i, "https://dl.dropboxusercontent.com/").replace(/([?&])dl=0\b/, "$1dl=1");
    return url;
  };

  // ---------- Entry ----------
  function entry(id, name, group, url, kind, image, subtitle) {
    return { id: id, name: name, group: group, url: url, kind: kind, image: isWeb(image) ? image : "", subtitle: subtitle || "", number: 0, sourceNumber: 0 };
  }

  // ---------- PresetSource ----------
  /** Neue mitgelieferte Quelle einmal übernehmen; spätere eigene Wahl und Abmeldung bleiben erhalten. */
  function choosePreset(saved, configured, appliedScope) {
    if (!configured) return saved;
    var preset = typeof configured === "string" ? new Source("m3u", configured, "", "") : Source.from(configured);
    return preset.scope() === appliedScope ? saved : preset;
  }

  // ---------- M3U ----------
  var ATTRIBUTE = /([\w-]+)\s*=\s*"([^"]*)"/g;
  function separator(line) {
    var quoted = false;
    for (var i = 0; i < line.length; i++) {
      var c = line.charAt(i);
      if (c === '"') quoted = !quoted;
      if (c === "," && !quoted) return i;
    }
    return -1;
  }
  var EPISODE_NAME = /S\d{1,2}E\d{1,3}/i, MOVIE_PATH = /\.(mp4|mkv|avi|mov|m4v|webm)$/;
  function parseM3u(text, baseUrl) {
    var result = [], name = "", group = "Ohne Gruppe", image = "", pending = false, chno = 0, count = 0;
    var pos = 0, len = text.length;
    while (pos < len) {
      var nl = text.indexOf("\n", pos); if (nl < 0) nl = len;
      var line = text.slice(pos, nl); pos = nl + 1;
      if (++count > 1000000 || line.length > 65536) throw new Error("Playlist zu gross.");
      if (line.charCodeAt(0) === 0xFEFF) line = line.slice(1);
      line = line.trim();
      if (line.indexOf("#EXTINF:") === 0) {
        var comma = separator(line);
        name = comma >= 0 ? line.slice(comma + 1).trim() : "";
        group = "Ohne Gruppe"; image = ""; chno = 0;
        var head = comma < 0 ? line : line.slice(0, comma), m;
        ATTRIBUTE.lastIndex = 0;
        while ((m = ATTRIBUTE.exec(head)) !== null) {
          var key = m[1].toLowerCase();
          if (key === "tvg-logo") image = m[2] ? resolveUrl(baseUrl, m[2]) : "";
          else if (key === "group-title") group = m[2];
          else if (key === "tvg-chno") { var raw = m[2].trim(); chno = /^[+-]?\d{1,9}$/.test(raw) ? Math.max(0, parseInt(raw, 10)) : 0; }
          else if (key === "tvg-name" && !name) name = m[2];
        }
        pending = true;
      } else if (line.indexOf("#EXTGRP:") === 0 && pending) {
        group = line.slice(8).trim();
      } else if (line && line.charAt(0) !== "#") {
        var url = resolveUrl(baseUrl, line);
        if (isWeb(url)) {
          var path = (parseUrl(url).path || "").toLowerCase();
          var kind = path.indexOf("/series/") >= 0 || EPISODE_NAME.test(name) ? "episode"
            : path.indexOf("/movie/") >= 0 || MOVIE_PATH.test(path) ? "movie" : "live";
          var e = entry(hash(url), name || "Eintrag " + (result.length + 1), group.trim() ? group : "Ohne Gruppe", url, kind, image, "");
          e.sourceNumber = chno; result.push(e);
        }
        name = ""; group = "Ohne Gruppe"; image = ""; pending = false; chno = 0;
      }
    }
    return result;
  }

  // ---------- Xtream (Katalog-Antworten auswerten; Netzwerk in app.js) ----------
  function str(v, def) { return v === undefined || v === null ? (def === undefined ? "" : def) : String(v); }
  function metadata(item) {
    var parts = [], year = str(item.year);
    if (!year) { var date = str(item.releaseDate); if (date.length >= 4) year = date.slice(0, 4); }
    if (year && year !== "null") parts.push(year);
    var rating = str(item.rating);
    if (rating && rating !== "0" && rating !== "null") parts.push("★ " + rating);
    return parts.join(" · ");
  }
  function xtreamEntries(source, kind, categories, rows) {
    var groups = {};
    (Array.isArray(categories) ? categories : []).forEach(function (c) { if (c && typeof c === "object") groups[str(c.category_id)] = str(c.category_name, "Ohne Gruppe"); });
    var entries = [];
    (Array.isArray(rows) ? rows : []).forEach(function (j) {
      if (!j || typeof j !== "object") return;
      var id = str(kind === "series" ? j.series_id : j.stream_id);
      if (!/^[0-9]+$/.test(id)) return;
      var ext = str(j.container_extension, kind === "live" ? "ts" : "mp4");
      if (!/^[A-Za-z0-9]+$/.test(ext)) ext = "mp4";
      var g = groups.hasOwnProperty(str(j.category_id)) ? groups[str(j.category_id)] : "Ohne Gruppe";
      var e = entry(kind + ":" + id, str(j.name, "Eintrag " + id), g,
        kind === "series" ? "" : source.stream(kind === "movie" ? "movie" : "live", id, ext), kind, str(kind === "series" ? j.cover : j.stream_icon), metadata(j));
      if (kind === "live") { var num = parseInt(j.num, 10); e.sourceNumber = isNaN(num) ? 0 : Math.max(0, num); }
      entries.push(e);
    });
    return entries;
  }
  function seasonNumber(v) { var n = parseInt(v, 10); return isNaN(n) || String(n) !== String(v).trim() ? Number.MAX_SAFE_INTEGER : n; }
  function xtreamEpisodes(source, response) {
    var seasons = response && response.episodes;
    if (!seasons || typeof seasons !== "object") throw new Error("Keine Episoden verfügbar.");
    var result = [], keys = Object.keys(seasons);
    keys.sort(function (a, b) { return seasonNumber(a) - seasonNumber(b); });
    keys.forEach(function (season) {
      var list = seasons[season]; if (!Array.isArray(list)) return;
      var sorted = list.filter(function (x) { return x && typeof x === "object"; });
      sorted.sort(function (a, b) { return (parseInt(a.episode_num, 10) || 0) - (parseInt(b.episode_num, 10) || 0); });
      sorted.forEach(function (e) {
        var id = str(e.id), ext = str(e.container_extension, "mp4");
        if (!/^[0-9]+$/.test(id)) return;
        if (!/^[A-Za-z0-9]+$/.test(ext)) ext = "mp4";
        var num = parseInt(e.episode_num, 10) || 0;
        result.push(entry("episode:" + id, str(e.title, "Episode " + num), "Staffel " + season, source.stream("series", id, ext), "episode",
          e.info && typeof e.info === "object" ? str(e.info.movie_image) : "", "Episode " + num));
      });
    });
    return result;
  }
  /** Prüft die Antwort von player_api.php; liefert das Ablaufdatum (s) oder 0. */
  function xtreamAuth(response, nowMs) {
    if (!response || typeof response !== "object" || Array.isArray(response)) throw new Error("Ungültige Serverantwort.");
    var info = response.user_info;
    if (!info || typeof info !== "object" || !(str(info.auth) === "1" || str(info.auth) === "true")) throw new Error("Anmeldung abgelehnt. Bitte Zugang prüfen.");
    if (str(info.status, "Active").toLowerCase() !== "active") throw new Error("Dein Zugang ist nicht aktiv.");
    var expiry = parseInt(info.exp_date, 10); if (isNaN(expiry)) expiry = 0;
    if (expiry > 0 && expiry * 1000 <= nowMs) throw new Error("Dein Abo ist abgelaufen.");
    return Math.max(expiry, 0);
  }

  // ---------- ChannelNumbers / NumberStore ----------
  /** Feste Kanalnummern: Nutzer, bisherige Nummer, Nummer der Quelle, dann fortlaufend. */
  function assignNumbers(ids, sourceNumbers, existing, pinned) {
    var numbers = {}, used = {}, max = 0, usedCount = 0;
    function take(id, n) {
      if (!(n >= 1) || numbers.hasOwnProperty(id) || used[n]) return false;
      numbers[id] = n; used[n] = true; usedCount++; if (n > max) max = n; return true;
    }
    ids.forEach(function (id) { if (pinned.hasOwnProperty(id)) take(id, pinned[id]); });
    ids.forEach(function (id) { if (existing.hasOwnProperty(id)) take(id, existing[id]); });
    var duplicates = 0, rest = [];
    for (var i = 0; i < ids.length; i++) {
      var id = ids[i]; if (numbers.hasOwnProperty(id)) continue;
      var source = sourceNumbers && i < sourceNumbers.length && sourceNumbers[i] ? sourceNumbers[i] : 0;
      if (source >= 1) { if (!take(id, source)) { duplicates++; rest.push(id); } } else rest.push(id);
    }
    var next = Object.keys(existing).length === 0 && Object.keys(pinned).length === 0 ? 1 : (usedCount === 0 ? 0 : max) + 1;
    rest.forEach(function (id) {
      if (numbers.hasOwnProperty(id)) return;
      while (used[next]) next++;
      numbers[id] = next; used[next] = true; next++;
    });
    return { numbers: numbers, duplicates: duplicates };
  }
  /** Vergibt Nummern für alle Live-Einträge (bisherige bleiben). Liefert die neue Zuordnung zum Speichern. */
  function applyNumbers(entries, existing, pinned) {
    var ids = [], src = [], live = [];
    for (var i = 0; i < entries.length; i++) { var e = entries[i]; if (e.kind === "live") { ids.push(e.id); src.push(e.sourceNumber); live.push(e); } }
    var r = assignNumbers(ids, src, existing || {}, pinned || {});
    live.forEach(function (e) { e.number = r.numbers.hasOwnProperty(e.id) ? r.numbers[e.id] : 0; });
    return r.numbers;
  }

  // ---------- ChannelNavigator (Zifferneingabe) ----------
  function ChannelNavigator() { this.d = ""; this.lastDigitAt = null; }
  ChannelNavigator.DIGIT_WINDOW_MS = 2000; ChannelNavigator.MAX_DIGITS = 4;
  ChannelNavigator.prototype.hasPendingDigits = function () { return this.d.length > 0; };
  ChannelNavigator.prototype.digits = function () { return this.d; };
  ChannelNavigator.prototype.enter = function (digit, nowMs) {
    if (digit < 0 || digit > 9) return;
    if (!this.d.length && digit === 0) return;
    if (this.d.length < ChannelNavigator.MAX_DIGITS) this.d += digit;
    this.lastDigitAt = nowMs;
  };
  ChannelNavigator.prototype.commitDigits = function () { var n = this.d ? parseInt(this.d, 10) : 0; this.cancelDigits(); return n; };
  ChannelNavigator.prototype.cancelDigits = function () { this.d = ""; this.lastDigitAt = null; };
  /** Nachbargruppe (umbrechend), wie ChannelNavigator.neighbourGroup. */
  function neighbourGroup(groups, current, offset) {
    if (!groups.length) return null;
    var index = current == null ? -1 : groups.indexOf(current);
    if (index < 0) index = offset >= 0 ? -1 : 0;
    var next = floorMod(index + offset, groups.length);
    return { name: groups[next], position: next + 1, count: groups.length };
  }

  // ---------- PlaybackQueue ----------
  function rank(e) { return e.number <= 0 ? Number.MAX_SAFE_INTEGER : e.number; }
  function PlaybackQueue(catalog, selected, scope, groupOrder) {
    this.scope = scope; this.groupOrder = (groupOrder || []).slice(); this.all = []; this.channels = []; this.index = 0; this.previousId = null;
    var ids = {};
    for (var i = 0; i < catalog.length; i++) { var e = catalog[i]; if (e.kind === "live" && isWeb(e.url) && !ids[e.id]) { ids[e.id] = true; this.all.push(e); } }
    this.loadGroup(selected.group, selected);
  }
  PlaybackQueue.prototype.loadGroup = function (group, selected) {
    var list = this.all.filter(function (e) { return e.group === group; });
    // Nach Kanalnummer; ohne Nummern bleibt die Reihenfolge des Anbieters (stabile Sortierung).
    list = list.map(function (e, i) { return [e, i]; }).sort(function (a, b) { return rank(a[0]) - rank(b[0]) || a[1] - b[1]; }).map(function (x) { return x[0]; });
    this.channels = list; this.index = -1;
    for (var i = 0; i < list.length; i++) if (list[i].id === selected.id) { this.index = i; break; }
    if (this.index < 0) { list.push(selected); this.index = list.length - 1; }
  };
  PlaybackQueue.prototype.current = function () { return this.channels[this.index]; };
  PlaybackQueue.prototype.move = function (direction) { this.previousId = this.current().id; this.index = floorMod(this.index + (direction > 0 ? 1 : -1), this.channels.length); return this.current(); };
  PlaybackQueue.prototype.select = function (id) { for (var i = 0; i < this.channels.length; i++) if (this.channels[i].id === id) { this.index = i; return; } };
  PlaybackQueue.prototype.size = function () { return this.channels.length; };
  PlaybackQueue.prototype.groups = function () {
    var present = [], seen = {};
    this.all.forEach(function (e) { if (!seen[e.group]) { seen[e.group] = true; present.push(e.group); } });
    var out = [], taken = {};
    this.groupOrder.forEach(function (g) { if (seen[g] && !taken[g]) { taken[g] = true; out.push(g); } });
    present.forEach(function (g) { if (!taken[g]) out.push(g); });
    return out;
  };
  PlaybackQueue.prototype.neighbourGroup = function (from, direction) { return neighbourGroup(this.groups(), from, direction); };
  PlaybackQueue.prototype.startGroup = function (group) {
    var first = null;
    this.all.forEach(function (e) { if (e.group === group && (first === null || rank(e) < rank(first))) first = e; });
    if (!first) return null; this.previousId = this.current().id; this.loadGroup(group, first); return this.current();
  };
  PlaybackQueue.prototype.byNumber = function (number) { for (var i = 0; i < this.all.length; i++) if (this.all[i].number === number) return this.all[i]; return null; };
  PlaybackQueue.prototype.jump = function (target) {
    this.previousId = this.current().id;
    for (var i = 0; i < this.channels.length; i++) if (this.channels[i].id === target.id) { this.index = i; return this.current(); }
    this.loadGroup(target.group, target); return this.current();
  };
  PlaybackQueue.prototype.previous = function () {
    if (this.previousId === null) return null;
    for (var i = 0; i < this.all.length; i++) if (this.all[i].id === this.previousId) return this.jump(this.all[i]);
    return null;
  };

  // ---------- Lists («Meine Listen») ----------
  var SECTIONS = ["hero", "continue", "last", "favorites", "live", "movies", "series"];
  var SECTION_LABELS = ["Titelbild", "Weiterschauen", "Zuletzt gesehen", "Favoriten", "Live TV", "Neue Filme", "Neue Serien"];
  var AREAS = ["live", "movie", "series"], AREA_LABELS = ["Live", "Filme", "Serien"], SIZES = ["Kompakt", "Normal", "Gross"];
  /** prefs: {get(key, def), set(key, value)} – JSON-Werte. */
  function Lists(prefs, scope) { this.prefs = prefs; this.scope = scope; this._c = {}; }
  Lists.SECTIONS = SECTIONS; Lists.AREAS = AREAS; Lists.AREA_LABELS = AREA_LABELS; Lists.SIZES = SIZES;
  Lists.area = function (e) { return e.kind === "episode" ? "series" : e.kind; };
  Lists.sectionLabel = function (s) { var i = SECTIONS.indexOf(s); return i < 0 ? s : SECTION_LABELS[i]; };
  Lists.areaLabel = function (a) { var i = AREAS.indexOf(a); return i < 0 ? a : AREA_LABELS[i]; };
  Lists.prototype.key = function (name) { return "lists:" + this.scope + ":" + name; };
  Lists.prototype.read = function (name, def) { var k = this.key(name); if (!this._c.hasOwnProperty(k)) this._c[k] = this.prefs.get(k, def); return this._c[k]; };
  Lists.prototype.write = function (name, value) { var k = this.key(name); this._c[k] = value; this.prefs.set(k, value); };
  Lists.prototype.setOf = function (name) { var a = this.read(name, []), s = {}; for (var i = 0; i < a.length; i++) s[a[i]] = true; return s; };
  Lists.prototype.toggle = function (name, value, on) {
    var a = this.read(name, []).filter(function (x) { return x !== value; }); if (on) a.push(value); this.write(name, a);
  };
  Lists.prototype.hidden = function (e) { return !!this.setOf("hidden")[e.id] || this.groupHidden(Lists.area(e), e.group); };
  Lists.prototype.channelHidden = function (e) { return !!this.setOf("hidden")[e.id]; };
  Lists.prototype.setHidden = function (e, hidden) { this.toggle("hidden", e.id, hidden); };
  Lists.prototype.groupHidden = function (area, group) { return !!this.setOf("hiddenGroups")[area + "\n" + group]; };
  Lists.prototype.setGroupHidden = function (area, group, hidden) { this.toggle("hiddenGroups", area + "\n" + group, hidden); };
  Lists.prototype.visible = function (all) {
    var ids = this.setOf("hidden"), groups = this.setOf("hiddenGroups"), anyIds = Object.keys(ids).length > 0, anyGroups = Object.keys(groups).length > 0;
    if (!anyIds && !anyGroups) return all.slice();
    return all.filter(function (e) { return !ids[e.id] && !groups[Lists.area(e) + "\n" + e.group]; });
  };
  Lists.prototype.map = function (name) { var m = this.read(name, {}); return m && typeof m === "object" ? m : {}; };
  Lists.prototype.put = function (name, k, value) {
    var m = Object.assign({}, this.map(name)); if (value == null || !String(value).trim()) delete m[k]; else m[k] = String(value).trim(); this.write(name, m);
  };
  Lists.prototype.name = function (e) { var c = this.map("names")[e.id]; return c ? c : e.name; };
  Lists.prototype.rename = function (e, name) { this.put("names", e.id, name); };
  Lists.prototype.groupName = function (area, group) { var c = this.map("groupNames")[area + "\n" + group]; return c ? c : group; };
  Lists.prototype.renameGroup = function (area, group, name) { this.put("groupNames", area + "\n" + group, name); };
  Lists.prototype.ordered = function (area, groups) {
    var order = this.read("order:" + area, []), present = [], seen = {}, out = [];
    groups.forEach(function (g) { if (!seen[g]) { seen[g] = true; present.push(g); } });
    order.forEach(function (g) { if (seen[g] === true) { seen[g] = false; out.push(g); } });
    present.forEach(function (g) { if (seen[g] === true) out.push(g); });
    return out;
  };
  Lists.prototype.move = function (area, groups, group, offset) {
    var order = this.ordered(area, groups), i = order.indexOf(group), j = i + offset;
    if (i < 0 || j < 0 || j >= order.length) return;
    order.splice(j, 0, order.splice(i, 1)[0]); this.write("order:" + area, order);
  };
  Lists.prototype.customOrder = function (area) { return this.read("order:" + area, []).length > 0; };
  Lists.prototype.resetOrder = function (area) { this.write("order:" + area, []); };
  Lists.prototype.homeOrder = function () { return this.ordered("home", SECTIONS); };
  Lists.prototype.sectionHidden = function (s) { return !!this.setOf("hiddenSections")[s]; };
  Lists.prototype.setSectionHidden = function (s, hidden) { this.toggle("hiddenSections", s, hidden); };
  Lists.prototype.moveSection = function (s, offset) { this.move("home", SECTIONS, s, offset); };
  Lists.prototype.visibleSections = function () { var self = this; return this.homeOrder().filter(function (s) { return !self.sectionHidden(s); }); };
  Lists.prototype.resetHome = function () { this.write("order:home", []); this.write("hiddenSections", []); };
  // Kacheln (gelten für alle Quellen)
  Lists.prototype.showNames = function () { return this.prefs.get("tiles:names", true); };
  Lists.prototype.setShowNames = function (v) { this.prefs.set("tiles:names", !!v); };
  Lists.prototype.tileSize = function () { var n = this.prefs.get("tiles:size", 1); return Math.max(0, Math.min(2, n | 0)); };
  Lists.prototype.setTileSize = function (n) { this.prefs.set("tiles:size", Math.max(0, Math.min(2, n | 0))); };
  /** Breite einer Senderkachel in dp (16:9-Logofläche). */
  Lists.prototype.tileWidth = function () { return [150, 188, 236][this.tileSize()]; };

  // ---------- MultiviewLayout ----------
  var ML_KEYS = ["grid", "focus", "stage", "strip", "pip"], ML_LABELS = ["Raster", "Fokus", "Bühne", "Reihe", "Bild in Bild"];
  var MultiviewLayout = {
    KEYS: ML_KEYS, LABELS: ML_LABELS, MAX: 4,
    label: function (key) { var i = ML_KEYS.indexOf(key); return ML_LABELS[i < 0 ? 0 : i]; },
    overlaps: function (key) { return key === "pip"; },
    /** Rechtecke [x, y, Breite, Höhe]; focus ist das grosse Bild. Nur so viele Felder wie laufende Sender. */
    frames: function (key, count, w, h, focus) {
      var out = []; if (count <= 0) return out;
      var landscape = w >= h, big = Math.min(Math.max(focus, 0), count - 1), i, s = 0, small = count - 1;
      if (count === 1 && key !== "strip" && key !== "grid") return [[0, 0, w, h]];
      if (key === "focus") {
        var bw = landscape ? w * 0.7 : w, bh = landscape ? h : h * 0.62;
        for (i = 0; i < count; i++) { if (i === big) { out[i] = [0, 0, bw, bh]; continue; } out[i] = landscape ? [bw, h / small * s, w - bw, h / small] : [w / small * s, bh, w / small, h - bh]; s++; }
        return out;
      }
      if (key === "stage") {
        var sh = h * (landscape ? 0.74 : 0.55);
        for (i = 0; i < count; i++) { if (i === big) { out[i] = [0, 0, w, sh]; continue; } out[i] = [w / small * s, sh, w / small, h - sh]; s++; }
        return out;
      }
      if (key === "strip") { for (i = 0; i < count; i++) out[i] = landscape ? [w / count * i, 0, w / count, h] : [0, h / count * i, w, h / count]; return out; }
      if (key === "pip") {
        var margin = Math.min(w, h) * 0.04, sw = w * (landscape ? 0.22 : 0.4), sh2 = sw * 9 / 16;
        for (i = 0; i < count; i++) { if (i === big) { out[i] = [0, 0, w, h]; continue; } out[i] = [w - margin - sw, h - margin - sh2 - (sh2 + margin / 2) * s, sw, sh2]; s++; }
        return out;
      }
      // Raster: 3 Bilder = 2 oben, 1 unten über die ganze Breite.
      var rows = count === 1 ? [1] : count === 2 ? (landscape ? [2] : [1, 1]) : count === 3 ? [2, 1] : [2, 2];
      var rh = h / rows.length, n = 0;
      for (var r = 0; r < rows.length; r++) for (var c = 0; c < rows[r] && n < count; c++) out[n++] = [w / rows[r] * c, rh * r, w / rows[r], rh];
      return out;
    }
  };

  // ---------- Live-Formate ----------
  /** Xtream-Live-Adresse in beiden erlaubten Formaten: MPEG-TS (eine durchgehende Verbindung) und HLS. Wie die alte Tizen-App,
      die auf dieser TV mit HLS lief, wenn TS mit PLAYER_ERROR_GENEREIC abbrach. preferred = "m3u8" stellt HLS nach vorn. */
  function streamVariants(url, preferred) {
    var m = /^(https?:\/\/[^\/]+)\/(?:live\/)?([^\/]+)\/([^\/]+)\/(\d+)(?:\.(ts|m3u8))?$/.exec(String(url));
    if (!m) return [url];
    var b = m[1] + "/live/" + m[2] + "/" + m[3] + "/" + m[4], list = preferred === "m3u8" ? [b + ".m3u8", b + ".ts"] : [b + ".ts", b + ".m3u8"];
    return list;
  }

  // ---------- Spulen ----------
  function seekTarget(position, duration, delta) {
    var end = Math.max(0, Math.max(0, position) + delta);
    return duration >= 0 ? Math.min(duration, end) : end;
  }

  var Core = {
    hash: hash, parseUrl: parseUrl, isWeb: isWeb, resolveUrl: resolveUrl, encode: encode, floorMod: floorMod,
    Source: Source, entry: entry, choosePreset: choosePreset, parseM3u: parseM3u, separator: separator,
    xtreamEntries: xtreamEntries, xtreamEpisodes: xtreamEpisodes, xtreamAuth: xtreamAuth,
    assignNumbers: assignNumbers, applyNumbers: applyNumbers, ChannelNavigator: ChannelNavigator, neighbourGroup: neighbourGroup,
    PlaybackQueue: PlaybackQueue, Lists: Lists, MultiviewLayout: MultiviewLayout, seekTarget: seekTarget, streamVariants: streamVariants
  };
  if (typeof module !== "undefined" && module.exports) module.exports = Core; else root.Core = Core;
})(this);
