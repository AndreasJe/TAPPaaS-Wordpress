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

# ── Write domain to VM and restart container ──────────────────────────────
# VM is already provisioned by cluster:vm and templates:nixos (Step 4).
# All we need to do is write the confirmed domain into the secrets file
# on the VM and start the container.

CONFIG_JSON="/home/tappaas/config/wordpress.json"
VMID="$(jq -r '.vmid' "${CONFIG_JSON}")"
NODE="$(jq -r '.node' "${CONFIG_JSON}")"

echo "  Getting VM IP address..."
VM_IP="$(ssh tappaas@proxmox-"${NODE}" \
    "qm guest exec ${VMID} -- ip -4 addr show ens18 2>/dev/null || true" 2>/dev/null \
    | grep -oP '(?<=inet )\d+\.\d+\.\d+\.\d+' | head -1 || true)"

# Fallback: resolve via internal DNS
if [[ -z "${VM_IP}" ]]; then
    VM_IP="$(getent hosts wordpress.srv.internal 2>/dev/null | awk '{print $1}' || true)"
fi

if [[ -z "${VM_IP}" ]]; then
    echo "[ERROR] Could not determine VM IP. Write domain manually:"
    echo "  sudo sed -i 's|DOMAIN=.*|DOMAIN=https://${SITE_DOMAIN}|' /etc/secrets/wordpress.env"
    exit 1
fi

echo "  Writing domain to VM (${VM_IP})..."
ssh -o StrictHostKeyChecking=no "tappaas@${VM_IP}" \
    "sudo sed -i 's|DOMAIN=.*|DOMAIN=https://${SITE_DOMAIN}|' /etc/secrets/wordpress.env && \
     sudo systemctl restart wordpress-container"

echo ""
echo "  ✓ WordPress deployed at https://${SITE_DOMAIN}"
