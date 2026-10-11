# AGENTS.md

agent-usage is a macOS menu bar app and CLI that shows Claude and Codex usage. Swift Package, zero dependencies, macOS 13+.

## Layout
- `Sources/AgentUsageCore`: providers, Keychain and auth-file readers, output formatting.
- `Sources/AgentUsage`: the `agent-usage` CLI.
- `Sources/AgentUsageBar`: the menu bar app (AppKit).
- `Sources/AgentUsageSelfTest`: offline checks. No XCTest needed.
- `Sources/AgentUsageSnapshot`: prints the menu bar label and rows from sample data.
- `scripts/`: install, package and uninstall.

## Build and test
- `swift build`
- `swift run AgentUsageSelfTest` must print `All checks passed.`
- `./scripts/install.sh` builds a release and installs to `/Applications`. Run it only when the user asks.

## Rules for changes
- Keep the attack surface fixed: 2 hardcoded URLs, 2 Keychain items, 1 file read, 0 files written.
- Never refresh or rewrite a token. The official CLIs own their tokens.
- Add no dependencies, telemetry, updater or subprocess.
- A missing usage window stays missing. Never show a made-up 0%.
- Add a self-test check for each parser change. Update the README if the surface changes.
