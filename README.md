# Homelab

Self-hosted services managed with Ansible and Docker Compose.
As it is "homelab" and not "homeprod", it is obviously small - I'm here to learn, both deployment and documentation.

## Architecture

- Reverse proxy: Caddy
- Container runtime: Docker
- Provisioning: Ansible
- Data root: /srv/homelab

## Remote Access

- All services are accessible via Tailscale IP. 
- Example: http://100.x.y.z:2283 → Immich
- Nothing is exposed to the internet which is exactly the point.
- Also, I operate under significant constraint called eduroam (the server is in the dorm room), so this is literalkly the only sane option

## Services

| Service    | Port | Data Location |
|------------|------|---------------|
| Immich     | 2283 | /srv/homelab/immich |
| Navidrome  | 4533 | /srv/homelab/navidrome |
| Vikunja    | 3456 | /srv/homelab/vikunja | 
| Karakeep   | 3000 | Docker volume |
| Glance     | 8080 | just configs here |

## Deployment

```bash
sudo ansible-playbook ansible/playbook.yml -i ansible/inventory.yml
```

Disclaimer: this is (obviously) a work in progress, so the setup is prone to very stupid mistakes.
Proceed with caution and according distance. I'm also open to suggestions, I'm just a girl after all :)
