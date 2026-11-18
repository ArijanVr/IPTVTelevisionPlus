#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [ -z "${JAVA_HOME:-}" ]; then
    if [ -d /opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home ]; then
        export JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home
    else
        export JAVA_HOME="$(/usr/libexec/java_home -v 17)"
    fi
fi
if [ -z "${ANDROID_HOME:-}" ]; then
    if [ -d "$HOME/Library/Android/sdk/platforms" ]; then
        export ANDROID_HOME="$HOME/Library/Android/sdk"
    elif [ -d /opt/homebrew/share/android-commandlinetools/platforms ]; then
        export ANDROID_HOME=/opt/homebrew/share/android-commandlinetools
    else
        echo 'Android SDK fehlt. ANDROID_HOME setzen oder das Projekt in Android Studio öffnen.' >&2
        exit 1
    fi
fi
./gradlew :app:testDebugUnitTest :app:lintDebug :app:assembleRelease --console=plain
mkdir -p Installation
cp app/build/outputs/apk/release/app-release.apk Installation/IPTelevision-GoogleTV-1.2.0.apk
(cd Installation && shasum -a 256 IPTelevision-GoogleTV-1.2.0.apk > IPTelevision-GoogleTV-1.2.0.apk.sha256)
echo 'Fertig: Installation/IPTelevision-GoogleTV-1.2.0.apk'
