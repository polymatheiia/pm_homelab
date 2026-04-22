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
- Container runtime: Docker
- Provisioning: Ansible
- Compose deploy root: `/srv/pm_homelab` (where Ansible copies compose files)
- Service data root: `/srv/homelab` (where most services store persistent data)

## Remote Access

- All services are accessible via Tailscale IP.
- Example: http://100.x.y.z:2283 → Immich
- Nothing is exposed to the internet which is exactly the point.
- Also, I operate under significant constraint called eduroam (the server is in the dorm room), so this is literally the only sane option

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
| Journiv    | 8050 | `/srv/homelab/journiv/data` | no (manual) |

> **Journiv** is not yet wired into the Ansible playbook — start it manually with `docker compose up -d` from `services/journiv/`.

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

The playbook will fail with a clear error if a required `.env` is missing.

## Deployment

```bash
sudo ansible-playbook ansible/playbook.yml -i ansible/inventory.yml
```

### Ansible collections (install once)

```bash
ansible-galaxy collection install -r ansible/requirements.yml
```
