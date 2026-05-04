# Tabs

Each tab in Issues.app is bound to one folder of issue files. You can have several folders open at once — one per project, say — and switch between them without losing scroll position, filter state, or the current selection inside each tab.

## Opening a folder

Click the `+` button at the right edge of the tab bar to pick a folder. The picker uses the standard macOS open panel and remembers your choice across launches via a security-scoped bookmark, so you only grant access once per folder.

## Reordering

Tabs reorder Safari-style. Press and drag a tab horizontally; the other tabs slide out of the way to show the drop target. Release to commit. The order is saved with the rest of your tab state.

## Context menu

Right-click any tab to get:

- **Close** — closes the tab without affecting others.
- **Close Other Tabs** — keeps the right-clicked tab and closes the rest.
- **Reveal in Finder** — opens the underlying folder in Finder.
- **Reload** — re-reads the folder immediately, bypassing the file watcher debounce.

## Keyboard

| Shortcut | Action |
|---|---|
| Cmd+1 … Cmd+9 | Jump to tab N |
| Cmd+Shift+Left | Previous tab |
| Cmd+Shift+Right | Next tab |
| Cmd+T | New tab (opens folder picker) |
| Cmd+W | Close current tab |
| Cmd+R | Reload current tab |

Cmd+1 through Cmd+9 are positional: Cmd+5 always means the fifth tab from the left, regardless of which tab is currently active.
