#!/bin/bash

# Configuration
MAC_ADDRESS="b0:6e:bf:82:d5:1c"
DROPBEAR_HOST="dropbear.pve-desktop.home.arpa"
MAIN_HOST="puritan.home.arpa"

# 1. Retrieve Password from Vault
echo "[-] Retrieving password from Vault..."
SERVER_PASS=$(vault kv get -field=pve-desktop kv/bitwarden)
RET_VAL=$?

# Check if the password variable is empty or if vault failed
if [ $RET_VAL -ne 0 ] || [ -z "$SERVER_PASS" ]; then
    echo "[!] Error: Could not retrieve password from Vault. Exiting."
    exit 1
fi
echo "[+] Password retrieved successfully."

# 2. Send Wake-on-LAN
echo "[-] Sending Wake-on-LAN packet to $MAC_ADDRESS..."
wakeonlan "$MAC_ADDRESS"

# 3. Connect to Dropbear and Unlock
echo "[-] Waiting for Dropbear SSH ($DROPBEAR_HOST) to become available..."

# Loop until port 2222 is open (timeout 120 seconds)
count=0
while ! nc -z -w 1 "$DROPBEAR_HOST" 2222; do
  sleep 2
  count=$((count+1))
  if [ $count -ge 60 ]; then
      echo "[!] Timed out waiting for Dropbear."
      exit 1
  fi
done

echo "[+] Dropbear is up. Attempting to unlock via expect..."
# We use 'expect' to handle the TTY interaction.
# We access the password via $env(SERVER_PASS) to avoid Bash syntax conflicts.
SERVER_PASS="$SERVER_PASS" expect <<EOF
  log_user 1
  set timeout 10
  
  # Spawn the SSH connection
  spawn ssh $DROPBEAR_HOST

  # Handle the prompt. 
  expect {
    "password for rpool/ROOT" {
      send "\$env(SERVER_PASS)\r"
    }
    timeout {
      puts "\n[!] Timed out waiting for password prompt."
      exit 1
    }
  }

  # Wait for the process to finish (EOF usually implies the server closed connection after unlock)
  expect eof
EOF

if [ $? -eq 0 ]; then
    echo "[+] Unlock command sent successfully."
else
    echo "[!] Failed to send unlock command."
    exit 1
fi

# 4. Connect to Main OS and start Sunshine
echo "[-] Waiting for Main OS ($MAIN_HOST) to boot..."

# Loop until Main OS SSH is open (timeout 180 seconds)
count=0
while ! nc -z -w 1 "$MAIN_HOST" 22; do
  sleep 5
  count=$((count+1))
  if [ $count -ge 36 ]; then
      echo "[!] Timed out waiting for Main OS."
      exit 1
  fi
done

echo "[+] Main OS is up. Starting Sunshine..."
sleep 10

# Connect and start the service
# Note: Since the command is --user, ensure your SSH config logs you in 
# as the correct non-root user, or specify user@puritan...
ssh "$MAIN_HOST" "systemctl --user start sunshine"

if [ $? -eq 0 ]; then
    echo "[+] Sunshine started successfully."
else
    echo "[!] Failed to start Sunshine."
    exit 1
fi
