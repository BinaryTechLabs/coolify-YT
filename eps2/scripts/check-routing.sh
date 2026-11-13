#!/usr/bin/env bash
#
# check-routing.sh - Binary Tech Labs
#
# Run this on YOUR COMPUTER (not the server). It checks that hostnames on your
# domain really go Browser -> Cloudflare -> Tunnel -> Coolify proxy -> app, and
# catches the usual mistakes from this episode:
#
#   - redirect loops (Coolify's "Redirect HTTP to HTTPS" left on behind the tunnel)
#   - hostnames NOT going through Cloudflare (an old A record overriding the wildcard)
#   - http:// not being upgraded to https:// (Cloudflare "Always Use HTTPS" off)
#   - the wildcard route missing (a random subdomain should reach Coolify's proxy
#     and get a 404, not a DNS error)
#   - optional: shows that two-level subdomains (a.b.example.com) fail TLS on
#     Cloudflare's free Universal SSL certificate
#
# It only sends normal HTTPS requests. It changes nothing.
#
# Requires: curl. Optional: openssl (certificate details).
#
# Usage:
#   bash check-routing.sh example.com coolify status whoami
#   bash check-routing.sh example.com status --deep
#
# Arguments: your domain, then the subdomains to test (default: coolify).
#            --deep also tests a two-level subdomain to demonstrate the TLS limit.

set -uo pipefail

DOMAIN=""
SUBS=()
DEEP=0
for arg in "$@"; do
    case "$arg" in
        --deep) DEEP=1 ;;
        -h|--help) sed -n '/^# Usage:/,/^# Arguments/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) if [[ -z "$DOMAIN" ]]; then DOMAIN="$arg"; else SUBS+=("$arg"); fi ;;
    esac
done

[[ -n "$DOMAIN" ]] || { echo "Usage: bash check-routing.sh example.com [sub ...] [--deep]"; exit 1; }
[[ ${#SUBS[@]} -gt 0 ]] || SUBS=(coolify)
command -v curl >/dev/null || { echo "curl is required"; exit 1; }

PASS=0 FAIL=0
ok()   { printf '  \033[1;32mOK\033[0m    %s\n' "$*"; PASS=$((PASS + 1)); }
bad()  { printf '  \033[1;31mFAIL\033[0m  %s\n' "$*"; FAIL=$((FAIL + 1)); }
note() { printf '  \033[1;33mNOTE\033[0m  %s\n' "$*"; }

check_host() {
    local host="$1" headers code redirects rc loc

    printf '\n\033[1m%s\033[0m\n' "$host"

    # 1. HTTPS: follow redirects, but detect loops.
    headers=$(curl -sS -o /dev/null -D - --max-redirs 8 -L -m 15 \
        -w 'BTL_RESULT %{http_code} %{num_redirects}\n' "https://$host/" 2>&1)
    rc=$?
    if [[ $rc -eq 47 ]]; then
        bad "redirect loop (too many redirects). Set 'Redirect HTTP to HTTPS' = Disabled on this resource in Coolify"
        return
    elif [[ $rc -eq 6 ]]; then
        bad "DNS: hostname doesn't resolve. Is the wildcard route (or a DNS record) in place?"
        return
    elif [[ $rc -eq 60 || $rc -eq 35 ]]; then
        bad "TLS error (curl $rc). Two-level subdomains aren't covered by Cloudflare's free certificate"
        return
    elif [[ $rc -ne 0 ]]; then
        bad "request failed (curl exit $rc): $(tail -1 <<<"$headers")"
        return
    fi

    read -r _ code redirects < <(grep '^BTL_RESULT' <<<"$headers")

    if grep -qi '^server: cloudflare' <<<"$headers" && grep -qi '^cf-ray:' <<<"$headers"; then
        ok "served by Cloudflare (cf-ray present)"
    else
        bad "NOT served through Cloudflare. An exact DNS record may be overriding the wildcard (check DNS > Records)"
    fi

    case "$code" in
        2??|401|403) ok "HTTPS status $code after $redirects redirect(s)" ;;
        404)         note "HTTPS status 404: reached a server, but no app answers this hostname (expected for unknown names)" ;;
        502|503|504) bad "HTTPS status $code: the proxy/tunnel can't reach the app (wrong port? container unhealthy?)" ;;
        52?)         bad "Cloudflare error $code: the tunnel can't reach the origin (cloudflared down, or wrong service URL)" ;;
        *)           note "HTTPS status $code after $redirects redirect(s)" ;;
    esac

    # 2. Plain HTTP should be upgraded to HTTPS by Cloudflare (Always Use HTTPS).
    loc=$(curl -sS -o /dev/null -m 10 -w '%{http_code} %{redirect_url}' "http://$host/" 2>/dev/null)
    if [[ "$loc" =~ ^30[1278]\ https:// ]]; then
        ok "http:// redirects to https:// (${loc%% *})"
    else
        note "http:// returned '$loc'. Turn on SSL/TLS > Edge Certificates > Always Use HTTPS"
    fi

    # 3. Certificate details (what the visitor actually sees).
    if command -v openssl >/dev/null; then
        local cert
        cert=$(openssl s_client -connect "$host:443" -servername "$host" </dev/null 2>/dev/null \
            | openssl x509 -noout -issuer -enddate 2>/dev/null | tr '\n' ' ')
        [[ -n "$cert" ]] && note "certificate: $cert"
    fi
}

printf 'Checking routing for %s\n' "$DOMAIN"

for sub in "${SUBS[@]}"; do
    check_host "$sub.$DOMAIN"
done

# Wildcard sanity check: a name that no app uses should still reach the
# Coolify proxy through the tunnel and come back as a 404.
rand="btl-check-$RANDOM$RANDOM"
printf '\n\033[1m%s.%s\033[0m  (random name, tests the wildcard)\n' "$rand" "$DOMAIN"
rcode=$(curl -sS -o /dev/null -m 15 -w '%{http_code}' "https://$rand.$DOMAIN/" 2>/dev/null)
rc=$?
if [[ $rc -eq 6 ]]; then
    bad "doesn't resolve: there's no wildcard DNS record (*). Add the '*' route to the tunnel"
elif [[ "$rcode" == 404 ]]; then
    ok "unknown hostname reaches the proxy and gets 404, so the wildcard works and nothing is exposed by accident"
else
    note "unknown hostname returned '$rcode' (curl exit $rc). Expected 404 from Coolify's proxy"
fi

if [[ $DEEP -eq 1 ]]; then
    printf '\n\033[1mdeep.%s.%s\033[0m  (two-level subdomain)\n' "$rand" "$DOMAIN"
    if curl -sS -o /dev/null -m 15 "https://deep.$rand.$DOMAIN/" 2>/dev/null; then
        note "two-level subdomain worked (you must have Advanced Certificate Manager / Total TLS)"
    else
        note "two-level subdomain failed, as expected on the free plan. Stick to app.$DOMAIN style names"
    fi
fi

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
