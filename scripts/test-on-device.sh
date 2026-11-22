#!/usr/bin/env bash
# Serve the built repo to a USB-connected SP-01 and open the "Add app pack"
# screen. No publishing, no domain, no GitHub — the phone reaches the host
# through the adb reverse tunnel.
#
# This works because the Library's networkSecurityConfig has
# `base-config cleartextTrafficPermitted="true"`, so plain HTTP to an arbitrary
# host is allowed.
#
#   KEYSTOREPASS=... ./scripts/test-on-device.sh [serial]
#
# Ctrl-C to stop the server. Afterwards, remove the test pack on the device via
# Library -> Settings -> App Packs, or it will keep retrying a dead address.
#
# WARNING: installing Sidetrack from the pack installs the RELEASE app with the
# release certificate. On a phone that already has your daily Sidetrack, that is
# an update in place, not a second app. Use a scratch phone, or accept that.
set -euo pipefail

cd "$(dirname "$0")/.."

PORT=8777
SERIAL="${1:-$(adb devices | awk 'NR==2{print $1}')}"

if [ -z "$SERIAL" ]; then
  echo "ERROR: no adb device found." >&2
  exit 1
fi

if [ ! -f repo/index-v2.json ]; then
  echo "ERROR: repo/index-v2.json not found — run ./scripts/build.sh first." >&2
  exit 1
fi

ADDRESS=$(python3 -c "import json;print(json.load(open('repo/index-v2.json'))['repo']['address'])")
FP=$(./scripts/fingerprint.sh)
echo "index address: $ADDRESS"
echo "fingerprint:   $FP"

mkdir -p www/fdroid
ln -sfn ../../repo www/fdroid/repo

adb -s "$SERIAL" reverse "tcp:$PORT" "tcp:$PORT"
trap 'adb -s "$SERIAL" reverse --remove tcp:'"$PORT"' 2>/dev/null || true' EXIT

( cd www && python3 -m http.server "$PORT" --bind 0.0.0.0 ) &
SRV=$!
trap 'kill $SRV 2>/dev/null; adb -s "$SERIAL" reverse --remove tcp:'"$PORT"' 2>/dev/null || true' EXIT
sleep 2

adb -s "$SERIAL" shell am force-stop org.fdroid.basic
adb -s "$SERIAL" shell am start \
  -n org.fdroid.basic/org.fdroid.fdroid.views.repos.AddRepoActivity \
  -a android.intent.action.VIEW \
  -d "fdroidrepo://127.0.0.1:$PORT/fdroid/repo?fingerprint=$FP"

cat <<'EOF'

Serving. On the device you should see "Add app pack" listing the apps.

Notes from the SideSuite run on an SP-01 (same Library app, so these hold here):
  * After tapping "Add app pack", the client opens the app list with the repo
    name pre-filled in the SEARCH FIELD, showing "No matching applications
    available." That is NOT a failure. Clear the field.
  * To open Sidetrack directly:
      adb shell am start -n org.fdroid.basic/org.fdroid.fdroid.views.AppDetailsActivity \
        -e appid io.github.manuelrtsch.sidetrack
  * To prove silent install, uninstall Sidetrack first (this wipes its data and
    resets permissions) and install it from the pack. Success looks like:
      installerPackageName=org.fdroid.basic  and no unknown-sources prompt.
  * Every app renders a placeholder icon in the Library, including Sidephone's
    own packs. Device-wide behaviour, not an index bug.

Ctrl-C to stop.
EOF

wait $SRV
