# Sparkle setup checklist

Issues.app ships with [Sparkle](https://sparkle-project.org/) wired into the build (#0118) but **inert** until two pieces of host-side configuration land:

1. An EdDSA key pair (private key in your Keychain, public key in `Info.plist`).
2. An `appcast.xml` hosted at `https://issues.sstools.co/appcast.xml`.

Until both are in place, the **Issues → Check for Updates…** menu item shows up as disabled. Once they're in place, no code change is needed — Sparkle picks the feed URL up on the next launch and the menu enables itself.

## One-time setup

### 1. Generate the EdDSA key pair

Use Sparkle's `generate_keys` tool (ships in the Sparkle package's `bin/` directory). The first run creates a key pair and stores the **private key in the macOS keychain** under `https://sparkle-project.org`; subsequent runs just print the existing public key.

```sh
# Replace <SPARKLE_VERSION> with whatever Xcode resolved in Package.resolved.
~/Library/Developer/Xcode/DerivedData/Issues-*/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys
```

It prints the public key as a base64 string. **Save the private key somewhere else too** (encrypted note, password manager, whatever) — losing it means every future update would be rejected by existing clients, and recovery means shipping a new public key + having users redownload the app manually.

### 2. Configure Info.plist

`SUFeedURL` and `SUPublicEDKey` need to live in the running app's `Info.plist`. Two options today:

- **If #0110 has landed** (explicit `Issues/Info.plist`), add directly:

  ```xml
  <key>SUFeedURL</key>
  <string>https://issues.sstools.co/appcast.xml</string>
  <key>SUPublicEDKey</key>
  <string><!-- paste the base64 public key from step 1 here --></string>
  ```

- **If `GENERATE_INFOPLIST_FILE = YES` is still set** (today's state), use `INFOPLIST_KEY_*` build settings in `project.pbxproj` for both Debug and Release configs of the Issues target:

  ```
  INFOPLIST_KEY_SUFeedURL = "https://issues.sstools.co/appcast.xml";
  INFOPLIST_KEY_SUPublicEDKey = "<base64 public key>";
  ```

  Recent Xcode versions honour arbitrary `INFOPLIST_KEY_*` settings even for non-standard keys; if this stops working, switch to the explicit Info.plist path (paired with #0110).

### 3. Stand up the appcast host

Point `issues.sstools.co` at a static host (GitHub Pages is the simplest fit — point the subdomain at the `gh-pages` branch of `brennanMKE/Issues` and publish `appcast.xml` from there). The DMG enclosure URL doesn't have to live on the same host; it can stay wherever release binaries already live.

Initial `appcast.xml` skeleton:

```xml
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
    <channel>
        <title>Issues.app</title>
        <link>https://issues.sstools.co/appcast.xml</link>
        <description>Updates for Issues.app</description>
        <language>en</language>
        <!-- One <item> per release; see "Per-release" below. -->
    </channel>
</rss>
```

## Per-release: sign and publish

For every new release built by `scripts/release.sh`:

1. Compute the EdDSA signature for the new DMG:

   ```sh
   ~/Library/Developer/Xcode/DerivedData/Issues-*/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update \
       build/Issues-x.y.z.dmg
   ```

   Prints `sparkle:edSignature="…" length="…"` — both attributes go on the `<enclosure>` element below.

2. Append an `<item>` to `appcast.xml`:

   ```xml
   <item>
       <title>Version x.y.z</title>
       <pubDate>Mon, 11 May 2026 12:00:00 -0700</pubDate>
       <sparkle:version>x.y.z</sparkle:version>
       <sparkle:shortVersionString>x.y.z</sparkle:shortVersionString>
       <sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>
       <description><![CDATA[
           <h3>What's new in x.y.z</h3>
           <ul>
               <li>Release notes here…</li>
           </ul>
       ]]></description>
       <enclosure
           url="https://example.com/path/to/Issues-x.y.z.dmg"
           sparkle:edSignature="<from step 1>"
           length="<from step 1>"
           type="application/octet-stream" />
   </item>
   ```

3. Commit + push the `appcast.xml` change to whichever branch backs `issues.sstools.co`.

Existing clients poll the feed (Sparkle checks once per launch by default; bumping the cadence is `SUScheduledCheckInterval` — `86400` for daily is a reasonable default once you're confident). When the next check sees a higher `sparkle:version`, the user gets the standard "A new version of Issues is available" dialog.

## Notes

- **`SUEnableAutomaticChecks` is not set in the project**. Sparkle defaults to manual-only — users have to pick "Check for Updates…" themselves. Once the appcast is live and tested, flip this to `YES` (and optionally set `SUScheduledCheckInterval` to e.g. `86400`) for a daily background check.
- **`sign_update` is not wired into `scripts/release.sh`** for v1. It stays manual so the release flow doesn't surprise the user with a Sparkle signature attempt before Sparkle is configured. Once the first appcast round-trip works, fold the invocation into the release script.
- **The private key never enters the repo** (and never should — it's the load-bearing secret for "any update I publish in the future will be trusted by existing clients"). Sparkle's `generate_keys` storing it in the macOS keychain is the right default.
- **Delta updates / multi-channel betas** aren't set up here. Sparkle supports both via additional `<item>` attributes; revisit if/when the release cadence warrants.
