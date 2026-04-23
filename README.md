# Homelab

Self-hosted services managed with Ansible and Docker Compose.
As it is "homelab" and not "homeprod", it is obviously small - I'm here to learn, both deployment and documentation.

## Supported OS / Scope

This repository is **Arch Linux only**.

Arch-specific assumptions/commands are used in:

- `ansible/roles/docker/tasks/main.yml`
  - installs packages using **pacman** (`docker`, `docker-compose`, `rsync`)
  - manages Docker using **systemd**
- `ansible/roles/caddy/tasks/main.yml`
  - installs **caddy** using **pacman**
  - manages Caddy using **systemd**
- `ansible/playbook.yml`
  - explicitly fails if the host is not Arch Linux

If you are not on Arch, the playbook will not work without modifying these roles.

## Architecture

- Reverse proxy: Caddy
- DNS / ad-blocking: AdGuard Home (resolves `*.lab` → Tailscale IP, filters ads)
- Container runtime: Docker
- Provisioning: Ansible
- Compose deploy root: `/srv/pm_homelab` (where Ansible copies compose files)
- Service data root: `/srv/homelab` (where most services store persistent data)

## Remote Access

All services are accessible via `https://<service>.lab` from any Tailscale-connected device.
Nothing is exposed to the internet (eduroam dorm constraint — Tailscale is the only sane option).
TLS is terminated at Caddy using its internal CA (`tls internal`). Trust the CA cert once per device — see below.

### DNS setup (one-time, per deployment)

1. Set `tailscale_ip` in `ansible/group_vars/all.yml` to the server's Tailscale IP:
   ```bash
   tailscale ip -4
   ```
2. Run the playbook — AdGuard Home is deployed and listens on port 53 of the Tailscale interface.
3. In the [Tailscale admin panel](https://login.tailscale.com/admin/dns) → **Nameservers → Add nameserver**:
   - Address: `<tailscale_ip>`
   - Restrict to domain: `lab`
4. Optionally add the same IP as a **global nameserver** (no domain restriction) to route all DNS through AdGuard Home for ad-blocking across all Tailscale devices.

All Tailscale devices will then resolve `*.lab` and have ad-blocking via AdGuard Home. The web UI is at `https://adguard.lab`.

### HTTPS / CA trust (one-time, per client device)

Caddy uses its own local CA to sign `*.lab` certificates. Fetch the root cert from the server and install it:

```bash
# On the server — find the root cert
sudo cat /var/lib/caddy/.local/share/caddy/pki/authorities/local/root.crt
```

**Arch Linux:** `sudo cp root.crt /etc/ca-certificates/trust-source/anchors/caddy-homelab.crt && sudo update-ca-trust`

**Debian/Ubuntu:** `sudo cp root.crt /usr/local/share/ca-certificates/caddy-homelab.crt && sudo update-ca-certificates`

**macOS:** Open Keychain Access → import → set to *Always Trust*

**Windows:** `certmgr` → Trusted Root Certification Authorities → import

**Firefox (any OS):** Settings → Privacy & Security → View Certificates → Authorities → Import  
*(or set `security.enterprise_roots.enabled = true` in `about:config` to inherit OS trust)*

**Android/iOS:** Download the `.crt` file in the browser and follow the install certificate prompt.

## Services

| Service    | Port | Data Location           | Ansible-managed |
|------------|------|-------------------------|-----------------|
| Immich     | 2283 | via `.env` (`UPLOAD_LOCATION`, `DB_DATA_LOCATION`) | yes |
| Navidrome  | 4533 | `/srv/homelab/navidrome`, `/srv/media/music` (read-only) | yes |
| Vikunja    | 3456 | `/srv/homelab/vikunja` (files), Docker volume (DB) | yes |
| Karakeep   | 3000 | Docker volumes          | yes |
| Glance     | 8080 | config files in repo    | yes |
| Nextcloud  | 8000 | Docker volumes          | yes |
| Keycloak   | 8081 | Docker volume           | yes |
| Journiv    | 8050 | `/srv/homelab/journiv/data` | yes |
| AdGuard Home | 3080 (UI) / 53 (DNS) | `/srv/homelab/adguard` | yes |
| Grocy       | 9283 | `/srv/homelab/grocy`       | yes |
| Vaultwarden | 8222 | `/srv/homelab/vaultwarden` | yes |
| Uptime Kuma | 3001 | `/srv/homelab/uptime-kuma` | yes |
| SearXNG     | 8888 | stateless (config in repo) | yes |

## Required manual config (.env)

Some services require a `services/<service>/.env` file (not committed). Create it before running Ansible.

Services that need a `.env` (have `manage_env: true` in `ansible/group_vars/all.yml`):

| Service   | Template available |
|-----------|--------------------|
| Immich    | no                 |
| Vikunja   | no                 |
| Karakeep  | no                 |
| Nextcloud | no                 |
| Keycloak  | yes — copy `services/keycloak/.env.example` → `services/keycloak/.env` |
| Journiv      | yes — copy `services/journiv/.env.example` → `services/journiv/.env` |
| Vaultwarden  | yes — copy `services/vaultwarden/.env.example` → `services/vaultwarden/.env` |
| SearXNG      | no — set `server.secret_key` directly in `services/searxng/settings.yml` |

The playbook will fail with a clear error if a required `.env` is missing.

## Deployment

```bash
sudo ansible-playbook ansible/playbook.yml -i ansible/inventory.yml
```

### Ansible collections (install once)

```bash
ansible-galaxy collection install -r ansible/requirements.yml
```
