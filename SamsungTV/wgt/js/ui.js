/* Fernbedienung, Fokus und Bedienelemente (entspricht TvStyle, Android-Fokussuche, AlertDialog und Toast). */
(function (root) {
  "use strict";
  var K = {
    LEFT: 37, UP: 38, RIGHT: 39, DOWN: 40, ENTER: 13, BACK: 10009, ESC: 27, BKSP: 8,
    CH_UP: 427, CH_DOWN: 428, PLAYPAUSE: 10252, PLAY: 415, PAUSE: 19, STOP: 413, FF: 417, RW: 412,
    INFO: 457, TOOLS: 10135, MENU: 18, PRECH: 10190, IME_DONE: 65376, IME_CANCEL: 65385,
    PAGE_UP: 33, PAGE_DOWN: 34
  };
  function isBack(k) { return k === K.BACK || k === K.ESC; }
  function digitOf(k) { return k >= 48 && k <= 57 ? k - 48 : k >= 96 && k <= 105 ? k - 96 : -1; }

  // ---------- Elemente ----------
  function h(tag, cls, text) { var e = document.createElement(tag); if (cls) e.className = cls; if (text != null) e.textContent = text; return e; }
  /** Knopf als Pille (TvStyle.button): Fokus weiss, ausgewählt Himmel-Tief, primär Himmel. */
  function button(label, action, opts) {
    opts = opts || {};
    var b = h("div", "btn f" + (opts.primary ? " primary" : "") + (opts.cls ? " " + opts.cls : ""), label);
    b._click = action || null;
    if (opts.selected) b.classList.add("selected");
    if (opts.label) b.setAttribute("aria-label", opts.label);
    return b;
  }
  function setEnabled(el, on) { el.classList.toggle("disabled", !on); }
  /** Titel mit orangem Schlusspunkt (Guide: Signal nur als Punkt). */
  function dotted(text) { var f = document.createDocumentFragment(); f.appendChild(document.createTextNode(text.replace(/\.$/, ""))); var s = h("span", "glut", "."); f.appendChild(s); return f; }

  // ---------- Fokus ----------
  var layers = [], current = null, keyHandlers = [], editing = null;
  function activeLayer() { return layers.length ? layers[layers.length - 1].el : document.body; }
  function visible(el) {
    if (!el.isConnected || el.classList.contains("disabled")) return false;
    var r = el.getBoundingClientRect(); if (r.width <= 0 || r.height <= 0) return false;
    for (var p = el; p && p !== document.body; p = p.parentElement) {
      var cs = p.style; if (cs.display === "none" || cs.visibility === "hidden") return false;
      if (p.hidden) return false;
    }
    return true;
  }
  function focusables(scope) {
    var all = (scope || activeLayer()).querySelectorAll(".f"), out = [];
    for (var i = 0; i < all.length; i++) if (visible(all[i])) out.push(all[i]);
    return out;
  }
  function focus(el, opts) {
    if (!el || el === current) { if (el) reveal(el); return; }
    var prev = current;
    if (prev) { prev.classList.remove("focused"); if (prev._blur) prev._blur(); }
    current = el; el.classList.add("focused");
    if (el._focus) el._focus();
    if (!(opts && opts.noReveal)) reveal(el);
    UI.onFocusChange && UI.onFocusChange(el, prev);
  }
  /** Scrollt umgebende Bereiche (Klasse «scroller», eigenes «_reveal») so, dass das Element sichtbar ist. */
  function reveal(el) {
    for (var p = el.parentElement; p && p !== document.body; p = p.parentElement) {
      if (p._reveal) { p._reveal(el); continue; }
      if (p.classList.contains("scroller")) {
        var pr = p.getBoundingClientRect(), er = el.getBoundingClientRect(), pad = p._pad || 48;
        if (er.top < pr.top + pad) p.scrollTop -= (pr.top + pad - er.top);
        else if (er.bottom > pr.bottom - pad) p.scrollTop += (er.bottom - (pr.bottom - pad));
        if (p.classList.contains("hscroll")) {
          if (er.left < pr.left + pad) p.scrollLeft -= (pr.left + pad - er.left);
          else if (er.right > pr.right - pad) p.scrollLeft += (er.right - (pr.right - pad));
        }
      }
    }
  }
  /** Fokussuche wie Androids FocusFinder: Kandidaten im «Strahl» bevorzugt, sonst gewichtete Entfernung (13·Haupt² + Neben²). */
  function findNext(from, dir, list) {
    var a = from.getBoundingClientRect(), best = null, bestScore = Infinity, beamBest = null, beamScore = Infinity;
    for (var i = 0; i < list.length; i++) {
      var c = list[i]; if (c === from || from.contains(c) || c.contains(from)) continue;
      var b = c.getBoundingClientRect(), major, minor, beam;
      if (dir === "right") { if (b.left < a.right - 4 && (b.left + b.right) / 2 <= (a.left + a.right) / 2 + 1) continue; if (b.right <= a.right) continue; major = Math.max(0, b.left - a.right); minor = Math.abs((b.top + b.bottom) / 2 - (a.top + a.bottom) / 2); beam = b.bottom > a.top && b.top < a.bottom; }
      else if (dir === "left") { if (b.right > a.left + 4 && (b.left + b.right) / 2 >= (a.left + a.right) / 2 - 1) continue; if (b.left >= a.left) continue; major = Math.max(0, a.left - b.right); minor = Math.abs((b.top + b.bottom) / 2 - (a.top + a.bottom) / 2); beam = b.bottom > a.top && b.top < a.bottom; }
      else if (dir === "down") { if (b.top < a.bottom - 4 && (b.top + b.bottom) / 2 <= (a.top + a.bottom) / 2 + 1) continue; if (b.bottom <= a.bottom) continue; major = Math.max(0, b.top - a.bottom); minor = Math.abs((b.left + b.right) / 2 - (a.left + a.right) / 2); beam = b.right > a.left && b.left < a.right; }
      else { if (b.bottom > a.top + 4 && (b.top + b.bottom) / 2 >= (a.top + a.bottom) / 2 - 1) continue; if (b.top >= a.top) continue; major = Math.max(0, a.top - b.bottom); minor = Math.abs((b.left + b.right) / 2 - (a.left + a.right) / 2); beam = b.right > a.left && b.left < a.right; }
      var score = 13 * major * major + minor * minor;
      if (beam && score < beamScore) { beamScore = score; beamBest = c; }
      if (score < bestScore) { bestScore = score; best = c; }
    }
    return beamBest || best;
  }
  function move(dir) {
    var list = focusables();
    if (!current || list.indexOf(current) < 0) { if (list.length) focus(list[0]); return true; }
    if (current._nav && current._nav(dir)) return true;
    for (var p = current.parentElement; p && p !== document.body; p = p.parentElement) if (p._nav && p._nav(dir, current)) return true;
    var next = findNext(current, dir, list);
    if (next) { focus(next); return true; }
    return false;
  }
  /** Ebenen (Seiten, Dialoge): Nur die oberste ist bedienbar. */
  function pushLayer(el, opts) {
    layers.push({ el: el, opts: opts || {}, restore: current });
    if (current) { current.classList.remove("focused"); current = null; }
  }
  function popLayer(el, noRestore) {
    for (var i = layers.length - 1; i >= 0; i--) if (layers[i].el === el) {
      var l = layers.splice(i, 1)[0];
      if (current && el.contains(current)) current = null;
      if (!noRestore && l.restore && l.restore.isConnected && i === layers.length) focus(l.restore);
      return;
    }
  }
  function focusFirst(scope) { var l = focusables(scope); if (l.length) focus(l[0]); }

  // ---------- Tasten ----------
  var okDown = false, okLong = false, okTimer = null;
  function onKey(e) {
    var k = e.keyCode;
    if (editing) {
      if (k === K.UP || k === K.DOWN) { stopEditing(); e.preventDefault(); move(k === K.UP ? "up" : "down"); return; }
      if (k === K.ENTER || k === K.IME_DONE) { var ed = editing; stopEditing(); e.preventDefault(); if (ed._submit) ed._submit(); return; }
      if (k === K.IME_CANCEL || isBack(k)) { stopEditing(); e.preventDefault(); return; }
      return; // Zeichen gehen ans Feld
    }
    for (var i = keyHandlers.length - 1; i >= 0; i--) if (keyHandlers[i](e, "down")) { e.preventDefault(); return; }
    if (k === K.ENTER) {
      e.preventDefault();
      if (okDown) return; okDown = true; okLong = false;
      clearTimeout(okTimer);
      var target = current;
      okTimer = setTimeout(function () { if (okDown && target === current && current && current._long) { okLong = true; current._long(); } }, 500);
      return;
    }
    var dir = k === K.LEFT ? "left" : k === K.RIGHT ? "right" : k === K.UP ? "up" : k === K.DOWN ? "down" : null;
    if (dir) { e.preventDefault(); move(dir); return; }
    if (isBack(k) || (k === K.BKSP && !editing)) { e.preventDefault(); back(); return; }
    if ((k === K.TOOLS || k === K.MENU) && current && current._long) { e.preventDefault(); current._long(); }
  }
  function onKeyUp(e) {
    var k = e.keyCode;
    if (editing) return;
    for (var i = keyHandlers.length - 1; i >= 0; i--) if (keyHandlers[i](e, "up")) { e.preventDefault(); okDown = false; clearTimeout(okTimer); return; }
    if (k !== K.ENTER) return;
    e.preventDefault();
    var was = okDown; okDown = false; clearTimeout(okTimer);
    if (!was || okLong) return;
    activate(current);
  }
  function activate(el) {
    if (!el || el.classList.contains("disabled")) return;
    if (el.tagName === "INPUT") { startEditing(el); return; }
    if (el._click) el._click();
  }
  function back() {
    if (layers.length) { var l = layers[layers.length - 1]; if (l.opts.onBack) { l.opts.onBack(); return; } }
    UI.onBack && UI.onBack();
  }
  function startEditing(input) { editing = input; input.focus(); try { input.setSelectionRange(input.value.length, input.value.length); } catch (e) {} }
  function stopEditing() { if (!editing) return; var i = editing; editing = null; i.blur(); }

  // ---------- Dialog (AlertDialog) ----------
  /** opts: title, message, items[], onItem(i), buttons[{label, primary, action}], input {value, hint}, onClose */
  function dialog(opts) {
    var shade = h("div", "dialog-shade"), box = h("div", "dialog");
    if (opts.title) box.appendChild(h("div", "dialog-title", opts.title));
    if (opts.message) box.appendChild(h("div", "dialog-message", opts.message));
    var input = null;
    if (opts.input) { input = h("input", "field f"); input.type = "text"; input.value = opts.input.value || ""; input.placeholder = opts.input.hint || ""; input.setAttribute("autocomplete", "off"); box.appendChild(input); }
    function close() { if (!shade.parentNode) return; shade.parentNode.removeChild(shade); popLayer(shade); if (opts.onClose) opts.onClose(); }
    if (opts.items && opts.items.length) {
      var list = h("div", "dialog-list scroller");
      opts.items.forEach(function (label, i) {
        var it = h("div", "dialog-item f", label);
        it._click = function () { close(); opts.onItem && opts.onItem(i); };
        list.appendChild(it);
      });
      box.appendChild(list);
    }
    var row = h("div", "dialog-buttons");
    (opts.buttons || []).forEach(function (b) {
      row.appendChild(button(b.label, function () { close(); b.action && b.action(input ? input.value : undefined); }, { primary: b.primary }));
    });
    if (row.children.length) box.appendChild(row);
    if (input) input._submit = function () { var p = (opts.buttons || []).filter(function (b) { return b.primary; })[0]; if (p) { close(); p.action && p.action(input.value); } };
    shade.appendChild(box); document.getElementById("overlay").appendChild(shade);
    pushLayer(shade, { onBack: close });
    focusFirst(shade);
    return { close: close, el: shade };
  }

  // ---------- Toast ----------
  var toastTimer = null;
  function toast(text, long) {
    var t = document.getElementById("toast"); t.textContent = text; t.classList.add("show");
    clearTimeout(toastTimer); toastTimer = setTimeout(function () { t.classList.remove("show"); }, long ? 3500 : 2000);
  }

  function addKeyHandler(fn) {
    var safe = function (e, phase) { try { return fn(e, phase); } catch (x) { if (root.console) console.error(x); return false; } };
    safe.inner = fn; keyHandlers.push(safe);
  }
  function removeKeyHandler(fn) { for (var i = keyHandlers.length - 1; i >= 0; i--) if (keyHandlers[i].inner === fn) keyHandlers.splice(i, 1); }

  document.addEventListener("keydown", onKey);
  document.addEventListener("keyup", onKeyUp);

  var UI = {
    K: K, isBack: isBack, digitOf: digitOf, h: h, button: button, setEnabled: setEnabled, dotted: dotted,
    focus: focus, move: move, focusFirst: focusFirst, focusables: focusables, reveal: reveal, pushLayer: pushLayer, popLayer: popLayer,
    current: function () { return current; }, clearFocus: function () { if (current) current.classList.remove("focused"); current = null; },
    layerCount: function () { return layers.length; }, topLayer: function () { return layers.length ? layers[layers.length - 1].el : null; },
    dialog: dialog, toast: toast, addKeyHandler: addKeyHandler, removeKeyHandler: removeKeyHandler, activate: activate,
    stopEditing: stopEditing, isEditing: function () { return !!editing; },
    onBack: null, onFocusChange: null
  };
  root.UI = UI;
})(this);
