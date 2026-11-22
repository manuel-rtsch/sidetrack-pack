#!/usr/bin/env bash
# Fetch the most recent KEEP_RELEASES release APKs for each app in apps.json
# into repo/.
#
# Stateless by design: repo/ is rebuilt from GitHub Releases on every run and is
# never committed. GitHub Releases stay the single source of truth, so the pack
# is always reconstructible from scratch and the git history never accumulates
# APK blobs.
#
# Why more than one release per app: F-Droid clients download an APK by the
# exact filename recorded in the index they last synced. A client that has not
# refreshed since the previous publish still asks for the OLD filename. Keeping
# the last few APKs live means every filename a client could plausibly still be
# holding keeps resolving, so a stale client downloads successfully and picks up
# the new version on its next sync. Costs a few MB of static hosting.
#
# Sidetrack-specific: a Sidetrack release carries TWO APKs — the universal one
# and the arm64-v8a one. The F-Droid index cannot hold both for one version (they
# would collide as the same package/versionCode rather than registering as ABI
# splits), so each app entry names exactly one asset glob. The pack ships the
# arm64-v8a APK: the SP-01 is arm64, the pack is not for emulators, and this
# halves both the download and the Pages egress. The universal APK stays on the
# GitHub release for everyone else.
set -euo pipefail

cd "$(dirname "$0")/.."

# How many releases back to keep downloadable per app. Anything >= 2 fixes the
# stale-client 404; 3 leaves room for two publishes in one day without a client
# ever falling off the end.
KEEP_RELEASES="${KEEP_RELEASES:-3}"

mkdir -p repo
rm -rf staging
mkdir -p staging

# Drop APKs from previous local runs so a local build matches a fresh CI one.
rm -f repo/*.apk

skipped=""

while read -r name package gh_repo asset_glob; do
  echo "==> $name  ($gh_repo, asset '$asset_glob')"

  # `gh api` rather than `gh release list --json`: the --json flag on
  # `release list` only exists in gh >= 2.36, and runners and laptops do not
  # agree on the gh version. The REST endpoint returns newest first.
  if ! releases=$(gh api "repos/$gh_repo/releases?per_page=30" \
        --jq '.[] | select(.draft == false and .prerelease == false) | .tag_name' \
        2>/dev/null </dev/null); then
    echo "    repo not found, or releases unreadable — skipping"
    skipped="$skipped $name"
    continue
  fi

  tags=$(printf '%s\n' "$releases" | grep -v '^$' | head -n "$KEEP_RELEASES" || true)
  if [ -z "$tags" ]; then
    echo "    no release yet — skipping"
    skipped="$skipped $name"
    continue
  fi

  got=0
  n=0
  while read -r tag; do
    [ -n "$tag" ] || continue
    n=$((n + 1))
    # The newest release is the one being published; an older one is only here
    # to keep stale clients working. So a problem with the newest is loud, and a
    # problem with an older one is a note.
    newest=$([ "$n" -eq 1 ] && echo yes || echo no)

    dest="staging/$package/$tag"
    mkdir -p "$dest"

    if ! gh release download "$tag" -R "$gh_repo" -p "$asset_glob" -D "$dest" --clobber \
          2>/dev/null </dev/null; then
      echo "    $tag: no asset matching '$asset_glob' — skipping"
      continue
    fi

    count=$(find "$dest" -name '*.apk' | wc -l | tr -d ' ')
    if [ "$count" -ne 1 ]; then
      if [ "$newest" = yes ]; then
        echo "::error::expected exactly 1 APK matching '$asset_glob' in $gh_repo $tag, found $count" >&2
        find "$dest" -name '*.apk' >&2
        echo "    Refusing to guess which one to publish. A release that ships both the" >&2
        echo "    universal and the arm64 APK must be disambiguated here, or the index" >&2
        echo "    would carry two files for one versionCode." >&2
        exit 1
      fi
      echo "    $tag: found $count APKs, not 1 — skipping this older version"
      continue
    fi

    apk=$(find "$dest" -name '*.apk')
    # This filename is a contract: it is what lands in the index and what every
    # client that synced during this version's lifetime will ask for later.
    mv "$apk" "repo/${name}-${tag}.apk"
    echo "    -> repo/${name}-${tag}.apk$([ "$newest" = yes ] && echo '  (current)' || echo '  (kept for stale clients)')"
    got=$((got + 1))
  done <<EOF
$tags
EOF

  if [ "$got" -eq 0 ]; then
    echo "    no usable APK in the last $KEEP_RELEASES releases — skipping"
    skipped="$skipped $name"
  fi
done < <(jq -r '.[] | "\(.name) \(.package) \(.repo) \(.asset)"' apps.json)

rm -rf staging

echo
echo "APKs staged in repo/:"
ls -la repo/*.apk 2>/dev/null || echo "  (none)"

if [ -n "$skipped" ]; then
  echo
  echo "NOT IN THIS BUILD (no release yet):$skipped"
fi
