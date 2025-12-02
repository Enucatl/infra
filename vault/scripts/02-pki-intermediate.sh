#!/bin/sh

# Install jq
apk add --no-cache jq > /dev/null 2>&1

VAULT_RETRIES=5

echo "--- Starting Intermediate CA Setup ---"

# 1. Wait for Vault
counter=0
while [ $counter -lt $VAULT_RETRIES ]; do
    if vault status > /dev/null 2>&1; then
        break
    fi
    echo "Waiting for Vault..."
    sleep 2
    counter=$((counter+1))
done

# 2. Login
ROOT_TOKEN=$(jq -r ".root_token" "$KEYS_FILE")
export VAULT_TOKEN=$ROOT_TOKEN

# 3. Idempotency Check
if vault secrets list -format=json | jq -e '."pki_int/"' > /dev/null; then
    echo "Intermediate PKI already enabled. Skipping setup."
    exit 0
fi

echo "Setting up Intermediate CA..."

# 4. Enable and Tune (5 Years)
vault secrets enable -path=pki_int pki
vault secrets tune -max-lease-ttl=43800h pki_int

# 8. Configure URLs for Intermediate
vault write pki_int/config/urls \
    issuing_certificates="https://hcv.home.arpa:8200/v1/pki_int/ca" \
    crl_distribution_points="https://hcv.home.arpa:8200/v1/pki_int/crl"

# 5. Generate CSR for Intermediate
echo "Generating Intermediate CSR..."
vault write -format=json pki_int/intermediate/generate/internal \
    common_name="Docker Home Arpa Intermediate CA" \
    ttl=43800h \
    | jq -r ".data.csr" > /tmp/pki_int.csr

# 6. Sign CSR with Root CA
# We sign it using the 'pki' (Root) engine
echo "Signing Intermediate CSR with Root CA..."
vault write -format=json pki/root/sign-intermediate \
    csr=@/tmp/pki_int.csr \
    format=pem_bundle \
    ttl=43800h \
    | jq -r ".data.certificate" > /tmp/intermediate.crt

# 7. Import Signed Cert back to Intermediate
vault write pki_int/intermediate/set-signed \
    certificate=@/tmp/intermediate.crt

echo "Intermediate CA successfully created and signed."

# 9. Create General Role
vault write pki_int/roles/general \
    allowed_domains="home.arpa" \
    allow_subdomains=true \
    allow_bare_domains=true \
    allow_wildcard_certificates=true \
    require_cn=false \
    max_ttl="8760h"

echo "--- Intermediate Setup Complete ---"
