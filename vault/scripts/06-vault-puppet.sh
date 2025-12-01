#!/bin/bash

#set -ex

vault audit enable file file_path=/vault/file/audit.log elide_list_responses=true
vault auth enable cert

vault write auth/cert/certs/puppet \
    certificate=@/etc/puppetlabs/puppet/ssl/certs/ca.pem \
    policies="puppet" \
    allowed_dns_sans="*.home.arpa" \
    ttl=15m

vault policy write puppet - <<EOF
path "kv/data/puppet" {
    capabilities = ["read"]
}
EOF

vault secrets enable -version=2 kv
