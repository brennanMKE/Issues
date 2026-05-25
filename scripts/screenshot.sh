#!/usr/bin/env zsh
#
# screenshot.sh [OUTPUT_PATH]
#
# Captures the Issues Beta window (co.sstools.Issues.beta) to a PNG file.
# Requires the `windows` CLI to be installed (resolves window IDs by bundle ID).
#
# Usage:
#   ./scripts/screenshot.sh                          # saves to screenshots/screenshot_YYYYMMDDHHMMSS.png
#   ./scripts/screenshot.sh project-issues/0138/after.png   # saves to a specific path
#
# Prerequisites:
#   - Issues Beta must be running (build and launch via the "Issues (Beta)" scheme,
#     or: ./scripts/set-environment.sh Beta && open -b co.sstools.Issues.beta)
#   - `windows` CLI must be on $PATH. Install: https://github.com/nicowillis/windows
#     Verify: which windows

# Find the window ID for Issues Beta
WINDOW_ID=$(windows | grep co.sstools.Issues.beta | head -1 | awk '{print $1}')

if [[ -z "$WINDOW_ID" ]]; then
    echo "Warning: Issues Beta window not found — is the app running?" >&2
    exit 1
fi

if [[ -n "$1" ]]; then
    FILENAME="$1"
    mkdir -p "${FILENAME:h}"
else
    mkdir -p screenshots
    TIMESTAMP=$(date +%Y%m%d%H%M%S)
    FILENAME="screenshots/screenshot_${TIMESTAMP}.png"
fi

/usr/sbin/screencapture -l $WINDOW_ID "$FILENAME" && echo "$FILENAME"
