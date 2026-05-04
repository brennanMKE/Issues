# Issues

A native macOS viewer for the markdown-based issue tracking format used by
[IssuesSkill](https://github.com/brennanMKE/IssuesSkill) — a Claude Code skill
that files, updates, and queries bugs directly from a conversation.

The skill is the editor; this app is the live dashboard. Tell Claude *"file
this as a bug"* and a markdown file appears in `issues/`. The app sees the
change and updates within ~150 ms — no JSON regeneration, no page refresh, no
manual sync.

## How it fits together

```
┌──────────────────────┐    writes / edits    ┌──────────────────┐
│  Claude Code         │ ───────────────────► │  issues/0042.md  │
│  + IssuesSkill       │                      │  issues/0043.md  │
│                      │                      │  issues/...      │
└──────────────────────┘                      └────────┬─────────┘
                                                       │ FSEvents
                                                       ▼
                                              ┌──────────────────┐
                                              │  Issues.app      │
                                              │  (this project)  │
                                              └──────────────────┘
```

Both sides treat the markdown files as the source of truth. There is no
database, no `issues.json`, no build step.

## Features

- **Four views** of the same dataset:
  - **Swimlanes** — issues grouped by primary module.
  - **Timeline** — Gantt-style, one bar per issue from `First seen` to `Closed`.
  - **List** — sortable table.
  - **Recent** — sorted by file modification time, so the issue you (or
    Claude) just touched is at the top.
- **Live file watching.** Edits made by Claude — or by you in any editor —
  show up in the UI within ~150 ms via FSEventStream.
- **Filters** by Status, Module, and Platform. Plain-click a status pill to
  filter to one; option-click to add or remove statuses from a multi-status
  selection.
- **Detail panel** with the issue's metadata, description, and a link that
  opens the underlying `.md` file in your default editor.
- **Folder memory.** Pick an `issues/` folder once via the open panel; the
  app remembers it (security-scoped bookmark) and lists prior folders on
  next launch.

## Markdown format

Each `NNNN.md` file is a standalone issue. The required header looks like:

```markdown
# 0042 — Title with an em-dash

| | |
|---|---|
| **Status**     | open |
| **Module**     | BlueskyFeed |
| **Platform**   | iOS |
| **First seen** | 2026-04-29 |

## Description

What's wrong, in plain prose.
```

`Closed` is optional. `Status` is one of `open`, `in-progress`, `resolved`,
`closed`, `wontfix`. The em-dash in the title is U+2014 (`—`), not a hyphen
— the parser is strict about this.

The IssuesSkill writes files in this exact format; the app reads them. Spec
details live in [PRD.md](PRD.md).

## Requirements

- macOS 15+ (the project currently targets macOS 26.4).
- Xcode 16+ to build.

## Build & run

```sh
xcodebuild -project Issues.xcodeproj -scheme Issues -configuration Debug -destination 'platform=macOS' build
```

Or open `Issues.xcodeproj` in Xcode and run. On first launch, click "Add
folder…" and pick an `issues/` directory — typically inside a project that
already has IssuesSkill installed.

## Logs

All app and watcher activity routes through `os.Logger` under subsystem
`co.sstools.Issues`. To stream live activity:

```sh
log stream --predicate 'subsystem == "co.sstools.Issues"' --level debug
```

## Dependencies

- [brennanMKE/Watcher](https://github.com/brennanMKE/Watcher) — wraps
  FSEventStream behind a Swift Concurrency `Session` API.
