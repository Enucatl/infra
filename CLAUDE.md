# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Home lab infrastructure stack managed via Docker Compose. Provides PKI certificate management (Vault), identity/LDAP (FreeIPA), configuration management (Puppet), and package caching (APT-Cacher-NG). Domain: `home.arpa`.

## Common Commands

```bash
# Start core services (vault, vault-unsealer, freeipa, apt-cacher-ng)
docker compose up -d

# Run one-off setup containers (PKI, CSR signing)
docker compose --profile setup run vault-pki-core-setup
docker compose --profile setup run vault-pki-intermediate-setup
docker compose --profile setup run freeipa-sign-csr

# View logs
docker compose logs -f vault
docker compose logs -f vault-unsealer

# Python tooling (uses uv for dependency management)
uv run python vault/scripts/launch_pve_desktop.py
```

## Architecture

### Services (docker-compose.yml)

- **vault** — HashiCorp Vault with file-based storage and TLS. Listens on port 8200. API address: `hcv.home.arpa:8200`.
- **vault-unsealer** — Sidecar that runs `vault/scripts/unseal.sh` in a loop (120s interval) to auto-initialize (1-of-1 key scheme) and unseal Vault. Stores keys in `/certificates/keys.json`.
- **freeipa** — FreeIPA server (AlmaLinux 10) for LDAP/Kerberos. Exposed via Traefik with TLS passthrough on `freeipa.home.arpa`. Ports: 88 (Kerberos), 389/636 (LDAP), 464 (kpasswd).
- **apt-cacher-ng** — APT package cache on port 3142. Cache stored at `/scratch/apt-cacher-ng`.

### Setup Containers (profile: `setup`)

Temporary containers under the `setup` profile run numbered scripts for one-time infrastructure bootstrapping. They are **not** part of normal `docker compose up`.

### Numbered Setup Scripts (`vault/scripts/`)

Scripts are sequential and build on each other:
1. `01-pki-core-setup.sh` — Root CA, Vault TLS cert
2. `02-pki-intermediate.sh` — Intermediate CA
3. `03-puppet-external-ca.sh` — Puppet external CA config
4. `04-sign-csr.sh` — Sign FreeIPA CSR with intermediate CA
5. `05-clone-puppet-repo.sh` — Clone Puppet control repo
6. `06-vault-puppet.sh` — Cert auth + KV v2 for Puppet
7. `07-configure-sudo.sh` — FreeIPA sudo rules
8. `08-vault-puppet-policy.sh` — Puppet Vault policy
9. `09-ipa-users.sh` — Service accounts (ldap_ro, printer, airflow)
10. `10-vault-ldap.sh` — LDAP auth backend wired to FreeIPA
11. `11-vault-airflow.sh` — Airflow KV read policy
12. `12-ipa-nfs.sh` — NFS configuration for FreeIPA

Other scripts: `unseal.sh` (auto-unseal loop), `backup.sh` (Vault backup with fs freeze), `launch_pve_desktop.sh`/`.py` (Proxmox VM automation).

### Networking

- **infra** — Internal network connecting Vault, unsealer, and FreeIPA (IPv6 enabled)
- **traefik_proxy** — Shared external network for Traefik reverse proxy integration

### Shared Volumes

- **certificates** — Mounted across Vault, unsealer, FreeIPA, and setup containers. Contains CA certs, service certs, and `keys.json`.
- **vault_data** / **freeipa_data** — Persistent service data.

### Environment Variables (.env)

`VAULT_ADDR`, `VAULT_CACERT`, `VAULT_TOKEN`, `KEYS_FILE`, `PASSWORD` (FreeIPA admin). The `.env` file is gitignored.

### Bootstrap Order

First-time setup: start Vault + unsealer → run `vault-pki-core-setup` (insecure mode) → switch Vault config to TLS → run `vault-pki-intermediate-setup` → generate FreeIPA CSR → run `freeipa-sign-csr` → start FreeIPA with signed certs → run remaining scripts (05-12) against Vault directly.

## Conventions

- Setup scripts are shell (`#!/bin/sh` or `#!/bin/bash`) and use `set -e`. They run inside Alpine-based Vault containers that install `jq` at runtime.
- Scripts use the Vault HTTP API via `curl` (not the `vault` CLI) when running in the unsealer/netshoot container.
- FreeIPA configuration scripts use `ipa` CLI commands with `echo $PASSWORD | kinit admin` for Kerberos auth.
- Traefik labels use TCP routers with TLS passthrough (not HTTP termination) for FreeIPA.
