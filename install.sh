#!/usr/bin/env bash
set -euo pipefail

# ── Domain prompt ─────────────────────────────────────────────────────────
# Ask for the public domain before any VM work starts, so the operator
# can confirm before a long install begins.

TAPPAAS_DOMAIN=$(jq -r '.tappaas.domain // empty' /home/tappaas/config/configuration.json 2>/dev/null || true)
DEFAULT_DOMAIN="wordpress.${TAPPAAS_DOMAIN:-yourdomain.example}"

echo ""
echo "  WordPress public domain"
echo "  ────────────────────────────────────────────"
echo "  This will be the URL users access WordPress on."
echo "  Default: ${DEFAULT_DOMAIN}"
echo ""
read -rp "  Domain [${DEFAULT_DOMAIN}]: " INPUT_DOMAIN
SITE_DOMAIN="${INPUT_DOMAIN:-${DEFAULT_DOMAIN}}"

echo ""
echo "  ┌──────────────────────────────────────────┐"
echo "  │  Site domain : https://${SITE_DOMAIN}"
echo "  │  Upstream    : wordpress.srv.internal"
echo "  │  Caddy wiring: auto via firewall:proxy"
echo "  └──────────────────────────────────────────┘"
echo ""
read -rp "  Confirm? [Y/n]: " CONFIRM
CONFIRM="${CONFIRM:-Y}"
if [[ ! "${CONFIRM}" =~ ^[Yy]$ ]]; then
    echo "  Aborted."
    exit 1
fi
echo ""

# ── Create the VM from wordpress.json ────────────────────────────────────
. /home/tappaas/bin/install-vm.sh

IMAGE_TYPE="$(get_config_value 'imageType' 'clone')"

/home/tappaas/bin/update-os.sh "${VMNAME}" "${VMID}" "${NODE}"

# ── Deploy NixOS module ───────────────────────────────────────────────────
info "Deploying wordpress.nix to ${VMNAME}"
scp wordpress.nix "root@${VMNAME}:/etc/nixos/wordpress.nix"
ssh "root@${VMNAME}" bash << REMOTE
  if ! grep -q "wordpress.nix" /etc/nixos/configuration.nix; then
    sed -i "/imports = \[/a\\    ./wordpress.nix" /etc/nixos/configuration.nix
  fi
  nixos-rebuild switch
  systemctl is-active --quiet generate-wordpress-secrets || \
    systemctl start generate-wordpress-secrets
  sleep 2
  # Write the confirmed domain into secrets
  sed -i "s|DOMAIN=.*|DOMAIN=https://${SITE_DOMAIN}|" /etc/secrets/wordpress.env
  systemctl restart wordpress-container
REMOTE

info "WordPress deployed at https://${SITE_DOMAIN}"
