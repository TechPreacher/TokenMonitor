# TokenMonitor — Design Spec

Date: 2026-08-26
Status: approved pending user review

## Purpose

Native macOS menu-bar app showing, in one small floating panel:

- Claude Code subscription usage: 5-hour session window utilization % + reset time, weekly utilization %, tokens consumed today
- Anthropic API spend: month-to-date USD via Admin API cost report

Cyberpunk "Neon HUD" aesthetic. Panel pinnable above all windows. Data auto-refreshes; no app self-update machinery (explicitly out of scope).

## Decisions (user-confirmed)

| Topic | Decision |
|---|---|
| Subscription data | Hybrid: OAuth usage endpoint (primary for limits) + local JSONL parsing (fallback + token detail) |
| API credit | Month-to-date cost via Admin API `cost_report`; needs Admin API key (`sk-ant-admin...`) pasted once in Settings, stored in Keychain. No public balance endpoint exists |
| App shape | Menu-bar only (`LSUIElement`), no Dock icon; floating pinnable panel |
| Auto-update | Data refresh only. No Sparkle |
| Aesthetic | Neon HUD: near-black translucent panel, cyan/magenta neon, glowing gauges, monospaced digits, subtle scanlines |
| Architecture | Core SPM package `TokenMonitorKit` (zero AppKit, `Sendable`, tested via `swift test`) + thin app shell target, wired by XcodeGen |

## Layout

```
TokenMonitor/
├── project.yml                  # XcodeGen: app target + app test target + local package ref
├── CLAUDE.md
├── TokenMonitorKit/             # SPM package — all logic, zero AppKit
│   ├── Package.swift
│   ├── Sources/TokenMonitorKit/
│   └── Tests/TokenMonitorKitTests/
└── App/                         # thin SwiftUI/AppKit shell
```

## TokenMonitorKit components

All source access behind protocols; everything `Sendable`; Swift 6 strict concurrency.

### Models

- `UsageSnapshot` — session (5h) utilization fraction + `resetsAt`, weekly utilization fraction, tokens today, source + fetch timestamp.
- `CostSnapshot` — month-to-date USD, fetch timestamp.
- `DashboardState` — merged view state: values + per-source freshness (`fresh` / `stale(since:)` / `unavailable(reason:)`).

### Providers

- `protocol UsageProviding` / `protocol CostProviding` — async `fetch()` returning snapshot or throwing typed error.
- `ClaudeOAuthClient: UsageProviding` — reads Claude Code OAuth token from Keychain service `Claude Code-credentials` (fallback: `~/.claude/.credentials.json`); calls the undocumented OAuth usage endpoint. **Endpoint is unofficial — Phase 0 spike must verify request/response shape before implementation. If spike fails, this provider ships returning `.unavailable` and the app runs on JSONL + cost report alone.**
- `TranscriptUsageReader: UsageProviding` — incremental scan of `~/.claude/projects/**/*.jsonl`; sums `message.usage` token fields into 5-hour-window and daily buckets. File-mtime cache so periodic rescans only touch changed files. Malformed lines skipped, never fatal.
- `AdminCostClient: CostProviding` — Anthropic Admin API cost report endpoint, current-month window, summed to USD. Admin key from `CredentialStore`. Verify exact endpoint/params against current Anthropic docs at implementation time.
- `CredentialStore` protocol — wraps Keychain read/write (Claude Code token read-only; admin key read/write). Mockable.
- `UsageAggregator` — pure function/type merging provider results into `DashboardState`. Merge rule: OAuth wins for utilization/limits; JSONL fills tokens-today detail and substitutes utilization estimate when OAuth unavailable; cost independent.

## App target

- `NSStatusItem` in menu bar + custom non-activating `NSPanel` hosting SwiftUI content. Not `MenuBarExtra` — its window cannot float/pin reliably.
- Pin behavior: pinned → `panel.level = .floating`, `hidesOnDeactivate = false`, stays open across app switches; unpinned → closes on outside click.
- `@Observable DashboardViewModel` — owns `DashboardState`, exposes formatted display values.
- `RefreshScheduler` — JSONL scan every 30 s; network fetches every 60 s; exponential backoff (max 10 min) per failing source.
- Settings sheet — admin key field (writes to Keychain), refresh-interval overrides.
- Theme: `NSVisualEffectView` blur behind near-black; cyan (#0ff-family) primary / magenta accents; neon glow via layered shadows on gauge strokes; monospaced digit font; faint scanline overlay. All theme tokens in one `Theme` type.

## Error handling

- Sources fail independently; one failing source never blocks or crashes others.
- Failed/stale source → section dimmed + "stale · HH:mm" badge showing last success.
- No admin key configured → cost section shows setup hint instead of error.
- Keychain access denied / credentials missing → provider `.unavailable` with reason surfaced as tooltip.

## Testing

- Kit (fast loop, `swift test`): JSONL parser against fixture transcripts (valid, malformed, truncated), 5h-window bucket math incl. boundary times, aggregator merge matrix (each source fresh/stale/unavailable), HTTP clients via `URLProtocol` stub, `CredentialStore` mocked throughout.
- App (`xcodebuild test`): build + smoke test that panel/view-model wire up. No UI-automation tests in v1.

## Out of scope (v1)

Sparkle/app self-update, Dock-app mode, multiple accounts, notifications/alerts on threshold, historical charts.
