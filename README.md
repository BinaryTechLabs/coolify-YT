# Self-Hosting Ep. 1: Coolify on an Ubuntu VPS + Cloudflare Tunnel

**Binary Tech Labs · Self-Hosting Series · Episode 1**

Install Coolify on a clean Ubuntu VPS and reach it through a Cloudflare Tunnel, with **no inbound web ports open**. Only SSH stays open, and only from your own IP.

▶️ **Watch the video:** *coming soon*

## What you'll end up with

- A hardened Ubuntu 24.04 server: key-only SSH, automatic security updates, and a provider firewall that allows nothing but SSH from your IP.
- Coolify installed, with the first admin login done safely over an SSH tunnel (the registration page is never public).
- The Coolify dashboard at `https://coolify.example.com`, served through a Cloudflare Tunnel with a free certificate.
- Coolify's ports locked to `localhost`, the `APP_KEY` saved, and backups and updates set up from day one.

## Before you start

- A VPS with **Ubuntu 24.04 LTS**: 2 vCPU, 4 GB RAM (2 GB works with swap), 40 GB disk, a public IPv4 address.
- A VPS provider with a **network firewall** (Docker-published ports bypass UFW, so you need one outside the server).
- A free **Cloudflare** account and a domain using Cloudflare's nameservers.
- An **SSH key** on your computer (`ssh-keygen -t ed25519`).

## What's in this folder

```
scripts/
├── prepare-server.sh        updates, admin user, key-only SSH, optional swap
├── check-coolify.sh         read-only health check: containers, tunnel, ports, SSH settings
└── backup-coolify.sh        manual Coolify database dump + .env (APP_KEY) snapshot
config/
├── sshd/00-btl-hardening.conf          → /etc/ssh/sshd_config.d/ on the server
├── coolify/docker-compose.custom.yml   → /data/coolify/source/ (binds 8000/6001/6002 to localhost)
└── ssh/config.example                  → ~/.ssh/config on YOUR computer
```

## Quick start

```bash
# 1. On the fresh server, as root. Read the script before you run it.
less scripts/prepare-server.sh
bash scripts/prepare-server.sh <your-username>

# 2. As your new user: install Coolify (read the installer first)
curl -fsSL https://cdn.coollabs.io/coolify/install.sh -o coolify-install.sh
less coolify-install.sh
sudo bash coolify-install.sh

# 3. From your computer: the first login, without exposing port 8000
ssh -N -L 8000:localhost:8000 -L 6001:localhost:6001 -L 6002:localhost:6002 <your-username>@<server-ip>
#    then open http://localhost:8000 and create your admin account straight away
```

Then create the tunnel in Cloudflare and route `coolify.example.com` to `http://localhost:80`, as shown in the video.

## The four things people get wrong

1. **Relying on UFW.** Docker-published ports bypass it. Use your VPS provider's firewall.
2. **`PermitRootLogin no`.** Coolify connects to its own server as root over SSH. Use `prohibit-password` instead.
3. **Leaving "Redirect HTTP to HTTPS" on** behind the tunnel. You'll get `TOO_MANY_REDIRECTS`.
4. **Updating with `install.sh`.** Use `upgrade.sh <version>`. Re-running `install.sh` resets permissions under `/data/coolify`.

## Script safety

- Plain, commented Bash. No obfuscation, and nothing downloaded and run behind your back.
- `prepare-server.sh` **refuses to run** if root has no SSH key, so you can't lock yourself out. It checks the SSH config with `sshd -t` before restarting, and it's safe to run again.
- `check-coolify.sh` changes nothing.
- `backup-coolify.sh` writes its files with mode `600` and keeps the last 7 copies by default.

## Tested with

Coolify 4.4.6 · Ubuntu 24.04 LTS · Docker (installed by Coolify) · `cloudflare/cloudflared` (Coolify one-click service) · October 2026

## Useful links

- Coolify docs: https://coolify.io/docs
- Cloudflare Tunnel docs: https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/

---

**Binary Tech Labs** · Finding useful technology, figuring out how it works, deploying it properly, and showing you how to do the same.
Read every script before you run it. Everything here is provided as-is, without warranty.
