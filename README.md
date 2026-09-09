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

| Service         | Port          | Data Location                        | Ansible-managed |
|-----------------|---------------|--------------------------------------|-----------------|
| Immich          | 2283          | via `.env` (`UPLOAD_LOCATION`, `DB_DATA_LOCATION`) | yes |
| Navidrome       | 4533          | `/srv/homelab/navidrome`, `/srv/media/music` (read-only) | yes |
| Karakeep        | 3000          | Docker volumes                       | yes |
| Glance          | 8080          | config files in repo                 | yes |
| Nextcloud       | 8000          | Docker volumes                       | yes |
| AdGuard Home    | 3080 (UI) / 53 (DNS) | `/srv/homelab/adguard`        | yes |
| SearXNG         | 8888          | stateless (config in repo)           | yes |
| Sparky Fitness  | 3004 (frontend) / 3010 (API) | `/srv/homelab/sparky` | yes |
| GramVault Atlas | 8777          | `/srv/homelab/gramvault-atlas` (db/chroma/media) | yes |

### GramVault Atlas

Local-first pipeline for saved Instagram content (pull/import → enrich →
categorize → digest → Obsidian) with a RAG chat and a reels-style feed.
Fork of [GramVault](https://github.com/aleksanderislami03-cell/gramvault);
this repo's copy lives at [`polymatheiia/gramvault-atlas`](https://github.com/polymatheiia/gramvault-atlas).

- **Source / build context:** `/srv/gramvault-atlas` (a git clone — this is
  the one service built from source, not pulled as an image).
- **Bundled Ollama:** `services/gramvault-atlas/docker-compose.yml` runs
  `ollama` as a second service on a private network, reusing the existing
  `ollama` Docker volume. There is no standalone `ollama` container.
- **First deploy:** `sudo bash services/gramvault-atlas/migrate-from-home.sh`
  (moves the checkout + data into place, drops the old standalone `ollama`),
  then the playbook.
- **Updating the app:** `git -C /srv/gramvault-atlas pull` then
  `docker compose -f services/gramvault-atlas/docker-compose.yml up -d --build`.
- This box has 7.7 GB RAM / no swap — route the `digest` (and heavy
  `categorize`) AI tasks to a hosted API in Settings → Models if local
  models thrash.

### Sparky Fitness — split routing

Sparky has a separate nginx frontend (port 3004) and Node.js backend (port 3010).
Caddy routes `/api/*` and `/uploads/*` directly to port 3010; everything else goes to the frontend.
This avoids the Docker DNS caching bug that would occur if nginx inside the frontend container
proxied to the backend — after a container recreation the cached IP would be stale.

### Bridge Manager

[Beeper bridge-manager](https://github.com/beeper/bridge-manager) (`bbctl`) is installed and managed
by the `bridge-manager` Ansible role. Bridges are defined in `ansible/group_vars/all.yml` under
`bridge_manager_bridges` and run as systemd units (`bbctl-<name>.service`).

## Required manual config (.env)

Some services require a `services/<service>/.env` file (not committed). Create it before running Ansible.

Services that need a `.env` (have `manage_env: true` in `ansible/group_vars/all.yml`):

| Service         | Template available |
|-----------------|--------------------|
| Immich          | no                 |
| Karakeep        | no                 |
| Nextcloud       | yes — copy `services/nextcloud/.env.example` → `services/nextcloud/.env` |
| Sparky Fitness  | no                 |
| GramVault Atlas | yes — copy `services/gramvault-atlas/.env.example` → `.env` (just host uid/gid) |

The playbook will fail with a clear error if a required `.env` is missing.

## Deployment

```bash
sudo ansible-playbook ansible/playbook.yml -i ansible/inventory.yml
```

### Ansible collections (install once)

```bash
ansible-galaxy collection install -r ansible/requirements.yml
```
