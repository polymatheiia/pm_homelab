# Homelab

Self-hosted services managed with Ansible and Docker Compose.

## Current list of Services

- Immich
- Navidrome
- Vikunja
- Glance
- Karakeep

## Provisioning

```bash
sudo ansible-playbook ansible/playbook.yml -i ansible/inventory.yml
```

Disclaimer: this is (obviously) a work in progress, so the setup is prone to very stupid mistakes.
Proceed with caution and according distance.
