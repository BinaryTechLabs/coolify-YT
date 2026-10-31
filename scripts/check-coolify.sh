#!/usr/bin/env bash
#
# check-coolify.sh - Binary Tech Labs
#
# Read-only health check for a Coolify server exposed through a Cloudflare Tunnel.
# It changes nothing. Run it after install, after a reboot, or when something
# looks wrong.
#
# Usage:  sudo bash check-coolify.sh

set -uo pipefail

ok()   { printf '  \033[1;32mOK\033[0m    %s\n' "$*"; }
bad()  { printf '  \033[1;31mFAIL\033[0m  %s\n' "$*"; }
note() { printf '  \033[1;33mNOTE\033[0m  %s\n' "$*"; }
section() { printf '\n\033[1m%s\033[0m\n' "$*"; }

[[ $EUID -eq 0 ]] || { echo "Run with sudo."; exit 1; }

section "Coolify containers"
for c in coolify coolify-db coolify-redis coolify-proxy cloudflare-tunnel; do
    state=$(docker inspect -f '{{.State.Status}}{{if .State.Health}} ({{.State.Health.Status}}){{end}}' "$c" 2>/dev/null)
    if [[ -z "$state" ]]; then
        bad "$c: not found"
    elif [[ "$state" == running* && "$state" != *unhealthy* ]]; then
        ok "$c: $state"
    else
        bad "$c: $state"
    fi
done

section "Coolify version"
image=$(docker inspect -f '{{.Config.Image}}' coolify 2>/dev/null || true)
if [[ -n "$image" ]]; then ok "${image##*:}"; else bad "Could not read the coolify image tag"; fi

section "Dashboard health endpoint (from the server itself)"
if curl -fsS --max-time 5 http://127.0.0.1:8000/api/health >/dev/null; then
    ok "http://127.0.0.1:8000/api/health responded"
else
    bad "Dashboard did not respond on 127.0.0.1:8000"
fi

section "Listening ports (8000/6001/6002 should be 127.0.0.1 after the lockdown step)"
ss -Hltn | awk '{print $4}' | grep -E ':(22|80|443|8000|6001|6002)$' | sort -u | while read -r addr; do
    case "$addr" in
        0.0.0.0:800[0]|0.0.0.0:600[12]|\[::\]:8000|\[::\]:600[12])
            note "$addr is on all interfaces. Make sure your provider firewall blocks it." ;;
        *) ok "$addr" ;;
    esac
done

section "Cloudflare Tunnel connections (last 50 log lines)"
conns=$(docker logs --tail 50 cloudflare-tunnel 2>&1 | grep -c "Registered tunnel connection")
if (( conns > 0 )); then
    ok "$conns registered connection line(s) found"
else
    note "No 'Registered tunnel connection' lines in recent logs. Check: docker logs cloudflare-tunnel"
fi

section "SSH effective settings"
sshd -T 2>/dev/null | grep -Ei '^(passwordauthentication|permitrootlogin) ' | while read -r k v; do
    case "$k $v" in
        "passwordauthentication no"|"permitrootlogin prohibit-password"|"permitrootlogin without-password")
            ok "$k $v" ;;
        "permitrootlogin no")
            bad "$k $v  (Coolify can't manage localhost. Use prohibit-password)" ;;
        *)  note "$k $v" ;;
    esac
done

section "Disk usage"
df -h / | tail -1 | awk '{print "  " $5 " used of " $2 " on /"}'
docker system df 2>/dev/null | sed 's/^/  /'

echo
