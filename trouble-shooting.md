# Troubleshooting

> Format: **Symptom → Likely cause → Diagnose → Fix**. Run diagnostics on the server unless marked 🖥️.

---

### 1. `ERR_TOO_MANY_REDIRECTS` on `https://coolify.example.com`
- **Cause:** Coolify's **Redirect HTTP to HTTPS** is enabled. The tunnel talks to the proxy over HTTP, Coolify redirects to HTTPS, Cloudflare comes back over HTTP, and it loops.
- **Diagnose 🖥️:** `curl -sI https://coolify.example.com | grep -i location` keeps pointing at itself.
- **Fix:** Use the SSH forward (`localhost:8000`) → **Settings → General → Redirect HTTP to HTTPS: Disabled** → Save. Use Cloudflare's **Always Use HTTPS** instead.

### 2. Route added but the domain doesn't load (DNS error / old site)
- **Cause:** A DNS record for that hostname already existed. Cloudflare won't overwrite it.
- **Diagnose 🖥️:** `dig +short coolify.example.com CNAME` doesn't return `…cfargotunnel.com`.
- **Fix:** Tunnel → Configure → copy **Tunnel ID**. **DNS → Records**: delete the old record and add `CNAME coolify → <TUNNEL_ID>.cfargotunnel.com`, **Proxied**.

### 3. Domain shows a plain `404 page not found`
- **Cause:** The tunnel and proxy work, but Coolify's instance **URL** isn't set (or doesn't match the hostname exactly).
- **Diagnose:** `docker logs --tail 50 coolify-proxy`, then check **Settings → General → URL**.
- **Fix:** Set the URL to `https://coolify.example.com` exactly (scheme included, no path, no trailing slash) and save.

### 4. Cloudflare `502 Bad Gateway` / error 1033
- **Cause (502):** `cloudflared` can't reach `localhost:80`. Usually the Coolify proxy is stopped, or `localhost` resolves to IPv6 `::1`.
- **Cause (1033):** No connector is running for the tunnel.
- **Diagnose:**
  ```bash
  docker ps --filter name=coolify-proxy --filter name=cloudflare-tunnel
  docker logs --tail 50 cloudflare-tunnel
  curl -sI http://127.0.0.1:80
  ```
- **Fix:** **Servers → localhost → Proxy → Start Proxy**. Change the route's service URL to `http://127.0.0.1:80`. Redeploy the Cloudflared service; check the token was pasted completely (no `docker run…` prefix, no trailing space).

### 5. Dashboard loads, but no live updates / terminal won't connect
- **Cause:** Websocket paths aren't reaching the proxy correctly: leftover `PUSHER_*`/`TERMINAL_*` overrides, an IPv6 `localhost` issue, or extra legacy routes in the wrong order.
- **Diagnose:**
  ```bash
  sudo grep -E '^(PUSHER_HOST|PUSHER_PORT|PUSHER_SCHEME|TERMINAL_HOST|TERMINAL_PORT)=' /data/coolify/source/.env
  ```
  Browser dev tools → Network → WS: the connections should go to `coolify.example.com`. Visit `/realtime` for the test event.
- **Fix:** Remove those overrides from `.env`, then re-apply Coolify (`upgrade.sh <current-version>`; a plain `docker restart` doesn't reload `.env`). Use a single route to `http://127.0.0.1:80`.

### 6. Localhost server "not reachable" / validation fails in Coolify
- **Cause:** Root SSH was disabled (`PermitRootLogin no`), or Coolify's key was removed from `/root/.ssh/authorized_keys`.
- **Diagnose:**
  ```bash
  sudo sshd -T | grep -i permitrootlogin
  sudo grep -c coolify /root/.ssh/authorized_keys
  ```
- **Fix:** Set `PermitRootLogin prohibit-password` (our drop-in) → `sudo sshd -t && sudo systemctl restart ssh`. If the key is missing, follow Coolify's OpenSSH "Manual" guide: https://coolify.io/docs/core/infrastructure/servers/openssh

### 7. Locked out of SSH after hardening
- **Cause:** Your key wasn't in the new user's (or root's) `authorized_keys` before passwords were disabled, or your home IP changed and the firewall rule no longer matches.
- **Diagnose 🖥️:** `ssh -v <username>@SERVER_IP`. "Connection timed out" points to the firewall/IP; "Permission denied (publickey)" points to the key.
- **Fix:** Update the provider firewall rule to your current IP. For key problems, use the **provider's web console** to log in and fix `~/.ssh/authorized_keys` (mode 600, dir 700, owned by the user).

### 8. "Domain does not point to this server" warning when saving the URL
- **Cause:** Expected. The domain resolves to Cloudflare's IPs, not the VPS.
- **Fix:** Continue/confirm. If it blocks saving: **Settings → Advanced → DNS validation: Disabled**, save the URL, then turn it back on if you like.

### 9. Port 8000 still reachable from the internet
- **Cause:** The provider firewall isn't attached or has an extra rule. UFW won't help, because Docker-published ports bypass it.
- **Diagnose 🖥️:** `curl -m 5 http://SERVER_IP:8000`. **☁️:** `sudo ss -ltnp | grep 8000`.
- **Fix:** Attach and fix the provider firewall. Apply the `docker-compose.custom.yml` localhost binding. No provider firewall? Use [ufw-docker](https://github.com/chaifeng/ufw-docker), and write rules by **port**, not container IP (container IPs change on updates).

### 10. Install script fails or Docker problems
- **Cause:** Docker from snap, an old Docker version (<24), or a non-fresh server with conflicting services on 80/443.
- **Diagnose:**
  ```bash
  snap list | grep -i docker
  docker version --format '{{.Server.Version}}'
  sudo ss -ltnp | grep -E ':(80|443)\b'
  ls -t /data/coolify/source/installation-*.log | head -1 | xargs sudo tail -50
  ```
- **Fix:** `sudo snap remove docker`, stop or remove whatever owns 80/443 (e.g. a preinstalled nginx/apache), re-run the installer. Ideally start from a fresh image.

### 11. Server freezes during builds / Coolify becomes unresponsive
- **Cause:** Out of memory. Builds run on the same box.
- **Diagnose:** `free -h`, `docker stats --no-stream`, `sudo dmesg | grep -i -E 'killed process|oom'`
- **Fix:** Add swap (`SWAP_SIZE=2G bash prepare-server.sh <user>` is idempotent), move to 4 GB+, or later in the series use a separate build server.

### 12. Coolify inaccessible after an update
- **Diagnose:**
  ```bash
  ls -t /data/coolify/source/upgrade-*.log | head -1 | xargs sudo tail -80
  docker ps -a --format 'table {{.Names}}\t{{.Status}}'
  ```
- **Fix:** Wait 2 minutes and refresh (Gateway Timeout during restart is normal). Check the custom Compose file is valid (`docker compose … config`). Re-run `upgrade.sh` with the **specific** version. Use the SSH forward (`ssh coolify-admin`) to reach `localhost:8000` if the tunnel is down.

### 13. Tunnel stops working after a reboot
- **Cause:** The Cloudflared service wasn't deployed successfully, or Docker isn't enabled at boot.
- **Diagnose:** `systemctl is-enabled docker`, `docker ps -a --filter name=cloudflare-tunnel`
- **Fix:** `sudo systemctl enable --now docker`. Redeploy the Cloudflared resource in Coolify (it uses `restart: unless-stopped`).

---

## Emergency access cheat sheet

```bash
# From your computer: reach the dashboard without the tunnel
ssh -N -L 8000:localhost:8000 -L 6001:localhost:6001 -L 6002:localhost:6002 <username>@SERVER_IP
# then open http://localhost:8000
```
Works even after the localhost-binding override, because the ports are still bound on `127.0.0.1`.
