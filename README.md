# WordPress on TAPPaaS

**Version:** 0.1.0
**Status:** Development

Self-hosted WordPress CMS on NixOS with MariaDB, Redis, PHP-FPM, and Nginx.

## Stack

| Component | Version | Notes |
|-----------|---------|-------|
| WordPress | 6.7-fpm | PHP-FPM image |
| PHP       | 8.3     | OPcache enabled |
| Nginx     | latest  | FastCGI proxy, static asset cache |
| MariaDB   | 11.4    | utf8mb4, query cache |
| Redis     | 7.x     | Object + full-page cache, port 6380 |
| Podman    | 5.x     | Container runtime |
| NixOS     | 25.05   | |

## Architecture

```
┌──────────────────────────────────┐
│  OPNsense / Caddy (dmz)          │
│  wordpress.<tappaas.domain>      │
│  → wordpress.srv.internal:8080   │
│  Auto-wired via firewall:proxy   │
└────────────────┬─────────────────┘
                 │
┌────────────────▼─────────────────┐
│  Nginx :8080                     │
│  Static assets served directly   │
│  PHP → FastCGI socket            │
└──────┬────────────────┬──────────┘
       │                │
┌──────▼──────┐  ┌──────▼──────────┐
│  PHP-FPM    │  │  WordPress      │
│  8 workers  │  │  Podman         │
│  OPcache    │  │                 │
└──────┬──────┘  └─────────────────┘
       │
┌──────▼──────────────────────────┐
│  MariaDB :3306   Redis :6380    │
│  localhost only  localhost only │
└─────────────────────────────────┘
```

## Authentication

| User type           | Auth method                               |
|---------------------|-------------------------------------------|
| Admins / Editors    | Authentik OIDC (optional, see INSTALL.md) |
| Public / Commenters | Native WordPress accounts                 |

## VM Specifications

| Resource | Value |
|----------|-------|
| vCPU     | 2 (4 recommended for production) |
| Memory   | 2 GB (4 GB recommended) |
| Disk     | 50 GB on tankc1 |
| Network  | srv zone |
| VMID     | 620 |

## Backups

| What         | Schedule               | Location                    |
|--------------|------------------------|-----------------------------|
| MariaDB dump | Daily 02:00            | /var/backup/wordpress-db/   |
| File archive | Daily 02:30            | /var/backup/wordpress-data/ |
| VM snapshot  | Per backup:vm schedule | Proxmox                     |
| Cleanup      | Monthly                | All backup dirs             |

Retention: 30 days.

## Lifecycle

```bash
install-module.sh wordpress        # install
update-module.sh wordpress         # update
delete-module.sh wordpress         # delete
```

## Management

```bash
# Health check
./test.sh

# Service status
systemctl status wordpress-container nginx mysql redis-wordpress

# Logs
journalctl -u wordpress-container -f

# Restart
systemctl restart wordpress-container
```

## License

Mozilla Public License 2.0 — see [LICENSE](LICENSE)
