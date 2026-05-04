# AI Integration

Issues.app pairs with the [IssuesSkill](https://github.com/brennanMKE/IssuesSkill) Claude Code skill. The skill writes; the app reads. Together they give you a hands-free way to capture, triage, and update issues while you stay in your editor or terminal.

## How the loop works

When you describe a bug, regression, or finding to Claude — anywhere a Claude Code session is running with IssuesSkill installed — the skill drops or updates a `NNNN.md` file in the project's `issues/` folder. The skill handles the next available number, the title format with the U+2014 em-dash, the metadata table, and the standard status vocabulary.

Issues.app is watching that same folder. A FSEventStream-backed watcher notices the change, a 150 ms debounce collapses save bursts into a single event, and the parser re-reads only what changed. By the time you've switched windows the new or updated issue is on screen, in the right swimlane, with the right status pill count.

## The author rule

The folder is meant to be edited by the skill, by your editor, or by direct git operations — not by the app itself. Issues.app is read-only by design. There is no inline editor, no "mark resolved" button, and no field-level commit. If you want to change something, edit the file (or ask Claude to).

This split keeps the markdown file as the single source of truth. Every change shows up in `git log` with a real diff, attributed to whoever made it.

## When not to edit by hand

For routine changes — filing a new issue, updating status, attaching a screenshot — let the skill do it. It enforces the conventions automatically. Hand-edit only when you specifically want to.
