# WordPress — Backlog

## Known limitations

- **Manual deployment** — no automated VM creation yet; follow INSTALL.md step by step
- **Single disk** — OS and data share one volume on tankc1; when TAPPaaS schema supports multi-disk VMs, split into OS disk (tanka1, 16G) and data disk (tankc1, 50G) for `/var/lib/wordpress` and `/var/lib/mysql`
- **No SSO wired by default** — Authentik OIDC config is present in `wordpress.nix` but commented out; see INSTALL.md — Authentication
- **DB password initialisation** — MariaDB `initialScript` uses a placeholder; synced on first boot via `wordpress-db-password-sync.service`

## Future work

- Cloud-init automation for zero-touch VM provisioning
- Multi-disk schema support in `wordpress.json`
- Caddy block auto-generated from `wordpress.json` `zone0` + `vmname`
- WP-CLI integration for plugin/theme management without wp-admin
