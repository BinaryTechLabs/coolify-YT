#!/usr/bin/env bash
#
# backup-volume.sh - Binary Tech Labs
#
# Makes a .tar.gz snapshot of ONE Docker volume (for example Uptime Kuma's data)
# on the Coolify server. It's a stop-gap until proper off-site backups (Ep. 4).
#
# Apps that use SQLite (Uptime Kuma does) should be stopped while copying, or
# the copy can be inconsistent. Pass the container name with -s and the script
# stops it, copies, and starts it again, even if the copy fails.
#
# Usage (on the server):
#   sudo bash backup-volume.sh -l                                   # list volumes
#   sudo bash backup-volume.sh <volume-name>                        # hot copy
#   sudo bash backup-volume.sh <volume-name> -s <container-name>    # stop, copy, start
#
# Restore (replaces the volume's contents; stop the app first!):
#   sudo docker run --rm -v <volume-name>:/data -v /data/backups/volumes:/backup:ro \
#     alpine sh -c 'rm -rf /data/* && tar xzf /backup/<file>.tar.gz -C /data'

set -euo pipefail

DEST_DIR="/data/backups/volumes"
VOLUME="" CONTAINER=""

[[ $EUID -eq 0 ]] || { echo "Run with sudo."; exit 1; }

case "${1:-}" in
    -l) docker volume ls --format '{{.Name}}'; exit 0 ;;
    ""|-h|--help) sed -n '/^# Usage/,/^# Restore/p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
    *) VOLUME="$1"; shift ;;
esac
while [[ $# -gt 0 ]]; do
    case "$1" in
        -s) CONTAINER="$2"; shift 2 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

docker volume inspect "$VOLUME" >/dev/null 2>&1 || { echo "No such volume: $VOLUME (use -l to list)"; exit 1; }

STAMP=$(date +%Y%m%d-%H%M%S)
FILE="$VOLUME-$STAMP.tar.gz"
mkdir -p "$DEST_DIR"
chmod 700 "$DEST_DIR"

restart_container() {
    if [[ -n "$CONTAINER" ]]; then
        echo "==> Starting $CONTAINER again"
        docker start "$CONTAINER" >/dev/null || echo "WARNING: could not start $CONTAINER. Start it from Coolify!"
    fi
}

if [[ -n "$CONTAINER" ]]; then
    docker inspect "$CONTAINER" >/dev/null 2>&1 || { echo "No such container: $CONTAINER (docker ps)"; exit 1; }
    echo "==> Stopping $CONTAINER for a consistent copy"
    docker stop "$CONTAINER" >/dev/null
    trap restart_container EXIT
fi

echo "==> Archiving volume $VOLUME"
docker run --rm -v "$VOLUME":/data:ro -v "$DEST_DIR":/backup alpine:3 \
    tar czf "/backup/$FILE" -C /data .
chmod 600 "$DEST_DIR/$FILE"
ls -lh "$DEST_DIR/$FILE"

cat <<EOF

Saved: $DEST_DIR/$FILE
Copy it off the server, e.g. from your computer:
  scp <admin-user>@<server-ip>:$DEST_DIR/$FILE .
(you may need: sudo chown <admin-user> $DEST_DIR/$FILE)
EOF
