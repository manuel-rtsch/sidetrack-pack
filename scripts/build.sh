#!/usr/bin/env bash
# Build the signed F-Droid index. Identical logic to CI, so a green local run
# means a green CI run.
#
#   KEYSTOREPASS=... KEYPASS=... ./scripts/build.sh
#
# Requires: fdroidserver 2.4.x, a JDK, apksigner from Android build-tools (via
# ANDROID_HOME), gh (authenticated), jq, python3.
set -euo pipefail

cd "$(dirname "$0")/.."

: "${KEYSTOREPASS:?set KEYSTOREPASS}"
: "${KEYPASS:?set KEYPASS}"
export KEYSTOREPASS KEYPASS

if [ ! -f sidetrack-repo.p12 ]; then
  echo "ERROR: sidetrack-repo.p12 not found." >&2
  echo "The repo index keystore is never committed. Restore it from backup, or see" >&2
  echo "README.md if you are generating it for the first time." >&2
  exit 1
fi

# fdroidserver warns about config.yml being group/other-readable, and CI
# checkouts are 0644. Harmless, but a clean run is easier to read.
chmod 0600 config.yml

# fdroidserver resolves repo_icon relative to repo/icons/, so the source icon
# has to be placed there before `fdroid update` runs.
mkdir -p repo/icons
cp icon.png repo/icons/icon.png

./scripts/fetch-apks.sh

echo
echo "==> fdroid update"
fdroid update -c --pretty --use-date-from-apk

echo
echo "==> verify"
python3 scripts/verify-index.py

echo
echo "==> fingerprint"
./scripts/fingerprint.sh
