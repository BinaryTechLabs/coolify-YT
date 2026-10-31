#!/usr/bin/env bash
#
# backup-coolify.sh - Binary Tech Labs
#
# Manual backup of Coolify's OWN data: its Postgres database plus the .env file
# that holds APP_KEY (the key that decrypts secrets stored in that database).
#
# What this does NOT back up: your applications' data, databases, or volumes.
# Those need their own backups (covered later in the series).
#
# Coolify's built-in scheduled backup (Settings > Backup) covers the database.
# This script is for a quick snapshot before you change something, or when the
# dashboard isn't available.
#
# Usage:   sudo bash backup-coolify.sh            (keeps the newest 7 backups)
#          sudo KEEP=14 bash backup-coolify.sh
#
# Based on: https://coolify.io/docs/core/backup-and-recovery/instance-backup

set -euo pipefail

KEEP="${KEEP:-7}"
BACKUP_ROOT="/data/backups/coolify-instance"
STAMP="$(date +%Y%m%d-%H%M%S)"
DEST="$BACKUP_ROOT/$STAMP"

[[ $EUID -eq 0 ]] || { echo "Run with sudo."; exit 1; }
docker inspect coolify-db >/dev/null 2>&1 || { echo "coolify-db container not found."; exit 1; }

umask 077
mkdir -p "$DEST"

echo "==> Dumping Coolify database"
docker exec coolify-db \
    pg_dump --format=custom --no-acl --no-owner \
    --username=coolify coolify >"$DEST/coolify-db.dmp"
test -s "$DEST/coolify-db.dmp" || { echo "Dump is empty, something went wrong."; exit 1; }

echo "==> Copying .env (contains APP_KEY - treat it like a password)"
cp /data/coolify/source/.env "$DEST/coolify.env"

chmod 600 "$DEST"/*
ls -lh "$DEST"

echo "==> Pruning old backups (keeping newest $KEEP)"
# Folder names are timestamps, so sorting by name newest-first is safe.
find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d | sort -r | tail -n +"$((KEEP + 1))" | xargs -r rm -rf --

cat <<EOF

Backup written to: $DEST

A backup that only lives on this server isn't really a backup.
Copy it somewhere else, for example from YOUR computer:

    scp -r <admin-user>@<server-ip>:$DEST ./coolify-backup-$STAMP

(you may need to: sudo chown -R <admin-user> $BACKUP_ROOT  first, or copy it as root)
EOF
