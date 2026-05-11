#!/usr/bin/env zsh
# Build a Debug `Issues.app`, ad-hoc sign it, and package it into a DMG
# ready to scp onto a test Mac. Intentionally minimal — skips
# notarization and Developer ID signing so the loop stays under a
# minute (#0107).
#
# Usage:
#   scripts/debug-dmg.sh           # default
#   scripts/debug-dmg.sh --clean   # wipe build/debug first
#
# Output: build/Issues-debug.dmg
# After copying to the test Mac:
#   xattr -d com.apple.quarantine /Applications/Issues.app

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
SCRIPT_NAME="${0##*/}"
REPO_ROOT="${SCRIPT_DIR:h}"
PROJECT="$REPO_ROOT/Issues.xcodeproj"
SCHEME="Issues"
BUILD_DIR="$REPO_ROOT/build"
DEBUG_DERIVED="$BUILD_DIR/debug"
DMG_OUT="$BUILD_DIR/Issues-debug.dmg"

CLEAN=0
for arg in "$@"; do
    case "$arg" in
        --clean) CLEAN=1 ;;
        -h|--help)
            cat <<EOF
Usage: $SCRIPT_NAME [--clean]

Builds a Debug Issues.app, ad-hoc signs it, and produces $DMG_OUT.

Options:
  --clean   Wipe build/debug/ before building.
  -h        Show this help.
EOF
            exit 0
            ;;
        *)
            print -u2 "$SCRIPT_NAME: unknown argument: $arg"
            exit 2
            ;;
    esac
done

if [[ ! -d "$PROJECT" ]]; then
    print -u2 "error: $PROJECT not found"
    exit 1
fi

if (( CLEAN )); then
    print "[debug-dmg] Cleaning $DEBUG_DERIVED"
    rm -rf "$DEBUG_DERIVED"
fi

mkdir -p "$BUILD_DIR"

# --- Build -----------------------------------------------------------------

print "[debug-dmg] Building Debug configuration"
xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Debug \
    -destination 'platform=macOS' \
    -derivedDataPath "$DEBUG_DERIVED" \
    build

APP_PATH="$DEBUG_DERIVED/Build/Products/Debug/Issues.app"
if [[ ! -d "$APP_PATH" ]]; then
    print -u2 "error: built app not found at $APP_PATH"
    exit 1
fi

# --- Ad-hoc sign -----------------------------------------------------------

# Re-sign with the ad-hoc identity ("-") so the app launches on any Mac
# without needing the Developer ID profile. Quarantine is still applied
# on first copy, so the user runs `xattr -d com.apple.quarantine` once.
print "[debug-dmg] Ad-hoc signing $APP_PATH"
codesign --force --deep --sign - "$APP_PATH"

# --- DMG -------------------------------------------------------------------

# `hdiutil create` with -srcfolder + -format UDZO gives a compact,
# read-only DMG. The volume name shows up in Finder when mounted.
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
cp -R "$APP_PATH" "$STAGING/"
# Convenience: drop a symlink to /Applications next to the .app so the
# user can drag-and-drop on mount.
ln -s /Applications "$STAGING/Applications"

rm -f "$DMG_OUT"
print "[debug-dmg] Building DMG at $DMG_OUT"
hdiutil create \
    -volname "Issues Debug" \
    -srcfolder "$STAGING" \
    -ov \
    -format UDZO \
    "$DMG_OUT"

# --- Done ------------------------------------------------------------------

print ""
print "[debug-dmg] Built: $DMG_OUT"
print ""
print "Copy to the test Mac, drag to /Applications, then run:"
print "  xattr -d com.apple.quarantine /Applications/Issues.app"
print ""
print "Stream logs once it's running:"
print "  log stream --predicate 'subsystem == \"co.sstools.Issues\"' --level debug"
