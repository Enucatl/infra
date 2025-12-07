#!/bin/bash

# Configuration
CONTAINER_NAME="freeipa"
GROUP_NAME="admins"
TARGET_USER="user"
RULE_NAME="admins_sudo_rule"

echo "Running configuration inside docker container: $CONTAINER_NAME..."

# We use a heredoc (<<EOF) to run multiple commands inside the single docker exec session
docker exec -i $CONTAINER_NAME bash <<EOF

# 1. Authenticate using the internal environment variable
echo "Authentication..."
echo "\$PASSWORD" | kinit admin > /dev/null

if [ \$? -ne 0 ]; then
    echo "❌ Authentication failed. Is \$PASSWORD set inside the container?"
    exit 1
fi

ipa user-add ldap_ro --first ldap --last ro --shell /usr/sbin/nologin
ipa user-add printer --first printer --last printer --shell /usr/sbin/nologin

echo "✅ Configuration Complete."
EOF
