# 1Panel — not deployed via docker-compose

1Panel (github.com/1Panel-dev/1Panel) has no officially documented docker-compose
deployment. Its own README's only supported install method is a host-level installer
script:

```bash
bash -c "$(curl -sSL https://resource.1panel.pro/v2/quick_start.sh)"
```

This script installs `1pctl` and its own Docker/systemd integration directly on the
host — it manages the whole machine (installs Docker if missing, wants direct access
to `docker.sock`, sets up its own systemd services), which is architecturally
different from every other on-demand service in this repo (each of which is a
self-contained container group behind Sablier). Wrapping the installer in a
docker-compose file would not match how 1Panel is meant to run and isn't officially
supported by the project.

Community docker-in-docker wrappers for 1Panel exist (e.g. `ghcr.io/1panel-dev/1panel`
appears in some third-party repos) but they are not the vendor's documented path and
were not used here to avoid fabricating an unsupported deployment.

**Status:** host port 9005 is reserved for 1Panel but no docker-compose.yml/.env exist
for it. Deploying 1Panel requires running the installer script directly on the host
(outside Ansible/Sablier's container-group model), which needs an operator decision
before proceeding (it will manage Docker on the whole host, not just this repo's
containers).
