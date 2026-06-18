#!/usr/bin/env zsh
# Build, sign, notarize, and package Issues.app for distribution.
#
# Produces dist/Issues-<sha>.dmg with a drag-to-Applications layout, signed
# with Developer ID and notarized so Gatekeeper accepts it on first launch
# without right-click bypass.

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
REPO_ROOT="${SCRIPT_DIR:h}"
PROJECT="$REPO_ROOT/Issues.xcodeproj"
SCHEME="Issues (Prod)"
# PRODUCT_NAME (and therefore the .app / .xcarchive filename) is "Issues",
# NOT the scheme name. The scheme was renamed to "Issues (Prod)" when the
# Beta/Prod xcconfig split landed (#0137), but the product is still Issues.app.
# Keep these two decoupled — conflating them is what broke the old release.sh
# (and the Beta launch bug in #0145).
APP_NAME="Issues"
BUILD_DIR="$REPO_ROOT/build"
DIST_DIR="$REPO_ROOT/dist"
ARCHIVE_PATH="$BUILD_DIR/$APP_NAME.xcarchive"
EXPORT_DIR="$BUILD_DIR/Export"
EXPORT_PLIST="$BUILD_DIR/exportOptions.plist"

NOTARY_PROFILE="Issues-notary"
TEAM_ID="XV8BAAVZ6V"
SIGN_IDENTITY="Developer ID Application: Brennan Stehling ($TEAM_ID)"

# --- Preflight ---------------------------------------------------------------

if [[ ! -d "$PROJECT" ]]; then
    print -u2 "error: $PROJECT not found"
    exit 1
fi

if ! command -v create-dmg >/dev/null 2>&1; then
    print -u2 "error: create-dmg not installed. Run: brew install create-dmg"
    exit 1
fi

if ! command -v fileicon >/dev/null 2>&1; then
    print -u2 "error: fileicon not installed. Run: brew install fileicon"
    exit 1
fi

if ! security find-identity -p codesigning -v | grep -q "$SIGN_IDENTITY"; then
    print -u2 "error: signing identity not found in Keychain:"
    print -u2 "       $SIGN_IDENTITY"
    print -u2 "       Add via Xcode > Settings > Accounts > Manage Certificates > + > Developer ID Application"
    exit 1
fi

if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    print -u2 "error: notarytool keychain profile '$NOTARY_PROFILE' missing or invalid."
    print -u2 "       Set up via:"
    print -u2 "         xcrun notarytool store-credentials \"$NOTARY_PROFILE\" \\"
    print -u2 "           --key ~/.appstoreconnect/AuthKey_<KEY_ID>.p8 \\"
    print -u2 "           --key-id <KEY_ID> \\"
    print -u2 "           --issuer <ISSUER_UUID>"
    exit 1
fi

# --- Select the Prod configuration -------------------------------------------

# The Beta/Prod variant is selected by Configuration/Active.xcconfig, which
# the schemes rewrite via a pre-action (set-environment.sh). xcodebuild does
# NOT run scheme pre-actions, and Active.xcconfig is a persisted (gitignored)
# file — so whatever variant was last built in Xcode is still active here.
# Force Prod explicitly, or we could archive with the beta bundle id
# (co.sstools.Issues.beta) and an empty Sparkle feed (#0145).
print "==> Selecting Prod environment (Active.xcconfig)"
"$SCRIPT_DIR/set-environment.sh" Prod

# --- Build & export ----------------------------------------------------------

print "==> Cleaning previous build"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR" "$DIST_DIR"

# Sparkle compares CFBundleVersion to decide whether an update is newer, so it
# must increase monotonically. Derive it from today's UTC date (YYYYMMDD)
# rather than maintaining a hand-bumped counter. The static CURRENT_PROJECT_VERSION
# in App.xcconfig is only used by Xcode-driven Debug builds, which Sparkle
# never sees.
BUILD_NUMBER="$(date -u +%Y%m%d)"
print "==> Build number for this release: $BUILD_NUMBER"

print "==> Writing export options plist"
cat > "$EXPORT_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>$TEAM_ID</string>
    <key>signingStyle</key>
    <string>automatic</string>
</dict>
</plist>
EOF

print "==> Archiving Release"
xcodebuild archive \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    -destination 'generic/platform=macOS' \
    CURRENT_PROJECT_VERSION="$BUILD_NUMBER"

print "==> Exporting signed app"
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_DIR" \
    -exportOptionsPlist "$EXPORT_PLIST"

APP_PATH="$EXPORT_DIR/$APP_NAME.app"
if [[ ! -d "$APP_PATH" ]]; then
    print -u2 "error: exported app not found at $APP_PATH"
    exit 1
fi

print "==> Verifying app signature"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

# Version-consistency gate: confirm the *built* bundle carries the versions we
# expect before it gets packaged and notarized.
#   - CFBundleShortVersionString must equal MARKETING_VERSION from App.xcconfig
#     (catches a stale build setting or a per-target override winning).
#   - CFBundleVersion must equal the build number we injected (catches the
#     archive not honoring the CURRENT_PROJECT_VERSION override — which would
#     make Sparkle's comparison key wrong).
# Failing here is cheap; discovering it in users' update dialogs is not.
EXPECTED_SHORT=$(grep -E '^MARKETING_VERSION' "$REPO_ROOT/Configuration/App.xcconfig" \
    | head -1 | awk -F= '{print $2}' | tr -d ' ')
ACTUAL_SHORT=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")
ACTUAL_BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_PATH/Contents/Info.plist")
if [[ "$ACTUAL_SHORT" != "$EXPECTED_SHORT" ]]; then
    print -u2 "error: built CFBundleShortVersionString ($ACTUAL_SHORT) != MARKETING_VERSION ($EXPECTED_SHORT)"
    print -u2 "       The bundle's marketing version drifted from App.xcconfig."
    exit 1
fi
if [[ "$ACTUAL_BUILD" != "$BUILD_NUMBER" ]]; then
    print -u2 "error: built CFBundleVersion ($ACTUAL_BUILD) != injected build number ($BUILD_NUMBER)"
    print -u2 "       The archive did not honor CURRENT_PROJECT_VERSION=$BUILD_NUMBER."
    exit 1
fi
print "==> Version check: $ACTUAL_SHORT (build $ACTUAL_BUILD) matches App.xcconfig + build number"

# AppIcon.icns is generated from Assets.xcassets/AppIcon.appiconset during the
# build and lives inside the built bundle. The same file drives both the
# mounted volume's Finder icon (--volicon below) and the DMG file's Finder
# icon (fileicon, applied after stapling).
APP_ICON="$APP_PATH/Contents/Resources/AppIcon.icns"
if [[ ! -f "$APP_ICON" ]]; then
    print -u2 "error: AppIcon.icns not found at $APP_ICON"
    exit 1
fi

# --- DMG ---------------------------------------------------------------------

GIT_SHA="$(git -C "$REPO_ROOT" rev-parse --short HEAD 2>/dev/null || print unknown)"

# Build/sign/notarize/staple all happen against a fixed-name DMG that matches
# the volume name. Reason: when the DMG filename and --volname differ, macOS
# (Gatekeeper provenance handling, observed during notarytool roundtrip) can
# silently rename the file on disk to match the volume — which then breaks
# the next step in the pipeline. Keeping name == volname avoids the rename;
# we tag with the git sha by renaming once, after stapling completes.
WORK_DMG="$DIST_DIR/Issues.dmg"
DMG_PATH="$DIST_DIR/Issues-$GIT_SHA.dmg"

print "==> Creating DMG: $WORK_DMG"
rm -f "$WORK_DMG" "$DMG_PATH"
create-dmg \
    --volname "Issues" \
    --volicon "$APP_ICON" \
    --window-pos 200 120 \
    --window-size 600 400 \
    --icon-size 100 \
    --icon "$APP_NAME.app" 175 190 \
    --hide-extension "$APP_NAME.app" \
    --app-drop-link 425 190 \
    --no-internet-enable \
    "$WORK_DMG" \
    "$APP_PATH"

print "==> Signing DMG"
codesign --force --sign "$SIGN_IDENTITY" --timestamp "$WORK_DMG"

# --- Notarize ----------------------------------------------------------------

print "==> Submitting for notarization (this can take several minutes)"
xcrun notarytool submit "$WORK_DMG" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait

print "==> Stapling notarization ticket"
xcrun stapler staple "$WORK_DMG"
xcrun stapler validate "$WORK_DMG"

print "==> Verifying Gatekeeper acceptance"
spctl -a -t open --context context:primary-signature -vv "$WORK_DMG"

print "==> Tagging final artifact with git sha"
mv "$WORK_DMG" "$DMG_PATH"

# Set the DMG file's Finder icon to the app icon. fileicon writes only to
# extended attributes (com.apple.ResourceFork + com.apple.FinderInfo) and
# leaves the disk image's data fork untouched, so codesign and the stapled
# notarization ticket on the .dmg remain valid.
print "==> Setting DMG file icon"
fileicon set "$DMG_PATH" "$APP_ICON"

# --- Cleanup -----------------------------------------------------------------

# Tear down the intermediate build/ directory after the DMG is produced.
# Reason (#0026): leaving a Release Issues.app in build/ means LaunchServices
# indexes it alongside the Debug build that Xcode normally runs from
# DerivedData. Both share bundle id co.sstools.Issues, and tapping a
# notification can route to either — producing two Issues.app dock icons.
# Removing the .app here keeps the DMG as the canonical distributable.
print "==> Cleaning up build artifacts ($BUILD_DIR)"
rm -rf "$BUILD_DIR"

print
print "Done. Distributable at:"
print "  $DMG_PATH"
print "  Build number: $BUILD_NUMBER"
print

# Emit a ready-to-paste appcast <item> derived from the artifact itself, so
# sparkle:version / sparkle:shortVersionString / length / edSignature can never
# be hand-typed out of sync with the DMG. Best-effort: if the Sparkle signing
# key isn't available on this machine the release still succeeded — the
# operator can run scripts/appcast-item.sh later.
print "==> Appcast item for website/appcast.xml (paste as the first <item>):"
print
if ! "$SCRIPT_DIR/appcast-item.sh" "$DMG_PATH"; then
    print -u2 "note: could not auto-generate the appcast item; run scripts/appcast-item.sh \"$DMG_PATH\" manually."
fi
print
print "On the recipient's Mac:"
print "  - Double-click the DMG"
print "  - Drag Issues.app onto the Applications shortcut"
print "  - Launch from Applications — no Gatekeeper warning, no right-click bypass"
