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
- Data root: /srv/pm_homelab

## Remote Access

- All services are accessible via Tailscale IP.
- Example: http://100.x.y.z:2283 → Immich
- Nothing is exposed to the internet which is exactly the point.
- Also, I operate under significant constraint called eduroam (the server is in the dorm room), so this is literally the only sane option

## Services

| Service    | Port | Data Location |
|------------|------|---------------|
| Immich     | 2283 | /srv/homelab/immich |
| Navidrome  | 4533 | /srv/homelab/navidrome |
| Vikunja    | 3456 | /srv/homelab/vikunja |
| Karakeep   | 3000 | Docker volume |
| Glance     | 8080 | just configs here |
| Nextcloud  | 8000 | /srv/homelab/nextcloud |

## Required manual config (.env)

Some services require a `services/<service>/.env` file (not committed). Create it before running Ansible:

- Copy `services/<service>/.env.example` → `services/<service>/.env`
- Fill in secrets/values

The playbook will fail with a clear error if a required `.env` is missing.

## Deployment

```bash
sudo ansible-playbook ansible/playbook.yml -i ansible/inventory.yml
