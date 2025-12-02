#!/bin/bash

# -----------------------------------------------------------------------------
# CONFIGURATION & PRE-FLIGHT
# -----------------------------------------------------------------------------
# Ensure jq is installed
if ! command -v jq &> /dev/null; then
    echo "[Unsealer] Error: jq is not installed."
    exit 1
fi

# -----------------------------------------------------------------------------
# LOGIC
# -----------------------------------------------------------------------------

echo "[Unsealer] Waiting for Vault to respond at $VAULT_ADDR..."

# Loop until Vault returns a valid HTTP response (connectivity check).
# Note: We use max-time to fail fast if connection hangs.
while true; do
    # Capture output and exit code
    HTTP_RESPONSE=$(curl -s --max-time 2 "$VAULT_ADDR/v1/sys/health")
    CURL_EXIT_CODE=$?

    echo "$HTTP_RESPONSE"
    if [ $CURL_EXIT_CODE -eq 0 ] && [ -n "$HTTP_RESPONSE" ]; then
        echo "[Unsealer] Vault is reachable."
        break
    else
        echo "[Unsealer] Vault not ready (curl exit code: $CURL_EXIT_CODE). Retrying in 2s..."
        sleep 2
    fi
done

echo "----------------------------------------------------------------"
echo "[Unsealer] Checking Initialization status..."

# Capture response to variable so we can print it AND parse it
INIT_RESPONSE=$(curl -s "$VAULT_ADDR/v1/sys/init")

# 1. Print response body
echo "$INIT_RESPONSE"

# 2. Parse variable
IS_INIT=$(echo "$INIT_RESPONSE" | jq -r '.initialized')

if [ "$IS_INIT" = "false" ]; then
    echo "[Unsealer] Vault is NOT initialized. Initializing..."
    
    # 1 Key Share, 1 Threshold (Lab Mode)
    INIT_PAYLOAD='{"secret_shares": 1, "secret_threshold": 1}'
    
    echo "[Unsealer] Sending Init Payload: $INIT_PAYLOAD"
    
    # Use 'tee' to write to file AND show stdout
    curl -s -X POST -d "$INIT_PAYLOAD" "$VAULT_ADDR/v1/sys/init" | tee "$KEYS_FILE"
    
    # Add a newline for clean formatting after the curl output
    echo "" 
    echo "[Unsealer] Initialization complete. Keys saved to $KEYS_FILE"
fi

echo "----------------------------------------------------------------"
echo "[Unsealer] Checking Seal status..."

# Capture response to variable
HEALTH_RESPONSE=$(curl -s "$VAULT_ADDR/v1/sys/health")

# 1. Print response body
echo "$HEALTH_RESPONSE"

# 2. Parse variable (Check for .sealed, handle nulls if structure differs)
SEALED_STATUS=$(echo "$HEALTH_RESPONSE" | jq -r '.sealed')

if [ "$SEALED_STATUS" = "true" ]; then
    echo "[Unsealer] Vault is SEALED. Unsealing..."
    
    if [ ! -f "$KEYS_FILE" ]; then
        echo "[Unsealer] ERROR: $KEYS_FILE not found! Cannot unseal."
        exit 1
    fi

    # Extract key using jq
    UNSEAL_KEY=$(jq -r '.keys_base64[0]' "$KEYS_FILE")
    
    # Unseal request - Removed output redirection to see the body
    curl -s -X POST -d "{\"key\": \"$UNSEAL_KEY\"}" "$VAULT_ADDR/v1/sys/unseal"
    
    echo ""
    echo "[Unsealer] Unseal request sent."
else
    # Vault health often returns non-200 (like 429) if it is a standby node, 
    # so we rely on the JSON 'sealed' status rather than HTTP codes.
    echo "[Unsealer] Vault is already UNSEALED (or in Standby mode)."
fi
