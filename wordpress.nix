{ config, pkgs, lib, ... }:

let
  versions = {
    wordpress = "6.7-fpm";
  };

  secretsFile = "/etc/secrets/wordpress.env";

in {

  # ── Networking ────────────────────────────────────────────────────────────
  services.cloud-init.enable = true;
  services.qemuGuest.enable  = true;
  boot.growPartition         = true;

  networking.firewall.allowedTCPPorts = [ 8080 ];


  # ── Nginx ─────────────────────────────────────────────────────────────────
  # Fronts PHP-FPM via FastCGI. Serves static assets directly with long-lived
  # cache headers, bypassing PHP entirely for images, CSS, JS, fonts.
  services.nginx = {
    enable = true;
    virtualHosts."wordpress" = {
      listen = [{ addr = "0.0.0.0"; port = 8080; }];
      root   = "/var/lib/wordpress";
      locations."/" = {
        tryFiles = "$uri $uri/ /index.php?$args";
      };
      locations."~ \\.php$" = {
        extraConfig = ''
          fastcgi_pass  unix:/run/phpfpm/wordpress.sock;
          fastcgi_index index.php;
          include       ${pkgs.nginx}/conf/fastcgi_params;
          fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        '';
      };
      locations."~* \\.(css|js|png|jpg|webp|woff2|ico)$" = {
        extraConfig = ''
          expires 1y;
          add_header Cache-Control "public, immutable";
        '';
      };
    };
  };

  # PHP-FPM — dynamic pool, max_children = vCPU × 2 for I/O-bound workloads.
  # OPcache keeps compiled PHP bytecode in memory, eliminating parse overhead.
  services.phpfpm.pools.wordpress = {
    user       = "nginx";
    group      = "nginx";
    phpPackage = pkgs.php83;
    settings = {
      "listen"               = "/run/phpfpm/wordpress.sock";
      "listen.owner"         = "nginx";
      "listen.group"         = "nginx";
      "pm"                   = "dynamic";
      "pm.max_children"      = 8;
      "pm.start_servers"     = 2;
      "pm.min_spare_servers" = 2;
      "pm.max_spare_servers" = 4;
      "php_admin_value[opcache.enable]"                = 1;
      "php_admin_value[opcache.memory_consumption]"    = 128;
      "php_admin_value[opcache.max_accelerated_files]" = 4000;
      "php_admin_value[opcache.revalidate_freq]"       = 60;
    };
  };


  # ── Secrets — auto-generated on first boot ────────────────────────────────
  systemd.services.generate-wordpress-secrets = {
    description = "Generate WordPress secret keys and DB password";
    wantedBy    = [ "multi-user.target" ];
    before      = [ "mysql.service" "wordpress-container.service" ];
    serviceConfig = {
      Type            = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      if [ ! -f ${secretsFile} ]; then
        mkdir -p /etc/secrets
        cat > ${secretsFile} <<EOF
# WordPress runtime secrets — generated $(date -Iseconds)
# Set DOMAIN to match your Caddy hostname before first run.

DOMAIN=https://wordpress.yourdomain.example

WORDPRESS_DB_HOST=127.0.0.1
WORDPRESS_DB_NAME=wordpress
WORDPRESS_DB_USER=wordpress
WORDPRESS_DB_PASSWORD=$(${pkgs.openssl}/bin/openssl rand -base64 24)

WORDPRESS_AUTH_KEY=$(${pkgs.openssl}/bin/openssl rand -base64 48)
WORDPRESS_SECURE_AUTH_KEY=$(${pkgs.openssl}/bin/openssl rand -base64 48)
WORDPRESS_LOGGED_IN_KEY=$(${pkgs.openssl}/bin/openssl rand -base64 48)
WORDPRESS_NONCE_KEY=$(${pkgs.openssl}/bin/openssl rand -base64 48)
WORDPRESS_AUTH_SALT=$(${pkgs.openssl}/bin/openssl rand -base64 48)
WORDPRESS_SECURE_AUTH_SALT=$(${pkgs.openssl}/bin/openssl rand -base64 48)
WORDPRESS_LOGGED_IN_SALT=$(${pkgs.openssl}/bin/openssl rand -base64 48)
WORDPRESS_NONCE_SALT=$(${pkgs.openssl}/bin/openssl rand -base64 48)
EOF
        chmod 600 ${secretsFile}

        cat > /etc/secrets/wordpress-template.env <<'TMPL'
DOMAIN=https://wordpress.<yourdomain>
WORDPRESS_DB_HOST=127.0.0.1
WORDPRESS_DB_NAME=wordpress
WORDPRESS_DB_USER=wordpress
WORDPRESS_DB_PASSWORD=<generated>
WORDPRESS_AUTH_KEY=<generated>
WORDPRESS_SECURE_AUTH_KEY=<generated>
WORDPRESS_LOGGED_IN_KEY=<generated>
WORDPRESS_NONCE_KEY=<generated>
WORDPRESS_AUTH_SALT=<generated>
WORDPRESS_SECURE_AUTH_SALT=<generated>
WORDPRESS_LOGGED_IN_SALT=<generated>
WORDPRESS_NONCE_SALT=<generated>
TMPL
        chmod 644 /etc/secrets/wordpress-template.env
      fi
    '';
  };


  # ── MariaDB ───────────────────────────────────────────────────────────────
  # innodb_buffer_pool: cache hot data/indexes in RAM, sized for 2GB VM.
  # query_cache: effective for read-heavy WP sites with repeated queries.
  # slow_query_log: disable once initial tuning is complete.
  services.mysql = {
    enable  = true;
    package = pkgs.mariadb;
    settings.mysqld = {
      bind-address            = "127.0.0.1";
      character-set-server    = "utf8mb4";
      collation-server        = "utf8mb4_unicode_ci";
      innodb_buffer_pool_size = "512M";
      max_connections         = 50;
      query_cache_type        = 1;
      query_cache_size        = "64M";
      query_cache_limit       = "2M";
      slow_query_log          = 1;
      slow_query_log_file     = "/var/log/mysql/slow.log";
      long_query_time         = 1;
    };
    initialScript = pkgs.writeText "wordpress-db-init.sql" ''
      CREATE DATABASE IF NOT EXISTS wordpress
        CHARACTER SET utf8mb4
        COLLATE utf8mb4_unicode_ci;
      CREATE USER IF NOT EXISTS 'wordpress'@'localhost'
        IDENTIFIED BY 'PLACEHOLDER';
      GRANT ALL PRIVILEGES ON wordpress.* TO 'wordpress'@'localhost';
      FLUSH PRIVILEGES;
    '';
  };

  systemd.services.wordpress-db-password-sync = {
    description = "Sync generated DB password into MariaDB";
    after       = [ "mysql.service" "generate-wordpress-secrets.service" ];
    wantedBy    = [ "multi-user.target" ];
    before      = [ "wordpress-container.service" ];
    serviceConfig = {
      Type            = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      source ${secretsFile}
      ${pkgs.mariadb}/bin/mysql -u root <<SQL
        ALTER USER 'wordpress'@'localhost' IDENTIFIED BY '$WORDPRESS_DB_PASSWORD';
        FLUSH PRIVILEGES;
SQL
    '';
  };


  # ── Redis ─────────────────────────────────────────────────────────────────
  # Named instance on port 6380. Serves both WP object cache (Redis Object
  # Cache plugin) and full-page cache (W3 Total Cache / WP Super Cache).
  # 256mb covers both layers; allkeys-lru evicts cold keys under pressure.
  services.redis.servers.wordpress = {
    enable          = true;
    port            = 6380;
    maxmemory       = "256mb";
    maxmemoryPolicy = "allkeys-lru";
    save            = [];
  };


  # ── WordPress container ───────────────────────────────────────────────────
  virtualisation.podman.enable = true;

  systemd.tmpfiles.rules = [
    "d /var/lib/wordpress 0750 nginx nginx -"
  ];

  systemd.services.wordpress-container = {
    description = "WordPress Podman container (PHP-FPM)";
    after = [
      "network.target"
      "mysql.service"
      "generate-wordpress-secrets.service"
      "wordpress-db-password-sync.service"
      "nginx.service"
    ];
    requires = [ "mysql.service" "nginx.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStartPre = "${pkgs.podman}/bin/podman pull docker.io/wordpress:${versions.wordpress}";
      ExecStart = ''
        ${pkgs.podman}/bin/podman run --rm \
          --name wordpress \
          --network host \
          --env-file ${secretsFile} \
          -e WORDPRESS_REDIS_HOST=127.0.0.1 \
          -e WORDPRESS_REDIS_PORT=6380 \
          -v /var/lib/wordpress:/var/www/html \
          -v /run/phpfpm/wordpress.sock:/run/phpfpm/wordpress.sock \
          docker.io/wordpress:${versions.wordpress}
      '';

      # ── OPTION: Authentik SSO for wp-admin ────────────────────────────
      #
      # Use this when admins and editors should authenticate via Authentik
      # (OIDC). Public users (readers, commenters) continue using native
      # WordPress accounts — no change needed for them.
      #
      # Prerequisites:
      #   1. Create an OAuth2/OIDC provider in Authentik named "wordpress"
      #   2. Map Authentik groups to WP roles (see INSTALL.md — Authentication)
      #   3. Install "OpenID Connect Generic Client" plugin in WordPress
      #   4. Fill OIDC_* values in /etc/secrets/wordpress.env
      #   5. Uncomment the env vars below and run: nixos-rebuild switch
      #   6. Once confirmed working, disable the native WP login form via
      #      the plugin settings to prevent password-based admin bypass.
      #
      # -e OIDC_CLIENT_ID=wordpress \
      # -e OIDC_CLIENT_SECRET=<from Authentik provider> \
      # -e OIDC_ENDPOINT_LOGIN_URL=https://authentik.<domain>/application/o/wordpress/authorize \
      # -e OIDC_ENDPOINT_TOKEN_URL=https://authentik.<domain>/application/o/wordpress/token \
      # -e OIDC_ENDPOINT_USERINFO_URL=https://authentik.<domain>/application/o/wordpress/userinfo \
      # -e OIDC_ENDPOINT_LOGOUT_URL=https://authentik.<domain>/application/o/wordpress/end-session \

      ExecStop   = "${pkgs.podman}/bin/podman stop wordpress";
      Restart    = "on-failure";
      RestartSec = "15s";
    };
  };


  # ── Backups ───────────────────────────────────────────────────────────────

  # MariaDB dump — daily 02:00
  systemd.services.backup-wordpress-db = {
    description = "Daily MariaDB dump for WordPress";
    serviceConfig.Type = "oneshot";
    script = ''
      mkdir -p /var/backup/wordpress-db
      ${pkgs.mariadb}/bin/mysqldump --single-transaction --routines wordpress \
        | ${pkgs.gzip}/bin/gzip > /var/backup/wordpress-db/wordpress-$(date +%Y%m%d).sql.gz
    '';
  };
  systemd.timers.backup-wordpress-db = {
    wantedBy    = [ "timers.target" ];
    timerConfig = { OnCalendar = "02:00"; Persistent = true; };
  };

  # File archive (uploads, themes, plugins) — daily 02:30
  systemd.services.backup-wordpress-data = {
    description = "Daily file archive for WordPress";
    serviceConfig.Type = "oneshot";
    script = ''
      mkdir -p /var/backup/wordpress-data
      ${pkgs.gnutar}/bin/tar czf \
        /var/backup/wordpress-data/wordpress-$(date +%Y%m%d).tar.gz \
        /var/lib/wordpress
    '';
  };
  systemd.timers.backup-wordpress-data = {
    wantedBy    = [ "timers.target" ];
    timerConfig = { OnCalendar = "02:30"; Persistent = true; };
  };

  # Cleanup backups older than 30 days — monthly
  systemd.services.backup-wordpress-cleanup = {
    description = "Remove WordPress backups older than 30 days";
    serviceConfig.Type = "oneshot";
    script = ''
      ${pkgs.findutils}/bin/find /var/backup/wordpress-db   -mtime +30 -delete
      ${pkgs.findutils}/bin/find /var/backup/wordpress-data -mtime +30 -delete
    '';
  };
  systemd.timers.backup-wordpress-cleanup = {
    wantedBy    = [ "timers.target" ];
    timerConfig = { OnCalendar = "monthly"; Persistent = true; };
  };


  # ── Packages ──────────────────────────────────────────────────────────────
  environment.systemPackages = with pkgs; [
    mariadb
    podman
    curl
    wget
  ];
}
