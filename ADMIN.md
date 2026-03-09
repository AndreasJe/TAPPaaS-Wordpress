# WordPress — Admin Reference

## Service management

```bash
systemctl status wordpress-container mysql redis-wordpress

systemctl restart wordpress-container
systemctl restart mysql
systemctl restart redis-wordpress
```

## Logs

```bash
journalctl -u wordpress-container -f
journalctl -u mysql -f
journalctl -u redis-wordpress -f
journalctl -u generate-wordpress-secrets
```

## Database

```bash
# Open MariaDB CLI
mysql -u wordpress -p wordpress

# Show active connections
mysql -u root -e "SHOW PROCESSLIST;"

# Database size
mysql -u root -e "SELECT table_schema, ROUND(SUM(data_length+index_length)/1024/1024,1) AS 'MB' FROM information_schema.tables GROUP BY table_schema;"
```

## Redis

```bash
redis-cli -p 6380 PING
redis-cli -p 6380 INFO stats
redis-cli -p 6380 DBSIZE
redis-cli -p 6380 FLUSHALL   # clear cache (safe — rebuilt automatically)
```

## Secrets

```bash
# View secrets
sudo cat /etc/secrets/wordpress.env

# View template (no real values)
cat /etc/secrets/wordpress-template.env
```

## Backups

```bash
# Trigger manual DB backup
systemctl start backup-wordpress-db

# Trigger manual file backup
systemctl start backup-wordpress-data

# List backup files
ls -lh /var/backup/wordpress-db/
ls -lh /var/backup/wordpress-data/

# Check timer status
systemctl list-timers | grep wordpress
```

## Disk usage

```bash
df -h /var/lib/wordpress
du -sh /var/lib/wordpress/wp-content/uploads
du -sh /var/backup/wordpress-*
```

## NixOS

```bash
# Apply config changes
nixos-rebuild switch

# Roll back last change
nixos-rebuild switch --rollback

# Check generation history
nixos-rebuild list-generations
```
