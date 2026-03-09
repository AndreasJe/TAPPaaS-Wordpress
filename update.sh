#!/usr/bin/env bash
# Usage: update.sh [--container]
#   --container   also pull a new WordPress image and restart
set -euo pipefail

. /home/tappaas/bin/common-install-routines.sh wordpress

UPDATE_CONTAINER=false
[[ "${1:-}" == "--container" ]] && UPDATE_CONTAINER=true

VMNAME="$(get_config_value 'vmname')"
NODE="$(get_config_value 'node')"

info "Deploying updated wordpress.nix to ${VMNAME}"
scp wordpress.nix "root@${VMNAME}:/etc/nixos/wordpress.nix"
ssh "root@${VMNAME}" nixos-rebuild switch

if [ "$UPDATE_CONTAINER" = true ]; then
  info "Pulling new WordPress image and restarting"
  ssh "root@${VMNAME}" bash << 'REMOTE'
    podman pull docker.io/wordpress:latest
    systemctl restart wordpress-container
REMOTE
fi

info "Done"
