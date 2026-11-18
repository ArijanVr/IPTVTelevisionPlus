#!/bin/zsh
# IPTelevision+ Update veröffentlichen: legt in der öffentlichen Ablage ArijanVr/IPTVTelevisionPlus ein GitHub-Release an,
# aus dem sich die Apps selbst aktualisieren (Mac: Sparkle über appcast.xml, Google TV: APK, iPhone/iPad/Apple TV: nur Hinweis).
# Ablauf: erst ./tools/release.sh --version X.Y.Z (baut die notarisierte DMG), dann dieses Skript.
# Aufruf:  tools/publish-update.sh --notes "Was ist neu" [--publish]
#   ohne --publish: baut und signiert alles nach $OUT, lädt aber nichts hoch (Testlauf).
# Der Sparkle-Schlüssel liegt im Login-Schlüsselbund (generate_keys); ohne ihn kann kein Update signiert werden.
# Die Google-TV-APK wird hier mit -PpublicBuild neu gebaut, damit KEINE Playlist-Adresse aus playlist.local.properties darin steckt.
set -euo pipefail
setopt null_glob
ROOT=${0:A:h:h}
REPO=ArijanVr/IPTVTelevisionPlus
NOTES=""; PUBLISH=0
while [ $# -gt 0 ]; do
  case "$1" in
    --notes) NOTES="$2"; shift 2 ;;
    --publish) PUBLISH=1; shift ;;
    *) echo "Unbekannte Option: $1" >&2; exit 2 ;;
  esac
done
[ -n "$NOTES" ] || { echo "--notes \"…\" fehlt" >&2; exit 2; }

V=$(sed -n 's/.*MARKETING_VERSION: "\(.*\)".*/\1/p' "$ROOT/Quellcode/project.yml" | head -1)
BUILD=$(sed -n 's/.*CURRENT_PROJECT_VERSION: "\(.*\)".*/\1/p' "$ROOT/Quellcode/project.yml" | head -1)
OUT=${PUBLISH_OUT:-$(mktemp -d)}
DMG_SRC="$ROOT/Download-macOS/IPTelevision-Mac.dmg"
DMG="$OUT/IPTelevisionPlus-$V-macOS.dmg"
APK="$OUT/IPTelevisionPlus-$V-GoogleTV.apk"
SPARKLE_BIN=${SPARKLE_BIN:-$(ls -d "$HOME"/Library/Developer/Xcode/DerivedData/ARJOTV-*/SourcePackages/artifacts/sparkle/Sparkle/bin 2>/dev/null | head -1)}
[ -x "$SPARKLE_BIN/sign_update" ] || { echo "Sparkle-Werkzeuge fehlen (SPARKLE_BIN setzen oder das Projekt einmal in Xcode bauen)" >&2; exit 1; }
[ -f "$DMG_SRC" ] || { echo "DMG fehlt: $DMG_SRC (zuerst tools/release.sh)" >&2; exit 1; }

echo "→ Prüfe, dass die DMG Version $V enthält"
MNT=$(mktemp -d); hdiutil attach -nobrowse -readonly -mountpoint "$MNT" "$DMG_SRC" >/dev/null
trap 'hdiutil detach "$MNT" >/dev/null 2>&1 || true' EXIT
INNER=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$MNT"/*.app/Contents/Info.plist)
INNER_BUILD=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$MNT"/*.app/Contents/Info.plist)
[ "$INNER" = "$V" ] && [ "$INNER_BUILD" = "$BUILD" ] || { echo "DMG enthält $INNER ($INNER_BUILD), project.yml sagt $V ($BUILD). Neu bauen." >&2; exit 1; }
/usr/libexec/PlistBuddy -c "Print SUPublicEDKey" "$MNT"/*.app/Contents/Info.plist >/dev/null || { echo "DMG enthält keine Sparkle-Konfiguration" >&2; exit 1; }
hdiutil detach "$MNT" >/dev/null; trap - EXIT
xcrun stapler validate "$DMG_SRC" >/dev/null || { echo "DMG ist nicht notarisiert/gestapelt" >&2; exit 1; }
cp "$DMG_SRC" "$DMG"

echo "→ Baue öffentliche Google-TV-APK (ohne Playlist-Adresse)"
export JAVA_HOME=${JAVA_HOME:-/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home}
export ANDROID_HOME=${ANDROID_HOME:-/opt/homebrew/share/android-commandlinetools}
(cd "$ROOT/AndroidTV" && ./gradlew :app:assembleRelease -PpublicBuild --console=plain -q)
cp "$ROOT/AndroidTV/app/build/outputs/apk/release/app-release.apk" "$APK"

echo "→ Signiere DMG mit dem Sparkle-Schlüssel"
SIG=$("$SPARKLE_BIN/sign_update" "$DMG")   # liefert: sparkle:edSignature="…" length="…"
cat > "$OUT/appcast.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>IP Television+</title>
    <item>
      <title>Version $V</title>
      <pubDate>$(LC_ALL=C date -u +"%a, %d %b %Y %H:%M:%S +0000")</pubDate>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$V</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>
      <description><![CDATA[$NOTES]]></description>
      <enclosure url="https://github.com/$REPO/releases/download/v$V/${DMG:t}" $SIG type="application/octet-stream" />
    </item>
  </channel>
</rss>
XML
echo "Fertig in $OUT:"; ls -l "$OUT"
[ $PUBLISH -eq 1 ] || { echo "Testlauf: nichts hochgeladen. Mit --publish veröffentlichen."; exit 0; }
gh release create "v$V" --repo "$REPO" --title "IP Television+ $V" --notes "$NOTES" "$DMG" "$APK" "$OUT/appcast.xml"
echo "Veröffentlicht: https://github.com/$REPO/releases/tag/v$V"
