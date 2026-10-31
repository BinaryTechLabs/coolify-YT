# Command Sheet

> In the order used in the video. **Values in `UPPER_CASE` or marked ✏️ are yours to change.**
> 🖥️ = run on your computer · ☁️ = run on the server · 🔐 = needs root/sudo · ⚠️ = destructive or disruptive

Replace throughout:

| Placeholder | Meaning |
|---|---|
| `SERVER_IP` ✏️ | Your VPS public IPv4 address |
| `<username>` ✏️ | The admin username you create |
| `example.com` ✏️ | Your Cloudflare-managed domain |
| `4.4.6` ✏️ | The Coolify version you're upgrading to (see release notes) |

---

## 1. Create an SSH key 🖥️

```bash
ssh-keygen -t ed25519 -C "<username>@<device>"   # ✏️ comment is just a label
cat ~/.ssh/id_ed25519.pub
```
Creates a modern ed25519 key pair. Add a passphrase when asked. The `.pub` file is what you give your VPS provider; the other file never leaves your computer. Skip this if you already have a key.

## 2. Find your public IP (for the firewall rule) 🖥️

```bash
curl -4 ifconfig.me
```
Prints your public IPv4. In the provider firewall, allow **TCP 22 from `THAT_IP/32`** only.

## 3. First login as root 🖥️

```bash
ssh root@SERVER_IP
```

## 4. Download, read, run the prep script ☁️ 🔐 ⚠️

```bash
curl -fsSL -o prepare-server.sh https://raw.githubusercontent.com/BinaryTechLabs/coolify-YT/refs/heads/main/scripts/prepare-server.sh
less prepare-server.sh
bash prepare-server.sh <username>            # ✏️ username
# On a 2 GB RAM server:
# SWAP_SIZE=2G bash prepare-server.sh lenard
```
- Runs `apt full-upgrade`, enables unattended security upgrades.
- Creates the user, adds to `sudo`, copies root's `authorized_keys`.
- ⚠️ **Disables SSH password logins** and sets root to key-only. It refuses to run if root has no SSH key, so you can't lock yourself out that way.
- Optional swap file.

<details><summary>Doing it by hand instead of the script</summary>

```bash
apt update && apt -y full-upgrade
apt -y install unattended-upgrades
adduser <username>                                  # ✏️
usermod -aG sudo <username>                         # ✏️
rsync --archive --chown=<username>:<username> ~/.ssh /home/<username>   # ✏️ copies root's keys
nano /etc/ssh/sshd_config.d/00-btl-hardening.conf   # paste companion/config/sshd/00-btl-hardening.conf
sshd -t                                         # no output = valid
systemctl restart ssh
sshd -T | grep -Ei '^(passwordauthentication|permitrootlogin) '
```
</details>

## 5. Test the new user — in a SECOND terminal 🖥️

```bash
ssh <username>@SERVER_IP
sudo whoami      # expect: root
```
Don't close the root session until this works.

## 6. Reboot after kernel updates ☁️ 🔐 ⚠️

```bash
sudo reboot
```

## 7. Install Coolify ☁️ 🔐

```bash
curl -fsSL https://cdn.coollabs.io/coolify/install.sh -o coolify-install.sh
less coolify-install.sh
sudo bash coolify-install.sh
```
Installs Docker (if missing), creates `/data/coolify`, generates Coolify's localhost SSH key (added to `/root/.ssh/authorized_keys`), pulls and starts Coolify. Official one-liner equivalent: `curl -fsSL https://cdn.coollabs.io/coolify/install.sh | sudo bash`.

*Optional: pre-create the admin so the registration page never exists at all:*
```bash
sudo env ROOT_USERNAME=<username> ROOT_USER_EMAIL=you@example.com ROOT_USER_PASSWORD='S0me-Str0ng!Pass' bash coolify-install.sh   # ✏️ all three
```
(The password needs 8+ characters with upper and lower case, a number and a symbol. It will end up in your shell history. Clear it afterwards, or use the SSH-forward method instead.)

## 8. First login via SSH port-forward 🖥️

```bash
ssh -N -L 8000:localhost:8000 -L 6001:localhost:6001 -L 6002:localhost:6002 <username>@SERVER_IP
```
Then browse to **http://localhost:8000**. `-L local:host:remote` forwards a port on your machine through SSH to the server. `-N` means don't open a shell. Leave it running; `Ctrl+C` to stop.

Shortcut: copy `config/ssh/config.example` into `~/.ssh/config` and use `ssh coolify-admin`.

## 9. Coolify dashboard steps (no commands)

1. Register the admin account → onboarding → **localhost / This machine**.
2. **Servers → localhost**: validated, **Proxy: Running** (else **Start Proxy**).
3. **Settings → Advanced → Registration: disabled**.
4. **Profile → Two-factor authentication: enable**.

## 10. Cloudflare steps (no commands)

1. **Networking → Tunnels → Create tunnel** → name it → choose **Docker** → copy only the `eyJ…` token.
2. Coolify: **Project → + New → Cloudflared** → env var **`CLOUDFLARE_TUNNEL_TOKEN`** = token → **Deploy**.
3. Cloudflare: connector shows **Healthy** → Continue.
4. Tunnel → **Routes → Add route → Published application**: subdomain `coolify`, domain `example.com` ✏️, path empty, service **`http://localhost:80`**.
5. Coolify: **Settings → General → URL** = `https://coolify.example.com` ✏️; **Redirect HTTP to HTTPS = Disabled**; Save.
6. Cloudflare: **SSL/TLS → Edge Certificates → Always Use HTTPS = On**.

## 11. Verify from outside 🖥️

```bash
curl -I https://coolify.example.com          # ✏️ expect 200/302 from Cloudflare
curl -m 5 http://SERVER_IP:8000              # expect timeout
curl -m 5 http://SERVER_IP                   # expect timeout
```
Also open `https://coolify.example.com/realtime` (test event) and **Servers → localhost → Terminal**.

## 12. Reboot test + health check ☁️ 🔐

```bash
sudo reboot
# after it's back:
curl -fsSL -o check-coolify.sh https://raw.githubusercontent.com/BinaryTechLabs/coolify-YT/refs/heads/main/scripts/check-coolify.sh
sudo bash check-coolify.sh
```
Read-only. Checks the containers, version, `/api/health`, listening ports, tunnel registrations, effective SSH settings and disk usage.

## 13. Bind 8000/6001/6002 to localhost ☁️ 🔐 ⚠️

**Only after** the dashboard works through the tunnel.

```bash
sudo curl -fsSL -o /data/coolify/source/docker-compose.custom.yml \
  https://raw.githubusercontent.com/BinaryTechLabs/coolify-YT/refs/heads/main/config/coolify/docker-compose.custom.yml
cd /data/coolify/source
sudo docker compose --env-file .env -f docker-compose.yml -f docker-compose.prod.yml -f docker-compose.custom.yml config > /dev/null && echo "Config OK"
curl -fsSL https://cdn.coollabs.io/coolify/install.sh | sudo bash
sudo ss -ltnp | grep -E ':(8000|6001|6002)\b'
```
- The `config` step validates the merged Compose files without starting anything.
- ⚠️ Re-running `install.sh` is what the Coolify firewall docs use here. It's fine on a fresh server, but **it resets ownership and permissions under `/data/coolify`**. On a server that's already running apps, use `upgrade.sh <current-version>` instead (it also picks up `docker-compose.custom.yml`).
- Expect `127.0.0.1:8000`, `127.0.0.1:6001`, `127.0.0.1:6002`.

**Undo:** `sudo rm /data/coolify/source/docker-compose.custom.yml`, then re-apply as above.

## 14. Save the APP_KEY ☁️ 🔐

```bash
sudo grep '^APP_KEY=' /data/coolify/source/.env
```
Copy the whole line into your password manager. Without it, restored backups can't decrypt stored secrets.

## 15. Manual instance backup ☁️ 🔐

```bash
curl -fsSL -o backup-coolify.sh https://raw.githubusercontent.com/BinaryTechLabs/coolify-YT/refs/heads/main/scripts/backup-coolify.sh
sudo bash backup-coolify.sh            # KEEP=14 to keep more
```
Dumps `coolify-db` with `pg_dump` and copies `.env` into `/data/backups/coolify-instance/<timestamp>/` (mode 600). **Copy it off the server afterwards.**

## 16. Update Coolify from the terminal ☁️ 🔐 ⚠️

```bash
curl -fsSL https://cdn.coollabs.io/coolify/upgrade.sh | sudo bash -s 4.4.6    # ✏️ target version, no leading "v"
```
Always pass a version. Without one, `COOLIFY_VERSION=latest` is written and update checks break. Back up first and read the release notes. Logs: `/data/coolify/source/upgrade-*.log`.

## 17. Useful diagnostics ☁️ 🔐

```bash
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
docker logs --tail 100 coolify
docker logs --tail 100 coolify-proxy
docker logs --tail 100 cloudflare-tunnel
docker inspect -f '{{.Config.Image}}' coolify      # current version
ls /data/coolify/source/                            # .env, compose files, install/upgrade logs
```
