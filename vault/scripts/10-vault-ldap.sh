#!/bin/bash

set -x

if [ -f .env ]; then
  set -o allexport
  source .env
  set +o allexport
fi
export VAULT_CACERT=/etc/ssl/certs/ca-certificates.crt

vault auth enable ldap

export LDAP_BIND_PASSWORD=$(vault kv get -field=ldap_ro::password kv/puppet)

# Check if the password was retrieved successfully (optional)
if [ -z "$LDAP_BIND_PASSWORD" ]; then
    echo "Error: Could not retrieve LDAP bind password from Vault KV."
    exit 1
fi

echo "LDAP bind password retrieved successfully."

vault write auth/ldap/config \
    url="ldaps://freeipa.home.arpa" \
    binddn="uid=ldap_ro,cn=users,cn=accounts,dc=home,dc=arpa" \
    bindpass="${LDAP_BIND_PASSWORD}" \
    userdn="cn=users,cn=accounts,dc=home,dc=arpa" \
    userattr="uid" \
    userfilter="(&({{.UserAttr}}={{.Username}})(objectClass=person))" \
    groupattr="cn" \
    groupdn="cn=groups,cn=accounts,dc=home,dc=arpa" \
    groupfilter="(|(member={{.UserDN}})(mepManagedBy={{.UserDN}}))" \
    tls_server_name="freeipa.home.arpa" \
    starttls="false" \
    request_timeout="10s" \
    certificate=@/etc/ssl/certs/ca-certificates.crt

unset LDAP_BIND_PASSWORD

vault write auth/ldap/groups/admins policies=admin,default
