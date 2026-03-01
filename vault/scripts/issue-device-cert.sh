#!/usr/bin/env bash

set -euo pipefail

# Usage: issue-device-cert.sh <hostname> [ttl]
# Example: issue-device-cert.sh brw4cebbd46ff8c.home.arpa 8760h
#
# Assumes VAULT_ADDR, VAULT_CACERT, and VAULT_TOKEN are already set in the environment.
#
# Outputs <basename>.crt, <basename>.key, and <basename>.pfx to ~/Downloads.
# Upload the .pfx via the printer web UI:
#   Network > Security > Certificate > Import Certificate and Private Key

HOSTNAME="${1:-}"
TTL="${2:-8760h}"
OUT_DIR="$HOME/Downloads"

if [ -z "$HOSTNAME" ]; then
    echo "Usage: $0 <hostname> [ttl]" >&2
    echo "  hostname  FQDN for the certificate (e.g. brw4cebbd46ff8c.home.arpa)" >&2
    echo "  ttl       Validity period (default: 8760h = 1 year)" >&2
    exit 1
fi

# Derive a safe base name from the hostname (strip domain suffix)
BASENAME="${HOSTNAME%%.*}"
CERT_FILE="${OUT_DIR}/${BASENAME}.crt"
KEY_FILE="${OUT_DIR}/${BASENAME}.key"
PFX_FILE="${OUT_DIR}/${BASENAME}.pfx"
JSON_TMP="${OUT_DIR}/${BASENAME}-vault.json"

echo "Issuing certificate for ${HOSTNAME} (ttl=${TTL})..."

vault write -format=json pki_int/issue/general \
    common_name="${HOSTNAME}" \
    ttl="${TTL}" \
    > "${JSON_TMP}"

jq -r '.data.certificate' "${JSON_TMP}" > "${CERT_FILE}"
jq -r '.data.private_key' "${JSON_TMP}" > "${KEY_FILE}"
rm "${JSON_TMP}"

echo "Converting to PKCS#12..."
openssl pkcs12 -export \
    -in "${CERT_FILE}" \
    -inkey "${KEY_FILE}" \
    -out "${PFX_FILE}" \
    -passout pass:""

echo ""
echo "Done. Files written to ${OUT_DIR}:"
echo "  Certificate : ${CERT_FILE}"
echo "  Private key : ${KEY_FILE}"
echo "  PKCS#12     : ${PFX_FILE}  <-- upload this to the printer"
echo ""
echo "Upload via: Network > Security > Certificate > Import Certificate and Private Key"
