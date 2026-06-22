#!/usr/bin/env bash
#
# One-time setup: create a STABLE self-signed code-signing certificate named
# "Potret Self-Signed" in your login keychain, and authorize codesign to use it.
#
# Why: ad-hoc signing (codesign --sign -) gives every build a different identity,
# so macOS resets the Screen Recording permission on every update. Signing every
# build with ONE stable certificate keeps the identity constant, so the permission
# PERSISTS across updates. (It does NOT remove the one-time Gatekeeper "Open
# Anyway" — that still needs Apple notarization.)
#
# Run this once IN A TERMINAL (it asks for your Mac login password to authorize
# the signing key — it's used only locally for one keychain command, never stored):
#
#   ./scripts/setup-signing-cert.sh
#
# Then build releases as usual:  ./scripts/release.sh   (auto-detects the cert)

set -euo pipefail

CERT_NAME="Potret Self-Signed"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

# 1. Create the certificate if it isn't in the keychain yet.
if security find-identity -p codesigning 2>/dev/null | grep -qF "$CERT_NAME"; then
  echo "✓ \"$CERT_NAME\" is already in the keychain."
else
  echo "▸ Generating self-signed code-signing certificate \"$CERT_NAME\"…"
  TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
  cat > "$TMP/openssl.cnf" <<'CNF'
[ req ]
distinguished_name = dn
x509_extensions    = v3
prompt             = no
[ dn ]
CN = Potret Self-Signed
[ v3 ]
basicConstraints = critical, CA:false
keyUsage         = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
CNF
  # System LibreSSL writes a .p12 that macOS `security import` accepts (Homebrew's
  # OpenSSL 3 uses a MAC algorithm macOS rejects).
  /usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -config "$TMP/openssl.cnf" 2>/dev/null
  /usr/bin/openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -name "$CERT_NAME" -out "$TMP/id.p12" -passout pass:potret 2>/dev/null
  security import "$TMP/id.p12" -k "$KEYCHAIN" -P potret -A -T /usr/bin/codesign >/dev/null
  echo "  imported into login keychain."
fi

# 2. Authorize codesign to use the private key without a dialog on every build.
#    This updates the key's access list and needs your login-keychain password.
echo "▸ Authorizing codesign to use the key."
printf "  Enter your Mac login password (hidden): "
read -r -s PW; echo
if security set-key-partition-list -S apple-tool:,apple: -s -k "$PW" "$KEYCHAIN" >/dev/null 2>&1; then
  echo "  ✓ authorized"
else
  echo "  ⚠ couldn't set the access list (wrong password?). The first build may show a"
  echo "    'codesign wants to use a key' dialog — click \"Always Allow\" once."
fi
unset PW

# 3. Verify codesign can actually sign with the identity.
echo "▸ Testing codesign…"
T="$(mktemp -d)"; cp /bin/echo "$T/probe"
if codesign --force --timestamp=none --sign "$CERT_NAME" "$T/probe" >/dev/null 2>&1; then
  rm -rf "$T"
  echo ""
  echo "✓ Working. ./scripts/release.sh will now sign with \"$CERT_NAME\","
  echo "  so the Screen Recording permission will persist across updates."
else
  rm -rf "$T"
  echo "  ✗ codesign still can't use the key."
  echo "    Open Keychain Access → 'login' → your \"$CERT_NAME\" key → and grant codesign access,"
  echo "    or re-run this script and enter the correct login password."
  exit 1
fi
