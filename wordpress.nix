# Copyright (c) 2025 TAPPaaS org
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

# ============================================================================
# TAPPaaS - WordPress CMS
# ============================================================================
# Version: 0.2.0
# Date: 2026-03-08
#
# Architecture:
# - WordPress (PHP-FPM) via Podman container
# - Nginx reverse proxy (port 8080)
# - MariaDB 11.x backend
# - Redis object cache (named instance, port 6380)
# - Secrets auto-generated on first boot
#
# Network: SRV zone (VLAN 210, 10.2.10.0/24)
# Firewall: ports 22 (SSH) + 8080 (WordPress HTTP)
# Secrets: Auto-generated on first boot at /etc/secrets/wordpress.env
# Backups: Daily DB dump + file archive, 30-day retention
# ============================================================================

{ config, lib, pkgs, modulesPath, ... }:

let
  versions = {
    wordpress = "6.7-fpm";
  };
  secretsFile = "/etc/secrets/wordpress.env";
in
{

  # ==========================================================================
  # IMPORTS
  # ==========================================================================

  imports = [
    /etc/nixos/hardware-configuration.nix
  ];

  # ==========================================================================
  # BOOT
  # ==========================================================================

  boot.loader.systemd-boot.enable      = lib.mkDefault true;
  boot.loader.efi.canTouchEfiVariables = lib.mkDefault true;
  boot.growPartition                   = lib.mkDefault true;

  # ==========================================================================
  # CLOUD-INIT
  # ==========================================================================

  services.cloud-init = {
    enable         = true;
    network.enable = false;
  };

  # ==========================================================================
  # NETWORKING
  # ==========================================================================

  networking.hostName = lib.mkDefault "wordpress";
  networking.networkmanager.enable = true;
  networking.networkmanager.ensureProfiles.profiles.tappaas-ethernet = {
    connection = { id = "tappaas-ethernet"; type = "ethernet"; autoconnect = "true"; autoconnect-priority = "100"; };
    ipv4       = { method = "auto"; };
    ipv6       = { method = "auto"; addr-gen-mode = "default"; };
  };

  systemd.network.enable             = lib.mkForce false;
  systemd.network.wait-online.enable = lib.mkForce false;

  systemd.services."serial-getty@ttyS0" = {
    enable            = true;
    wantedBy          = [ "getty.target" ];
    serviceConfig.Restart = "always";
  };

  networking.firewall = {
    enable          = true;
    allowedTCPPorts = [ 22 8080 ];
  };

  # ==========================================================================
  # TIME ZONE
  # ==========================================================================

  time.timeZone = lib.mkDefault "Europe/Amsterdam";

  # ==========================================================================
  # USERS & SECURITY
  # ==========================================================================

  users.users.tappaas = {
    isNormalUser = true;
    extraGroups  = [ "wheel" "networkmanager" ];
  };

  security.sudo.wheelNeedsPassword = false;

  # ==========================================================================
  # NIX SETTINGS
  # ==========================================================================

  nix.settings.trusted-users         = [ "root" "@wheel" ];
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nixpkgs.config.allowUnfree          = true;

  nix.gc = {
    automatic = true;
    dates     = "weekly";
    options   = "--delete-older-than 30d";
  };

  nix.optimise = {
    automatic = true;
    dates     = [ "weekly" ];
  };

  # ==========================================================================
  # ESSENTIAL SERVICES
  # ==========================================================================

  services.qemuGuest.enable = true;

  services.openssh = {
    enable   = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin        = "no";
    };
  };

  programs.ssh.startAgent = true;

  # ==========================================================================
  # NGINX
  # ==========================================================================

  services.nginx = {
    enable = true;
    virtualHosts."wordpress" = {
      listen = [{ addr = "0.0.0.0"; port = 8080; }];
      root   = "/var/lib/wordpress";
      extraConfig = "index index.php index.html index.htm;";  # ← ADD THIS
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

  # ==========================================================================
  # PHP-FPM
  # ==========================================================================

  services.phpfpm.pools.wordpress = {
    user       = "nginx";
    group      = "nginx";
    phpPackage = pkgs.php83;
    settings = {
      "listen"                                         = "/run/phpfpm/wordpress.sock";
      "listen.owner"                                   = "nginx";
      "listen.group"                                   = "nginx";
      "pm"                                             = "dynamic";
      "pm.max_children"                                = 8;
      "pm.start_servers"                               = 2;
      "pm.min_spare_servers"                           = 2;
      "pm.max_spare_servers"                           = 4;
      "php_admin_value[opcache.enable]"                = 1;
      "php_admin_value[opcache.memory_consumption]"    = 128;
      "php_admin_value[opcache.max_accelerated_files]" = 4000;
      "php_admin_value[opcache.revalidate_freq]"       = 60;
    };
  };

  # ==========================================================================
  # SECRETS - auto-generated on first boot
  # ==========================================================================

  systemd.services.generate-wordpress-secrets = {
    description = "Generate WordPress secret keys and DB password";
    wantedBy    = [ "multi-user.target" ];
    after       = [ "local-fs.target" ];
    before      = [ "mysql.service" "wordpress-container.service" ];
    unitConfig.ConditionPathExists = "!${secretsFile}";
    serviceConfig = {
      Type            = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "generate-wordpress-secrets" ''
        mkdir -p /etc/secrets
        cat > ${secretsFile} <<EOF
# WordPress runtime secrets - generated on first boot
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
      '';
    };
  };

  # ==========================================================================
  # MARIADB
  # ==========================================================================

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
      ExecStart = pkgs.writeShellScript "wordpress-db-password-sync" ''
        source ${secretsFile}
        ${pkgs.mariadb}/bin/mysql -u root <<SQL
          ALTER USER 'wordpress'@'localhost' IDENTIFIED BY '$WORDPRESS_DB_PASSWORD';
          FLUSH PRIVILEGES;
SQL
      '';
    };
  };

  # ==========================================================================
  # REDIS
  # ==========================================================================

  services.redis.servers.wordpress = {
    enable   = true;
    port     = 6380;
    settings = {
      maxmemory        = 268435456;
      maxmemory-policy = "allkeys-lru";
      save             = "";
    };
  };

  # ==========================================================================
  # WORDPRESS CONTAINER
  # ==========================================================================

  virtualisation.podman.enable = true;

  systemd.tmpfiles.rules = [
    "d /var/lib/wordpress         0750 nginx nginx -"
    "d /var/backup/wordpress-db   0700 root  root  -"
    "d /var/backup/wordpress-data 0700 root  root  -"
    "d /var/log/mysql             0755 mysql mysql -" 
  ];

  systemd.services.wordpress-container = {
    description = "WordPress via Podman (PHP-FPM)";
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
      ExecStart    = ''
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

      # ── OPTION: Authentik SSO for wp-admin ──────────────────────────────
      #
      # Use when admins/editors should authenticate via Authentik (OIDC).
      # Public users (readers, commenters) use native WordPress accounts.
      #
      # Prerequisites:
      #   1. Create an OAuth2/OIDC provider in Authentik named "wordpress"
      #   2. Map Authentik groups to WP roles (see INSTALL.md - Authentication)
      #   3. Install "OpenID Connect Generic Client" plugin in WordPress
      #   4. Fill OIDC_* values in /etc/secrets/wordpress.env
      #   5. Uncomment the env vars below and run: nixos-rebuild switch
      #   6. Disable the native WP login form via the plugin settings
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

  # ==========================================================================
  # BACKUPS
  # ==========================================================================

  systemd.services.backup-wordpress-db = {
    description = "Daily MariaDB dump for WordPress";
    serviceConfig = {
      Type      = "oneshot";
      ExecStart = pkgs.writeShellScript "backup-wordpress-db" ''
        ${pkgs.mariadb}/bin/mysqldump --single-transaction --routines wordpress \
          | ${pkgs.gzip}/bin/gzip > /var/backup/wordpress-db/wordpress-$(date +%Y%m%d).sql.gz
      '';
    };
  };
  systemd.timers.backup-wordpress-db = {
    wantedBy    = [ "timers.target" ];
    timerConfig = { OnCalendar = "02:00"; Persistent = true; };
  };

  systemd.services.backup-wordpress-data = {
    description = "Daily file archive for WordPress";
    serviceConfig = {
      Type      = "oneshot";
      ExecStart = pkgs.writeShellScript "backup-wordpress-data" ''
        ${pkgs.gnutar}/bin/tar czf \
          /var/backup/wordpress-data/wordpress-$(date +%Y%m%d).tar.gz \
          /var/lib/wordpress
      '';
    };
  };
  systemd.timers.backup-wordpress-data = {
    wantedBy    = [ "timers.target" ];
    timerConfig = { OnCalendar = "02:30"; Persistent = true; };
  };

  systemd.services.backup-wordpress-cleanup = {
    description = "Remove WordPress backups older than 30 days";
    serviceConfig = {
      Type      = "oneshot";
      ExecStart = pkgs.writeShellScript "backup-wordpress-cleanup" ''
        ${pkgs.findutils}/bin/find /var/backup/wordpress-db   -mtime +30 -delete
        ${pkgs.findutils}/bin/find /var/backup/wordpress-data -mtime +30 -delete
      '';
    };
  };
  systemd.timers.backup-wordpress-cleanup = {
    wantedBy    = [ "timers.target" ];
    timerConfig = { OnCalendar = "monthly"; Persistent = true; };
  };

  # ==========================================================================
  # SYSTEM PACKAGES
  # ==========================================================================

  environment.systemPackages = with pkgs; [
    vim
    wget
    curl
    htop
    git
    jq
    openssl
    mariadb
    podman
  ];

  # ==========================================================================
  # SYSTEM STATE VERSION - DO NOT CHANGE after initial install
  # ==========================================================================

  system.stateVersion = "25.05";
}
