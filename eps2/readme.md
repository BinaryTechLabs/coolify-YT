# Self-Hosting Ep. 2: Your First App Through the Tunnel (Wildcard Route)

**Binary Tech Labs · Self-Hosting Series · Episode 2**

One wildcard route in Cloudflare, one wildcard domain in Coolify, and every app you deploy from now on gets its own `https://<name>.example.com` address. Still with no ports opened. We deploy `whoami` to see exactly what a request looks like, then a real app: **Uptime Kuma**, monitoring the server.

▶️ **Watch the video:** *coming soon*

## What you'll end up with

- A `*.example.com` tunnel route and Coolify's wildcard domain working together.
- **Uptime Kuma v2** at `https://status.example.com`, with 2FA, monitors and notifications.
- A clear picture of how a request finds its way from Cloudflare to the right container, so the errors make sense.

## Before you start

- The setup from **Episode 1**: Coolify on a VPS behind a Cloudflare Tunnel.
- On your computer: `curl` and `openssl` (on Windows, use WSL or Git Bash).
- A notification service for Uptime Kuma (Discord, ntfy, email…).

## What's in this folder

```
scripts/
├── check-routing.sh          run on YOUR computer: Cloudflare, tunnel, redirect and wildcard checks
└── backup-volume.sh          run on the server: snapshot one Docker volume (stops the app if asked)
config/
└── uptime-kuma.compose.yml   Coolify's Uptime Kuma template with the image pinned to an exact version
```

## Quick start

```bash
# On your computer: check every hostname, plus a random one (the wildcard)
bash scripts/check-routing.sh example.com coolify status --deep

# On the server: list volumes, then back up Uptime Kuma's
sudo bash scripts/backup-volume.sh -l
sudo bash scripts/backup-volume.sh <uptime-kuma-volume> -s <uptime-kuma-container>
```

## The three settings that matter

1. **Cloudflare tunnel route:** `*.example.com` → `http://localhost:80`
2. **Coolify → Servers → Wildcard Domain:** `https://example.com`
3. **Every app → Domains → Redirect HTTP to HTTPS:** Disabled (Cloudflare already does that)

Keep app names **one level deep** (`status.example.com`, not `status.apps.example.com`). Cloudflare's free certificate only covers one level.

## Script safety

- Plain, commented Bash; checked with `shellcheck`.
- `check-routing.sh` only makes normal HTTPS requests and changes nothing.
- `backup-volume.sh` mounts the volume read-only. If it stops a container, it always starts it again, even if the copy fails. Backups are written with mode `600`.

## Tested with

Coolify 4.4.6 · Uptime Kuma 2.5.6 (`louislam/uptime-kuma:2`) · traefik/whoami v1.12.0 · October 2026

## Useful links

- Coolify docs: https://coolify.io/docs
- Uptime Kuma: https://github.com/louislam/uptime-kuma

---

**Binary Tech Labs** · Finding useful technology, figuring out how it works, deploying it properly, and showing you how to do the same.
Read every script before you run it. Everything here is provided as-is, without warranty.
