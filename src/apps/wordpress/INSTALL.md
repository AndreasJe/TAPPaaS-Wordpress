# WordPress — Installation Guide

## Prerequisites

- TAPPaaS cluster running with `firewall:proxy` (Caddy) and `backup:vm` operational
- DNS record `wordpress.<yourdomain>` pointing to your Caddy VM
- VM 620 available in Proxmox

## Install

From the tappaas-cicd command line:

```bash
install-module.sh wordpress
```

This validates all `dependsOn` services, wires them, then calls `install.sh`. `install.sh` sources `install-vm.sh` to create the VM from `wordpress.json`, runs `update-os.sh`, then deploys `wordpress.nix` and applies the NixOS configuration — all from the cicd host without manual SSH steps.

To override the target node:

```bash
install-module.sh wordpress --node tappaas2
```

## Post-install configuration

### 1. Set the site domain

During install, you'll be prompted for the public domain. This is written to the secrets file.

### 2. Complete the WordPress setup wizard

Open `https://wordpress.<yourdomain>` and follow the WordPress setup wizard.

### 3. Caddy reverse proxy

Configured automatically by `install-module.sh` via the `firewall:proxy` dependency. The proxy service wires `wordpress.<tappaas.domain>` → `wordpress.srv.internal:8080` via `caddy-manager` on OPNsense. No manual steps required.

If `firewallType` is `NONE` in `firewall.json`, the install will print the equivalent manual configuration to apply on your own proxy.

## Verification

```bash
./test.sh
```

---

## Update

```bash
update-module.sh wordpress
```

To also pull a new WordPress container image:

```bash
update-module.sh wordpress  # runs update.sh
# then on the VM:
./update.sh --container
```

## Delete

```bash
delete-module.sh wordpress
```

Stops all services and removes the NixOS module before VM teardown. Use `--force` to bypass reverse-dependency checks if other modules depend on `cms`.

```bash
delete-module.sh wordpress --force
```

---

## Authentication

Two models are supported and can coexist.

### Native WordPress accounts (default)

Active out of the box. Used for public users, readers, and commenters. No configuration needed.

### Authentik SSO for admins and editors

Admins and editors authenticate via your TAPPaaS Authentik instance. Native WordPress login remains active for public/commenter accounts.

**1. Create an OIDC provider in Authentik**

- Name: `wordpress`
- Redirect URI: `https://wordpress.<yourdomain>/wp-admin/admin-ajax.php?action=openid-connect-authorize`
- Note the Client ID and Client Secret

**2. Create group mappings in Authentik**

| Authentik group      | WordPress role |
|----------------------|----------------|
| wordpress-admins     | Administrator  |
| wordpress-editors    | Editor         |

**3. Install the WordPress plugin**

In wp-admin, install **OpenID Connect Generic Client** by daggerhart.

**4. Fill in secrets**

Secrets are auto-generated on first boot at `/etc/secrets/wordpress.env`. Edit as needed:

```bash
sudo vim /etc/secrets/wordpress.env
```

Uncomment and fill:

```
OIDC_CLIENT_ID=wordpress
OIDC_CLIENT_SECRET=<from Authentik>
OIDC_ENDPOINT_LOGIN_URL=https://authentik.<domain>/application/o/wordpress/authorize
OIDC_ENDPOINT_TOKEN_URL=https://authentik.<domain>/application/o/wordpress/token
OIDC_ENDPOINT_USERINFO_URL=https://authentik.<domain>/application/o/wordpress/userinfo
OIDC_ENDPOINT_LOGOUT_URL=https://authentik.<domain>/application/o/wordpress/end-session
```

**5. Enable in wordpress.nix and apply**

Uncomment the `OIDC_*` env var block in `wordpress.nix` and run:

```bash
update-module.sh wordpress
```

**6. Disable native login for admin accounts**

Once SSO is confirmed working, enable "Disable WordPress login form for SSO users" in the plugin settings. Public/commenter accounts are unaffected.

---

## Performance notes

The following are enabled by default and require no configuration:

- **PHP-FPM** — `wordpress:6.7-fpm` image, dynamic pool (max 8 workers)
- **OPcache** — PHP bytecode cached in memory, 128MB
- **Nginx** — serves static assets directly with 1-year cache headers
- **Redis** — 256MB object + full-page cache on port 6380
- **MariaDB query cache** — 64MB, effective for read-heavy sites

To enable full-page caching, install **W3 Total Cache** or **WP Super Cache** in wp-admin and point it at Redis `127.0.0.1:6380`.

Disable the slow query log once initial tuning is complete:

```nix
slow_query_log = 0;
```

Then run `update-module.sh wordpress`.

---

## Upgrading WordPress

Edit the version in `wordpress.nix`:

```nix
wordpress = "6.8-fpm";
```

```bash
update-module.sh wordpress
```

## Backup & restore

Backups run automatically:

- `/var/backup/wordpress-db/` — gzipped SQL dumps, daily 02:00
- `/var/backup/wordpress-data/` — gzipped file archives, daily 02:30
- Both retained 30 days

Full VM snapshots are handled by `backup:vm` in Proxmox.

**Restore:**

```bash
systemctl stop wordpress-container
gunzip -c /var/backup/wordpress-db/wordpress-YYYYMMDD.sql.gz | mysql wordpress
tar xzf /var/backup/wordpress-data/wordpress-YYYYMMDD.tar.gz -C /
systemctl start wordpress-container
```

## Security notes

- Secrets auto-generated on first boot, stored in `/etc/secrets/wordpress.env` (mode 600)
- WordPress security keys must not be changed after the site is live — doing so invalidates all active sessions
- MariaDB and Redis bound to `127.0.0.1` only
- WordPress not directly internet-exposed — all traffic via Caddy in the proxy zone
