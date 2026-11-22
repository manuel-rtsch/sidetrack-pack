#!/usr/bin/env bash
# Print the fingerprint a client actually pins: the SHA-256 of the repo index
# signing certificate, read out of the signed index itself.
#
#   ./scripts/fingerprint.sh            # from repo/entry.jar (post-build)
#
# Why from entry.jar: the fingerprint is NOT in any of the index JSON files. The
# certificate lives in the JAR signature block (META-INF/<alias>.RSA), which is
# what the client verifies anyway. Deriving it from the artefact rather than from
# the keystore means a published fingerprint cannot disagree with the live pack.
#
# Falls back to the keystore only when no built index is present, and says so.
set -euo pipefail

cd "$(dirname "$0")/.."

if [ -f repo/entry.jar ]; then
  FINGERPRINT=$(keytool -printcert -jarfile repo/entry.jar 2>/dev/null \
    | grep -i 'SHA256:' | head -1 | sed 's/.*SHA256: *//; s/://g' | tr -d '[:space:]' \
    | tr '[:lower:]' '[:upper:]')

  if [ ${#FINGERPRINT} -ne 64 ]; then
    echo "ERROR: could not read a 64-char SHA-256 from repo/entry.jar (got '${FINGERPRINT}')." >&2
    echo "       Do not paste a fingerprint from anywhere else." >&2
    exit 1
  fi

  # Second, independent derivation. Agreement between two code paths is the
  # whole reason for publishing a fingerprint.
  VIA_OPENSSL=$(unzip -p repo/entry.jar 'META-INF/*.RSA' 2>/dev/null \
    | openssl pkcs7 -inform DER -print_certs 2>/dev/null \
    | openssl x509 -outform DER 2>/dev/null \
    | (command -v sha256sum >/dev/null && sha256sum || shasum -a 256) \
    | awk '{print toupper($1)}')

  if [ -n "$VIA_OPENSSL" ] && [ "$VIA_OPENSSL" != "$FINGERPRINT" ]; then
    echo "ERROR: keytool and openssl disagree on the fingerprint:" >&2
    echo "  keytool: $FINGERPRINT" >&2
    echo "  openssl: $VIA_OPENSSL" >&2
    exit 1
  fi

  echo "$FINGERPRINT"
  exit 0
fi

if [ -n "${KEYSTOREPASS:-}" ] && [ -f sidetrack-repo.p12 ]; then
  echo "note: no repo/entry.jar yet; reading the keystore instead" >&2
  keytool -list -keystore sidetrack-repo.p12 -storepass "$KEYSTOREPASS" 2>/dev/null \
    | grep -i 'SHA-256' | sed 's/.*: //; s/://g' | tr '[:lower:]' '[:upper:]'
  exit 0
fi

echo "ERROR: build the pack first (./scripts/build.sh), or set KEYSTOREPASS." >&2
exit 1
