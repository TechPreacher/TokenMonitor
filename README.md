# TokenMonitor

A native macOS menu-bar app displaying Claude Code subscription usage and Anthropic API spend in a floating, pinnable cyberpunk "Neon HUD" panel.

## Overview

TokenMonitor tracks:

- **Claude Code subscription usage**: 5-hour session percentage, weekly percentage, and per-model weekly limits (from the OAuth usage endpoint)
- **Local token counts**: Parsed from Claude Code transcript JSONL files (`~/.claude/projects`)
- **Anthropic API spend**: Month-to-date costs via the Anthropic Admin API

The panel floats above all windows and can be pinned to stay visible. Data auto-refreshes (local scan every 30 s, network every 60 s, exponential backoff on failures). Right-click the menu-bar icon for About / Quit.

![screenshot](docs/screenshot.png) <!-- TODO -->

## Requirements

- **Xcode 26 or later** (verified with Xcode 26.6, Swift 6.3)
- **XcodeGen** (installed separately; defines the project in `project.yml`)
- **macOS 15.0** or later (deployment target)

## Build and Test

### Regenerate Xcode project from `project.yml`:

```sh
xcodegen generate
```

### Build:

```sh
xcodebuild -project TokenMonitor.xcodeproj -scheme TokenMonitor -configuration Debug build
```

### Test

Run all tests:

```sh
cd TokenMonitorKit && swift test       # Unit tests (TokenMonitorKit)
xcodebuild -project TokenMonitor.xcodeproj -scheme TokenMonitor test  # App integration tests
```

Run a single Kit test:

```sh
cd TokenMonitorKit && swift test --filter SomeSuite.someTest
```

Lint:

```sh
swiftlint
```

## First Run

1. **Keychain dialog**: On first launch, macOS will prompt "TokenMonitor wants to use the password stored for 'Claude Code-credentials'" — click **Always Allow**. This accesses your Claude Code OAuth credentials from the system Keychain.

2. **Admin API key (optional)**: Without an Admin API key, the API spend section shows a setup hint. To add spend tracking, visit the Anthropic Console, generate an Admin API key (`sk-ant-admin…`), and enter it via the app's settings (gear icon). Settings shows whether a key is stored and validates a new key live against the API before saving — rejected keys are never persisted. Without a key, the app still shows subscription usage and local token counts.

3. **OAuth endpoint (unofficial)**: The subscription usage endpoint is undocumented and may change or break at any time. If it does, the app degrades to showing only local JSONL transcript data.

4. **Menu-bar managers** (Bartender, Ice, …): new status items may land in the hidden overflow section — set TokenMonitor to "Always show" there.

## Distribution

Release builds are signed with **Developer ID Application** (hardened runtime, secure timestamp) and notarized via `notarytool`:

```sh
xcodebuild -project TokenMonitor.xcodeproj -scheme TokenMonitor -configuration Release clean build
ditto -c -k --keepParent <built .app> TokenMonitor.zip
xcrun notarytool submit TokenMonitor.zip --keychain-profile "notarytool-profile" --wait
xcrun stapler staple <built .app>
```

The stapled app and distribution zip land in `dist/` (gitignored). Debug builds sign with Apple Development automatically. A `.pkg` installer would additionally require a "Developer ID Installer" certificate (not currently present).

## Caveats

- **OAuth endpoint**: Unofficial; subject to change without notice.
- **No Dock icon**: Launches as menu-bar only (`LSUIElement`). Click the menu-bar icon to open the panel; right-click for About / Quit.
- **Pin button**: Keeps the panel above all windows; unpinned, the panel closes on an outside click.

## Architecture

- **TokenMonitorKit/** — All business logic (parsers, API clients, aggregator, models). Zero AppKit imports; `Sendable` types for thread safety. Test here first.
- **App/** — Thin SwiftUI/AppKit shell (menu-bar status item, floating `NSPanel`, view models, theme).
- **project.yml** — XcodeGen project definition; `.xcodeproj` is generated and gitignored.

Data sources (`UsageProviding`, `CostProviding`) fail independently; the aggregator merges results, degrading gracefully if any provider is unavailable or returns stale data.

## Development

For development guidance, see [CLAUDE.md](CLAUDE.md).
