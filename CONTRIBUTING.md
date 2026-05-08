# Contributing to Issues.app

Thanks for taking the time to look. Issues.app is a small, focused native macOS app, and contributions of any size are welcome — bug reports, feature ideas, documentation fixes, or pull requests.

## Reporting bugs and requesting features

File issues on GitHub: **<https://github.com/brennanMKE/Issues/issues>**.

Before opening a new issue, please scan the existing list (open *and* closed) — many things are already known or have prior discussion worth reading.

A good bug report includes:

- **macOS version** (e.g. 15.4, 26.4) and **Mac model** (Apple Silicon vs. Intel).
- **Issues.app version or commit** — visible in `Issues.app → About`, or use the short SHA from the build you're running.
- **What you did** — a short list of steps. The more reproducible, the better.
- **What you expected** vs. **what actually happened**.
- **A screenshot or screen recording** if the problem is visual. Drag-and-drop attaches files to GitHub Issues directly. Crash logs from `~/Library/Logs/DiagnosticReports/` are gold for crash reports.
- **Console output** if relevant. The app logs through `os.Logger` under subsystem `co.sstools.Issues`:

  ```sh
  log stream --predicate 'subsystem == "co.sstools.Issues"' --level debug
  ```

For feature requests, lead with the use case ("when I'm doing X, I'd like the app to Y") rather than a proposed implementation. The "why" is usually more useful than the "how".

## Submitting a pull request

1. **Fork** the repo and create a topic branch off `main`.
2. **Make focused commits.** The repo's commit style is `#NNNN <verb> <short title>` for issue-linked commits, or a plain declarative title for unrelated changes. Keep commits small and self-contained when possible.
3. **Build and test locally** (see "Development setup" below) before opening the PR.
4. **Open a PR** against `main`. In the description, link the GitHub issue you're closing (if any), describe what changed, and call out anything that's intentionally out of scope or worth a follow-up.
5. **Be patient** — this is a small project maintained on a part-time basis. A response may take a few days.

PRs that are most likely to land quickly:

- **Bug fixes with a regression test.** Tests live in `IssuesTests/` and run as part of the `Issues` scheme.
- **Small, well-scoped features.** A 50-line PR with a clear motivation is far easier to review than a 500-line PR that bundles three unrelated changes.
- **Documentation and code-comment improvements.** Especially around the parser, the folder-watching glue, and security-scoped bookmarks — these are the parts new readers most often get tripped up on.

## Development setup

### Requirements

- macOS 15 or newer (the project currently targets macOS 26.4).
- Xcode 16 or newer.

### Build

```sh
xcodebuild -project Issues.xcodeproj -scheme Issues -configuration Debug -destination 'platform=macOS' build
```

Or open `Issues.xcodeproj` in Xcode and ⌘R.

### Run tests

```sh
# All tests
xcodebuild -project Issues.xcodeproj -scheme Issues -destination 'platform=macOS' test

# A single test class
xcodebuild -project Issues.xcodeproj -scheme Issues -destination 'platform=macOS' \
    test -only-testing:IssuesTests/MarkdownIssueParserTests
```

Any change to the markdown parser (`Issues/Services/MarkdownIssueParser.swift`) **must** come with parser tests. The four regexes used by the parser are intentionally strict — see the inline comments and `IssuesTests/MarkdownIssueParserTests.swift` for examples of what's accepted and rejected.

### Reset persisted state

The app remembers folders via security-scoped bookmarks stored in `UserDefaults`. To wipe the state for a clean-slate test:

```sh
defaults delete co.sstools.Issues
```

## Code conventions

A few project-specific notes that aren't obvious from reading the code:

- **Source files auto-register.** Folders under `Issues/` use `PBXFileSystemSynchronizedRootGroup`, so adding a new `.swift` file on disk registers it with the target automatically. Don't edit `project.pbxproj` to add sources — only edit it for build settings, entitlements, or package dependencies.
- **The em-dash in issue titles is U+2014, not a hyphen.** The parser rejects hyphens by design.
- **Architecture is intentionally small.** The data flow lives almost entirely in `Issues/State/IssueStore.swift`. Don't introduce a JSON cache, generated index, or other intermediate artifact — the markdown files are the source of truth, and the live FSEvents reload pass keeps them current.
- **Light/dark adaptive palette.** Colors live in `Issues/Theme/` and the asset catalog. Don't hardcode hex values in views.

Deeper architectural notes are in [`CLAUDE.md`](CLAUDE.md) — it's written for AI assistants working in the repo, but it's the most concise architecture doc the project has.

## About `project-issues/`

This repo has its own `project-issues/` folder for tracking bugs and features in **Issues.app itself** — separate from the `issues/` folders the app *renders*. The folder name is `project-issues/` (not `issues/`) to avoid a case-insensitive filesystem clash with the `Issues/` Xcode source folder.

For external contributors, **GitHub Issues is the right place to report things** — `project-issues/` is the maintainer's working tracker, not a contribution surface.

## Code of conduct

Be kind. Assume the other person is acting in good faith. Disagree on technical merits, not on people. That's about it.

## License

By contributing, you agree that your contributions are licensed under the same terms as the rest of the repository.
