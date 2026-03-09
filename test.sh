#!/usr/bin/env bash
set -euo pipefail

PASS=0
FAIL=0

check() {
  local label="$1"
  local cmd="$2"
  if eval "$cmd" &>/dev/null; then
    echo "  ✅ $label"
    ((PASS++))
  else
    echo "  ❌ $label"
    ((FAIL++))
  fi
}

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║   TAPPaaS WordPress — Health Check       ║"
echo "╚══════════════════════════════════════════╝"
echo ""

check "MariaDB running"             "systemctl is-active mysql"
check "Redis running"               "systemctl is-active redis-wordpress"
check "Secrets file present"        "test -f /etc/secrets/wordpress.env"
check "PHP-FPM container up"        "systemctl is-active wordpress-fpm"
check "Nginx running"               "systemctl is-active nginx"
check "HTTP 200 on :8080"           "curl -sf http://localhost:8080 -o /dev/null"
check "Redis responding"            "redis-cli -p 6380 PING"
check "DB backup timer active"      "systemctl is-active backup-wordpress-db.timer"
check "Data backup timer active"    "systemctl is-active backup-wordpress-data.timer"

echo ""
echo "  Passed: $PASS   Failed: $FAIL"
echo ""

[ "$FAIL" -eq 0 ]
