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

### On-demand services (Sablier)

This box has 7.7GB RAM and no swap. Most of the ~20 self-hosted tools in
`services/` are things used in bursts, not continuously — a PDF tool, a
BI dashboard, a backup runner, a budgeting app — so holding them in
memory 24/7 would waste most of that budget on idle processes. Instead
they run through [Sablier](https://github.com/sablierapp/sablier)
(`services/sablier/`), which starts a container on first request and
stops it again after an idle timeout, like a desktop app rather than a
server.

How it fits together:

- **Caddy** (per-vhost, via the `sablier` directive in
  `ansible/roles/caddy/templates/Caddyfile.j2`) intercepts requests to a
  gated service. If the container isn't running, it shows a
  self-refreshing "waiting" page (the `dynamic` strategy) while Sablier
  starts it, then reloads into the real app once it's ready.
- **Sablier** itself talks to the Docker socket to start/stop
  containers, grouped by a `sablier.group=<name>` label on the
  container (set in each service's `docker-compose.yml`) and gated by
  `sablier.enable=true`.
- **Each service is registered** in `ansible/group_vars/all.yml` with
  `sablier: true` and a `sablier_session_duration` — how long it stays
  up after the last request before Sablier shuts it down again (10–30
  minutes depending on the service; a quick PDF conversion doesn't need
  the same runway as a CI build).
- **Glance's Lab page** shows every gated service's live running/idle
  status via the `docker-containers` widget (reads the same
  `glance.category=on-demand` label), so "is X actually up right now"
  is a glance away without needing Sablier's own waiting page as a
  status board — it isn't one, it only ever shows one service's loading
  state at a time.

Important nuance learned the hard way: **Sablier has no dashboard or
status-overview page.** Don't mistake the per-service loading screen
for one, or assume it can substitute for an actual dashboard tool —
it can't.

**Kill switch:** `scripts/kill-on-demand.sh` stops every currently-running
on-demand container immediately (same `docker stop` Sablier would do on
timeout, just all at once, on demand — pass `--dry-run` to preview).
Always-on services and the Sablier/Caddy infra itself are untouched, and
nothing is removed, so the next request to any of them still wakes it
normally.

A handful of services stay **always-on** instead (Immich, Navidrome,
Glance, AdGuard, Sparky Fitness, Syncthing,
cloudflared, Prometheus, Healthchecks.io, dayGLANCE, Semaphore) — things that need
to be listening continuously (DNS, reverse proxy,
continuous file sync) rather than started on demand.

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
| Glance          | 8080          | config files in repo                 | yes |
| AdGuard Home    | 3080 (UI) / 53 (DNS) | `/srv/homelab/adguard`        | yes |
| Sparky Fitness  | 3004 (frontend) / 3010 (API) | `/srv/homelab/sparky` | yes |

## On-Demand Services

Sablier-gated — see [On-demand services (Sablier)](#on-demand-services-sablier)
above for how this works. Idle timeout is how long each stays up after
the last request before Sablier stops it again.

| Service      | Port | Purpose                                   | Idle timeout |
|--------------|------|--------------------------------------------|--------------|
| Mealie       | 9001 | Recipe manager                             | 30m |
| dawarich     | 9002 | Location history / life-logging            | 15m |
| DroppedNeedle| 9003 | Music acquisition (replaces Lidarr)        | 30m |
| Calibre-Web  | 9008 | Ebook library browser/reader (OPDS), reads /srv/pm_files/Books/Calibre Library read-only | 15m |
| homelable    | 9006 | Network topology visualizer                | 15m |
| Activepieces | 9009 | Workflow automation                        | 20m |
| Woodpecker CI| 9011 | CI/CD                                      | 20m |
| Scrutiny     | 9014 | Disk S.M.A.R.T. health monitoring          | 10m |
| Glances      | 9015 | Live CPU/mem/disk/process viewer           | 10m |
| Stirling-PDF | 9016 | PDF toolkit                                | 15m |
| Atheos       | 9017 | Cloud IDE                                  | 30m |
| Gramps Web   | 9019 | Genealogy software                         | 20m |
| Plakar       | 9021 | Backup (targets: Immich library, Karakeep, the retired Nextcloud data archive) | 10m |
| Grafana      | 9022 | BI/analytics, pairs with Prometheus        | 15m |
| Splitpro     | 9023 | Expense splitting                          | 15m |
| Actual       | 9024 | Budgeting (envelope-style, bank sync)      | 15m |
| Ryot         | 9025 | Media/life tracker (movies/TV/books/games) | 20m |
| Pipe Bomb    | 9026 | Plugin-based music streaming aggregator    | 20m |
| lifeGLANCE   | 9027 | Zoomable personal timeline (GLANCE family) | 20m |
| lastGLANCE   | 9028 | Recency tracker for chores/upkeep (GLANCE family) | 20m |
| GramVault Atlas | 8777 | Saved Instagram pipeline (pull/import → enrich → categorize → digest → Obsidian), RAG chat + reels-style feed, bundled Ollama | 20m |
| Karakeep     | 3000 | Bookmark/read-later manager with full-text search + screenshotting | 20m |

1Panel (`onepanel`) is deliberately excluded from Ansible deploy — no
official docker-compose path exists, only a host-level installer that
wants to manage the whole machine. Port 9005 is reserved but unused.
FreedomBox and localsend were considered but dropped: FreedomBox has no
viable Docker path (its containerization project was archived in 2019),
and localsend is a peer-to-peer LAN client for your own devices, not a
headless service — see `ansible/group_vars/all.yml` for the full
reasoning as inline comments.

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
