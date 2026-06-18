#!/usr/bin/env zsh
# Push the website/ tree to the EC2 host that serves https://issues.sstools.co/.
#
# Reads:
#   ISSUES_EC2_HOST   user@host or user@public-dns (e.g. ec2-user@issues.sstools.co),
#                     or just an SSH config alias.
#   ISSUES_EC2_PATH   Absolute path on the remote, e.g. /var/www/issues.
#   ISSUES_EC2_PORT   (optional) SSH port; defaults to whatever ~/.ssh/config says,
#                     falling back to 22.
#   ISSUES_EC2_KEY    (optional) Path to a .pem file. Permissions must be 400/600.
#                     Leave unset to let SSH pick the right key from ~/.ssh/config
#                     or the default identity files.
#
# Idempotent. rsync --delete keeps the remote in sync with website/, so
# files removed locally also disappear from the live site. Excludes
# .DS_Store and editor cruft.
#
# Run after a release pipeline completes and after appcast.xml has been
# regenerated for the new <item> (and the DMG copied into website/downloads/).
# Does NOT bump versions, sign, notarize, or tag — those are separate scripts.

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
REPO_ROOT="${SCRIPT_DIR:h}"
SITE_DIR="$REPO_ROOT/website"

# --- Preflight ---------------------------------------------------------------

require_env() {
    local name="$1"
    local value
    value="${(P)name:-}"
    if [[ -z "$value" ]]; then
        print -u2 "error: env var $name is not set"
        print -u2 "       export $name=... before re-running"
        exit 1
    fi
}

require_env ISSUES_EC2_HOST
require_env ISSUES_EC2_PATH

if [[ -n "${ISSUES_EC2_KEY:-}" ]]; then
    if [[ ! -f "$ISSUES_EC2_KEY" ]]; then
        print -u2 "error: key file not found at $ISSUES_EC2_KEY"
        exit 1
    fi

    KEY_PERMS=$(stat -f '%Lp' "$ISSUES_EC2_KEY" 2>/dev/null || stat -c '%a' "$ISSUES_EC2_KEY")
    if [[ "$KEY_PERMS" != "400" && "$KEY_PERMS" != "600" ]]; then
        print -u2 "error: $ISSUES_EC2_KEY has permissions $KEY_PERMS — SSH will refuse it."
        print -u2 "       chmod 600 \"$ISSUES_EC2_KEY\""
        exit 1
    fi
fi

if [[ ! -d "$SITE_DIR" ]]; then
    print -u2 "error: $SITE_DIR does not exist; nothing to deploy"
    exit 1
fi

if [[ ! -f "$SITE_DIR/index.html" ]]; then
    print -u2 "error: $SITE_DIR/index.html missing — bail before pushing a broken site"
    exit 1
fi

if [[ ! -f "$SITE_DIR/appcast.xml" ]]; then
    print -u2 "warning: $SITE_DIR/appcast.xml is missing — Sparkle clients will 404 on update checks"
fi

# --- Deploy ------------------------------------------------------------------

# Build SSH option list: -i and -p are only added if explicitly configured.
# Otherwise, defer to ~/.ssh/config and the user's default identity files.
SSH_OPTS=(-o StrictHostKeyChecking=accept-new)
if [[ -n "${ISSUES_EC2_KEY:-}" ]]; then
    SSH_OPTS+=(-i "$ISSUES_EC2_KEY")
fi
if [[ -n "${ISSUES_EC2_PORT:-}" ]]; then
    SSH_OPTS+=(-p "$ISSUES_EC2_PORT")
fi

print "==> Deploying website to $ISSUES_EC2_HOST:$ISSUES_EC2_PATH"
if [[ -n "${ISSUES_EC2_KEY:-}" ]]; then
    print "    Key:    $ISSUES_EC2_KEY"
else
    print "    Key:    (ssh default — from ~/.ssh/config / identity files)"
fi
print "    Port:   ${ISSUES_EC2_PORT:-(ssh default)}"
print "    Source: $SITE_DIR"

# Confirm the remote path exists before pushing — rsync will create files
# but not the leaf directory. Fail loudly if the user mistyped the path.
if ! ssh "${SSH_OPTS[@]}" "$ISSUES_EC2_HOST" "test -d \"$ISSUES_EC2_PATH\""; then
    print -u2 "error: remote directory $ISSUES_EC2_PATH does not exist on $ISSUES_EC2_HOST"
    print -u2 "       ssh in and create it, then re-run"
    exit 1
fi

rsync \
    -avz \
    --delete \
    --exclude '.DS_Store' \
    --exclude '*.swp' \
    --exclude '*.bak' \
    -e "ssh ${SSH_OPTS[*]}" \
    "$SITE_DIR/" \
    "$ISSUES_EC2_HOST:$ISSUES_EC2_PATH/"

print "==> Done. Verify https://issues.sstools.co/ in a browser."
