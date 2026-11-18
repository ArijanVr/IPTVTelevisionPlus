#!/bin/zsh
# ARJOTV – Multi-Plattform-Build. Aufruf: ARJOTV-RELEASE/scripts/build.sh
# Optional: ARJO_TEAM_ID=XXXXXXXXXX (sonst aus dem lokalen Provisioning Profile von ch.arjo.iptelevision erkannt)
#           ARJO_EXPORT_METHOD=debugging (kostenlos, Standard) | release-testing | app-store-connect (bezahlt)
#           ARJO_DEVID="Developer ID Application: NAME (TEAMID)"  signiert die Mac-App mit Hardened Runtime (statt ad-hoc)
#           ARJO_NOTARY_PROFILE=name   Keychain-Profil von `xcrun notarytool store-credentials`: notarisiert, heftet an und baut eine DMG
#           ARJO_ONLY_MAC=1            überspringt iOS/tvOS
# Verändert weder das Xcode-Projekt noch dessen Signing-Einstellungen: alles wird per Kommandozeile übergeben.
set -u
HERE="${0:A:h}"
REL="$(dirname "$HERE")"
PROJ_DIR="$(dirname "$REL")"
# Arbeitsordner ausserhalb von iCloud Drive: iCloud hängt sonst während des Baus Attribute an die App und die Signaturprüfung scheitert.
WORK="${ARJO_WORK:-${TMPDIR:-/tmp}/iptelevision-build}"
LOGS="$WORK/logs"
mkdir -p "$LOGS" "$REL/downloads" "$REL/simulator-builds/iOS" "$REL/simulator-builds/tvOS"

# Fest ARJOTV.xcodeproj: iCloud legt sonst Kopien wie «ARJOTV 2.xcodeproj» an, die alphabetisch zuerst kämen (falsche App).
PROJECT="$PROJ_DIR/ARJOTV.xcodeproj"
[ -d "$PROJECT" ] || { echo "Projekt fehlt: $PROJECT" >&2; exit 1; }
SCHEME="${ARJO_SCHEME:-$(xcodebuild -list -project "$PROJECT" 2>/dev/null | awk '/Schemes:/{f=1;next} f&&NF{print $1}' | grep -ix 'ARJOTV' | head -1)}"
SETTINGS="$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -showBuildSettings 2>/dev/null)"
BUNDLE_ID="$(echo "$SETTINGS" | awk -F' = ' '/ PRODUCT_BUNDLE_IDENTIFIER/{print $2; exit}')"
VERSION="$(echo "$SETTINGS" | awk -F' = ' '/ MARKETING_VERSION/{print $2; exit}')"
BUILD_NO="$(echo "$SETTINGS" | awk -F' = ' '/ CURRENT_PROJECT_VERSION/{print $2; exit}')"
echo "Projekt: $PROJECT | Scheme: $SCHEME | Bundle-ID: $BUNDLE_ID | Version: $VERSION ($BUILD_NO)"

typeset -A STATUS NOTE; setopt null_glob
run() { # name logfile cmd...
  local name="$1" log="$LOGS/$2.log"; shift 2
  echo "→ $name"; "$@" >"$log" 2>&1; local rc=$?
  if [ $rc -ne 0 ]; then echo "  FEHLER (siehe $log)"; grep -E "error:" "$log" | sort -u | head -5; fi
  return $rc
}
XB=(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release)
# Unsignierte Builds haben keine iCloud-Berechtigung: dort ohne Kompilierflag ICLOUD_SYNC bauen
# (CloudKit würde die App ohne Berechtigung beim Start beenden). Release setzt sonst keine Bedingungen.
NOSYNC=(SWIFT_ACTIVE_COMPILATION_CONDITIONS=)

# ---- macOS (universal) ----
# Mit ARJO_DEVID: Archiv + Export «developer-id» mit automatischer Signierung. Xcode bettet das Developer-ID-Profil
# mit iCloud-Container ein (nötig für CloudKit ausserhalb des App Store) und setzt die Hardened Runtime.
# Ohne ARJO_DEVID: unsigniert bauen, ad-hoc signieren, ohne iCloud-Sync.
DEVID="${ARJO_DEVID:-}"; NOTARY="${ARJO_NOTARY_PROFILE:-}"
if [ -n "$DEVID" ]; then
  MACARCH="$WORK/ARJOTV-mac.xcarchive"; MACEXP="$WORK/export-mac"; rm -rf "$MACARCH" "$MACEXP"
  cat >"$WORK/export-mac.plist" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>method</key><string>developer-id</string><key>signingStyle</key><string>automatic</string></dict></plist>
PL
  run "macOS Archiv" mac "${XB[@]}" -destination 'generic/platform=macOS' -archivePath "$MACARCH" -derivedDataPath "$WORK/dd-mac" -allowProvisioningUpdates archive \
    && run "macOS Export (Developer ID)" mac-export xcodebuild -exportArchive -archivePath "$MACARCH" -exportPath "$MACEXP" -exportOptionsPlist "$WORK/export-mac.plist" -allowProvisioningUpdates
  MACOK=$?
  APP="$(ls -d "$MACEXP/"*.app 2>/dev/null | head -1)"
  SIGN=(codesign --force --options runtime --timestamp --sign "$DEVID")   # nur noch für die DMG
  SIGNNOTE="Developer ID, Hardened Runtime, iCloud-Profil eingebettet"
else
  run "macOS Build" mac "${XB[@]}" -destination 'generic/platform=macOS' -derivedDataPath "$WORK/dd-mac" ONLY_ACTIVE_ARCH=NO CODE_SIGNING_ALLOWED=NO "${NOSYNC[@]}" build
  MACOK=$?
  APP="$(ls -d "$WORK/dd-mac/Build/Products/Release/"*.app 2>/dev/null | head -1)"
  SIGN=(codesign --force --sign -)   # Ad-hoc ohne --deep: erst Frameworks, dann die App
  SIGNNOTE="ad-hoc signiert, nicht notarisiert, ohne iCloud-Sync"
  if [ $MACOK -eq 0 ]; then
    # Von innen nach aussen: verschachtelte Bundles/Binaries der Frameworks, Frameworks, dann die App.
    for fw in "$APP"/Contents/Frameworks/*(N); do
      for nested in "$fw"/Versions/*/(XPCServices|Helpers|Libraries)/*(N); do "${SIGN[@]}" "$nested" >>"$LOGS/mac.log" 2>&1; done
      "${SIGN[@]}" "$fw" >>"$LOGS/mac.log" 2>&1
    done
    "${SIGN[@]}" "$APP" >>"$LOGS/mac.log" 2>&1
  fi
fi
if [ $MACOK -eq 0 ] && [ -n "$APP" ]; then
  # iCloud Drive hängt Finder-/FileProvider-Attribute an: sie machen die Signaturprüfung ungültig («detritus not allowed»).
  xattr -cr "$APP" 2>/dev/null || true
  if codesign --verify --verbose=2 "$APP" >>"$LOGS/mac.log" 2>&1 && codesign --verify --deep --strict "$APP" 2>>"$LOGS/mac.log"; then
    ARCHS="$(lipo -archs "$APP/Contents/MacOS/"*)"
    if [ -n "$DEVID" ] && [ -n "$NOTARY" ]; then
      echo "→ macOS Notarisierung (kann einige Minuten dauern)"
      NZIP="$WORK/notarize-app.zip"; rm -f "$NZIP"; ditto -c -k --keepParent "$APP" "$NZIP"
      if xcrun notarytool submit "$NZIP" --keychain-profile "$NOTARY" --wait >"$LOGS/notarize-app.log" 2>&1 && grep -q "status: Accepted" "$LOGS/notarize-app.log"; then
        xcrun stapler staple "$APP" >>"$LOGS/notarize-app.log" 2>&1 && SIGNNOTE="Developer ID, notarisiert und angeheftet"
        STAGE="$WORK/dmg"; rm -rf "$STAGE" "$REL/downloads/ARJOTV-macOS.dmg"; mkdir -p "$STAGE"
        ditto "$APP" "$STAGE/$(basename "$APP")"; ln -s /Applications "$STAGE/Applications"
        hdiutil create -volname "IPTelevision+" -srcfolder "$STAGE" -ov -format UDZO "$REL/downloads/ARJOTV-macOS.dmg" >>"$LOGS/notarize-dmg.log" 2>&1
        "${SIGN[@]}" "$REL/downloads/ARJOTV-macOS.dmg" >>"$LOGS/notarize-dmg.log" 2>&1
        xcrun notarytool submit "$REL/downloads/ARJOTV-macOS.dmg" --keychain-profile "$NOTARY" --wait >>"$LOGS/notarize-dmg.log" 2>&1 \
          && xcrun stapler staple "$REL/downloads/ARJOTV-macOS.dmg" >>"$LOGS/notarize-dmg.log" 2>&1 \
          || { echo "  DMG-Notarisierung fehlgeschlagen (siehe $LOGS/notarize-dmg.log)"; rm -f "$REL/downloads/ARJOTV-macOS.dmg"; }
      else
        SIGNNOTE="Developer ID signiert, Notarisierung FEHLGESCHLAGEN (siehe $LOGS/notarize-app.log)"
        echo "  $SIGNNOTE"
      fi
    fi
    rm -f "$REL/downloads/ARJOTV-macOS.zip"
    ditto -c -k --sequesterRsrc --keepParent "$APP" "$REL/downloads/ARJOTV-macOS.zip"
    if unzip -tq "$REL/downloads/ARJOTV-macOS.zip" >/dev/null; then
      STATUS[macOS]=ok; NOTE[macOS]="Architekturen: $ARCHS; $SIGNNOTE"
    else STATUS[macOS]=fail; NOTE[macOS]="ZIP-Prüfung fehlgeschlagen"; fi
  else STATUS[macOS]=fail; NOTE[macOS]="Signaturprüfung fehlgeschlagen"; fi
else STATUS[macOS]=fail; NOTE[macOS]="Build fehlgeschlagen"; fi

# ---- Simulator-Builds ----
sim() { # Plattform Ordner SDK-Ordner
  local plat="$1" dir="$2" sdkdir="$3"
  if run "$plat Simulator Build" "sim-$dir" "${XB[@]}" -destination "generic/platform=$plat Simulator" -derivedDataPath "$WORK/dd-$dir" CODE_SIGNING_ALLOWED=NO "${NOSYNC[@]}" build; then
    local app; app="$(ls -d "$WORK/dd-$dir/Build/Products/Release-$sdkdir/"*.app | head -1)"
    local out="$REL/simulator-builds/$dir/ARJOTV-$dir-SIMULATOR-ONLY.zip"
    rm -f "$out"; ditto -c -k --sequesterRsrc --keepParent "$app" "$out"
    echo "NUR FÜR DEN SIMULATOR. Auf echten Geräten nicht installierbar." >"$REL/simulator-builds/$dir/NICHT-FUER-GERAETE.txt"
    STATUS[sim-$dir]=ok; NOTE[sim-$dir]="Simulator-Bundle erstellt (nicht auf Geräten installierbar)"
  else STATUS[sim-$dir]=fail; NOTE[sim-$dir]="Build fehlgeschlagen"; fi
}
if [ -z "${ARJO_ONLY_MAC:-}" ]; then
  sim iOS iOS iphonesimulator
  sim tvOS tvOS appletvsimulator
fi

# ---- Geräte-IPAs (nur wenn Signierung vorhanden) ----
METHOD="${ARJO_EXPORT_METHOD:-debugging}"
TEAM="${ARJO_TEAM_ID:-}"
if [ -z "$TEAM" ]; then
  for p in "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles/"*.mobileprovision; do
    [ -f "$p" ] || continue
    security cms -D -i "$p" 2>/dev/null | plutil -extract Entitlements.application-identifier raw - 2>/dev/null | grep -q "\.$BUNDLE_ID\$" || continue
    TEAM="$(security cms -D -i "$p" | plutil -extract TeamIdentifier.0 raw -)"; break
  done
fi
device() { # Plattform Ordner
  local plat="$1" dir="$2"
  if [ -z "$TEAM" ]; then STATUS[dev-$dir]=skip; NOTE[dev-$dir]="Kein Team / Provisioning Profile gefunden"; return; fi
  local arch="$WORK/ARJOTV-$dir.xcarchive" exp="$WORK/export-$dir"
  rm -rf "$arch" "$exp"
  if run "$plat Geräte-Archiv" "arch-$dir" "${XB[@]}" -destination "generic/platform=$plat" -archivePath "$arch" -derivedDataPath "$WORK/dd-dev-$dir" DEVELOPMENT_TEAM="$TEAM" -allowProvisioningUpdates archive; then
    cat >"$WORK/export-$dir.plist" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>method</key><string>$METHOD</string><key>teamID</key><string>$TEAM</string><key>signingStyle</key><string>automatic</string></dict></plist>
PL
    if run "$plat IPA-Export ($METHOD)" "export-$dir" xcodebuild -exportArchive -archivePath "$arch" -exportPath "$exp" -exportOptionsPlist "$WORK/export-$dir.plist" -allowProvisioningUpdates; then
      cp "$exp/"*.ipa "$REL/downloads/ARJOTV-$dir.ipa"
      local prof="$WORK/prof-$dir.plist"; unzip -p "$REL/downloads/ARJOTV-$dir.ipa" 'Payload/*/embedded.mobileprovision' | security cms -D -i /dev/stdin >"$prof" 2>/dev/null
      STATUS[dev-$dir]=ok
      NOTE[dev-$dir]="Methode $METHOD, Team $TEAM, Profil läuft ab: $(plutil -extract ExpirationDate raw "$prof" 2>/dev/null), registrierte Geräte: $(plutil -extract ProvisionedDevices raw "$prof" 2>/dev/null | head -1)"
    else STATUS[dev-$dir]=fail; NOTE[dev-$dir]="Export fehlgeschlagen"; fi
  else STATUS[dev-$dir]=skip; NOTE[dev-$dir]="Archiv nicht signierbar (kein passendes Provisioning Profile, siehe $LOGS/arch-$dir.log)"; fi
}
if [ -z "${ARJO_ONLY_MAC:-}" ]; then
  device iOS iOS
  device tvOS tvOS
fi

# ---- Prüfsummen, Daten für die Website, Report ----
SUMS=""; JS="window.ARJO_RELEASE = {version:\"$VERSION\",build:\"$BUILD_NO\",files:{"
for f in "$REL"/downloads/* "$REL"/simulator-builds/*/*.zip; do
  [ -f "$f" ] || continue
  sz=$(stat -f%z "$f"); sha=$(shasum -a 256 "$f" | awk '{print $1}')
  SUMS="$SUMS| \`${f#$REL/}\` | $(echo "$sz" | awk '{printf "%.1f MB",$1/1048576}') | \`$sha\` |"$'\n'
  JS="$JS\"${f#$REL/}\":{size:$sz,sha256:\"$sha\"},"
done
IOSNOTE="${NOTE[dev-iOS]:-}"; EXP="$(echo "$IOSNOTE" | sed -n 's/.*läuft ab: \([0-9-]*\).*/\1/p')"
JS="$JS},status:{macOS:\"${STATUS[macOS]:-skip}\",iOS:\"${STATUS[dev-iOS]:-skip}\",tvOS:\"${STATUS[dev-tvOS]:-skip}\",simIOS:\"${STATUS[sim-iOS]:-skip}\",simTVOS:\"${STATUS[sim-tvOS]:-skip}\"},iosExpires:\"$EXP\"};"
echo "$JS" >"$REL/website/release-data.js"

{
echo "# ARJOTV Build-Report"; echo
echo "- Datum: $(date '+%Y-%m-%d %H:%M')"; echo "- Xcode: $(xcodebuild -version | tr '\n' ' ')"
echo "- Version: $VERSION ($BUILD_NO), Bundle-ID \`$BUNDLE_ID\`"; echo
echo "## Ergebnisse"; echo; echo "| Ziel | Status | Hinweis |"; echo "|---|---|---|"
for k in macOS dev-iOS dev-tvOS sim-iOS sim-tvOS; do echo "| $k | ${STATUS[$k]:-nicht ausgeführt} | ${NOTE[$k]:-} |"; done
echo; echo "## Dateien"; echo; echo "| Datei | Grösse | SHA256 |"; echo "|---|---|---|"; printf "%s" "$SUMS"
echo; echo "Logs: \`$LOGS\`. Einschränkungen: siehe INSTALLATION.md."
} >"$REL/BUILD-REPORT.md"
echo "Fertig. Report: $REL/BUILD-REPORT.md"
