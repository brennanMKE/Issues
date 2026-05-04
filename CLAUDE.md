# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

**Issues.app** — a native macOS SwiftUI app that watches a folder of `NNNN.md` issue files and renders them as swimlane / timeline / list / recent views. It is the live dashboard for the [IssuesSkill](https://github.com/brennanMKE/IssuesSkill) Claude Code skill: the skill writes/edits markdown, the app reflects it within ~150 ms.

The markdown files **are** the source of truth. There is no JSON, generated artifact, or index to keep in sync. Do not introduce one.

## Build & run

```sh
xcodebuild -project Issues.xcodeproj -scheme Issues -configuration Debug -destination 'platform=macOS' build
```

Run tests:

```sh
xcodebuild -project Issues.xcodeproj -scheme Issues -destination 'platform=macOS' test
# Single test class:
xcodebuild -project Issues.xcodeproj -scheme Issues -destination 'platform=macOS' test -only-testing:IssuesTests/MarkdownIssueParserTests
```

Stream live logs (subsystem is `co.sstools.Issues`, taken from the bundle identifier):

```sh
log stream --predicate 'subsystem == "co.sstools.Issues"' --level debug
```

Reset persisted state (remembered folders + bookmarks live in `UserDefaults` under key `rememberedFolders`):

```sh
defaults delete co.sstools.Issues
```

## Project structure (Xcode quirks worth knowing)

- Source folders under `Issues/` use `PBXFileSystemSynchronizedRootGroup`. Adding a new `.swift` file on disk auto-registers it with the target — **do not edit `project.pbxproj` to add sources**. Edit `project.pbxproj` only for build settings, entitlements, or package dependencies.
- App is sandboxed with read-only user-selected files plus app-scope bookmarks. Entitlements live at `Issues/Issues.entitlements`; the `com.apple.security.files.bookmarks.app-scope` key is required for security-scoped bookmarks to persist across launches and is not part of Xcode's default set.
- Deployment target is macOS 26.4 (project min is macOS 15+). Anything else built against older SDKs will fail to compile.

## Architecture

The app is intentionally small. The data flow is one-directional and lives almost entirely in `Issues/State/IssueStore.swift`:

```
FolderBookmarkService → URL → IssueStore.start()
                                 │
                                 ├── FolderWatcher (debounced FSEvents) ──┐
                                 │                                         │
                                 └── reload() ── MarkdownIssueParser ◄─────┘
                                                  │
                                                  └── [Issue] → @Observable → SwiftUI views
```

- **`Models/`** — `Issue`, `IssueStatus`. `IssueStatus.init(raw:)` lowercases and replaces whitespace with `-` before matching, falling back to `.open`. `Issue.modules` splits the raw module string on ` / `.
- **`Services/MarkdownIssueParser.swift`** — pure, regex-based. The four regexes (filename gate `^\d{4}\.md$`, title with U+2014 em-dash, field-row extractor, description block) are pre-compiled as `static let`. The em-dash in titles is **U+2014, not a hyphen** — the parser rejects hyphens by design. Add tests in `IssuesTests/MarkdownIssueParserTests.swift` for any parser change.
- **`Services/FolderWatcher.swift`** — wraps the [Watcher](https://github.com/brennanMKE/Watcher) package (FSEventStream behind a Swift Concurrency `Session` API). 150 ms debounce so save bursts collapse into one reload.
- **`Services/FolderBookmarkService.swift`** — security-scoped bookmarks persisted as JSON in `UserDefaults`. Pair `startAccessingSecurityScopedResource()` / `stop…` carefully; `IssueStore` owns the lifetime for the active folder. On stale bookmarks, re-create from the resolved URL; on resolve failure, surface "Locate folder…".
- **`State/IssueStore.swift`** — `@Observable` `@MainActor` class. Single source of truth for `selectedIssueID`, filters, view mode, sort order. `reload()` lists the directory, filters by `^\d{4}\.md$`, parses each file, sorts by id. For ~60 files this runs on the main thread in milliseconds — don't optimize prematurely.
- **`Views/`** — `RootView` shows `FolderPickerView` if no store, else `MainView`. `MainView` is a vertical stack (no `NavigationSplitView`): Header, StatsBar, Toolbar, then `HStack { contentArea, optional DetailPanel }`. View mode (`swimlane | timeline | list | recent`) swaps the content area.

### Filtering rules (must stay exact)

```swift
issues.filter { issue in
    if let s = statusFilter, issue.status != s { return false }
    if let m = moduleFilter, !issue.modules.contains(m) { return false }
    if let p = platformFilter, issue.platform != p, issue.platform != "All" { return false }
    return true
}
```

Note the `"All"` short-circuit on platform — an issue with platform `All` matches every platform filter. Status counts in the stats bar are computed from the **unfiltered** list so the bar doesn't shift as filters change.

### Theme

Adaptive light/dark — the window honors the system color scheme. Palette is in `Issues/Theme/Theme.swift`; each `Color.app*` constant is a `Color(light:dark:)` pair backed by an `NSColor` dynamic provider. Status colors are in `StatusColor.swift` and exposed as `IssueStatus.foreground`, `.background15` (badges), `.background22` (timeline bars); status hues are shared across both schemes. There is no in-app appearance toggle yet — that's tracked separately.

## Issue tracking for this repo

This project tracks **its own** bugs in `project-issues/` — not `issues/`. The folder name avoids a case-insensitive filesystem clash with the `Issues/` Xcode source folder. The local guide for filing/updating is `project-issues/Issues.md`.

When filing or querying issues for this repo:
- Use `project-issues/NNNN.md`.
- Image attachments go in `project-issues/NNNN/foo.png`, referenced with relative paths.
- Status vocabulary is the standard IssuesSkill set (`open`, `in-progress`, `resolved`, `closed`, `wontfix`).
- Never mark an issue `resolved`/`closed`/`wontfix` without explicit user confirmation.

The unrelated file `Issues.md` at the repo root is the **legacy** skill guide from before IssuesSkill existed; treat it as historical and don't update it. Authoritative guide is `project-issues/Issues.md`.

## Out of scope (v1)

Documented in `PRD.md`; do not silently introduce these without discussion: search across title/description, inline attachment rendering, full-body markdown rendering for Steps/Notes, write access, per-folder remembered filters. (Light theme was originally out of scope; #0020 made the palette adaptive.)
