#!/usr/bin/env bash

set -euo pipefail

. "$(dirname "$0")/config.sh"

echo "Running configuration inside docker container: $FREEIPA_CONTAINER..."

# We use a heredoc (<<EOF) to run multiple commands inside the single docker exec session
docker exec -i "$FREEIPA_CONTAINER" bash <<EOF
set -eu

echo "Authentication..."
echo "\$PASSWORD" | kinit admin > /dev/null

if [ \$? -ne 0 ]; then
    echo "Authentication failed. Is \\\$PASSWORD set inside the container?"
    exit 1
fi
#ipa service-add nfs/${DOCKER_FQDN}
#ipa service-add nfs/forbearance.${DOMAIN}
ipa service-add-host nfs/${DOCKER_FQDN} --hosts ${DOCKER_FQDN} 2>/dev/null || true
ipa service-add-host nfs/forbearance.${DOMAIN} --hosts forbearance.${DOMAIN} 2>/dev/null || true
echo "Configuration Complete."
EOF

ssh "user@${DOCKER_FQDN}" "kinit -k && ipa-getkeytab -s ${FREEIPA_FQDN} -p nfs/${DOCKER_FQDN} -k /etc/krb5.keytab"
ssh "user@forbearance.${DOMAIN}" "kinit -k && ipa-getkeytab -s ${FREEIPA_FQDN} -p nfs/forbearance.${DOMAIN} -k /etc/krb5.keytab"
