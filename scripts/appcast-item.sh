#!/usr/bin/env zsh
# Emit a ready-to-paste Sparkle <item> for a built DMG.
#
# Every attribute is derived from the artifact itself — the app's
# CFBundleShortVersionString and CFBundleVersion are read from the bundle
# *inside* the DMG, the length is the DMG's byte count, and the EdDSA
# signature is computed over the DMG. Nothing is hand-typed, so the appcast
# can't drift from the DMG (Sparkle compares CFBundleVersion for the update
# decision but prints the marketing strings in its dialog — a mismatch
# produces a "You're up to date" dialog that names a newer version).
#
# Usage:
#   scripts/appcast-item.sh dist/Issues-<sha>.dmg
#
# The printed enclosure URL and release-notes link follow the published
# convention and are derived from the marketing version:
#   url:             https://issues.sstools.co/downloads/Issues-<X.Y.Z>.dmg
#   releaseNotesLink https://issues.sstools.co/releases/<X.Y.Z>.html
# Copy the DMG to website/downloads/Issues-<X.Y.Z>.dmg before deploying, and
# add the matching website/releases/<X.Y.Z>.html notes page.

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
REPO_ROOT="${SCRIPT_DIR:h}"

DMG="${1:-}"
if [[ -z "$DMG" || ! -f "$DMG" ]]; then
    print -u2 "usage: scripts/appcast-item.sh <path/to/Issues-*.dmg>"
    exit 2
fi

MIN_SYSTEM=$(grep -E '^MACOSX_DEPLOYMENT_TARGET' "$REPO_ROOT/Configuration/Build.xcconfig" \
    2>/dev/null | head -1 | awk -F= '{print $2}' | tr -d ' ')
MIN_SYSTEM="${MIN_SYSTEM:-15.0}"

# Locate sign_update — it ships as an SPM artifact, either under the package
# .build (CLI swift build) or Xcode's DerivedData (Xcode-driven build).
find_sign_update() {
    local candidates=(
        "$REPO_ROOT/IssuesKit/.build/artifacts/sparkle/Sparkle/bin/sign_update"
        $HOME/Library/Developer/Xcode/DerivedData/Issues-*/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update(N)
    )
    local c
    for c in $candidates; do
        [[ -x "$c" ]] && { print -r -- "$c"; return 0 }
    done
    return 1
}

SIGN_UPDATE=$(find_sign_update) || {
    print -u2 "error: sign_update not found. Build IssuesKit once (e.g. open the project in"
    print -u2 "       Xcode and build, or 'swift build' in IssuesKit/) so the Sparkle SPM"
    print -u2 "       artifacts are produced, then retry."
    exit 1
}

# Read the version fields from the app bundle inside the DMG. Mount read-only,
# no-browse, on a random mountpoint; always detach on exit.
MOUNT_DIR=$(hdiutil attach "$DMG" -nobrowse -readonly -mountrandom /tmp \
    | awk '/\/tmp\// {print $NF; exit}')
if [[ -z "$MOUNT_DIR" || ! -d "$MOUNT_DIR" ]]; then
    print -u2 "error: failed to mount $DMG"
    exit 1
fi
trap 'hdiutil detach "$MOUNT_DIR" -quiet 2>/dev/null || true' EXIT

APP=$(print -r -- "$MOUNT_DIR"/*.app(N) | head -1)
if [[ -z "$APP" || ! -d "$APP" ]]; then
    print -u2 "error: no .app found inside $DMG"
    exit 1
fi

PLIST="$APP/Contents/Info.plist"
SHORT_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")
BUILD_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST")

if [[ -z "$SHORT_VERSION" || -z "$BUILD_VERSION" ]]; then
    print -u2 "error: could not read version fields from $PLIST"
    exit 1
fi

# sign_update prints: sparkle:edSignature="..." length="..."
# The keychain account is "Issues" (the default "ed25519" won't find the key).
SIG_LINE=$("$SIGN_UPDATE" --account Issues "$DMG")
ED_SIGNATURE=$(print -r -- "$SIG_LINE" | grep -oE 'sparkle:edSignature="[^"]+"' | sed -E 's/.*="([^"]+)"/\1/')
LENGTH=$(print -r -- "$SIG_LINE" | grep -oE 'length="[0-9]+"' | sed -E 's/.*="([0-9]+)"/\1/')

if [[ -z "$ED_SIGNATURE" || -z "$LENGTH" ]]; then
    print -u2 "error: sign_update output not understood:"
    print -u2 "       $SIG_LINE"
    exit 1
fi

# Cross-check length against the actual file size.
ACTUAL_BYTES=$(stat -f '%z' "$DMG")
if [[ "$LENGTH" != "$ACTUAL_BYTES" ]]; then
    print -u2 "error: sign_update length ($LENGTH) != DMG byte size ($ACTUAL_BYTES)"
    exit 1
fi

PUBDATE=$(date -u +"%a, %d %b %Y 00:00:00 +0000")

cat <<EOF
    <item>
      <title>${SHORT_VERSION}</title>
      <pubDate>${PUBDATE}</pubDate>
      <sparkle:minimumSystemVersion>${MIN_SYSTEM}</sparkle:minimumSystemVersion>
      <sparkle:releaseNotesLink>https://issues.sstools.co/releases/${SHORT_VERSION}.html</sparkle:releaseNotesLink>
      <description><![CDATA[
        TODO: paste user-visible release notes for ${SHORT_VERSION} here.
      ]]></description>
      <enclosure
        url="https://issues.sstools.co/downloads/Issues-${SHORT_VERSION}.dmg"
        sparkle:version="${BUILD_VERSION}"
        sparkle:shortVersionString="${SHORT_VERSION}"
        sparkle:edSignature="${ED_SIGNATURE}"
        length="${LENGTH}"
        type="application/octet-stream" />
    </item>
EOF

print -u2 ""
print -u2 "Generated <item> for Issues ${SHORT_VERSION} (build ${BUILD_VERSION})."
print -u2 "  - Paste it as the FIRST <item> in website/appcast.xml (newest first)."
print -u2 "  - Copy the DMG to website/downloads/Issues-${SHORT_VERSION}.dmg."
print -u2 "  - Add release notes at website/releases/${SHORT_VERSION}.html."
print -u2 "  - Fill in the <description> release notes."
