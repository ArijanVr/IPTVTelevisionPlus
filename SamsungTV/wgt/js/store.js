/* Speicher und Netz: entspricht SharedPreferences, Vault, CatalogCache und Catalog (Netzteil) der Google-TV-App.
   Unterschied zu Android: Tizen hat keinen Android Keystore. Zugang, Verlauf und Katalog liegen im privaten Speicher der App
   (localStorage bzw. IndexedDB), den andere Apps nicht lesen können. Siehe README. */
(function (root) {
  "use strict";
  var PREFIX = "iptv.";

  /** Kleine Einstellungen (JSON) in localStorage, wie SharedPreferences. */
  var Prefs = {
    get: function (key, def) {
      try { var v = localStorage.getItem(PREFIX + key); return v === null ? def : JSON.parse(v); } catch (e) { return def; }
    },
    set: function (key, value) {
      try { if (value === undefined || value === null) localStorage.removeItem(PREFIX + key); else localStorage.setItem(PREFIX + key, JSON.stringify(value)); return true; }
      catch (e) { return false; }
    },
    remove: function (key) { try { localStorage.removeItem(PREFIX + key); } catch (e) {} }
  };

  /** Grosse Daten (Katalog, Kanalnummern) in IndexedDB. Fehler sind nicht schlimm: dann wird neu geladen. */
  var db = null, dbReady = null;
  function openDb() {
    if (dbReady) return dbReady;
    dbReady = new Promise(function (resolve) {
      try {
        var req = indexedDB.open("iptelevision", 1);
        req.onupgradeneeded = function () { req.result.createObjectStore("kv"); };
        req.onsuccess = function () { db = req.result; resolve(db); };
        req.onerror = function () { resolve(null); };
        req.onblocked = function () { resolve(null); };
      } catch (e) { resolve(null); }
    });
    return dbReady;
  }
  var Big = {
    get: function (key) {
      return openDb().then(function (d) {
        if (!d) return null;
        return new Promise(function (resolve) {
          try { var r = d.transaction("kv", "readonly").objectStore("kv").get(key); r.onsuccess = function () { resolve(r.result === undefined ? null : r.result); }; r.onerror = function () { resolve(null); }; }
          catch (e) { resolve(null); }
        });
      });
    },
    put: function (key, value) {
      return openDb().then(function (d) {
        if (!d) return false;
        return new Promise(function (resolve) {
          try { var t = d.transaction("kv", "readwrite"); t.objectStore("kv").put(value, key); t.oncomplete = function () { resolve(true); }; t.onerror = t.onabort = function () { resolve(false); }; }
          catch (e) { resolve(false); }
        });
      });
    },
    clear: function (prefix) {
      return openDb().then(function (d) {
        if (!d) return;
        return new Promise(function (resolve) {
          try {
            var t = d.transaction("kv", "readwrite"), s = t.objectStore("kv");
            if (!prefix) s.clear();
            else { var r = s.openCursor(); r.onsuccess = function () { var c = r.result; if (!c) return; if (String(c.key).indexOf(prefix) === 0) c.delete(); c.continue(); }; }
            t.oncomplete = t.onerror = t.onabort = function () { resolve(); };
          } catch (e) { resolve(); }
        });
      });
    }
  };

  /** Lokaler Katalog-Zwischenspeicher. Ab 6 Stunden wird im Hintergrund aktualisiert, bis dahin gilt der gespeicherte Stand. */
  var CatalogCache = {
    MAX_AGE_MS: 6 * 60 * 60 * 1000, VERSION: 1,
    key: function (scope, key) { return "catalog:" + Core.hash(scope + "|" + key); },
    load: function (scope, key) {
      return Big.get(CatalogCache.key(scope, key)).then(function (v) {
        if (!v || v.v !== CatalogCache.VERSION || !Array.isArray(v.entries)) return null;
        return { entries: v.entries, savedAt: v.t, stale: function () { return Date.now() - v.t > CatalogCache.MAX_AGE_MS; } };
      });
    },
    save: function (scope, key, entries) { return Big.put(CatalogCache.key(scope, key), { v: CatalogCache.VERSION, t: Date.now(), entries: entries }); },
    clear: function () { return Big.clear("catalog:"); }
  };

  /** Zugang und Verlauf (Android: verschlüsselter Vault). */
  var Vault = {
    save: function (source) { if (!Prefs.set("vault:source", source.json())) throw new Error("Speichern fehlgeschlagen."); },
    load: function () { var j = Prefs.get("vault:source", null); return j ? Core.Source.from(j) : null; },
    saveHistory: function (scope, entries) { if (!Prefs.set("vault:history:" + scope, entries.slice(0, 30))) throw new Error("Speichern fehlgeschlagen."); },
    history: function (scope) { var a = Prefs.get("vault:history:" + scope, []); return Array.isArray(a) ? a.slice(0, 30) : []; },
    forget: function () {
      try { Object.keys(localStorage).forEach(function (k) { if (k.indexOf(PREFIX + "vault:") === 0) localStorage.removeItem(k); }); } catch (e) {}
    }
  };

  /** Feste Kanalnummern je Quelle; im Arbeitsspeicher gespiegelt, in IndexedDB gesichert (zu gross für localStorage). */
  var numberCache = {};
  var NumberStore = {
    preload: function (scope) {
      if (numberCache[scope]) return Promise.resolve(numberCache[scope]);
      return Big.get("numbers:" + scope).then(function (v) { numberCache[scope] = v && typeof v === "object" ? v : {}; return numberCache[scope]; });
    },
    apply: function (scope, entries, persist) {
      var existing = numberCache[scope] || {}, pinned = Prefs.get("pinned:" + scope, {});
      var numbers = Core.applyNumbers(entries, existing, pinned);
      if (persist) { numberCache[scope] = numbers; Big.put("numbers:" + scope, numbers); }
    }
  };

  // ---------- Netz (Catalog.request) ----------
  function request(url, asJson) {
    return new Promise(function (resolve, reject) {
      if (!Core.isWeb(url)) { reject(new Error("Ungültige Adresse.")); return; }
      var x = new XMLHttpRequest();
      try { x.open("GET", Core.Source.transport(url)); } catch (e) { reject(new Error("Ungültige Adresse.")); return; }
      x.timeout = 120000;
      x.onload = function () {
        var code = x.status;
        if (code === 401 || code === 403) return reject(new Error("Anmeldung abgelehnt. Bitte Zugang prüfen."));
        if (code < 200 || code > 299) return reject(new Error("Server antwortet nicht erfolgreich (" + code + ")."));
        var text = x.responseText || "";
        if (!asJson) return resolve(text);
        if (text.length > 48 * 1024 * 1024) return reject(new Error("Serverantwort zu gross."));
        try { resolve(JSON.parse(text)); } catch (e) { reject(new Error("Ungültige Serverantwort.")); }
      };
      x.onerror = function () { reject(new Error("Anbieter nicht erreichbar.")); };
      x.ontimeout = function () { reject(new Error("Anbieter nicht erreichbar.")); };
      x.send();
    });
  }

  /** Catalog: lädt Live/Filme/Serien aus Xtream oder der M3U. */
  function Catalog(source) { this.source = source; }
  Catalog.prototype.authenticate = function () {
    if (this.source.mode !== "xtream") return Promise.resolve(0);
    return request(this.source.api(""), true).then(function (r) { return Core.xtreamAuth(r, Date.now()); });
  };
  Catalog.prototype.array = function (action) {
    return request(this.source.api(action), true).then(function (r) { if (!Array.isArray(r)) throw new Error("Der Anbieter liefert keine gültige Liste."); return r; });
  };
  Catalog.prototype.load = function (kind) {
    var s = this.source, self = this;
    if (s.mode !== "xtream") return request(s.address, false).then(function (text) {
      if (/^\s*</.test(text.slice(0, 200))) throw new Error("Die Playlist-Adresse liefert eine Webseite statt einer M3U-Datei.");
      return Core.parseM3u(text, s.address);
    });
    var prefix = kind === "live" ? "live" : kind === "movie" ? "vod" : "series";
    return self.array("get_" + prefix + "_categories").then(function (categories) {
      return self.array(kind === "series" ? "get_series" : "get_" + prefix + "_streams").then(function (rows) { return Core.xtreamEntries(s, kind, categories, rows); });
    });
  };
  Catalog.prototype.detail = function (e) {
    var id = e.id.slice(e.id.indexOf(":") + 1);
    return request(this.source.api(e.kind === "series" ? "get_series_info" : "get_vod_info") + (e.kind === "series" ? "&series_id=" : "&vod_id=") + Core.encode(id), true)
      .then(function (r) { if (!r || typeof r !== "object" || Array.isArray(r)) throw new Error(); return r; });
  };
  Catalog.prototype.episodes = function (details) { return Core.xtreamEpisodes(this.source, details); };

  root.Store = { Prefs: Prefs, Big: Big, CatalogCache: CatalogCache, Vault: Vault, NumberStore: NumberStore, request: request, Catalog: Catalog };
})(this);
