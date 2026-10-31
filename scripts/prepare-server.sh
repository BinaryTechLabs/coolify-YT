#!/usr/bin/env bash
#
# prepare-server.sh - Binary Tech Labs
#
# Prepares a FRESH Ubuntu 24.04 LTS VPS before Coolify is installed:
#   1. Installs updates and makes sure automatic security updates are on
#   2. Creates a sudo admin user and copies root's SSH key to it
#   3. Installs an SSH hardening drop-in (keys only, root by key only)
#   4. Optionally adds a swap file (set SWAP_SIZE, e.g. SWAP_SIZE=2G)
#
# It does NOT install Coolify, Docker, or a firewall. Those steps are done by hand
# in the video so you can see what each one does.
#
# Usage (as root, on the server):
#   curl -fsSL -o prepare-server.sh <raw GitHub URL of this file>
#   less prepare-server.sh            # read it first. Always.
#   bash prepare-server.sh lenard     # or: SWAP_SIZE=2G bash prepare-server.sh lenard
#
# Safe to re-run: every step checks whether it's already been done.

set -euo pipefail

ADMIN_USER="${1:-}"
SWAP_SIZE="${SWAP_SIZE:-}"
DROPIN="/etc/ssh/sshd_config.d/00-btl-hardening.conf"

info() { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mWARNING:\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

# --- Safety checks ------------------------------------------------------------

[[ $EUID -eq 0 ]] || die "Run this as root (sudo -i first)."
[[ -n "$ADMIN_USER" ]] || die "Usage: bash prepare-server.sh <admin-username>"
[[ "$ADMIN_USER" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] || die "'$ADMIN_USER' isn't a valid Linux username."

# shellcheck disable=SC1091
. /etc/os-release
[[ "${ID:-}" == "ubuntu" ]] || warn "This script was written for Ubuntu; you're on '${ID:-unknown}'. Continuing anyway."

# If root has no SSH key, disabling password logins would lock us out.
if [[ ! -s /root/.ssh/authorized_keys ]]; then
    die "/root/.ssh/authorized_keys is empty. Add your SSH key to the server first (most providers do this when you create the VPS)."
fi

# --- 1. Updates ---------------------------------------------------------------

info "Installing updates (this can take a few minutes)"
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get -y full-upgrade
apt-get -y install unattended-upgrades curl ca-certificates

info "Making sure unattended security upgrades are enabled"
cat >/etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF

# --- 2. Admin user ------------------------------------------------------------

if id "$ADMIN_USER" &>/dev/null; then
    info "User '$ADMIN_USER' already exists, skipping creation"
else
    info "Creating user '$ADMIN_USER'"
    adduser --disabled-password --gecos "" "$ADMIN_USER"
    echo "Set a password for '$ADMIN_USER'. You'll use it for sudo, NOT for SSH logins:"
    passwd "$ADMIN_USER"
fi
usermod -aG sudo "$ADMIN_USER"

info "Copying root's authorized SSH keys to '$ADMIN_USER'"
install -d -m 700 -o "$ADMIN_USER" -g "$ADMIN_USER" "/home/$ADMIN_USER/.ssh"
# Copy only lines that aren't already there, so re-running doesn't duplicate keys.
touch "/home/$ADMIN_USER/.ssh/authorized_keys"
new_keys=$(grep -vxF -f "/home/$ADMIN_USER/.ssh/authorized_keys" /root/.ssh/authorized_keys || true)
[[ -n "$new_keys" ]] && printf '%s\n' "$new_keys" >>"/home/$ADMIN_USER/.ssh/authorized_keys"
chown "$ADMIN_USER:$ADMIN_USER" "/home/$ADMIN_USER/.ssh/authorized_keys"
chmod 600 "/home/$ADMIN_USER/.ssh/authorized_keys"

# --- 3. SSH hardening ---------------------------------------------------------
# Keep this block in sync with config/sshd/00-btl-hardening.conf

info "Writing SSH hardening drop-in to $DROPIN"
cat >"$DROPIN" <<'EOF'
# Binary Tech Labs - SSH hardening for a Coolify server.
# Keys only. Root may log in with a key only (Coolify needs this for localhost).
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin prohibit-password
MaxAuthTries 4
LoginGraceTime 30
X11Forwarding no
EOF
chmod 644 "$DROPIN"

info "Validating SSH configuration"
sshd -t || die "sshd config test failed. Fix $DROPIN before restarting SSH."

info "Effective SSH settings:"
sshd -T | grep -Ei '^(passwordauthentication|kbdinteractiveauthentication|permitrootlogin|pubkeyauthentication) '

systemctl restart ssh

# --- 4. Optional swap ---------------------------------------------------------

if [[ -n "$SWAP_SIZE" ]]; then
    if swapon --show | grep -q .; then
        info "Swap already active, skipping"
    else
        info "Creating ${SWAP_SIZE} swap file at /swapfile"
        fallocate -l "$SWAP_SIZE" /swapfile
        chmod 600 /swapfile
        mkswap /swapfile
        swapon /swapfile
        grep -q '^/swapfile ' /etc/fstab || echo '/swapfile none swap sw 0 0' >>/etc/fstab
    fi
fi

# --- Done ---------------------------------------------------------------------

cat <<EOF

All done.

BEFORE you close this session, open a NEW terminal on your computer and run:

    ssh ${ADMIN_USER}@<server-ip>
    sudo whoami        # should print: root

If that works, you're ready to install Coolify.
EOF

if [[ -f /var/run/reboot-required ]]; then
    warn "A reboot is required to finish installing updates. Run 'reboot' after testing the new login."
fi
