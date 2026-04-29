# WordPress — Backlog

## Known limitations

- **Single disk** — OS and data share one volume on tankb1. When the TAPPaaS schema supports multi-disk VMs, split into an OS disk (tanka1, 16G) and a data disk (tankb1, 50G) mounting `/var/lib/wordpress` and `/var/lib/mysql` separately. Until then, disk failure takes both OS and data.

- **Application backups are on-VM only** — MariaDB dumps and file archives write to `/var/backup/` on the same disk. Proxmox VM snapshots cover full restore, but granular content recovery (e.g. a single deleted post) depends on these dumps surviving. A disk failure loses both. Backups should be shipped off-VM to the TAPPaaS backup target.

- **`identity:identity` not wired** — dependency declared but Authentik OIDC is not connected by default. See INSTALL.md — Authentication for setup steps.

## Future work

- Multi-disk schema support in `wordpress.json`
- Off-VM backup shipping for MariaDB dumps and file archives
- WP-CLI integration for plugin/theme management without wp-admin
