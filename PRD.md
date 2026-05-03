# Mac App: Issue Viewer — PRD

## Context

There is an existing web-based issue tracker at `/Users/brennan/Developer/ReactNative/Bluesky-Migration/issues/`:

- Each issue is an `NNNN.md` file (4-digit zero-padded). Metadata lives in a markdown table (Status, Module, Platform, First seen, optional Closed). The first paragraph after `## Description` is shown in the visualization.
- A Python script (`generate.py`) parses the markdown, emits `issues.json` and `issues.js`, and the static `index.html` reads the JS file to render swimlane / timeline / list views with status, module, and platform filters.

The friction: every change to a markdown file requires re-running `generate.py` before the web page updates. We want a native Mac app that **reads markdown directly and watches the folder**, eliminating the JSON regeneration step entirely. v1 targets feature parity with the web page; we'll add things (full markdown rendering, inline attachments, search) once the core is solid.

The Xcode project at `/Users/brennan/Developer/brennanMKE/Issues/` is already a fresh SwiftUI macOS scaffold — verified in `project.pbxproj`: `SDKROOT = macosx`, `MACOSX_DEPLOYMENT_TARGET = 26.4`, `ENABLE_APP_SANDBOX = YES`, `ENABLE_USER_SELECTED_FILES = readonly`. Source folders use `PBXFileSystemSynchronizedRootGroup`, so adding new `.swift` files on disk auto-registers them with the target — no `pbxproj` edits for sources.

## Decisions locked in

- **Folder source:** user picks at first launch via `NSOpenPanel`; bookmarks persisted across launches; launch screen lists remembered folders + "Add folder…".
- **Read-only.** No editing in v1.
- **Parity-first.** Same three views, same filters, same dark color scheme. No search, no inline attachments, no full-body markdown rendering yet.
- **Min target:** macOS 15+ (project is already at 26.4, well above).
- **Dark mode only** — matches the web UI; light theme is a future enhancement.

## Project changes (Xcode)

1. **Add entitlements file** at `Issues/Issues.entitlements`:
   ```xml
   <?xml version="1.0" encoding="UTF-8"?>
   <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
   <plist version="1.0">
   <dict>
       <key>com.apple.security.app-sandbox</key><true/>
       <key>com.apple.security.files.user-selected.read-only</key><true/>
       <key>com.apple.security.files.bookmarks.app-scope</key><true/>
   </dict>
   </plist>
   ```
   The `bookmarks.app-scope` key is required for security-scoped bookmarks to persist across launches; the Xcode auto-entitlements do not include it.
2. **Edit** `Issues.xcodeproj/project.pbxproj` — add `CODE_SIGN_ENTITLEMENTS = Issues/Issues.entitlements;` to **both** the Issues target's Debug and Release `XCBuildConfiguration` blocks. Also delete `REGISTER_APP_GROUPS = YES;` from those blocks (we don't use app groups).
3. **Delete** `Issues/ContentView.swift` (placeholder).
4. **Modify** `Issues/IssuesApp.swift` — point `WindowGroup` at `RootView()`, set `.defaultSize(width: 1200, height: 800)`, apply `.preferredColorScheme(.dark)`.

## File layout (all under `Issues/`)

```
Models/
  Issue.swift
  IssueStatus.swift
Services/
  MarkdownIssueParser.swift
  FolderBookmarkService.swift
  RememberedFolder.swift
  FolderWatcher.swift
State/
  IssueStore.swift
Theme/
  Theme.swift             // Color palette + hex initializer
  StatusColor.swift       // IssueStatus -> foreground/background colors
Views/
  RootView.swift
  FolderPickerView.swift
  MainView.swift
  HeaderView.swift
  StatsBarView.swift
  ToolbarView.swift
  SwimlaneView.swift
  TimelineView.swift
  ListView.swift
  DetailPanelView.swift
  IssueCardView.swift
  StatusBadgeView.swift
  StatusDotView.swift
  FlowLayout.swift        // custom Layout for wrapping cards
```

## Data model

```swift
enum IssueStatus: String, CaseIterable, Hashable, Codable, Sendable {
    case open, inProgress = "in-progress", resolved, closed, wontfix
    init(raw: String)               // lowercases + replaces whitespace with "-"; falls back to .open
    var displayName: String         // "Open", "In Progress", ...
    static let displayOrder: [IssueStatus] = [.open, .inProgress, .resolved, .closed, .wontfix]
}

struct Issue: Identifiable, Equatable, Hashable, Sendable {
    let id: String                  // "0001"
    let title: String
    let status: IssueStatus
    let module: String              // raw, may contain " / "
    let platform: String            // "iOS" | "macOS" | "iPadOS" | "All" | other
    let firstSeen: Date?
    let firstSeenRaw: String
    let closed: Date?
    let closedRaw: String
    let description: String         // newlines preserved
    let fileURL: URL
    var modules: [String] { /* split " / ", trim, drop empties */ }
    var primaryModule: String { modules.first ?? "Unknown" }
}
```

## Markdown parser — `Services/MarkdownIssueParser.swift`

Pure, testable. Mirrors the regex set from `generate.py`:

- **Filename gate:** `^\d{4}\.md$` — id is the 4-digit string.
- **Title:** `^# \d+ — (.+)$` (multiline, anchors-match-lines). Em-dash is U+2014; verified in real files (e.g. `0001.md`).
- **Field extractor:** `\|\s*\*\*<NAME>\*\*\s*\|\s*(.+?)\s*\|` — run for Status, Module, Platform, First seen, Closed.
- **Description:** `## Description\s+(.+?)(?=\n##|\Z)` (dot-matches-line-separators). Trim leading/trailing whitespace; preserve internal newlines.
- **Date:** `DateFormatter` with `dateFormat = "yyyy-MM-dd"`, `Locale(identifier: "en_US_POSIX")`, UTC. Empty raw ⇒ `nil`.
- Pre-compile each `NSRegularExpression` as `static let` — these run for every file on every reload.

API:
```swift
enum MarkdownIssueParser {
    static func parse(fileURL: URL) throws -> Issue?
    static func parse(fileURL: URL, contents: String) -> Issue?  // pure, for tests
}
```

Add tests in `IssuesTests/` covering: missing Closed, missing Description, multi-module split, em-dash title, status case-folding, malformed dates.

## Folder access — `Services/FolderBookmarkService.swift`

`@Observable` `@MainActor` class.

- `RememberedFolder { displayPath: String, bookmarkData: Data, lastUsed: Date }` — persisted as JSON in `UserDefaults.standard` under key `rememberedFolders`.
- Bookmark create: `url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess])`.
- Bookmark resolve: `URL(resolvingBookmarkData:options:[.withSecurityScope], …, bookmarkDataIsStale: &stale)`. If stale and resolve succeeded, immediately re-create the bookmark from the resolved URL. If resolve failed, surface error and offer "Locate folder…".
- `presentOpenPanel()` configures `NSOpenPanel` with `canChooseFiles = false`, `canChooseDirectories = true`, `allowsMultipleSelection = false`. Run on main actor.
- Pair `startAccessingSecurityScopedResource()` / `stop…` carefully; `IssueStore` owns the lifetime for the active folder.

## File watcher — `Services/FolderWatcher.swift`

Use `DispatchSource.makeFileSystemObjectSource` (not `FSEventStream`) — single directory, lower latency, simpler lifecycle.

- `open(url.path, O_EVTONLY)` for an FD.
- Event mask: `.write | .delete | .rename | .extend | .attrib`.
- **Debounce:** keep a `DispatchWorkItem`; cancel-and-reschedule with 150ms delay on each event so save bursts collapse into one reload.
- `setCancelHandler { close(fd) }`. Stop on `deinit` and on folder switch.
- If the watched folder itself is deleted/renamed, the FD goes invalid — surface that and bounce back to `FolderPickerView`.

## State — `State/IssueStore.swift`

```swift
@Observable @MainActor
final class IssueStore {
    enum ViewMode: String, CaseIterable { case swimlane, timeline, list }
    enum SortColumn: String { case id, status, title, module, platform, firstSeen }

    let folderURL: URL
    private(set) var issues: [Issue] = []     // sorted by id asc
    private(set) var loadError: String?

    var statusFilter: IssueStatus? = nil
    var moduleFilter: String? = nil
    var platformFilter: String? = nil
    var viewMode: ViewMode = .swimlane
    var selectedIssueID: String? = nil
    var sortColumn: SortColumn = .id
    var sortAscending: Bool = true

    func start(); func stop(); func reload()
    var filteredIssues: [Issue]
    var selectedIssue: Issue? { issues.first { $0.id == selectedIssueID } }
    func groupedByPrimaryModule(_ list: [Issue]) -> [(module: String, issues: [Issue])]
    var uniqueModules: [String]      // post-split, sorted, unique
    var uniquePlatforms: [String]
    var statusCounts: [IssueStatus: Int]   // computed from unfiltered issues (matches web)
    func toggleSelection(_ id: String); func deselect()
}
```

**Filtering logic (port from `issues.js` `filtered()` — must match exactly):**
```swift
issues.filter { issue in
    if let s = statusFilter, issue.status != s { return false }
    if let m = moduleFilter, !issue.modules.contains(m) { return false }
    if let p = platformFilter, issue.platform != p, issue.platform != "All" { return false }
    return true
}
```

**`reload()`**: list dir → filter `^\d{4}\.md$` → parse each → sort by id → assign. If `selectedIssueID` is no longer present, set nil. Stats counts use the unfiltered array.

For ~60 files this runs on the main thread in milliseconds. Don't optimize prematurely.

## Theme

`Color` extension with hex initializer. Palette ported from CSS variables:

```
appBackground       #0d1117      statusOpen          #f59e0b
appBackgroundCard   #161b22      statusInProgress    #3b82f6
appBackgroundHover  #1c2230      statusResolved      #10b981
appBorder           #30363d      statusClosed        #6b7280
appText             #e6edf3      statusWontfix       #ef4444
appMuted            #8b949e
appAccent           #0085ff      // also used for AccentColor.colorset
appAccentDim        #0059b3
```

`IssueStatus` extension: `foreground`, `background15` (`.opacity(0.15)` for badges), `background22` (`.opacity(0.22)` for timeline bars).

## View hierarchy

**`RootView`** owns `FolderBookmarkService` and the optional `IssueStore`. If no store, show `FolderPickerView`; otherwise `MainView`. Switching folders sets store to nil.

**`FolderPickerView`**: list of remembered folders (button rows: folder name + muted parent path + last-used date; context menu "Forget"). "Add folder…" button calls `bookmarks.presentOpenPanel()` then `bookmarks.remember(url:)` then hands the URL up.

**`MainView`** layout (no `NavigationSplitView` — the web isn't sidebar/list/detail, it's stacked + sliding):
```
VStack(spacing: 0) {
    HeaderView                  // sticky title + folder name + "Switch folder…"
    StatsBarView                // colored dots + counts (skip rows with count 0, except "All")
    ToolbarView                 // status pills, module/platform pickers, view-mode segmented
    HStack(spacing: 0) {
        contentArea             // Swimlane | Timeline | List, depending on viewMode
        if store.selectedIssue != nil {
            DetailPanelView.frame(width: 360).transition(.move(edge: .trailing))
        }
    }.animation(.easeInOut(duration: 0.2), value: store.selectedIssueID)
}.preferredColorScheme(.dark)
```

Background-tap-to-deselect: in the `contentArea`, layer a `Color.clear.contentShape(Rectangle()).onTapGesture { store.deselect() }` *behind* the actual content via `ZStack`. Cards have their own `.onTapGesture` which consumes the tap before it bubbles.

**`HeaderView`**: sticky 52pt bar. Title `"<RepoName> — Issues"` (derive `<RepoName>` from `folderURL.deletingLastPathComponent().lastPathComponent`); the word "Issues" is `.appAccent`. Trailing "Switch folder…" button.

**`StatsBarView`**: `HStack` with 8pt dots + bold count + muted label for `[.all] + IssueStatus.displayOrder`.

**`ToolbarView`**:
- Status pills: capsule buttons with status-tinted background/border when active. Clicking the active pill resets to nil.
- Module / Platform: `Picker(selection:)` with `.menu` style, "All …" option for nil.
- View mode: custom three-button capsule on the right (segmented `Picker` doesn't match the dim accent style).

**`SwimlaneView`**: `ScrollView(.vertical)` → `LazyVStack` of module groups. Each group: small uppercase label + `FlowLayout(spacing: 6)` of `IssueCardView`. (`FlowLayout` is a ~30-line `Layout` conformance — variable card widths preclude `LazyVGrid`.)

**`IssueCardView`**: `HStack` of 7×7 status dot, `#NNNN` muted heavy 11pt, title 12pt with `.lineLimit(1).truncationMode(.tail)`. Frame `minWidth: 120, maxWidth: 300`. Selected: accent border + `appAccent.opacity(0.08)` fill. `.help(issue.title)` for hover tooltip.

**`ListView`**: native SwiftUI `Table` with selection binding to `store.selectedIssueID`. Columns: # (60pt), Status (badge), Title, Module (muted, truncated), Platform (80pt), Filed (100pt). Pipe `sortOrder` into a sort applied to `store.filteredIssues` before rendering. `Table` gives clickable headers and arrows for free.

**`TimelineView`**: most involved.
- `TimelineGeometry`: `minDate = earliestFirstSeen - 1d`, `maxDate = max(latestClosed, today) + 2d`, `dispMaxDate = minDate + max(14d, maxDate - minDate)`.
- Weekly ticks via `Calendar.nextDate(after:matching: DateComponents(weekday: 2))` iterating to `dispMaxDate`.
- Layout: 180pt label gutter + flexible track inside `ScrollView(.horizontal)`. `GeometryReader` over the track yields width; bars positioned with `.offset(x: width * fraction)`. Each module = a row stack of bars (bars stacked vertically by index within group).
- Bars: status color at `.opacity(0.22)` fill, 1pt status-color border, 10pt corner radius. `#NNNN` label inside in same color, 10pt heavy. End date for empty `closed` ⇒ `today + 1d`. Hover/selected: `.scaleEffect(y: 1.15)`.
- Min track width: 600pt. "today" line as a vertical accent rule.

**`DetailPanelView`** (360pt, scrollable):
- Sticky ✕ close button (`store.deselect()`) top-right.
- `#NNNN` heavy muted, then title 15pt semibold.
- 2-column `Grid`: Status (badge), Module, Platform, Filed (em-dash if empty), Closed (row only shown when set).
- Divider, then `Text(issue.description)` 12pt muted, `.fixedSize(horizontal: false, vertical: true)` so newlines preserve.
- "NNNN.md ↗" link → `NSWorkspace.shared.open(issue.fileURL)`. Works under sandbox because the URL is reached through the active security scope.

## Selection flow

Single source of truth: `store.selectedIssueID`. All selectable views use the store binding (or `toggleSelection`). The 0.2s slide animation hangs off the parent `HStack`'s `.animation(_:value:)`.

## Verification

Point at `/Users/brennan/Developer/ReactNative/Bluesky-Migration/issues/`:

1. **First launch:** `defaults delete co.sstools.Issues`, run, expect empty `FolderPickerView` → "Add folder…" → choose folder → swimlane renders ~60 issues.
2. **Stats accuracy:** counts match the dataset; rows with count 0 hidden (web behavior). Cross-check with `jq 'group_by(.status) | map({status: .[0].status, n: length})' issues.json`.
3. **All three views render** correctly — switch with toolbar, selection persists across switches.
4. **Filters AND-combine.** Status pill `Open` + Module `BlueskyFeed` narrows further; Platform `iOS` keeps issues whose platform is `iOS` *or* `All`. Click active status pill again to clear.
5. **Detail panel:** click an issue → slides in within ~200ms. Try `0001` (has Closed) and `0011` (no Closed) — Closed row only shows for `0001`. Description preserves newlines (try `0034`'s numbered list). `0001.md ↗` opens the file.
6. **File watcher (the headline feature):** while app runs, in another editor:
   - Edit `0046.md` Status `open`→`in-progress`, save — UI updates within ~1s.
   - Create `0061.md` (copy template), save — appears within ~1s.
   - Delete `0061.md` — disappears within ~1s.
   - Burst: `for i in 1 2 3 4 5; do touch 0001.md; done` — debounce collapses to one reload.
7. **Switch folder** from header — returns to `FolderPickerView` with prior folder listed.
8. **Restart restores remembered folders** ordered by `lastUsed` desc.
9. **Stale bookmark:** rename folder outside the app → relaunch → click remembered entry → clear error + "Locate folder…" path.
10. **Sandbox check:** `codesign -d --entitlements - <built .app>` lists all three keys.

## Critical files

- `Issues/IssuesApp.swift` — modify `@main` to host `RootView`.
- `Issues/Issues.entitlements` — new; sandbox + user-selected read-only + app-scope bookmarks.
- `Issues.xcodeproj/project.pbxproj` — add `CODE_SIGN_ENTITLEMENTS` to both Issues build configs; remove `REGISTER_APP_GROUPS`.
- `Issues/Services/MarkdownIssueParser.swift` — correctness lives here; mirror the four regexes from `generate.py`.
- `Issues/Services/FolderBookmarkService.swift` — security-scoped bookmarks, the part most likely to misbehave under sandbox.
- `Issues/Services/FolderWatcher.swift` — `DispatchSource` + 150ms debounce; the live-update behavior the user will judge the app on.
- `Issues/State/IssueStore.swift` — `@Observable` store; filtering/grouping/selection logic.

## Out of scope (v1)

Document with TODOs in code; revisit after v1:

- Search box across title + description (and optionally body).
- Inline rendering of attachments (read sibling `NNNN/` directory, resolve relative image paths).
- Full-body markdown rendering (Steps to reproduce, Notes, etc.) via `AttributedString(markdown:)`.
- Editing markdown (would require switching to user-selected read-write).
- Light theme.
- Per-folder remembered filters / view mode.
