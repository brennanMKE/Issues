# Lint Findings

When Issues.app parses your folder it also runs a small set of lint checks. If anything is suspicious, an amber capsule appears in the toolbar with a count of findings. Click the capsule to open the lint sheet, which lists every finding with the file it came from and a short explanation.

Lint is informational. The app still loads and renders flagged files; it just nudges you that something looks off so the issue history stays clean.

## What the rules check

The five v1 rules are:

1. **Filename format** — the file name must match `^\d{4}\.md$`. A file named `bug-123.md` or `0042-something.md` is flagged. The app only lists files that match the pattern, so a flag here usually means a stray file in the folder.

2. **Title em-dash** — H1 titles must use a U+2014 em-dash (`—`), not a hyphen (`-`) or en-dash (`–`). The parser is strict by design — it makes "real titles" trivial to find with grep.

3. **Missing metadata table** — every issue needs the four-row pipe table directly under the H1, with rows for status, module, platform, and first-seen date. Files missing it still load but lose all their metadata.

4. **Unknown status** — the status cell has to be one of `open`, `in-progress`, `resolved`, `closed`, or `wontfix`. Anything else falls back to `open` and is flagged here so you can fix the typo.

5. **Closed-without-date** — an issue marked `resolved`, `closed`, or `wontfix` should also have a non-empty closed date in the metadata. A missing date suggests an incomplete close.
