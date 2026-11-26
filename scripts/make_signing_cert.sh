#!/usr/bin/env bash
# Creates a local, self-signed code-signing identity for Fisper in its own keychain
# (~/Library/Keychains/fisper-signing.keychain-db). Your login keychain is not touched.
#
# Why: macOS ties Microphone/Accessibility permissions to an app's signature. Ad-hoc signatures change on
# every build, so you'd have to re-grant after each rebuild. With a stable identity, grants survive updates.
set -euo pipefail

NAME="Fisper Local Code Signing"
KC="$HOME/Library/Keychains/fisper-signing.keychain-db"
KCPASS="fisper-local-signing"   # protects only this throwaway signing keychain

if security find-identity -p codesigning "$KC" 2>/dev/null | grep -q "$NAME"; then
  echo "Signing identity already exists in $KC"; exit 0
fi

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/cert.cnf" <<EOF
[ req ]
distinguished_name = dn
x509_extensions = ext
prompt = no
[ dn ]
CN = $NAME
[ ext ]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$TMP/cert.cnf" \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" 2>/dev/null
/usr/bin/openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -name "$NAME" \
  -out "$TMP/id.p12" -passout pass:fisper 2>/dev/null

# create the keychain without leaving it in the user's search list
ORIG_LIST=$(security list-keychains -d user | tr -d '"' | xargs)
[[ -f "$KC" ]] || security create-keychain -p "$KCPASS" "$KC"
security set-keychain-settings "$KC"            # no auto-lock timeout
security unlock-keychain -p "$KCPASS" "$KC"
security import "$TMP/id.p12" -k "$KC" -P fisper -T /usr/bin/codesign >/dev/null
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KCPASS" "$KC" >/dev/null
# shellcheck disable=SC2086
security list-keychains -d user -s $ORIG_LIST

echo "Created signing identity '$NAME' in $KC"
