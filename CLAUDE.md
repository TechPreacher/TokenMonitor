# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

TokenMonitor — a native macOS menu-bar app showing Claude Code subscription usage (5h window, weekly, tokens today) and Anthropic API month-to-date spend in a small cyberpunk "Neon HUD" panel, pinnable above all windows. Data auto-refreshes; app self-update (Sparkle) is explicitly out of scope.

Design spec: `docs/superpowers/specs/2026-08-26-tokenmonitor-design.md` — read it before structural changes.

## Toolchain (verified on this machine)

- Xcode 26.6 (build 17F113), Swift 6.3 — use the Swift Testing framework (`import Testing`), not XCTest, for new unit tests
- XcodeGen installed (`/opt/homebrew/bin/xcodegen`) — the project is defined in `project.yml`; the `.xcodeproj` is generated and should be gitignored
- SwiftLint installed; SwiftFormat and Tuist are NOT installed

## Layout

- `TokenMonitorKit/` — SPM package with ALL logic (parsers, API clients, aggregator, models). Zero AppKit imports, `Sendable` types. Test here first.
- `App/` — thin SwiftUI/AppKit shell (status item, floating NSPanel, view models, theme).
- `project.yml` — XcodeGen definition; `.xcodeproj` is generated, gitignored.

## Commands

Fast logic-test loop (preferred during development):

```sh
cd TokenMonitorKit && swift test
```

Run a single Kit test:

```sh
cd TokenMonitorKit && swift test --filter SomeSuite.someTest
```

Regenerate the Xcode project after any target/file-structure change to `project.yml`:

```sh
xcodegen generate
```

Build:

```sh
xcodebuild -project TokenMonitor.xcodeproj -scheme TokenMonitor -configuration Debug build
```

Run all tests:

```sh
xcodebuild -project TokenMonitor.xcodeproj -scheme TokenMonitor test
```

Run a single test (Swift Testing):

```sh
xcodebuild -project TokenMonitor.xcodeproj -scheme TokenMonitor test -only-testing:TokenMonitorTests/SomeSuite/someTest
```

Lint:

```sh
swiftlint
```

## Architecture

- Menu-bar only (`LSUIElement`): `NSStatusItem` + custom non-activating `NSPanel` hosting SwiftUI (NOT `MenuBarExtra` — can't float/pin reliably). Pin = `panel.level = .floating`.
- Data providers behind protocols (`UsageProviding`, `CostProviding`, `CredentialStore`), merged by `UsageAggregator`; sources fail independently and degrade to stale/unavailable badges, never crash.
- Subscription usage: OAuth usage endpoint (undocumented — verified by spike; provider returns `.unavailable` if it breaks) + local `~/.claude/projects/**/*.jsonl` parsing (ccusage-style) as fallback/detail.
- API spend: Anthropic Admin API cost report; admin key lives in Keychain, entered via Settings. Do not invent Anthropic endpoints; verify against current docs.
- ViewModels (`@Observable`) own polling (`RefreshScheduler`: 30s local, 60s network, exponential backoff); views stay dumb. Theme tokens centralized in one `Theme` type.

## Conventions

- Swift 6 strict concurrency; keep data-layer types `Sendable`
- Test-driven: write the failing test first (see superpowers:test-driven-development skill)
- Any script committed to the repo must be POSIX sh or `#!/usr/bin/env bash` — never fish syntax (user's shell is fish, but scripts must not be)
