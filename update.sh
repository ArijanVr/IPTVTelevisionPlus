#!/bin/zsh
# IPTelevision+ Update: baut Mac (signiert, notarisiert), iPhone und Google TV neu und füllt die Download-Ordner.
# Jeder Lauf legt zusätzlich einen neuen Release-Ordner an: iCloud «Projektelab/01_Apps/IPTelevision+/Releases/<Datum>_v<X.Y.Z>/Dateien/{macOS,iOS,Android}»
#   (Basis änderbar mit ARJO_UPDATE_ROOT; gibt es den Ordner schon, wird _2, _3 … angehängt).
# Aufruf:  ./update.sh [--version 1.1.0] [--only mac|ios|android]... [--skip-tests] [--install] [--dry-run]
# --install: installiert die neue IPA auf alle gerade verbundenen, entsperrten iPhones/iPads (müssen im Profil registriert sein).
# Voraussetzungen: Xcode, xcodegen, Developer-ID-Zertifikat, Keychain-Profil "arjo-notary", Android SDK + JDK 17.
# Nichts wird committet, gepusht oder hochgeladen. Alte Download-Dateien werden ersetzt.
set -u
setopt null_glob
ROOT="${0:A:h}"
SRC="$ROOT/Quellcode"
REL="$SRC/ARJOTV-RELEASE"
TEAM="${ARJO_TEAM_ID:-D752V8XA4G}"
DEVID="${ARJO_DEVID:-Developer ID Application: ARIJAN VRANJA (D752V8XA4G)}"
NOTARY="${ARJO_NOTARY_PROFILE:-arjo-notary}"
WORK="$(mktemp -d)"
VERSION=""; TESTS=1; DRY=0; INSTALL=0; ONLY=()
while [ $# -gt 0 ]; do
  case "$1" in
    --version) VERSION="$2"; shift 2 ;;
    --only) ONLY+=("$2"); shift 2 ;;
    --skip-tests) TESTS=0; shift ;;
    --install) INSTALL=1; shift ;;
    --dry-run) DRY=1; shift ;;
    *) echo "Unbekannte Option: $1" >&2; exit 2 ;;
  esac
done
want() { [ ${#ONLY[@]} -eq 0 ] || [[ " ${ONLY[*]} " == *" $1 "* ]]; }
declare -A RESULT
step() { echo "→ $*"; }
run() { if [ $DRY -eq 1 ]; then echo "   (Testlauf) $*"; return 0; fi; "$@"; }
fail() { echo "FEHLER: $*" >&2; RESULT[$CURRENT]="FEHLER"; }

# Voraussetzungen prüfen
if [ $DRY -eq 0 ]; then
  command -v xcodegen >/dev/null || { echo "xcodegen fehlt" >&2; exit 1; }
  if want mac; then
    security find-identity -v -p codesigning | grep -q "$DEVID" || { echo "Zertifikat fehlt: $DEVID" >&2; exit 1; }
    xcrun notarytool history --keychain-profile "$NOTARY" >/dev/null 2>&1 || { echo "Keychain-Profil '$NOTARY' fehlt (xcrun notarytool store-credentials)" >&2; exit 1; }
  fi
fi

# Version setzen
if [ -n "$VERSION" ]; then
  [[ "$VERSION" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] || { echo "Ungültige Version: $VERSION" >&2; exit 2; }
  step "Version $VERSION setzen"
  if [ $DRY -eq 0 ]; then
    BUILD=$(( $(sed -n 's/.*CURRENT_PROJECT_VERSION: "\([0-9]*\)".*/\1/p' "$SRC/project.yml" | head -1) + 1 ))
    sed -i '' "s/MARKETING_VERSION: \".*\"/MARKETING_VERSION: \"$VERSION\"/; s/CURRENT_PROJECT_VERSION: \".*\"/CURRENT_PROJECT_VERSION: \"$BUILD\"/" "$SRC/project.yml"
    (cd "$SRC" && xcodegen generate >/dev/null)
    CODE=$(( $(sed -n "s/.*versionCode \([0-9]*\).*/\1/p" "$ROOT/AndroidTV/app/build.gradle" | head -1) + 1 ))
    sed -i '' "s/versionName '.*'/versionName '$VERSION'/; s/versionCode [0-9]*/versionCode $CODE/" "$ROOT/AndroidTV/app/build.gradle"
    sed -i '' "s/IPTelevision-GoogleTV-[0-9.]*apk/IPTelevision-GoogleTV-$VERSION.apk/g" "$ROOT/AndroidTV/scripts/build.sh"
    sed -i '' "s/IPTelevision-GoogleTV-[0-9.]*[0-9]\.apk/IPTelevision-GoogleTV-$VERSION.apk/g" "$ROOT/Download-GoogleTV/ANLEITUNG.md" "$ROOT/AndroidTV/README.md"
  fi
fi
CUR_VERSION="${VERSION:-$(sed -n 's/.*MARKETING_VERSION: "\(.*\)".*/\1/p' "$SRC/project.yml" | head -1)}"

# Neuer Update-Ordner pro Build (wird erst beim ersten fertigen Download angelegt)
# Repo liegt seit 2026-11-13 in ~/Developer/IPTelevision-plus; Releases in iCloud › Projektelab (Regel D in Projektelab/MAIN.md)
UPDATE_ROOT="${ARJO_UPDATE_ROOT:-$HOME/Library/Mobile Documents/com~apple~CloudDocs/Projektelab/01_Apps/IPTelevision+/Releases}"
REL_VERSION="$CUR_VERSION"; while [ "$(printf '%s' "$REL_VERSION" | tr -cd . | wc -c | tr -d ' ')" -lt 2 ]; do REL_VERSION="$REL_VERSION.0"; done
UPD="$UPDATE_ROOT/$(date +%Y-%m-%d)_v$REL_VERSION"
n=2; base="$UPD"; while [ -e "$UPD" ]; do UPD="${base}_$n"; n=$((n+1)); done
step "Update-Ordner: $UPD"

# Tests
if [ $TESTS -eq 1 ]; then
  CURRENT=tests; step "Tests (Swift-Packages)"
  for p in ARJONetwork ARJOData ARJOPlayer ARJOUI; do
    run zsh -c "cd '$SRC/Packages/$p' && swift test >'$WORK/test-$p.log' 2>&1" || { fail "Tests $p, siehe $WORK/test-$p.log"; exit 1; }
  done
fi

publish() { # Quelle Zielordner Zieldatei Sparte
  [ $DRY -eq 1 ] && { echo "   (Testlauf) $1 → $2/$3 und $UPD/Dateien/$4/$3"; return 0; }
  mkdir -p "$2"; rm -f "$2"/*.ipa "$2"/*.dmg "$2"/*.apk "$2"/*.sha256
  cp "$1" "$2/$3"; (cd "$2" && shasum -a 256 "$3" > "$3.sha256")
  mkdir -p "$UPD/Dateien/$4"; cp "$2/$3" "$2/$3.sha256" "$UPD/Dateien/$4/"
  [ -f "$2/ANLEITUNG.md" ] && cp "$2/ANLEITUNG.md" "$UPD/Dateien/$4/"
  return 0
}

# macOS
if want mac; then
  CURRENT=mac; step "macOS: bauen, signieren, notarisieren, DMG"
  if run zsh -c "cd '$REL' && ARJO_ONLY_MAC=1 ARJO_DEVID='$DEVID' ARJO_NOTARY_PROFILE='$NOTARY' ./scripts/build.sh >'$WORK/mac.log' 2>&1"; then
    if [ $DRY -eq 1 ] || { [ -f "$REL/downloads/ARJOTV-macOS.dmg" ] && xcrun stapler validate "$REL/downloads/ARJOTV-macOS.dmg" >/dev/null 2>&1; }; then
      publish "$REL/downloads/ARJOTV-macOS.dmg" "$ROOT/Download-macOS" "IPTelevision-Mac.dmg" macOS && RESULT[mac]="ok"
    else fail "DMG fehlt oder nicht notarisiert, siehe $WORK/mac.log und ${TMPDIR:-/tmp}/iptelevision-build/logs"; fi
  else fail "Mac-Build, siehe $WORK/mac.log"; fi
fi

install_devices() {
  [ $INSTALL -eq 1 ] || return 0
  step "Installation auf verbundene Geräte"
  [ $DRY -eq 1 ] && { echo "   (Testlauf) devicectl device install app"; return 0; }
  xcrun devicectl list devices --json-output "$WORK/devices.json" >/dev/null 2>&1 || { echo "   devicectl nicht verfügbar"; return 0; }
  local ids; ids=("${(@f)$(python3 -I - "$WORK/devices.json" <<'PY'
import json,sys
for d in json.load(open(sys.argv[1]))["result"]["devices"]:
    h,c=d["hardwareProperties"],d["connectionProperties"]
    if h.get("reality")=="physical" and h.get("platform")=="iOS" and c.get("tunnelState")=="connected":
        print(d["identifier"]+"|"+d["deviceProperties"].get("name",""))
PY
)}")
  [ -z "${ids[1]:-}" ] && { echo "   Kein verbundenes iPhone/iPad gefunden (Kabel, entsperrt, Entwicklermodus)."; return 0; }
  local entry
  for entry in "${ids[@]}"; do
    if xcrun devicectl device install app --device "${entry%%|*}" "$ROOT/Download-iOS/IPTelevision-iOS.ipa" >"$WORK/install.log" 2>&1; then echo "   installiert: ${entry#*|}"
    else echo "   FEHLER bei ${entry#*|}, siehe $WORK/install.log (Gerät nicht im Profil registriert?)"; fi
  done
}

# iPhone
if want ios; then
  CURRENT=ios; step "iPhone: archivieren und exportieren"
  PL="$WORK/export.plist"
  cat >"$PL" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>method</key><string>${ARJO_IOS_METHOD:-debugging}</string><key>teamID</key><string>$TEAM</string><key>signingStyle</key><string>automatic</string></dict></plist>
EOF
  if run zsh -c "cd '$SRC' && xcodebuild -project ARJOTV.xcodeproj -scheme ARJOTV -configuration Release -destination 'generic/platform=iOS' -archivePath '$WORK/iOS.xcarchive' DEVELOPMENT_TEAM=$TEAM -derivedDataPath '$WORK/dd-ios' -allowProvisioningUpdates archive >'$WORK/ios-archive.log' 2>&1 && xcodebuild -exportArchive -archivePath '$WORK/iOS.xcarchive' -exportPath '$WORK/ios-export' -exportOptionsPlist '$PL' -allowProvisioningUpdates >'$WORK/ios-export.log' 2>&1"; then
    IPA="$(ls "$WORK"/ios-export/*.ipa 2>/dev/null | head -1)"
    if [ $DRY -eq 1 ] || [ -n "$IPA" ]; then publish "$IPA" "$ROOT/Download-iOS" "IPTelevision-iOS.ipa" iOS && RESULT[ios]="ok"; install_devices; else fail "IPA fehlt, siehe $WORK/ios-export.log"; fi
  else fail "iOS-Build, siehe $WORK/ios-archive.log und $WORK/ios-export.log"; fi
fi

# Google TV
if want android; then
  CURRENT=android; step "Google TV: Tests, Lint, APK"
  if run zsh -c "cd '$ROOT/AndroidTV' && ./scripts/build.sh >'$WORK/android.log' 2>&1"; then
    APK="$(ls -t "$ROOT"/AndroidTV/Installation/*.apk 2>/dev/null | head -1)"
    if [ $DRY -eq 1 ] || [ -n "$APK" ]; then
      publish "$APK" "$ROOT/Download-GoogleTV" "IPTelevision-GoogleTV-$CUR_VERSION.apk" Android && RESULT[android]="ok"
      [ $DRY -eq 0 ] && find "$ROOT/AndroidTV/Installation" -name "*.apk*" ! -name "*-$CUR_VERSION.apk*" -delete
    else fail "APK fehlt, siehe $WORK/android.log"; fi
  else fail "Android-Build, siehe $WORK/android.log"; fi
fi

# Aufräumen und Bericht
[ $DRY -eq 0 ] && rm -rf "$REL/.build-work" "${TMPDIR:-/tmp}/iptelevision-build/dd-mac" "$REL/downloads" "$SRC"/Packages/*/.build
echo "\nIPTelevision+ $CUR_VERSION: Ergebnis"
for k in mac ios android; do want $k && echo "  $k: ${RESULT[$k]:-nicht erfolgreich}"; done
[ -d "$UPD" ] && echo "Update-Ordner: $UPD"
echo "Logs: $WORK"
