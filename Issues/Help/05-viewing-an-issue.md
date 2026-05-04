# Viewing an Issue

Issues have two levels of detail: the inline detail panel that slides in from the right, and the full markdown sheet that overlays the window.

## Selecting

A single click on any issue card or row selects it. The detail panel opens on the right edge of the window and shows:

- The issue ID and title.
- The metadata block — status badge, module, platform, filed date, and closed date when present.
- The full markdown body below the metadata, rendered the same way as the standalone sheet.
- A small file link in the footer — clicking it opens the markdown sheet.

You can scroll the detail panel independently of the main view. The panel stays in sync with the underlying file: edits made by IssuesSkill or your editor refresh inside ~150 milliseconds.

To dismiss the panel, click the `x` button in its header or click an empty area of the main view to deselect.

## Opening the full sheet

Double-click the issue card or row, or click the file link in the detail panel footer, to open the markdown sheet. The sheet is a resizable window-modal overlay sized for comfortable reading — minimum 600×400, default 900×800. Drag any corner or edge to resize. Press Esc or click the close button to dismiss.

The sheet renders the entire markdown file, including the H1 title and the metadata table at the top. This is useful when you want the unprocessed view of the file, exactly as Claude or your editor wrote it.

Both the detail panel and the sheet enable text selection so you can copy any part of the body for an email, commit message, or follow-up.
