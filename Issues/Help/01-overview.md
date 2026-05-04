# Overview

Issues.app is a native macOS dashboard for a folder of plain markdown issue files. Each file is a `NNNN.md` document with a four-digit numeric prefix, a single H1 title using a U+2014 em-dash, a small metadata table, and a free-form description below.

The markdown files **are** the source of truth. There is no JSON index, no database, and no generated artifact to keep in sync. The app reads the folder, parses the markdown, and renders it. Anything you can see in the UI came directly from a file you can open in any text editor.

## How it fits with IssuesSkill

Issues.app is the live companion to the [IssuesSkill](https://github.com/brennanMKE/IssuesSkill) Claude Code skill. The skill is the writer: when you describe a bug or ask Claude to log a finding, the skill creates or edits a markdown file under your project's `issues/` folder. Issues.app is the reader: it watches that folder with FSEvents, debounces save bursts, and reflects changes within roughly 150 milliseconds.

The two pieces are deliberately separate. The skill never queries the app, and the app never writes back to disk. If you need to triage on the road without Claude running, you can still browse and search the same folder.

## Why markdown

Markdown survives. It diffs cleanly in git, opens in any editor, and travels between tools without a converter. Treating the file as the canonical record means an issue's history lives in your repo's commit log, not in a proprietary store.
