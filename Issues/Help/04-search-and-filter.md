# Search and Filter

The toolbar above each view holds the controls for narrowing the issue list. All filters combine with AND semantics: an issue has to satisfy every active filter to remain visible.

## Search

Press Cmd+F to jump straight to the search field. Type any substring; the list updates as you type. Search currently matches issue titles and identifiers — full-body description search is on the roadmap but not in v1.

Clearing the field, or pressing Esc while it's focused, restores the unfiltered list.

## Status pills

Status appears as a row of pills directly under the search field. Each pill shows a status name and the count of matching issues. Clicking a pill toggles it: an inactive pill turns on, an active pill turns off. Multiple status pills can be active at once — selecting **open** and **in-progress** together shows everything in either state.

The pill counts are computed against the **unfiltered** list, so the numbers stay stable as you change other filters. This is deliberate: a moving baseline makes it hard to tell at a glance how many open items you really have.

## Module and platform pickers

Two dropdowns sit alongside the search field: **Module** and **Platform**. Each lets you pin the view to a single module (parsed from the slash-separated module string) or a single platform (`iOS`, `macOS`, `tvOS`, `watchOS`, `All`).

The platform filter has one short-circuit: an issue tagged `All` matches every platform filter. So an iOS-only filter still shows cross-platform issues, which is usually what you want.

## Combining

Filters AND together. A search of `crash`, status `open`, module `Networking`, platform `iOS` shows only issues that match all four.
