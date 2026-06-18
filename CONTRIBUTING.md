# Contributing to Fettle

Thanks for your interest in improving Fettle! This guide covers how to get set up,
how the codebase is organized, and how to add a new tool.

## Getting started

1. **Requirements:** macOS 27+ and Xcode 26+ (Swift 6.4).
2. Open `Fettle.xcodeproj` in Xcode and run the **Fettle** scheme, or build from
   the command line:
   ```sh
   xcodebuild -project Fettle.xcodeproj -scheme Fettle -configuration Debug \
     -destination 'platform=macOS' build
   ```
3. The project uses Xcode's **file-system-synchronized groups** — just add files
   under `Fettle/` (or `FettleBatteryHelper/`) and they're compiled automatically.
   No `.pbxproj` edits needed for new source files.

Fettle is intentionally **not sandboxed**: the Clean Mode keyboard event tap and
the battery helper cannot run under App Sandbox.

## Project layout

```
Fettle/
  App/         FettleApp (MenuBarExtra scene) + AppState
  Core/        Theme, FettleTool protocol, shared SwiftUI components,
               AudioSystem, Store (UserDefaults), HotKey, ShortcutsRunner
  Tools/       One folder per tool: model (@Observable) + any system glue
  Views/       Dashboard, Settings, and per-tool detail views
FettleBatteryHelper/   Privileged root XPC daemon (SMC charge keys)
```

## Architecture

Each tool is a self-contained, observable module:

- A tool is an `@Observable @MainActor final class` conforming to **`FettleTool`**
  (`kind` / `title` / `symbol` / `tint` / `section` / `isActive` / `statusText` /
  `control` / `hasDetail`).
- `AppState` owns one instance of each tool and exposes them to the UI.
- The dashboard renders tool rows generically; `RootView` routes to a detail view
  by `ToolID`.
- Persist user-facing settings with `Store` (read defaults in the property
  initializer, write in `didSet`) so `@Observable` tracking keeps working.

### Adding a new tool

1. Add a case to `ToolID` (and pick its `ToolSection`).
2. Create `Tools/MyTool/MyTool.swift` — an `@Observable` class conforming to
   `FettleTool`. Keep all system access (IOKit, Core Audio, `Process`, etc.) in
   this folder.
3. Add a stored instance to `AppState` and include it in `allTools` and
   `tool(for:)`.
4. If it has a detail screen, create `Views/MyToolDetailView.swift` and add a
   case in `RootView`.
5. Persist any preferences via `Store`.

That's it — the dashboard, active-count, and menu bar pick it up automatically.

## Conventions

- **Match the surrounding code.** Mirror the existing naming, spacing, and SwiftUI
  patterns rather than introducing new ones.
- Keep design tokens in `Theme`; don't hardcode colors/sizes in views.
- **No competitor mimicry.** Don't reuse other apps' signature metaphors (e.g. the
  coffee-cup "stay awake" icon). Keep Fettle's marks neutral and original.
- Be honest about platform limits. If something needs a permission, a helper, or
  has no public API, surface it in the UI instead of faking it.

## Pull requests

- Branch off `main`, keep PRs focused, and describe what you changed and how you
  verified it.
- Make sure the project builds (`xcodebuild … build`) before opening a PR.
- Note any tool that needs **on-device verification** (audio taps, the battery
  SMC helper) — these can't be fully tested in CI.

## Reporting bugs

Open an issue with your macOS version, Mac model (Intel vs Apple Silicon matters
for the battery helper), steps to reproduce, and any relevant Console logs
(`log show --predicate 'subsystem == "com.fettle.app"' --last 5m`).
