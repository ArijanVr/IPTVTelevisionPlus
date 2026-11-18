#!/bin/bash
# Baut IPTelevision-SamsungTV-<Version>.wgt (Tizen-Web-App) in Installation/.
#   PROFILE=<Zertifikatsprofil> signiert mit Tizen Studio, INSTALL=1 installiert zusätzlich auf die TV (TV_IP, TV_NAME).
# Eingebaute Quellen kommen aus playlist.<Name>.local.properties und playlist.local.properties (playlistUrl=…, nicht versioniert). Nichts wird hochgeladen.
set -euo pipefail
cd "$(dirname "$0")"
VERSION=$(grep -o 'id="https[^"]*" version="[0-9.]*"' wgt/config.xml | sed 's/.*version="//; s/"//')
# Eingebaute Quellen: playlist.<Name>.local.properties (z. B. Durim) zuerst, dann playlist.local.properties als «Standard».
# Die erste Quelle ist die Voreinstellung beim Start.
python3 -I - <<'PY'
import json, os, glob, re
def url(path):
    for line in open(path, encoding="utf-8"):
        if line.startswith("playlistUrl="): return line[len("playlistUrl="):].strip()
    return ""
lists = []
for f in sorted(glob.glob("playlist.*.local.properties")):
    name = re.match(r"playlist\.(.+)\.local\.properties$", f).group(1)
    u = url(f)
    if not u: continue
    # Xtream-Adressen (get.php mit Benutzer und Passwort) laufen über die Xtream-API: viele Anbieter sperren get.php.
    m = re.match(r"^(https?://[^/?#]+)/get\.php\?(.*)$", u)
    q = dict(kv.split("=", 1) for kv in m.group(2).split("&") if "=" in kv) if m else {}
    if m and q.get("username") and q.get("password"):
        from urllib.parse import unquote
        lists.append({"name": name, "mode": "xtream", "address": m.group(1), "user": unquote(q["username"]), "password": unquote(q["password"])})
    else:
        lists.append({"name": name, "url": u})
env = os.environ.get("IPTV_DEFAULT_PLAYLIST_URL", "")
std = env or (url("playlist.local.properties") if os.path.exists("playlist.local.properties") else "")
if std: lists.append({"name": "Standard", "url": std})
first = lists[0] if lists else None
cfg = {"preset": ({k: first[k] for k in ("mode", "address", "user", "password")} if first and "mode" in first else (first["url"] if first else "")), "playlists": lists}
open("wgt/js/config.local.js", "w").write("window.IPTV_CONFIG = " + json.dumps(cfg) + ";\n")
print("Eingebaute Quellen: " + (", ".join(l["name"] + (" (Xtream)" if "mode" in l else " (M3U)") for l in lists) or "keine"))
PY
grep -q "VERSION: \"$VERSION\"" wgt/js/app.js || { echo "Version in app.js passt nicht zu config.xml ($VERSION)" >&2; exit 1; }
for f in wgt/js/*.js; do node --check "$f"; done
node tests/core.test.js
node tests/player.test.js
xmllint --noout wgt/config.xml
mkdir -p Installation
NAME="IPTelevision-SamsungTV-$VERSION.wgt"
rm -f "Installation/$NAME"
(cd wgt && zip -qr -X "../Installation/$NAME" config.xml index.html icon.png css js img fonts -x '.*')
echo "unsigniert: Installation/$NAME"
if [ -n "${PROFILE:-}" ]; then
  TIZEN="${TIZEN_STUDIO:-$HOME/tizen-studio}/tools/ide/bin/tizen"
  OUT="$PWD/signed"; rm -rf "$OUT" && mkdir "$OUT"
  "$TIZEN" package -t wgt -s "$PROFILE" -o "$OUT" -- "$PWD/Installation/$NAME" | tail -1
  cp "$OUT/$NAME" "Installation/$NAME"
  (cd Installation && shasum -a 256 "$NAME" > "$NAME.sha256")
  echo "signiert: Installation/$NAME"
  if [ -n "${INSTALL:-}" ]; then
    "${TIZEN_STUDIO:-$HOME/tizen-studio}/tools/sdb" connect "${TV_IP:-192.168.1.85}" >/dev/null
    "$TIZEN" install -n "Installation/$NAME" -t "${TV_NAME:-QE75Q65AAUXXN}" | grep -iE "success|fail|error"
  fi
fi
