#!/usr/bin/env bash
# omgstop.org—Install the per-vhost Nginx config into Web Station.
#
# Run this from your Mac AFTER creating the virtual host in DSM. It finds the
# vhost's generated service UUID on the NAS, drops nginx-user.conf into the
# `user.conf` hook Web Station already includes, validates, and reloads.
#
# Needs sudo on the NAS, so it opens an interactive SSH session and you type
# your DSM password once.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/deploy-utils.sh"

DOMAIN="omgstop.org"
DRY_RUN=""
for arg in "$@"; do
  case "$arg" in
    --dry-run|-n) DRY_RUN=1 ;;
    --domain=*)   DOMAIN="${arg#*=}" ;;
    --help|-h)
      cat <<EOF
Usage: $(basename "$0") [--dry-run] [--domain=example.com]

Installs utils/deploy/nginx-user.conf as the Web Station per-vhost user.conf
for DOMAIN, then validates and reloads Nginx on the NAS.

  --dry-run, -n      Locate the vhost and show what would happen. Changes
                     nothing and needs no sudo.
  --domain=DOMAIN    Target a different site (default: omgstop.org).

Prerequisite: the virtual host must already exist in DSM (Web Station →
Web Service + Web Portal), with document root /volume1/web/DOMAIN and
Nginx as the backend. This script cannot create it—DSM generates those
configs from its own database.
EOF
      exit 0 ;;
    *) err "Unknown flag: $arg"; exit 1 ;;
  esac
done

require_cmd ssh "OpenSSH client is required."
require_cmd jq  "Install with 'brew install jq'."

CONF="$SCRIPT_DIR/nginx-user.conf"
[ -f "$CONF" ] || { err "Missing $CONF"; exit 1; }

SFTP_JSON="$PROJECT_ROOT/.vscode/sftp.json"
[ -f "$SFTP_JSON" ] || { err "Missing $SFTP_JSON—can't resolve the NAS."; exit 1; }
HOST=$(jq -r '.host' "$SFTP_JSON")
SSH_USER=$(jq -r '.username' "$SFTP_JSON")
SSH_PORT=$(jq -r '.port // 22' "$SFTP_JSON")
DOCROOT="/volume1/web/${DOMAIN}"

echo ""
echo -e "${CYAN}═══ ${DOMAIN} · Nginx vhost config ═══${NC}"
echo -e "  NAS     : ${BOLD}${SSH_USER}@${HOST}:${SSH_PORT}${NC}"
echo -e "  Docroot : ${BOLD}${DOCROOT}${NC}"
[ -n "$DRY_RUN" ] && warn "DRY RUN—nothing will be changed"

# Locate the vhost by its document root. Web Station names each generated
# service config .service.<portal-uuid>.<service-uuid>.conf, and the user.conf
# hook lives in a directory named after the SERVICE uuid (the second one).
info "Locating the virtual host on the NAS..."
UUID=$(ssh -p "$SSH_PORT" "${SSH_USER}@${HOST}" "
  grep -ls 'root[[:space:]]*\"${DOCROOT}\"' /usr/local/etc/nginx/conf.d/.service.*.conf 2>/dev/null |
  head -1 |
  sed 's|.*/\.service\.[0-9a-f-]*\.||; s|\.conf\$||'
" 2>/dev/null | tr -d '\r')

if [ -z "$UUID" ]; then
  err "No Web Station virtual host found with document root ${DOCROOT}."
  echo ""
  echo "  Create it first in DSM:"
  echo "    Web Station → Web Service → Create → Static website"
  echo "      Document root : ${DOCROOT}"
  echo "      HTTP backend  : Nginx"
  echo "    Web Station → Web Portal → Create → Name-based"
  echo "      Hostname      : ${DOMAIN}"
  echo ""
  echo "  Then re-run this script."
  exit 1
fi

ok "Found virtual host (service UUID: ${UUID})"
DEST_DIR="/usr/local/etc/nginx/conf.d/${UUID}"

if [ -n "$DRY_RUN" ]; then
  echo ""
  info "Would install $(basename "$CONF") → ${DEST_DIR}/user.conf"
  info "Would run: nginx -t, then reload Web Station"
  warn "Dry-run complete. Re-run without --dry-run to apply."
  exit 0
fi

# Ship the file to a staging path ziad can write, then move it into place with
# sudo. Two steps because the conf.d tree is root-owned and Synology's SFTP
# subsystem is restricted, so scp into /usr/local is not an option.
info "Uploading config..."
ssh -p "$SSH_PORT" "${SSH_USER}@${HOST}" "cat > /tmp/omgstop-user.conf" < "$CONF"
ok "Uploaded to /tmp/omgstop-user.conf"

echo ""
# If the root-owned wrapper is installed and sudoers grants it NOPASSWD, the
# whole thing runs unattended. `sudo -n` fails immediately rather than
# prompting, so this probe is safe to run either way.
if ssh -p "$SSH_PORT" "${SSH_USER}@${HOST}" \
     "sudo -n /usr/local/bin/omgstop-nginx-reload >/dev/null 2>&1 <<< ''" 2>/dev/null; then
  ok "Reloaded via the passwordless wrapper (no prompt needed)"
  PASSWORDLESS=1
else
  PASSWORDLESS=""
  warn "No passwordless wrapper—falling back to an interactive sudo."
  warn "To set it up once, see docs/DEPLOYMENT.md → Reloading without a password."
  echo ""
fi

if [ -z "$PASSWORDLESS" ]; then

# -t for a TTY so sudo can prompt.
#
# `set -e` and NO error suppression anywhere in here. An earlier version ran the
# reload as `... 2>/dev/null || true` and then echoed 'reloaded' unconditionally,
# so when the reload command turned out not to exist on this DSM the script
# reported success while nginx carried on serving the old config. The file was
# on disk, the site was not using it, and nothing said so.
#
# Reload is `synow3tool --deploy-hup`—the DSM-sanctioned regenerate-and-HUP.
# synosystemctl/synoservice are not the right tools here. Validate against
# nginx.conf.run (what actually gets loaded) BEFORE the HUP: a bad config that
# reaches a reload takes every other site on this NAS down with it.
ssh -t -p "$SSH_PORT" "${SSH_USER}@${HOST}" "
  set -e
  sudo mkdir -p '${DEST_DIR}'
  sudo cp /tmp/omgstop-user.conf '${DEST_DIR}/user.conf'
  sudo chown root:root '${DEST_DIR}/user.conf'
  sudo chmod 644 '${DEST_DIR}/user.conf'
  rm -f /tmp/omgstop-user.conf
  echo ''
  echo '--- regenerating nginx config ---'
  sudo /usr/syno/bin/synow3tool --gen-all
  echo '--- validating ---'
  sudo /usr/bin/nginx -t -c /etc/nginx/nginx.conf.run
  echo '--- reloading (hup) ---'
  sudo /usr/syno/bin/synow3tool --deploy-hup
  echo 'reload command completed'
"
fi

# Trust nothing. Prove the running server actually picked it up, because the
# failure mode above was a script that said 'reloaded' and meant nothing.
echo ""
info "Verifying against the running server..."
VERIFY=$(ssh -p "$SSH_PORT" "${SSH_USER}@${HOST}" "
  printf 'less_status=%s\n' \"\$(curl -s -o /dev/null -w '%{http_code}' -H 'Host: ${DOMAIN}' http://127.0.0.1/less)\"
  printf 'headers=%s\n'     \"\$(curl -sI -H 'Host: ${DOMAIN}' http://127.0.0.1/ | grep -ci 'x-content-type-options')\"
  printf 'custom404=%s\n'   \"\$(curl -s -H 'Host: ${DOMAIN}' http://127.0.0.1/nope | grep -c 'notfound__title')\"
" 2>/dev/null)

LESS_STATUS=$(echo "$VERIFY" | sed -n 's/^less_status=//p')
HEADERS=$(echo "$VERIFY"     | sed -n 's/^headers=//p')
CUSTOM404=$(echo "$VERIFY"   | sed -n 's/^custom404=//p')

FAILED=""
[ "$LESS_STATUS" = "200" ] && ok "/less serves 200 (no redirect hop)" || { err "/less returned ${LESS_STATUS:-?}, expected 200"; FAILED=1; }
[ "${HEADERS:-0}" -ge 1 ]  && ok "security headers present"           || { err "security headers missing"; FAILED=1; }
[ "${CUSTOM404:-0}" -ge 1 ] && ok "custom 404 page served"            || { err "custom 404 not served"; FAILED=1; }

echo ""
if [ -n "$FAILED" ]; then
  err "Config is on disk at ${DEST_DIR}/user.conf but the running server is not using it."
  echo "  Check whether the reload actually happened:"
  echo "    ssh -p ${SSH_PORT} ${SSH_USER}@${HOST} 'ps -eo pid,lstart,cmd | grep \"nginx: worker\"'"
  echo "  Worker start times must be NEWER than the user.conf mtime."
  exit 1
fi

ok "Installed and live → ${DEST_DIR}/user.conf"
