#!/bin/bash

# Configuration
CONTAINER_NAME="freeipa"

echo "Running configuration inside docker container: $CONTAINER_NAME..."

# We use a heredoc (<<EOF) to run multiple commands inside the single docker exec session
docker exec -i $CONTAINER_NAME bash <<EOF
echo "Authentication..."
echo "\$PASSWORD" | kinit admin > /dev/null

if [ \$? -ne 0 ]; then
    echo "❌ Authentication failed. Is \$PASSWORD set inside the container?"
    exit 1
fi
#ipa service-add nfs/docker.home.arpa
#ipa service-add nfs/forbearance.home.arpa
ipa service-add-host nfs/docker.home.arpa --hosts docker.home.arpa
ipa service-add-host nfs/forbearance.home.arpa --hosts forbearance.home.arpa
echo "✅ Configuration Complete."
EOF

ssh user@docker.home.arpa "kinit -k && ipa-getkeytab -s freeipa.home.arpa -p nfs/docker.home.arpa -k /etc/krb5.keytab"
ssh user@forbearance.home.arpa "kinit -k && ipa-getkeytab -s freeipa.home.arpa -p nfs/forbearance.home.arpa -k /etc/krb5.keytab"
