# Privacy and Sandbox

Issues.app runs inside the macOS App Sandbox. It can only read folders you have explicitly granted it access to, and it cannot write to your filesystem at all.

## User-selected folders

When you click the `+` button or open the folder picker, you're invoking the standard macOS open panel. The folder you pick is the only directory the app can read; nothing above or beside it is reachable. If you select `~/Projects/MyApp/issues`, the app sees `issues/` and its contents, and that is all.

## Security-scoped bookmarks

To remember your folder selection across launches without re-prompting, the app stores a security-scoped bookmark in `UserDefaults`. The bookmark is a sealed reference that proves you granted access in a previous session — macOS validates it on each launch and re-grants the same scope.

The required entitlement is `com.apple.security.files.bookmarks.app-scope`, which is enabled in `Issues.entitlements`. Bookmarks survive app updates and macOS upgrades; if one ever goes stale, the app drops it and you'll see a "Locate folder…" prompt to re-select.

## Read-only by design

The sandbox is configured for read-only access to user-selected files. The app has no entitlement to write, even if a future bug tried to. This is deliberate — the app's job is to render, not to mutate. Edits go through your editor, git, or the IssuesSkill agent.

## What's stored locally

Only your folder bookmarks, tab order, and view-mode preferences live in `UserDefaults` under the bundle identifier `co.sstools.Issues`. No telemetry, no analytics, no network calls. To wipe local state, run `defaults delete co.sstools.Issues`.
