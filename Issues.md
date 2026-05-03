# Issues

Lightweight issue tracking for bugs and regressions found while testing the Bluesky SwiftUI app.

Issues are described verbally (or with screenshots) and recorded here so work is not interrupted. Each issue gets a unique four-digit number, left-padded with zeros (`0001`, `0002`, …).

---

## How to file an issue

1. Pick the next number from the index above.
2. Create `issues/NNNN.md` using the template below.
3. If there are screenshots or other attachments, drop them in `issues/NNNN/` and add them to the Attachments section using inline image syntax (see template).
4. Add a row to the Index table above.
5. Run `python3 issues/generate.py` to update the visualization data.

## How to update an existing issue

Any change to an issue — status update, added notes, new attachment, or any other edit — requires these steps:

1. Edit `issues/NNNN.md` with the change.
2. If the status changed, update the matching row in the Index table above.
3. Run `python3 issues/generate.py` to refresh the visualization data.

**Adding screenshots:** macOS screenshot filenames contain a **narrow no-break space** (U+202F) before AM/PM — visually identical to a regular space but distinct in bytes. Quoting the literal filename in a `cp` command will fail with "No such file or directory" because of this character.

Claude handles this automatically using a glob that skips the problematic character:

```bash
cp /Users/brennan/Desktop/Screenshot\ YYYY-MM-DD\ at\ H.MM.SS*XM.png issues/NNNN/screenshot.png
```

If Claude cannot copy the file (e.g. no Desktop access), run the copy yourself using the `!` prefix in the Claude Code prompt — your shell has the necessary permissions:

```
! cp /Users/brennan/Desktop/Screenshot\ YYYY-MM-DD\ at\ H.MM.SS*XM.png issues/NNNN/screenshot.png
```

**Status values:** `open` · `in-progress` · `resolved` · `wontfix`

> **IMPORTANT — do not close issues without explicit confirmation.**
> An issue must **never** be marked `resolved` or `wontfix` unless the user has explicitly said the bug is fixed or won't be addressed. Do not infer resolution from a code change, a commit message, or the filing of a related issue. Always leave status as `open` until the user confirms closure.

---

## Issue template

```markdown
# NNNN — Title

| | |
|---|---|
| **Status** | open |
| **Module** | e.g. BlueskyFeed, BlueskyAuth, Bluesky-SwiftUI |
| **Platform** | iOS · macOS · iPadOS · All |
| **First seen** | YYYY-MM-DD |

## Description

What is wrong.

## Steps to reproduce

1. …
2. …
3. …

## Expected behavior

What should happen.

## Actual behavior

What actually happens.

## Attachments

![Description of screenshot](screenshot.png)

## Notes

Any additional context, guesses at root cause, related code locations.
```
