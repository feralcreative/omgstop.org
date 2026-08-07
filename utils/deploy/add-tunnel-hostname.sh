#!/usr/bin/env bash
# omgstop.org—Publish the site on the Cloudflare Tunnel via the API.
#
# Does what the Zero Trust dashboard's "Add a public hostname" button does:
#   1. adds an ingress rule to the tunnel config
#   2. creates the proxied CNAME to <tunnel-id>.cfargotunnel.com
#
# THE DANGEROUS PART: the tunnel config API is PUT-only. It replaces the entire
# ingress list. This NAS routes a lot of live hostnames through that one tunnel,
# so a naive PUT would take every one of them offline. This script always GETs
# the current config, merges into it, and refuses to continue if the merge would
# drop or reorder an existing rule.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/deploy-utils.sh"

DOMAIN="omgstop.org"
ORIGIN="http://localhost:80"
DRY_RUN=""
for arg in "$@"; do
  case "$arg" in
    --dry-run|-n) DRY_RUN=1 ;;
    --domain=*)   DOMAIN="${arg#*=}" ;;
    --origin=*)   ORIGIN="${arg#*=}" ;;
    --help|-h)
      cat <<EOF
Usage: $(basename "$0") [--dry-run] [--domain=example.com] [--origin=http://localhost:80]

Adds DOMAIN as a public hostname on the Cloudflare Tunnel that fronts the NAS,
then creates the proxied CNAME. Idempotent: re-running with the same values
reports "already published" and changes nothing.

  --dry-run, -n   Show the exact ingress list that would be written. No writes.
  --domain=       Hostname to publish (default: omgstop.org).
  --origin=       Local service the tunnel forwards to (default: http://localhost:80).

Needs CLOUDFLARE_TUNNEL_API_TOKEN in .env. See .env.example for the four
permissions it must carry.
EOF
      exit 0 ;;
    *) err "Unknown flag: $arg"; exit 1 ;;
  esac
done

require_cmd curl "curl is required."
require_cmd jq   "Install with 'brew install jq'."
require_cmd ssh  "OpenSSH client is required."

[ -f "$PROJECT_ROOT/.env" ] || { err "No .env — copy .env.example and add your token."; exit 1; }
set -a; source "$PROJECT_ROOT/.env"; set +a

TOKEN="${CLOUDFLARE_TUNNEL_API_TOKEN:-${CLOUDFLARE_API_TOKEN:-}}"
[ -n "$TOKEN" ] || { err "CLOUDFLARE_TUNNEL_API_TOKEN is empty in .env"; exit 1; }

API="https://api.cloudflare.com/client/v4"
cf() { curl -sS -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" "$@"; }

# Fail loudly on API errors instead of feeding `null` into the next step.
cf_check() {
  local resp="$1" what="$2"
  if ! echo "$resp" | jq -e '.success == true' >/dev/null 2>&1; then
    err "$what failed:"
    echo "$resp" | jq -r '.errors[]? | "  [\(.code)] \(.message)"' 2>/dev/null || echo "  $resp"
    exit 1
  fi
}

# Single source of truth for which tunnel: the credential the NAS is actually
# running with. Reading it from the NAS means this can't target the wrong tunnel.
#
# This has to happen BEFORE the token check, because the only verify endpoint
# that works for an account-owned token is account-scoped.
info "Reading tunnel identity from the NAS..."
SFTP_JSON="$PROJECT_ROOT/.vscode/sftp.json"
NAS_HOST=$(jq -r '.host' "$SFTP_JSON"); NAS_USER=$(jq -r '.username' "$SFTP_JSON"); NAS_PORT=$(jq -r '.port // 22' "$SFTP_JSON")
IDS=$(ssh -p "$NAS_PORT" "${NAS_USER}@${NAS_HOST}" \
  "grep -o '^token: \"[^\"]*\"' /volume1/@appdata/cloudflared/config.yml | sed 's/token: //; s/\"//g'" 2>/dev/null | \
  python3 -c "
import sys, base64, json
t = sys.stdin.read().strip()
d = json.loads(base64.b64decode(t + '=' * (-len(t) % 4)))
print(d['a']); print(d['t'])
")
ACCOUNT_ID=$(echo "$IDS" | sed -n 1p)
TUNNEL_ID=$(echo "$IDS" | sed -n 2p)
[ -n "$ACCOUNT_ID" ] && [ -n "$TUNNEL_ID" ] || { err "Could not read tunnel identity from the NAS."; exit 1; }
ok "Tunnel ${TUNNEL_ID}"

# Cloudflare has two kinds of API token, and they verify at different endpoints.
# An ACCOUNT-owned token (Manage Account → API Tokens) returns a flat
# "[1000] Invalid API Token" from /user/tokens/verify even when it is perfectly
# valid and carries every permission needed — that endpoint only understands
# USER-owned tokens (My Profile → API Tokens). An earlier version of this script
# checked only /user/tokens/verify and rejected a working token on that basis.
# Try the account endpoint first, fall back to the user one.
info "Verifying token..."
RESP=$(cf "$API/accounts/$ACCOUNT_ID/tokens/verify")
if echo "$RESP" | jq -e '.success == true' >/dev/null 2>&1; then
  ok "Token is valid (account-owned)"
else
  RESP=$(cf "$API/user/tokens/verify")
  cf_check "$RESP" "Token verification (tried account-scoped, then user-scoped)"
  ok "Token is valid (user-owned)"
fi

echo ""
echo -e "${CYAN}═══ publish ${DOMAIN} ═══${NC}"
echo -e "  Origin : ${BOLD}${ORIGIN}${NC}"
[ -n "$DRY_RUN" ] && warn "DRY RUN—nothing will be written"

# ---------------------------------------------------------------- ingress ----
info "Fetching current tunnel ingress..."
CONFIG=$(cf "$API/accounts/$ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations")
cf_check "$CONFIG" "Reading tunnel configuration"

INGRESS=$(echo "$CONFIG" | jq '.result.config.ingress // []')
BEFORE_COUNT=$(echo "$INGRESS" | jq 'length')
ok "${BEFORE_COUNT} existing rule(s)"
echo "$INGRESS" | jq -r '.[] | "    \(.hostname // "(catch-all)") -> \(.service)"'

if echo "$INGRESS" | jq -e --arg h "$DOMAIN" 'any(.[]; .hostname == $h)' >/dev/null; then
  echo ""
  ok "${DOMAIN} is already in the tunnel ingress—nothing to add."
  SKIP_INGRESS=1
else
  SKIP_INGRESS=""
  # The final rule is the catch-all (no .hostname) and MUST stay last; Cloudflare
  # matches top-down and anything after it is dead. Insert immediately before it.
  NEW_INGRESS=$(echo "$INGRESS" | jq --arg h "$DOMAIN" --arg s "$ORIGIN" '
    (map(select(.hostname != null))) as $named
    | (map(select(.hostname == null))) as $catchall
    | $named + [{hostname: $h, service: $s}] + $catchall
  ')

  # Refuse to write if anything that was there before is not still there.
  DROPPED=$(jq -n --argjson a "$INGRESS" --argjson b "$NEW_INGRESS" '
    [$a[] | select(.hostname != null) | .hostname]
    - [$b[] | select(.hostname != null) | .hostname]
  ')
  if [ "$(echo "$DROPPED" | jq 'length')" != "0" ]; then
    err "Merge would drop existing hostname(s): $(echo "$DROPPED" | jq -c .)"
    err "Refusing to write. This would have taken those sites offline."
    exit 1
  fi

  echo ""
  info "Ingress after merge ($(echo "$NEW_INGRESS" | jq 'length') rules):"
  echo "$NEW_INGRESS" | jq -r '.[] | "    \(.hostname // "(catch-all)") -> \(.service)"'
fi

# -------------------------------------------------------------------- dns ----
info "Looking up the ${DOMAIN} zone..."
ZONE=$(cf "$API/zones?name=$DOMAIN")
cf_check "$ZONE" "Zone lookup"
ZONE_ID=$(echo "$ZONE" | jq -r '.result[0].id // empty')
[ -n "$ZONE_ID" ] || { err "No zone found for ${DOMAIN}. Is it in this Cloudflare account?"; exit 1; }
ok "Zone ${ZONE_ID}"

CNAME_TARGET="${TUNNEL_ID}.cfargotunnel.com"
EXISTING_DNS=$(cf "$API/zones/$ZONE_ID/dns_records?name=$DOMAIN")
cf_check "$EXISTING_DNS" "DNS lookup"
DNS_ID=$(echo "$EXISTING_DNS" | jq -r '.result[0].id // empty')
DNS_CONTENT=$(echo "$EXISTING_DNS" | jq -r '.result[0].content // empty')

if [ -n "$DRY_RUN" ]; then
  echo ""
  [ -n "$SKIP_INGRESS" ] || info "Would PUT the merged ingress above"
  if [ -z "$DNS_ID" ]; then
    info "Would CREATE proxied CNAME ${DOMAIN} -> ${CNAME_TARGET}"
  elif [ "$DNS_CONTENT" != "$CNAME_TARGET" ]; then
    info "Would UPDATE ${DOMAIN}: ${DNS_CONTENT} -> ${CNAME_TARGET}"
  else
    info "CNAME already correct"
  fi
  warn "Dry-run complete. Re-run without --dry-run to apply."
  exit 0
fi

if [ -z "$SKIP_INGRESS" ]; then
  info "Writing tunnel ingress..."
  BODY=$(jq -n --argjson ing "$NEW_INGRESS" '{config: {ingress: $ing}}')
  RESP=$(cf -X PUT "$API/accounts/$ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations" --data "$BODY")
  cf_check "$RESP" "Writing tunnel configuration"
  ok "Ingress updated ($BEFORE_COUNT -> $(echo "$NEW_INGRESS" | jq 'length') rules)"
fi

if [ -z "$DNS_ID" ]; then
  info "Creating proxied CNAME..."
  RESP=$(cf -X POST "$API/zones/$ZONE_ID/dns_records" --data "$(jq -n \
    --arg n "$DOMAIN" --arg c "$CNAME_TARGET" \
    '{type:"CNAME", name:$n, content:$c, proxied:true, ttl:1, comment:"omgstop.org via Cloudflare Tunnel"}')")
  cf_check "$RESP" "Creating DNS record"
  ok "CNAME created -> ${CNAME_TARGET}"
elif [ "$DNS_CONTENT" != "$CNAME_TARGET" ]; then
  info "Updating existing CNAME..."
  RESP=$(cf -X PATCH "$API/zones/$ZONE_ID/dns_records/$DNS_ID" --data "$(jq -n \
    --arg c "$CNAME_TARGET" '{content:$c, proxied:true}')")
  cf_check "$RESP" "Updating DNS record"
  ok "CNAME updated -> ${CNAME_TARGET}"
else
  ok "CNAME already correct"
fi

echo ""
info "Verifying (DNS and edge propagation can take a minute)..."
for i in 1 2 3 4 5 6; do
  CODE=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 15 "https://${DOMAIN}/less" 2>/dev/null || echo "000")
  if [ "$CODE" = "200" ]; then
    ok "https://${DOMAIN}/less -> 200"
    echo ""
    ok "Live."
    exit 0
  fi
  warn "attempt ${i}/6: got ${CODE}, retrying..."
  sleep 10
done

err "Still not answering 200 after 60s. Config is written; this may just be propagation."
echo "  Re-check with: curl -sI https://${DOMAIN}/less | head -1"
exit 1
