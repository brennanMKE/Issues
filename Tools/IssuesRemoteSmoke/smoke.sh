#!/usr/bin/env zsh
# Wrapper for `swift run issues-remote-smoke`. Reads the bearer token
# from $ISSUES_REMOTE_TOKEN so it doesn't end up in shell history.
#
# Usage:
#   ISSUES_REMOTE_TOKEN=iat_... ./smoke.sh --host 100.74.12.5:51823
#
# All other flags pass through to the binary.

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
cd "$SCRIPT_DIR"

if [[ -z "${ISSUES_REMOTE_TOKEN:-}" ]]; then
    print -u2 "warning: ISSUES_REMOTE_TOKEN is not set; pass --token explicitly or export it"
fi

exec swift run -c release issues-remote-smoke "$@"
