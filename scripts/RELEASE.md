# Cutting an Issues release

End-to-end checklist for producing a signed, notarized, stapled DMG that
Gatekeeper accepts on a clean Mac, then publishing it through Sparkle. Pairs
with `scripts/release.sh`.

## One-time setup

- **Apple Developer account** with a Developer ID Application certificate
  installed in your login keychain. Team ID: `XV8BAAVZ6V`
  (`Configuration/Build.xcconfig:DEVELOPMENT_TEAM`).
- **Notary keychain profile** named `Issues-notary`. Create it with:

  ```bash
  xcrun notarytool store-credentials "Issues-notary" \
    --key ~/.appstoreconnect/AuthKey_<KEY_ID>.p8 \
    --key-id <KEY_ID> \
    --issuer <ISSUER_UUID>
  ```

- **Sparkle EdDSA key**: `generate_keys --account Issues` stores the private
  key in your keychain; the public key is already in
  `Configuration/Build.xcconfig` as `SU_PUBLIC_ED_KEY`. See
  `scripts/SPARKLE.md` and `scripts/SparkleSetup.md`.
- **Website deploy env vars** (EC2, shared with the Batty deploy box) in your
  shell init:
  - `export ISSUES_EC2_KEY=~/keys/issues.pem` — path to your AWS .pem
    (must be `chmod 600`). Optional — omit to use `~/.ssh/config`.
  - `export ISSUES_EC2_HOST=ec2-user@issues.sstools.co` — SSH login.
  - `export ISSUES_EC2_PATH=/var/www/issues` — remote document root.
  - `export ISSUES_EC2_PORT=22` — optional, defaults to 22.
- **Tools**: `brew install create-dmg fileicon`.

## Release steps

0. **Run the preflight**

   ```bash
   scripts/preflight.sh
   ```

   Walks every release-readiness gate (build, tests, version drift, Sparkle
   plist, signing cert, notarytool profile, website env vars, working tree).
   Fix every `[✗]` before continuing; `[!]` warnings are advisory.
   `--skip-build` for a faster check, `--strict` to promote warnings to
   failures.

1. **Choose the version**

   Bump `MARKETING_VERSION` in `Configuration/App.xcconfig` — that file is
   the single source of truth for the marketing version; the Info.plist reads
   it via `$(MARKETING_VERSION)`. SemVer (`1.2.0`).

   **Do not bump `CURRENT_PROJECT_VERSION` by hand.** `release.sh` overrides
   it at archive time with today's UTC date in `YYYYMMDD` form — the
   monotonically-increasing build number Sparkle compares against. The number
   is printed at the end of `release.sh` and baked into the appcast `<item>`
   automatically.

   Commit the bump on its own as `Bump version to <X.Y.Z>`.

2. **Sanity-check the build and run tests**

   ```bash
   xcodebuild -project Issues.xcodeproj -scheme 'Issues (Prod)' -configuration Debug -destination 'platform=macOS' build
   xcodebuild -project Issues.xcodeproj -scheme 'Issues (Prod)' -destination 'platform=macOS' test
   ```

   Both must pass clean. Don't proceed if anything is red.

3. **Run the release pipeline**

   ```bash
   scripts/release.sh
   ```

   Selects Prod (`set-environment.sh Prod`) → archives → exports → signs →
   notarizes → staples → DMG-packages → verifies versions and Gatekeeper, then
   prints a ready-to-paste appcast `<item>`. Output lands at
   `dist/Issues-<sha>.dmg`. Notarization typically takes 2–10 minutes; the
   script blocks via `notarytool ... --wait`.

   **Do not run this step autonomously from an agent session.** The
   submission modifies a shared system (Apple's notary service).

4. **Verify the DMG**

   ```bash
   scripts/verify-dmg.sh dist/Issues-<sha>.dmg
   ```

   Confirms signing, notarization, stapling, and Gatekeeper acceptance under
   quarantine.

5. **Smoke-test on a clean Mac** (or a fresh user account that has never run
   Issues). Drag from the DMG to `/Applications`, double-click, confirm it
   opens without right-click bypass or an "unidentified developer" warning.

6. **Update the appcast, downloads, and release notes**

   - **Generate the `<item>` from the DMG — do not hand-type it.**
     `release.sh` prints it; regenerate any time with:

     ```bash
     scripts/appcast-item.sh dist/Issues-<sha>.dmg
     ```

     Every attribute (`sparkle:version`, `sparkle:shortVersionString`,
     `length`, `sparkle:edSignature`) is read from the artifact itself, so the
     appcast can't drift from the DMG.
   - Paste the generated `<item>` as the **first** item in
     `website/appcast.xml` (newest first) and fill in its `<description>`.
   - Copy the DMG to `website/downloads/Issues-<X.Y.Z>.dmg`.
   - Add a release-notes page at `website/releases/<X.Y.Z>.html` (mirror the
     existing `1.0.0.html`), and link it from `website/index.html` if
     appropriate.
   - Re-run `scripts/preflight.sh` after pasting — the appcast↔DMG consistency
     gate mounts the newest item's DMG and checks its real version fields and
     byte length against the advertised attributes.

7. **Deploy the website**

   ```bash
   scripts/deploy-website.sh
   ```

   rsyncs `website/` to `$ISSUES_EC2_HOST:$ISSUES_EC2_PATH`. Sparkle clients
   poll the appcast on a schedule, so the new version appears in "Check for
   Updates…" within a few hours.

8. **Tag the release**

   ```bash
   scripts/tag-release.sh
   ```

   Reads `MARKETING_VERSION` from `App.xcconfig`, creates an annotated
   `v<X.Y.Z>` tag on HEAD, and prompts before pushing. `--push` / `--no-push`
   to skip the prompt.

## Troubleshooting

- **`spctl --assess` fails on the freshly-signed `.app` but the DMG is fine.**
  The script staples the DMG, not the bare `.app`; re-test via
  `verify-dmg.sh`.
- **Notarization rejected.** `xcrun notarytool log <submission-id>
  --keychain-profile Issues-notary` prints the actual issues. Most common:
  hardened runtime missing, embedded binaries unsigned, or a mismatched
  bundle id.
- **Sparkle says "You're up to date" naming a newer version.** The appcast's
  `sparkle:version` drifted from the DMG's `CFBundleVersion`. Always
  regenerate the `<item>` with `appcast-item.sh` rather than hand-editing.
- **`release.sh` archived a beta build.** It runs `set-environment.sh Prod`
  first to prevent this; if you bypass the script, ensure
  `Configuration/Active.xcconfig` includes `Prod.xcconfig` before archiving
  (#0145).
