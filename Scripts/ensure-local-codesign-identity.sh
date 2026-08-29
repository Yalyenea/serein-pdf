#!/usr/bin/env bash
# Ensure a stable local code-signing identity exists for Serein builds.
# Usage: Scripts/ensure-local-codesign-identity.sh ["Identity Name"]

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IDENTITY_NAME="${1:-Serein Local Code Signing}"
KEYCHAIN="${HOME}/Library/Keychains/login.keychain-db"
TMP_DIR="${PROJECT_ROOT}/.tmp/codesign"
P12_PASSWORD="serein-local-codesign"

identity_exists() {
    security find-identity -p codesigning -v | grep -F "\"${IDENTITY_NAME}\"" >/dev/null
}

if identity_exists; then
    echo "codesign identity ready: ${IDENTITY_NAME}"
    exit 0
fi

mkdir -p "$TMP_DIR"
KEY_PATH="${TMP_DIR}/serein-local-codesign.key.pem"
CERT_PATH="${TMP_DIR}/serein-local-codesign.cert.pem"
P12_PATH="${TMP_DIR}/serein-local-codesign.p12"

echo "==> creating local code-signing identity: ${IDENTITY_NAME}"
/usr/bin/openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
    -subj "/CN=${IDENTITY_NAME}/" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=codeSigning" \
    -keyout "$KEY_PATH" \
    -out "$CERT_PATH" >/dev/null 2>&1

/usr/bin/openssl pkcs12 -export \
    -inkey "$KEY_PATH" \
    -in "$CERT_PATH" \
    -name "$IDENTITY_NAME" \
    -out "$P12_PATH" \
    -passout "pass:${P12_PASSWORD}" >/dev/null

security import "$P12_PATH" \
    -k "$KEYCHAIN" \
    -P "$P12_PASSWORD" \
    -T /usr/bin/codesign \
    -T /usr/bin/security >/dev/null

security add-trusted-cert \
    -r trustRoot \
    -p codeSign \
    -k "$KEYCHAIN" \
    "$CERT_PATH" >/dev/null

if ! identity_exists; then
    echo "error: codesign identity was imported but is not usable: ${IDENTITY_NAME}" >&2
    exit 1
fi

echo "codesign identity ready: ${IDENTITY_NAME}"
