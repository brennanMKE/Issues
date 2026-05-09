# Remote Access — design plan

Working draft. Single-author project, single-user constraint. Goal is to view a folder of issues on Mac A from Issues.app running on Mac B without copying files, opening ports to the public internet, or asking the user to manage credentials.

This is exploratory — read it as "the design we're iterating toward," not "the spec to implement."

## Goals

- **Read-only** remote viewing — on every platform, present and future. The remote folder's `.md` files are the source of truth; nothing about this design admits writes from a remote viewer.
- **Token-based auth, identity-agnostic.** The host generates named access tokens; the user copies/pastes one into each viewer. Works regardless of whether the viewer is signed into the same Apple ID, on the same Tailnet, or anywhere else. No assumptions about the *user identity* on the viewer device.
- **Multi-platform viewers.** The host is always a Mac (it has the files); viewers can be Macs or iPhones running the same codebase. The protocol and auth are platform-neutral; only the server-side filesystem code is Mac-only.
- **Multiple simultaneous viewers.** A user might have a Mac viewer and an iPhone viewer open against the same host at once, each subscribed to one or more folders. The host broadcasts updates to all connected viewers; nothing in the design assumes "one viewer at a time."
- **Multi-folder.** The host can serve any number of folders it's currently monitoring. Each viewer picks which folders to follow — one, several, or all — and the picker UI supports each of those choices in one click. Subscriptions are independent per viewer and per folder.
- **Project metadata via `project.json`.** Folders carry their own display name and GitHub repo URL via a `project.json` file at the folder root (written by IssuesSkill). The viewer uses these to render meaningful tabs and "Open repo" links. Folders without a `project.json` fall back to today's parent-folder-name behavior.
- **Toggleable.** A clear on/off in the app, with a visible indicator when serving.
- **No tunneling, no port-forwarding, no public exposure.** The server listens on local network interfaces only and relies on auth + the user's network being reasonable. We never ask the user to open a port on their router.
- **No new daemons or system services.** Everything lives inside `Issues.app` so a quit terminates the server (matches #0074's single-window-on-close behavior).
- **Live updates.** Edits on the host show up on every connected viewer within ~1 sec, the same feel as the local FSEvents path today.

## Non-goals (v1)

- **Not** multi-user / shared with other people. If the Tailnet has more than one human, this design is wrong for v2 and we'd revisit auth.
- **Not** end-to-end auditing, rate limiting, or attack-surface hardening beyond what Tailscale + a shared secret give us.
- **Not** offline caching on the viewer side. If the host is unreachable, the remote tab shows a disconnected state. Nothing on disk.
- **Not** handling concurrent writes from multiple viewers. Write support is out of scope; if it ever lands it's a separate design.

## Topology

```
                    ┌─────────────────────────────────┐
                    │  Mac A (host)                   │
                    │  Issues.app                     │
                    │  ┌─────────────────────────┐    │
                    │  │ folder "bluesky"        │    │
                    │  │ folder "Issues-app"     │    │  ← multiple folders,
                    │  │ folder "scratch"        │    │    each with its own
                    │  └────────┬────────────────┘    │    IssueStore + watcher
                    │           │                     │
                    │  ┌────────▼────────────────┐    │
                    │  │ RemoteServer            │    │
                    │  │ HTTP + WS + Bonjour     │    │
                    │  └────────┬────────────────┘    │
                    └───────────┼─────────────────────┘
                                │
                    ─ any IP network (LAN / overlay) ─
                                │
              ┌─────────────────┴────────────────────┐
              │                                      │
   ┌──────────▼─────────────┐         ┌──────────────▼────────────┐
   │  Mac B (viewer)        │         │  iPhone (viewer)          │
   │  Issues.app (macOS)    │         │  Issues.app (iOS)         │
   │  • subscribes "bluesky"│         │  • subscribes "bluesky"   │
   │  • subscribes "scratch"│         │                           │
   └────────────────────────┘         └───────────────────────────┘
```

Three roles, all the same binary at heart:

- **Host** — Mac only. Already monitors one or more folders locally; toggling on remote access publishes those folders.
- **Mac viewer** — same Issues.app the user already runs. A viewer tab points at a remote folder instead of a local one.
- **iPhone viewer** — same codebase, iOS target. Adapts the layout but consumes the same protocol. Hosts no folders; viewer-only by definition.

The role isn't a setting at app launch — a single Issues.app on a Mac can simultaneously host its own folders *and* view remote ones in other tabs. iPhone is viewer-only because the iOS target won't include the server code.

## Transport: HTTP over the local network

- **Why HTTP, not a custom protocol.** It's debuggable from `curl`, fits the request/response shape we need, and SwiftUI/`URLSession` already handle it. We can add WebSocket on the same port for live updates.
- **What the server binds to.** By default the server listens on **all non-loopback IPv4/IPv6 interfaces** the OS sees. That covers home Wi-Fi, Ethernet, and any VPN/overlay interface (Tailscale's `utun`, ZeroTier, etc.) without the app needing to know which is which. The auth layer (next section) is what makes "listen broadly" safe; without the user's iCloud-synced secret nothing on the network gets data.
- **Optional interface restriction (later).** A power-user setting could let the user pin the listener to specific interfaces (e.g. "only my Tailscale interface, never my coffee-shop Wi-Fi"). Not in v1; the auth layer + Bonjour-only-on-trusted-networks model carries the same intent without forcing the user to understand IP ranges.
- **TLS not strictly required for v1.** On a home LAN the network is usually trusted at the link layer; on overlay networks like Tailscale the tunnel encrypts every byte between peers. The shared-secret auth + a token never sent in cleartext over an untrusted hop covers most of what TLS would. We can add TLS later (self-signed, pinned via Keychain) if v2 needs it.

## Service discovery: Bonjour

- **Service type:** `_issues._tcp.local.`
- **One service per host, not per folder.** A single Bonjour advertisement covers the entire app instance — listing folders is the server's job once a viewer connects (via `GET /v1/folders`). Publishing a separate Bonjour record for each folder would clutter the picker UI and re-broadcast every time a folder is added or removed.
- **TXT record:** protocol version + host's display name + folder count (small hint for the picker — "Brennan's MacBook Air · 3 folders"). Folder *names* don't go in the TXT record because TXT has a 255-byte cap per string and the user could have any number of folders.
- **Published via** `NWListener` + `NWListener.service` on the Network framework. Bonjour works on any LAN by default; whether it reaches over an overlay network depends on whether that overlay forwards mDNS (Tailscale does with MagicDNS enabled, most others don't).
- **Browsed via** `NWBrowser(for: .bonjourWithTXTRecord(type: "_issues._tcp", domain: nil), …)`. Same API is available on iOS, so the iPhone target uses the same browser code.
- **Manual fallback** — if mDNS doesn't traverse the network in question (some overlays drop multicast), the viewer also accepts a typed-in `host:port`. Stored per-tab in the existing tab state. This is the path most users on non-Bonjour-friendly overlays will use.

## Authentication: named access tokens

Modeled directly on GitHub Personal Access Tokens. The host generates tokens; the user copies one into each viewer device. No assumptions about Apple ID, no hidden iCloud Keychain magic — the token is a string, and possession of the string is the credential.

### Token shape

- **Format:** `iat_<43-char base64url>` where the body is 32 random bytes. The `iat_` prefix (Issues Access Token) makes tokens grep-able and easy to recognize if accidentally pasted somewhere they shouldn't be.
- **Stored on the host as a hash, not plaintext.** The host keeps a list of tokens in its Keychain; each entry holds the SHA-256 hash, not the original string. The plaintext is shown to the user *once* at generation time and never again. This matches GitHub's PAT model and means a host-side keychain dump can't be replayed against a viewer.
- **Per-token metadata** (kept on the host, alongside the hash):
  - `name` — user-supplied label, e.g. "iPhone", "MacBook Air", "Brennan's spare Mac"
  - `createdAt` — ISO8601
  - `expiresAt` — optional ISO8601; absent means "valid until deleted"
  - `lastUsedAt` — optional, updated by the server on use; useful for spotting stale tokens
  - `lastUsedFrom` — optional reverse-DNS or IP of the most recent client; same purpose

### Generating, transferring, revoking

- **Generate**: in host settings → "Access tokens" → "+". User types a name (and optionally an expiration), clicks Generate. The token string appears with a Copy button and a notice that it won't be shown again.
- **Transfer**: copy from the host, paste on the viewer. For iPhone there's also a QR-code variant — the host renders the token as a QR code, the iPhone camera reads it (no third-party libraries; `AVCaptureSession` + `Vision` covers it). Both transfer paths are user-initiated, no automatic pairing.
- **Revoke**: delete the token from the host's list. Any viewer holding it gets `401` on the next request and falls into a disconnected state. No recovery — the user creates a new token if they want the device back.
- **Expiration**: optional. If set and reached, the host returns `401 expired_token`. Viewer surfaces an "expired — generate a new token on the host" message; doesn't silently retry.

### Request shape

- `Authorization: Bearer iat_<…>` on every HTTP and WebSocket connection.
- Server hashes the incoming token with SHA-256, looks up the entry by hash (constant-time per-byte compare on the hash bytes themselves; lookup by hash key is fine), checks expiration, updates `lastUsedAt`, accepts.
- No nonce / replay-window in v1 — over a trusted local network the threat model doesn't justify it. If we later want device-binding or short-lived signed requests, the data shape supports adding HMAC over `(timestamp, path)` later.

### Optional: iCloud Keychain sync of the host's token list

For the user who runs Issues.app as a host on more than one Mac and wants both Macs to accept the same set of tokens, the host's token-database keychain item can be marked `kSecAttrSynchronizable = true`. Then "tokens generated on Mac A also work against Mac B" without having to redo the work — the iPhone's token grants access to whichever Mac happens to be hosting at the moment.

This is opt-in, not a default. A separate "Sync tokens via iCloud" toggle in host settings turns it on. Off by default because the simplest possible model is "tokens live on the host that issued them."

### What this protects against

- Network peers reaching the listening port without a token → `401`. The load-bearing security property.
- Stolen viewer device → revoke the token from the host; the device is locked out within seconds.
- Compromised host → all tokens it issued are equally compromised; user revokes all, generates fresh ones. Same blast radius as compromised GitHub.

### What this doesn't protect against

- Someone who has the token plaintext. That's the entire point of a token; treat them like passwords.
- Someone with full access to the host's Keychain (i.e. the user themselves, or a compromise of the host). Out of scope for v1.

### Why not the alternatives

- **iCloud-synced shared secret (the previous draft).** Worked, but assumed both ends share an Apple ID. Tokens don't make that assumption — the iPhone could be signed into a different iCloud account, or the user could grant access to a friend's Mac without ever sharing iCloud. Tokens generalize cleanly.
- **CloudKit identity** — heavyweight (CloudKit container, entitlements, background sync) for a problem solved by a 43-character string.
- **Sign in with Apple** — requires server-side validation infra, overkill for one user.
- **Per-session pairing code** — works fine for one-time pairing but doesn't compose with revocation, expiration, or "this token is just for the iPhone." Tokens cover all three.

## Reachability: how Macs find each other

The app doesn't care what kind of network connects the two Macs — it just needs both ends to have a routable IP and (ideally) be on the same Bonjour broadcast domain. A few realistic scenarios:

- **Same Wi-Fi or Ethernet at home.** The default. Bonjour works, the app finds the host automatically. No setup beyond toggling the host on.
- **Different Wi-Fi networks (e.g. home and café), via [Tailscale](https://tailscale.com/) or a similar overlay (ZeroTier, Hamachi, …).** The user installs the overlay separately — Issues.app doesn't ship or manage it. Once both Macs are on the same overlay, they're effectively on the same private network as far as this feature is concerned. With Tailscale's MagicDNS enabled, Bonjour even traverses; without it, the viewer uses the manual `host:port` field.
- **Different networks, no overlay.** Won't work, and the design intentionally doesn't try to make it work — exposing a port to the public internet would require a different threat model. Tailscale (or equivalent) is the obvious user-side answer here, and the app's job is just to be usable over whatever they install.

In short: **Tailscale is one way to extend the LAN scenario to "anywhere," but the app stays neutral about how the network gets to the host.** No Tailscale CLI dependency, no detection logic, no "Tailscale required" error.

## Project metadata: `project.json`

Today the tab name in Issues.app is the **parent folder name** of the issues directory (e.g. an `issues/` folder inside `~/Developer/bluesky-migration/` becomes a tab labeled `bluesky-migration`). That's serviceable locally, where the user picked the folder and remembers what they picked. It falls apart over remote access, because the viewer sees a list of folder ids and parent names that may or may not be meaningful out of context.

The fix lives in the IssuesSkill (already updated): each `issues/` folder may contain a `project.json` at its root, holding the project's display name and links. The Issues.app reads it as just-another-file, with no special parser hookups beyond JSON decoding.

### Schema (consumer side)

Issues.app reads the file lenient-style — anything it doesn't recognize is ignored, and any missing field falls back to today's behavior. The fields it cares about for v1:

```json
{
  "name": "Bluesky Migration",
  "repository": "https://github.com/brennanMKE/Bluesky-Migration",
  "description": "Move Bluesky feeds into the new pipeline."
}
```

- `name` — the display name. Replaces the parent-folder fallback when present. Used for the tab label, the swimlane header, the remote folder picker, etc.
- `repository` — optional URL. Surfaces in the detail panel as an "Open repository" link, and in the remote folder picker as a clickable subtitle. Doesn't have to be GitHub specifically; anything that opens via `NSWorkspace` / `UIApplication.open(_:)` is fine.
- `description` — optional one-line summary. Shown beneath the name in the remote folder picker; ignored on the local side for v1 (the local side already has the user's mental model).

The schema authority is the IssuesSkill — Issues.app is just a consumer. If the skill grows new fields later, the app ignores them until it adds support, no version negotiation needed.

### Folder identity

`project.json` doesn't change how folder identity works at the protocol level — the host still uses a stable hash (e.g. of the security-scoped bookmark) as the `folderId` because that's the thing that survives display-name changes. But the *displayed* identity in every UI is `project.json`'s `name` when present. If two folders happen to share a `name`, they're still distinct via `folderId`; the picker disambiguates by also showing the parent path.

### Folder without a `project.json`

Treated as today: parent-folder name as the display name, no repository link, no description. Nothing breaks, the experience is just a hair less informative.

### Folder with a malformed `project.json`

Logged as a warning (the project's standard `os.Logger` channel), all fields treated as missing, fall back to today's behavior. We don't surface the parse error to the user — `project.json` is optional metadata, not a required manifest.

## Protocol surface (v1)

JSON over HTTP. All endpoints require the bearer token. Every folder-scoped endpoint includes the folder identifier in the path so a single connection can move between folders without reconnecting.

| Method | Path | Returns |
|---|---|---|
| `GET` | `/v1/host` | `{ displayName: String, version: Int, folderCount: Int }` |
| `GET` | `/v1/folders` | `[FolderInfo]` — one entry per folder the host is currently serving |
| `GET` | `/v1/folders/{folderId}` | `{ id, displayName, repository?, description?, root, modifiedAt: ISO8601, issueCount }` |
| `GET` | `/v1/folders/{folderId}/issues` | `[IssueMetadata]` (same shape as `Issue` minus body, plus `hasAttachments`) |
| `GET` | `/v1/folders/{folderId}/issues/{id}` | `{ metadata, body: String, attachments: [String] }` |
| `GET` | `/v1/folders/{folderId}/issues/{id}/attachments/{name}` | binary stream, content-type by extension |
| `WS`  | `/v1/events` | client subscribes per folder; server pushes scoped events |

### Folder identifiers

Folders need a stable identifier that survives moves and renames. The host's existing security-scoped bookmark is the natural anchor — hash it (SHA-256, first 16 hex chars) to get a `folderId` that's stable for as long as the bookmark stays valid. The display name comes from `project.json`'s `name` field when present, otherwise the parent folder name (today's behavior).

If the bookmark is invalidated and re-resolved (folder moved on the host's disk), the `folderId` changes; viewers see the old id disappear from `/v1/folders` and the new one appear, and they can reconnect by `project.json` `name` if they were following by name.

### WebSocket events

A single WS connection per viewer, not per folder. After connecting and authenticating, the viewer sends:

```json
{ "type": "subscribe", "folderIds": ["a3f1…", "97c0…"] }
```

The server tracks each WS's subscription set. When a folder reloads, every WS subscribed to that folder gets:

```json
{ "type": "reload",  "folderId": "a3f1…" }
{ "type": "update",  "folderId": "a3f1…", "id": "0042" }
{ "type": "delete",  "folderId": "a3f1…", "id": "0042" }
```

Viewers can `unsubscribe` and re-`subscribe` as the user opens and closes tabs without dropping the connection. Multiple viewers (Mac + iPhone) just mean N WSes in the server's subscription map; broadcast is a small for-each.

The existing FSEvents debounce on the host already coalesces save bursts into one `reload()`, so each event corresponds to one user-visible change. No risk of flooding viewers.

### Reusing the existing model layer

The `IssueMetadata` shape mirrors the existing `Issue` struct minus `bodyText`; reuse `Codable` synthesis. The viewer-side code reads through the same store-shape so swimlane / list / timeline / recent views work unchanged on both macOS and iOS.

## App changes

The repo currently builds a single macOS target. Adding the iPhone app is a parallel piece of work; this design assumes that a sibling iOS target will exist and consume the same Swift sources where possible. Anything macOS-only is gated behind `#if os(macOS)`; the protocol/model code is platform-neutral.

### New files (cross-platform unless noted)

- `Issues/Remote/RemoteServer.swift` — `NWListener` + a small route table. **macOS only** — gated behind `#if os(macOS)`. The iPhone target doesn't include this file.
- `Issues/Remote/RemoteClient.swift` — `URLSession` + WebSocket wrapper that exposes the same shape as the local file-reading path so views don't care. Cross-platform.
- `Issues/Remote/AccessToken.swift` — token type + Keychain helpers. On the host: `generate(name:expiresAt:)`, `revoke(_:)`, `list()`, hash-based `validate(plaintext:)`. On the viewer: `store(token:forHost:)`, `tokenForHost(_:)`. Cross-platform; same Keychain APIs on macOS and iOS. The host's token list is a single Keychain item (JSON-encoded) so we can persist `name` / `createdAt` / `lastUsedAt` alongside the hash without one keychain entry per token.
- `Issues/Remote/RemoteServiceBrowser.swift` — `NWBrowser` wrapper, exposes a published `[DiscoveredHost]`. Cross-platform.
- `Issues/Remote/RemoteProtocol.swift` — shared `Codable` types (`FolderInfo`, `IssueMetadata`, `RemoteEvent`, `ProjectMetadata`). Cross-platform; the host and the viewer both link this file.
- `Issues/Models/ProjectMetadata.swift` — decoder for `project.json`, with lenient decoding (unknown fields ignored, missing fields default). Read by both the local file source and the remote server when assembling `FolderInfo`.
- `Issues/Views/RemoteHostSettingsView.swift` — host-side controls: enable toggle, access-token list, folders-being-served list, connected-viewers list. **macOS only**.
- `Issues/Views/RemoteFolderPickerView.swift` — shared between macOS and iOS viewer. The "select 1 / subset / all" flow described in the UI section.

### Modified

- `Issues/State/IssueStore.swift` — generalize from "I read files" to "I read from an `IssueSource` protocol". Two impls: `LocalFolderIssueSource` (today's behavior, Mac-only since FSEvents is Mac-only; also reads `project.json` if present) and `RemoteHostIssueSource` (talks HTTP/WS; cross-platform; project metadata arrives in `FolderInfo`). The store itself becomes platform-neutral.
- `Issues/Models/TabPersistedState.swift` — record whether a tab is local or remote, plus the discovered host display name + folder id + (for remote tabs) the access-token reference for reconnect.
- `Issues/Issues.entitlements` (macOS):
  - `com.apple.security.network.server` (host role — Mac only)
  - `com.apple.security.network.client` (viewer role)
  - `com.apple.developer.networking.multicast` (Bonjour)
  - `keychain-access-groups` for sharing the access-token list across the Mac and iPhone targets, so a token entered on the iPhone is visible to the Mac viewer running under the same app group. Plan on adding `$(AppIdentifierPrefix)co.sstools.Issues` as the access group for both targets. The optional iCloud-sync of the host's token database is a separate `kSecAttrSynchronizable = true` flag on that single keychain item, set when the user toggles "Sync tokens via iCloud" on the host.
- New iOS target's entitlements (when it lands):
  - `com.apple.security.network.client` (viewer)
  - `com.apple.developer.networking.multicast` (Bonjour browse)
  - `keychain-access-groups` matching the macOS target.
- `Issues/Info.plist` (and the iOS target's) — `NSBonjourServices` array listing `_issues._tcp` so the OS lets us browse it on both platforms. iOS additionally needs `NSLocalNetworkUsageDescription` for the local-network permission prompt that fires on first browse.

### UI

#### macOS host

- A new settings sheet (or in-line settings) accessed from the toolbar:
  - **Enable hosting** toggle. When on, shows the host display name and the IP(s) it's listening on.
  - **Access tokens** list — modeled on GitHub's PAT settings page:
    - Each row: name + created date + last-used date + expiration (or "never"); a Revoke button on the row.
    - "+ Generate token" button → name field + optional expiration → reveals the token string once with Copy and "Show QR code" buttons.
    - The plaintext token isn't recoverable after the sheet closes; if the user loses it they generate a new one.
  - **Folders being served** list — every folder currently in the user's Issues.app gets a per-folder toggle. The user can host all folders, none, or a chosen subset.
  - **Connected viewers** list — currently-connected WS clients, with their reported display name (e.g. "Brennan's iPhone"), the access-token name they authenticated with, and which folders they're subscribed to. Useful for confirming a viewer connected and for spotting stale connections.

#### macOS viewer

- A new entry in the existing tab-picker / folder-picker flow: "Connect to remote host…"
  - Opens a sheet listing discovered Bonjour services (multiple per host if the user is hosting and viewing the same instance).
  - Click a host → paste-token field (skipped if the viewer already has a token cached for that host) → fetch `/v1/folders` → folder selection (see below) → confirm.
- A "remote" indicator on tabs that point to a remote folder.

#### iOS viewer

- Tab bar / sidebar entry "Remote" → same browse-then-pick flow as the macOS viewer, adapted for touch:
  - Discovered hosts in a list, with the count of folders each is serving as a subtitle.
  - Tap a host → token entry (or QR scan) → folder selection → confirm.
  - On iPhone there's no concept of multiple tabs the way the Mac has them; the user toggles between followed folders via a top-level segmented control or sidebar entry.

#### Folder selection (shared between macOS and iOS viewer)

Once a viewer has authenticated and fetched `/v1/folders`, the picker UI needs to make "one, some, or all" easy:

- **List shape** — every folder rendered as a row with a checkbox, the `project.json` `name` as the title, the `description` (if any) as the subtitle, and the repository URL as a small link icon. Folders without `project.json` show the parent folder name and no subtitle.
- **One-click All / None** — the picker has two persistent buttons at the top: "Select all" and "Select none". Tapping "Select all" checks every row in one action; this is the common "I just want to see everything from this host" case.
- **Per-row toggle** — single tap on a row toggles its checkbox. No drag-to-select, no shift-click range; the lists are short enough that one click per folder is fine.
- **Confirm** — a primary button at the bottom: "Connect to N folder(s)". Disabled when nothing is selected.
- **Persistence** — the viewer remembers the selection per-host so reconnecting doesn't re-prompt. Changes (host adds/removes folders, user wants to follow more or fewer) go through a "Manage subscriptions" sheet that re-shows the same UI.

## Phased rollout

So we can iterate without committing to the whole thing up front:

1. **Phase 0 — IssueSource refactor + `project.json` consumer.** Pull the file-reading code behind an `IssueSource` protocol with one impl (`LocalFolderIssueSource`) that's bit-for-bit equivalent to today, plus reads `project.json` and exposes its fields on the source. Tab name comes from `project.json` `name` when present, parent folder name otherwise. No remote functionality yet. Verify the local app still works as today (with the small visible win of `project.json` taking effect for tabs / detail panel).
2. **Phase 1 — Access token storage + multi-folder server.** Wire `RemoteServer` and `AccessToken`. Host-side settings show the access-token list (generate, revoke, expiration). The server enumerates the user's currently-loaded folders and serves all of them by default with per-folder toggles in settings. No client UI yet — verify with `curl --header "Authorization: Bearer iat_…" http://<ip>:port/v1/folders` from another Mac.
3. **Phase 2 — Bonjour publish + browse.** Add `NWListener.service` and `NWBrowser`. Discovery list in the host settings (connected viewers) and the viewer (browse-and-pick).
4. **Phase 3 — RemoteHostIssueSource + remote tabs + folder picker (macOS viewer).** Wire the second `IssueSource` impl and the shared `RemoteFolderPickerView` with select-all / select-none / per-row toggles. New tab type that points at a (host, folder) pair. Token paste flow + caching per host. All four views (swimlane / timeline / list / recent) work against it for free.
5. **Phase 4 — Live updates over WebSocket.** Wire the `/v1/events` channel with subscribe/unsubscribe semantics. Host fans out reload/update events to every subscribed viewer.
6. **Phase 5 — iOS target.** Add the iPhone target sharing the model + remote + view layer. The folder picker re-uses Phase 3's `RemoteFolderPickerView`. Adapt the navigation shell for touch; add QR-code token transfer (host renders, iPhone scans). The data path is identical to the macOS viewer.
7. **Phase 6 — Polish.** Reconnect logic, disconnect indicator, expired-token UI, network-change pause behavior, error states, optional iCloud-sync of the host's token database.

Each phase is independently shippable and testable. Phase 5 (the iOS target) is large but additive; it depends on phases 0–4 being stable but doesn't change them. We can stop at any phase if it turns out one of the assumptions is wrong.

## Open questions for iteration

These are the calls I want a second pass on before committing:

1. **Default bind: all interfaces vs. private-network heuristic.** Listening on every non-loopback interface is the simplest design and the auth layer makes it safe in principle. But on a coffee-shop Wi-Fi the port is visible (just unauthenticated) to other patrons. Alternative: by default bind only to interfaces whose addresses fall in private/link-local/overlay ranges (RFC1918, RFC4193, `100.64/10`, etc.) and require an explicit toggle to listen on public-looking interfaces. Leaning toward the heuristic; it's a small amount of code and a meaningful default.
2. **Token rotation cadence.** Should we suggest expirations by default (e.g. "30 / 90 / never" buttons in the generation sheet)? GitHub leans toward suggesting expiration; the simpler "never" is fine for a single-user setup but worse hygiene if a token leaks. Probably show three buttons + a custom date picker; default to "never" so the casual case is one fewer click.
3. **Should the viewer ever auto-connect on launch?** If a previous session was on a remote folder, do we re-resolve the Bonjour name and reconnect, or stay disconnected until the user clicks? My instinct: try once with a 2-sec timeout, fall back to disconnected state. Token comes from the viewer's Keychain so reconnect doesn't re-prompt.
4. **Attachment streaming.** Large screen recordings (#0072 had a 4.5 MB `.mov`) over HTTP is fine, but the existing inline thumbnail path uses `NSImage(contentsOf:)` synchronously. Remote attachments need an async fetch with placeholder UI on both platforms. Either piggyback on the Quick Look path from #0073 (which already has async thinking — and has an iOS analogue via `QLPreviewController`) or add an explicit async layer in `AttachmentThumbnailView`. Worth a separate issue.
5. **Naming.** "Host" / "viewer" or "server" / "client"? Or "publish" / "subscribe"? Pick one set and use it consistently in UI + code. Tentative: **Host** (the Mac with the folders) and **Viewer** (the device — Mac or iPhone — connecting to it).
6. **Bonjour over the local Wi-Fi network the user doesn't realize they're on.** If the user toggles host on at home but later joins a coworking Wi-Fi, the service is still publishing. Should the app pause publishing on network changes and require a re-toggle? Probably yes — `NWPathMonitor` can drive this. Cheap to do, prevents accidental exposure.
7. **Folder-id stability across sessions.** The proposal is `SHA-256(securityScopedBookmark)[..16hex]`. That's stable as long as the bookmark resolves to the same path; it changes when the user re-locates a missing folder. The viewer also remembers `project.json`'s `name` and can fall back to "find by name" on reconnect, which is more user-meaningful than the bookmark hash anyway.
8. **What does `project.json`'s `repository` link do exactly?** Open in default browser? Copy to clipboard? Both via a small popover menu? Probably the simplest: button label "Open repository" → `NSWorkspace.open` / `UIApplication.open(_:)`. Right-click / long-press → copy URL. No menu.
9. **iPhone-specific UI for the no-tabs world.** macOS uses tabs to host multiple folders; iOS likely uses a sidebar (iPad) or a top-level segmented control / list (iPhone). Decide whether the iPhone view follows one folder at a time (with a switcher) or mirrors the Mac's "all open simultaneously" via a navigation stack. Doesn't change the protocol, only the UI shell.
10. **Connected-viewers list privacy.** The host sees which viewers are connected. What does the viewer report as its display name? Default: device name (`Brennan's iPhone`). Sensitive enough to want a "report as: ___" override? Probably not in v1; the host is the same user.
11. **QR-code transfer scope.** Should the QR encode just the token, or also the host address + display name so the iPhone can connect in one scan instead of "scan token, then pick from Bonjour list"? Encoding `iat_…@hostname:port` is short enough to QR-encode reliably. Leaning yes — it's a meaningfully better UX.

## What this design *isn't* doing

A note on restraint, since the project's CLAUDE.md is explicit about not adding more than the task needs:

- **No JSON cache, no on-disk index.** The remote source streams from the host, the same way the local source streams from the filesystem. Nothing persists on the viewer.
- **No write semantics.** Editing the same `0042.md` from two Macs at once is a real problem we're not solving in v1. Read-only sidesteps it entirely.
- **No multi-user shared link.** Single user, single Apple ID assumption is load-bearing. If we ever want to share with someone else, the auth model needs a redesign.
- **No background process.** Server lives inside `Issues.app`. Quitting the app stops serving. That matches #0074's single-window-on-close model and avoids LaunchAgents/daemons.

## What I'd like feedback on first

1. **The IssueSource refactor + `project.json` consumer (Phase 0).** Big enough to want a sanity check before doing it. Also load-bearing for the iOS viewer — it needs the same protocol abstraction.
2. **Token model details.** The GitHub-PAT shape (`iat_<base64url-32>`, hashed at rest, named, optionally expiring) feels right; worth pressure-testing whether single-keychain-item-with-JSON-blob is better than one keychain entry per token. Single item is simpler; many items is more granular for revocation auditing.
3. **Default bind behavior.** All interfaces vs. private-network heuristic — see Open Question 1.
4. **Live updates: WebSocket vs. server-sent events vs. long polling.** I lean WS — its bidirectional shape (subscribe / unsubscribe messages from the viewer) suits the multi-folder subscription model. SSE would force the subscription set into the URL and require reconnects to change it.
5. **`project.json` schema confirmation.** The doc assumes `name` / `repository` / `description`; if the IssuesSkill chose different field names, this should track. Worth a glance at the actual schema before Phase 0.
6. **Whether to start with Phase 0+1 in one PR or split.** Phase 0 (IssueSource refactor + project.json consumer) is invasive but contained; Phase 1 (token + server + multi-folder enumeration) is additive. I lean separate PRs so the refactor lands and bakes before the network code arrives.
