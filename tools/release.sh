#!/bin/zsh
# IPTelevision+ Release: einheitlicher Einstieg, ruft das bestehende ./update.sh auf (baut Mac, iPhone, Google TV).
# Ziel: iCloud Drive › Projektelab/01_Apps/IPTelevision+/Releases/<JJJJ-MM-TT>_v<X.Y.Z>/Dateien/<Plattform> (Regel D in Projektelab/MAIN.md).
# Das Repo liegt ausserhalb von iCloud in ~/Developer/IPTelevision-plus. Anderer Zielordner: PROJEKTELAB_RELEASES setzen.
# Danach Release.md aus Projektelab/99_Vorlagen/Release.md im Release-Ordner anlegen.
# update.sh hängt _2, _3 … an, wenn der Ordner schon existiert. Alte Release-Ordner werden nie überschrieben.
# Achtung: update.sh ersetzt die Dateien in Download-macOS/-iOS/-GoogleTV und räumt Build-Caches weg.
# Aufruf: tools/release.sh [Optionen von update.sh]   z. B. --version 2.3.0, --only mac, --skip-tests, --dry-run
#         tools/release.sh --pfad                     nur den Zielordner anzeigen, nichts bauen
set -euo pipefail
here=${0:A:h:h}                      # Repo-Wurzel
releases=${PROJEKTELAB_RELEASES:-"$HOME/Library/Mobile Documents/com~apple~CloudDocs/Projektelab/01_Apps/IPTelevision+/Releases"}
[[ -d $releases ]] || { echo "Releases-Ordner fehlt: $releases (Repo verschoben? Pfad in tools/release.sh prüfen)" >&2; exit 1; }
ziel() { local v=$1; while [[ ${#v//[^.]/} -lt 2 ]]; do v="$v.0"; done; local base="$releases/$(date +%Y-%m-%d)_v$v" d n=2; d=$base; while [[ -e $d ]]; do d="${base}_$n"; n=$((n+1)); done; print -r -- "$d/Dateien/$2"; }

if [[ ${1:-} == --pfad ]]; then
  version=$(sed -n 's/.*MARKETING_VERSION: "\(.*\)".*/\1/p' "$here/Quellcode/project.yml" | head -1)
  echo "Ziel: $(ziel "$version" '{macOS,iOS,Android}')"; exit 0
fi
exec "$here/update.sh" "$@"
