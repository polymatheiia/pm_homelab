#!/usr/bin/env bash
# Stops every currently-running Sablier-gated (on-demand) container.
#
# Sablier scales these to zero on its own after each service's idle
# timeout, but on a 7.7GB/no-swap box you sometimes want that to happen
# right now (memory pressure, about to start something heavy, or just
# winding down before leaving). This does the same thing Sablier does —
# `docker stop` on containers carrying the `sablier.enable=true` label —
# just immediately and for all of them at once instead of one at a time
# on a timer. Always-on and Sablier infra containers are untouched, and
# nothing is removed or taken down with compose, so the next request to
# any of these services still wakes it normally.
#
# Usage:
#   scripts/kill-on-demand.sh          # stop all running on-demand containers
#   scripts/kill-on-demand.sh --dry-run   # show what would be stopped

set -euo pipefail

dry_run=false
if [[ "${1:-}" == "--dry-run" ]]; then
    dry_run=true
fi

mapfile -t containers < <(docker ps --filter "label=sablier.enable=true" --format '{{.Names}}')

if [[ ${#containers[@]} -eq 0 ]]; then
    echo "No on-demand containers currently running."
    exit 0
fi

if $dry_run; then
    echo "Would stop ${#containers[@]} on-demand container(s):"
    printf '  %s\n' "${containers[@]}"
    exit 0
fi

echo "Stopping ${#containers[@]} on-demand container(s):"
printf '  %s\n' "${containers[@]}"
docker stop "${containers[@]}"
