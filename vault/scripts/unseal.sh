#!/bin/bash

# -----------------------------------------------------------------------------
# LOGIC
# -----------------------------------------------------------------------------

echo "[Unsealer] Waiting for Vault..."

curl -s "$VAULT_ADDR/v1/sys/health"

# Loop until Vault returns a response (even if 503/Sealed)
until curl -s -o /dev/null "$VAULT_ADDR/v1/sys/health"; do
    echo "[Unsealer] Vault not ready. Retrying in 2s..."
    sleep 2
    curl -s "$VAULT_ADDR/v1/sys/health"
done

echo "[Unsealer] Vault is online. Checking status..."

# Check if Vault is initialized
IS_INIT=$(curl -s "$VAULT_ADDR/v1/sys/init" | jq -r '.initialized')

if [ "$IS_INIT" = "false" ]; then
    echo "[Unsealer] Vault is NOT initialized. Initializing..."
    
    # 1 Key Share, 1 Threshold (Lab Mode)
    INIT_PAYLOAD='{"secret_shares": 1, "secret_threshold": 1}'
    
    curl -s -X POST -d "$INIT_PAYLOAD" "$VAULT_ADDR/v1/sys/init" > "$KEYS_FILE"
    
    echo "[Unsealer] Initialization complete. Keys saved to $KEYS_FILE"
fi

# Check if Vault is Sealed
SEALED_STATUS=$(curl -s "$VAULT_ADDR/v1/sys/health" | jq -r '.sealed')

if [ "$SEALED_STATUS" = "true" ]; then
    echo "[Unsealer] Vault is SEALED. Unsealing..."
    
    if [ ! -f "$KEYS_FILE" ]; then
        echo "[Unsealer] ERROR: $KEYS_FILE not found!"
        exit 1
    fi

    # Extract key using jq
    UNSEAL_KEY=$(jq -r '.keys_base64[0]' "$KEYS_FILE")
    
    # Unseal
    curl -s -X POST -d "{\"key\": \"$UNSEAL_KEY\"}" "$VAULT_ADDR/v1/sys/unseal" > /dev/null
    
    echo "[Unsealer] Unseal request sent."
else
    echo "[Unsealer] Vault is already UNSEALED."
fi
