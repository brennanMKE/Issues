#!/usr/bin/env zsh
# Build a Release Issues.app and zip it for distribution.

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
REPO_ROOT="${SCRIPT_DIR:h}"
PROJECT="$REPO_ROOT/Issues.xcodeproj"
SCHEME="Issues"
BUILD_DIR="$REPO_ROOT/build"
DIST_DIR="$REPO_ROOT/dist"

if [[ ! -d "$PROJECT" ]]; then
    print -u2 "error: $PROJECT not found"
    exit 1
fi

print "==> Cleaning previous build"
rm -rf "$BUILD_DIR"
mkdir -p "$DIST_DIR"

print "==> Building Release"
xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR" \
    -destination 'platform=macOS' \
    clean build

APP_PATH="$BUILD_DIR/Build/Products/Release/$SCHEME.app"
if [[ ! -d "$APP_PATH" ]]; then
    print -u2 "error: built app not found at $APP_PATH"
    exit 1
fi

GIT_SHA="$(git -C "$REPO_ROOT" rev-parse --short HEAD 2>/dev/null || print unknown)"
ZIP_PATH="$DIST_DIR/Issues-$GIT_SHA.zip"

print "==> Packaging $APP_PATH -> $ZIP_PATH"
rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

# Tear down the intermediate build/ directory after the zip is produced.
# Reason (#0026): leaving a Release Issues.app in build/Build/Products/
# means LaunchServices indexes it alongside the Debug build that Xcode
# normally runs from DerivedData. Both share bundle id co.sstools.Issues,
# and tapping a notification can route to either — producing two
# Issues.app dock icons. Removing the .app here keeps the zip as the
# canonical distributable and stops LaunchServices from finding a second
# bundle.
print "==> Cleaning up build artifacts ($BUILD_DIR)"
rm -rf "$BUILD_DIR"

print
print "Done. Distributable at:"
print "  $ZIP_PATH"
print
print "On the recipient's Mac:"
print "  - Extract Issues.zip"
print "  - First launch: right-click Issues.app -> Open (Gatekeeper bypass)"
print "  - Or strip quarantine: xattr -cr ~/Downloads/Issues.app"
