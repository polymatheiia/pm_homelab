#!/usr/bin/env bash
# One-time migration: move the GramVault Atlas checkout + data out of the
# home directory and into the homelab layout, and hand Ollama over to the
# bundled compose service.
#
#   sudo bash /srv/pm_homelab/services/gramvault-atlas/migrate-from-home.sh
#
# Idempotent-ish: safe to re-run; each step is skipped if already done.
# Everything is on one filesystem, so the moves are instant.

set -euo pipefail

HOME_SRC="${HOME_SRC:-/home/nymph/gramvault}"
SRC="/srv/gramvault-atlas"
DATA="/srv/homelab/gramvault-atlas"
OWNER="${SUDO_UID:-1000}:${SUDO_GID:-1000}"

[ "$(id -u)" -eq 0 ] || { echo "run with sudo"; exit 1; }

echo "==> stopping the old standalone GramVault container"
docker rm -f gramvault-gramvault-1 2>/dev/null || true

echo "==> moving the app checkout: $HOME_SRC -> $SRC"
if [ -d "$SRC/.git" ]; then
  echo "    $SRC already exists, skipping"
elif [ -d "$HOME_SRC/.git" ]; then
  mv "$HOME_SRC" "$SRC"
else
  echo "    ERROR: no git checkout at $HOME_SRC or $SRC" >&2
  exit 1
fi

echo "==> creating data root: $DATA"
mkdir -p "$DATA"

echo "==> moving data + library out of the checkout into $DATA"
for d in data library; do
  if [ -e "$DATA/$d" ]; then
    echo "    $DATA/$d already exists, skipping"
  elif [ -e "$SRC/$d" ]; then
    mv "$SRC/$d" "$DATA/$d"
  fi
done

echo "==> config.yaml + secrets.yaml -> $DATA"
[ -e "$DATA/config.yaml" ]  || { [ -e "$SRC/config.yaml" ]  && mv "$SRC/config.yaml"  "$DATA/config.yaml"; }
[ -e "$DATA/secrets.yaml" ] || { [ -e "$SRC/secrets.yaml" ] && mv "$SRC/secrets.yaml" "$DATA/secrets.yaml"; }
[ -e "$DATA/config.yaml" ]  || cp "$SRC/config.example.yaml" "$DATA/config.yaml"
[ -e "$DATA/secrets.yaml" ] || : > "$DATA/secrets.yaml"

# server.host / ollama.host / paths are all overridden by the compose env;
# this just keeps config.yaml sane if it is ever read directly.
sed -i -E '/^[[:space:]]*host:[[:space:]]*"?100\./ s#.*#  host: "127.0.0.1"#' "$DATA/config.yaml" || true
mkdir -p "$DATA/data/instaloader" "$DATA/data/hf"

echo "==> ownership: $DATA -> $OWNER, mode 600 on secrets"
chown -R "$OWNER" "$DATA" "$SRC"
chmod 600 "$DATA/secrets.yaml"
[ -f "$DATA/data/instaloader/session-"* ] 2>/dev/null && chmod 600 "$DATA"/data/instaloader/session-* || true

echo "==> removing the standalone 'ollama' container (its volume 'ollama' is kept and reused)"
docker rm -f ollama 2>/dev/null || true

cat <<EOF

Done. Layout is now:
  source : $SRC
  data   : $DATA  ($(du -sh "$DATA" 2>/dev/null | cut -f1))

Next:
  sudo ansible-playbook /srv/pm_homelab/ansible/playbook.yml -i /srv/pm_homelab/ansible/inventory.yml
  # or just this service:
  docker compose -f /srv/pm_homelab/services/gramvault-atlas/docker-compose.yml up -d --build

Then: https://gramvault-atlas.lab

Old DB/chroma backups moved along in $DATA/data (gramvault.db.bak-*,
chroma.bak-nomic) — delete when you're happy the migration worked.
EOF
