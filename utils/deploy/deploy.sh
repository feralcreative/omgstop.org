#!/usr/bin/env bash
# omgstop.org—Build with Eleventy, then rsync _site/ over SSH to the Synology
# NAS (Web Station), then purge Cloudflare.
# Don't run directly—use prod.sh, which sets DEPLOY_ENV.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/deploy-utils.sh"

# Parse flags
DRY_RUN=""; FORCE=""; SKIP_BUILD=""
for arg in "$@"; do
  case "$arg" in
    --dry-run|-n)   DRY_RUN=1 ;;
    --force|-f)     FORCE=1 ;;
    --skip-build)   SKIP_BUILD=1 ;;
    --help|-h)
      cat <<EOF
Usage: $(basename "$0") [--dry-run] [--force] [--skip-build]

Builds the site with Eleventy and deploys _site/ to production via rsync over
SSH, then purges the Cloudflare cache (if credentials are present in .env).

  --dry-run, -n   Show what would be transferred without uploading.
  --force,   -f   Bypass prod safety gates (does NOT bypass confirmation).
  --skip-build    Deploy the existing _site/ without rebuilding it.

Called via:
  utils/deploy/prod.sh    # deploys to production
EOF
      exit 0 ;;
    *) err "Unknown flag: $arg"; exit 1 ;;
  esac
done

[ -n "${DEPLOY_ENV:-}" ] || { err "DEPLOY_ENV not set—run prod.sh"; exit 1; }
[ "$DEPLOY_ENV" = "prod" ] || { err "Invalid DEPLOY_ENV: $DEPLOY_ENV (only 'prod' is configured)"; exit 1; }

require_cmd rsync "Install with 'brew install rsync'."
require_cmd ssh   "OpenSSH client is required."
require_cmd jq    "Install with 'brew install jq'."
require_cmd git   "Git is required."
require_cmd npm   "Node/npm is required to build the site."
require_cmd curl  "curl is required for the Cloudflare purge."

cd "$PROJECT_ROOT"
DEPLOY_START=$(date +%s)

# Read target from .vscode/sftp.json (flat single-profile layout)
SFTP_JSON="$PROJECT_ROOT/.vscode/sftp.json"
[ -f "$SFTP_JSON" ] || { err "Missing $SFTP_JSON—can't resolve target."; exit 1; }

HOST=$(jq -r '.host' "$SFTP_JSON")
SSH_USER=$(jq -r '.username' "$SFTP_JSON")
SSH_PORT=$(jq -r '.port // 22' "$SFTP_JSON")
REMOTE_PATH=$(jq -r '.remotePath' "$SFTP_JSON")

[ "$HOST" != "null" ]        || { err "Could not read .host from $SFTP_JSON"; exit 1; }
[ "$SSH_USER" != "null" ]    || { err "Could not read .username from $SFTP_JSON"; exit 1; }
[ "$REMOTE_PATH" != "null" ] || { err "Could not read .remotePath from $SFTP_JSON"; exit 1; }

BUILD_DIR="$PROJECT_ROOT/_site"
TARGET_URL="https://omgstop.org"
ENV_LABEL="PRODUCTION"
ENV_COLOR="$RED"

echo ""
echo -e "${CYAN}═══ omgstop.org · ${ENV_COLOR}${ENV_LABEL}${NC}${CYAN} deploy ═══${NC}"
echo -e "  Target : ${BOLD}${SSH_USER}@${HOST}:${REMOTE_PATH}${NC}"
[ -n "$DRY_RUN" ] && warn "DRY RUN—no files will be uploaded"

# Load .env (Cloudflare creds, optional SSH_KEY_PATH override)
if [ -f "$PROJECT_ROOT/.env" ]; then
  set -a; source "$PROJECT_ROOT/.env"; set +a
fi

# Resolve how to authenticate over SSH:
#   explicit SSH_KEY_PATH → ssh-agent (sftp.json default) → ~/.ssh/id_ed25519 → ~/.ssh/id_rsa
SSH_IDENTITY=""
if [ -n "${SSH_KEY_PATH:-}" ] && [ -f "$SSH_KEY_PATH" ]; then
  SSH_IDENTITY="-i $SSH_KEY_PATH"
elif ssh-add -l >/dev/null 2>&1; then
  SSH_IDENTITY=""   # use the agent
elif [ -f "$HOME/.ssh/id_ed25519" ]; then
  SSH_IDENTITY="-i $HOME/.ssh/id_ed25519"
elif [ -f "$HOME/.ssh/id_rsa" ]; then
  SSH_IDENTITY="-i $HOME/.ssh/id_rsa"
else
  err "No SSH identity found (no ssh-agent keys, no SSH_KEY_PATH, no default keys)."; exit 1
fi
SSH_E="ssh -p ${SSH_PORT} ${SSH_IDENTITY}"

# Production safety gates
GIT_SHA=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
GIT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")

if [ -z "$FORCE" ]; then
  if [ -n "$(git status --porcelain)" ]; then
    err "Working tree is dirty. Commit/stash, or pass --force."; exit 1
  fi
  if [ "$GIT_BRANCH" != "main" ]; then
    err "Not on 'main' (current: $GIT_BRANCH). Switch or pass --force."; exit 1
  fi
fi

if [ -z "$DRY_RUN" ]; then
  echo ""
  echo -e "${RED}${BOLD}⚠  You are about to deploy to PRODUCTION${NC}"
  echo -e "   URL    : ${BOLD}${TARGET_URL}${NC}"
  echo -e "   Commit : ${BOLD}${GIT_SHA}${NC} on ${BOLD}${GIT_BRANCH}${NC}"
  [ -n "$FORCE" ] && echo -e "   Mode   : ${YELLOW}--force (gates bypassed)${NC}"
  read -r -p "Type 'yes' to continue: " CONFIRM
  [ "$CONFIRM" = "yes" ] || { err "Aborted."; exit 1; }
fi

# Build. _site/ is gitignored and rsync runs with --delete, so a stale or
# half-written build directory is the one thing that can wreck the server.
BUILD_TIME=0
if [ -n "$SKIP_BUILD" ]; then
  warn "Skipping build (--skip-build)—deploying whatever is in _site/"
else
  info "Building site with Eleventy..."
  BUILD_START=$(date +%s)
  rm -rf "$BUILD_DIR"
  npm run build >/dev/null
  BUILD_TIME=$(($(date +%s) - BUILD_START))
  ok "Built in $(format_time $BUILD_TIME)"
fi

# Refuse to sync a build that obviously didn't work. --delete against an empty
# directory would take the live site with it.
[ -d "$BUILD_DIR" ] || { err "No build directory at $BUILD_DIR"; exit 1; }
for f in index.html 404.html css/style.css; do
  [ -s "$BUILD_DIR/$f" ] || { err "Expected _site/$f to exist and be non-empty—refusing to deploy."; exit 1; }
done
PAGE_COUNT=$(find "$BUILD_DIR" -name 'index.html' | wc -l | tr -d ' ')
info "Build looks sane: ${PAGE_COUNT} page(s), $(find "$BUILD_DIR" -type f | wc -l | tr -d ' ') file(s) total"

# Build rsync exclude list from ignore.json
IGNORE_JSON="$SCRIPT_DIR/ignore.json"
[ -f "$IGNORE_JSON" ] || { err "Missing $IGNORE_JSON"; exit 1; }
EXCLUDE_FILE=$(mktemp -t rsync-excludes.XXXXXX)
cleanup() { rm -f "$EXCLUDE_FILE"; }
trap cleanup EXIT
jq -r '.patterns[]' "$IGNORE_JSON" > "$EXCLUDE_FILE"

info "Syncing _site/ over SSH..."
UPLOAD_START=$(date +%s)
RSYNC_ARGS=(-avz --delete --delete-after --max-delete=50 --stats --human-readable --exclude-from="$EXCLUDE_FILE" -e "$SSH_E")

# Normalize modes on the receiver where rsync can do it in one pass. macOS now
# ships openrsync (reports "2.6.9 compatible") which has no --chmod, so this is
# feature-detected rather than assumed. The post-sync pass below is the real
# guarantee; this only saves it some work.
if rsync --chmod=D755,F644 --version >/dev/null 2>&1; then
  RSYNC_ARGS+=(--chmod=D755,F644)
else
  warn "$(rsync --version 2>&1 | head -1) has no --chmod—relying on the post-sync pass"
fi

[ -n "$DRY_RUN" ] && RSYNC_ARGS+=(--dry-run)

# Trailing slash on the source is load-bearing: it syncs the CONTENTS of _site/
# into REMOTE_PATH rather than creating REMOTE_PATH/_site/.
set +e
rsync "${RSYNC_ARGS[@]}" "${BUILD_DIR}/" "${SSH_USER}@${HOST}:${REMOTE_PATH}/"
RSYNC_CODE=$?
set -e
if [ "$RSYNC_CODE" -eq 25 ]; then
  err "rsync hit --max-delete=50. That many removals usually means the build is wrong, not that you meant it. Nothing beyond the cap was removed."
  exit 25
fi
[ "$RSYNC_CODE" -eq 0 ] || { err "rsync failed with exit code $RSYNC_CODE"; exit "$RSYNC_CODE"; }

UPLOAD_TIME=$(($(date +%s) - UPLOAD_START))
ok "Files synced in $(format_time $UPLOAD_TIME)"

# Web Station runs as a different user, so a mode-700 directory or mode-600 file
# is a 403 regardless of whether the content is correct. Only touches paths that
# are actually wrong.
normalize_remote_perms() {
  if [ -n "$DRY_RUN" ]; then
    warn "Dry run—skipping remote permission normalization"; return 0
  fi
  info "Normalizing remote permissions..."
  local fixed
  fixed=$($SSH_E "${SSH_USER}@${HOST}" \
    "find '$REMOTE_PATH' -type d ! -perm -o=x -exec chmod 755 {} + -print 2>/dev/null | wc -l;
     find '$REMOTE_PATH' -type f ! -perm -o=r -exec chmod 644 {} + -print 2>/dev/null | wc -l" \
    2>/dev/null | tr -d ' ' | paste -sd, -)
  if [ -n "$fixed" ]; then
    ok "Permissions normalized (dirs,files fixed: ${fixed})"
  else
    warn "Permission normalization returned nothing—check manually"
  fi
}
normalize_remote_perms

# Cloudflare cache purge (non-fatal). Skipped on dry-run.
purge_cloudflare_cache() {
  if [ -n "$DRY_RUN" ]; then
    warn "Dry run—skipping Cloudflare purge"; return 0
  fi
  if [ -z "${CLOUDFLARE_API_TOKEN:-}" ] || [ -z "${CLOUDFLARE_ZONE_ID:-}" ]; then
    warn "Cloudflare credentials not set in .env—skipping cache purge"; return 0
  fi
  info "Purging Cloudflare cache..."
  local response
  response=$(curl -s -X POST \
    "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/purge_cache" \
    -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
    -H "Content-Type: application/json" \
    -d '{"purge_everything":true}')
  if echo "$response" | grep -q '"success"[[:space:]]*:[[:space:]]*true'; then
    ok "Cloudflare cache purged"
  else
    warn "Cloudflare cache purge failed (non-fatal)"
  fi
}
purge_cloudflare_cache

TOTAL_TIME=$(($(date +%s) - DEPLOY_START))

# Summary
echo ""
echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
echo -e "  ${BOLD}${ENV_COLOR}${ENV_LABEL} DEPLOY SUMMARY${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
echo -e "  Target      : ${BOLD}${TARGET_URL}${NC}"
echo -e "  Remote path : ${DIM}${SSH_USER}@${HOST}:${REMOTE_PATH}${NC}"
echo -e "  Git         : ${BOLD}${GIT_SHA}${NC} (${GIT_BRANCH})"
echo -e "  Pages       : ${BOLD}${PAGE_COUNT}${NC}"
echo -e "  Build time  : $(format_time $BUILD_TIME)"
echo -e "  Upload time : $(format_time $UPLOAD_TIME)"
echo -e "  Total time  : ${GREEN}$(format_time $TOTAL_TIME)${NC}"
echo -e "  Timestamp   : $(date '+%Y-%m-%d %H:%M:%S')"
[ -n "$DRY_RUN" ] && echo -e "  ${YELLOW}Mode        : DRY RUN (nothing uploaded)${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"

if [ -n "$DRY_RUN" ]; then
  warn "Dry-run complete. Re-run without --dry-run to push for real."
else
  ok "${ENV_LABEL} deploy complete → ${TARGET_URL}"
fi
