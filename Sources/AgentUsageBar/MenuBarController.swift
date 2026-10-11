import AppKit
import AgentUsageCore

@MainActor
final class MenuBarController {
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private var refreshTimer: Timer?
    private var latest: AgentSnapshot?

    init() {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "⋯"
        statusItem.button?.toolTip = "Agent Usage — click for details"
        statusItem.menu = menu

        rebuildMenu(snapshot: nil)
        refresh()

        refreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    private func refresh() {
        Task {
            let snapshot = await Fetcher.fetchAll()
            await MainActor.run { self.apply(snapshot: snapshot) }
        }
    }

    @MainActor
    private func apply(snapshot: AgentSnapshot) {
        self.latest = snapshot
        let successes = snapshot.successes

        statusItem.button?.title = Output.compact(snapshot)
        var tips = successes.map { Output.line($0) }
        for p in Provider.allCases {
            if case .failure(let e) = snapshot.results[p] { tips.append("\(p.displayName) — \(e)") }
        }
        statusItem.button?.toolTip = tips.isEmpty ? "No providers signed in." : tips.joined(separator: "\n")
        rebuildMenu(snapshot: snapshot)
    }

    private func rebuildMenu(snapshot: AgentSnapshot?) {
        menu.removeAllItems()

        if let snapshot {
            for provider in Provider.allCases {
                let header = NSMenuItem(title: "━━━ \(provider.displayName) ━━━", action: nil, keyEquivalent: "")
                header.isEnabled = false
                menu.addItem(header)

                switch snapshot.results[provider] {
                case .success(let usage):
                    // Render only the windows this plan exposes. A Codex team
                    // plan has no session window, so that row is omitted.
                    for lineText in Output.windowLines(usage) {
                        let row = NSMenuItem(title: lineText, action: nil, keyEquivalent: "")
                        row.isEnabled = false
                        menu.addItem(row)
                    }

                case .failure(let error):
                    let msg = String(describing: error)
                    let err = NSMenuItem(title: "Error: \(msg.prefix(100))", action: nil, keyEquivalent: "")
                    err.isEnabled = false
                    menu.addItem(err)

                case .none:
                    let none = NSMenuItem(title: "Not signed in", action: nil, keyEquivalent: "")
                    none.isEnabled = false
                    menu.addItem(none)
                }

                menu.addItem(NSMenuItem.separator())
            }
        } else {
            let loading = NSMenuItem(title: "Fetching…", action: nil, keyEquivalent: "")
            loading.isEnabled = false
            menu.addItem(loading)
            menu.addItem(NSMenuItem.separator())
        }

        let refreshItem = NSMenuItem(title: "Refresh now", action: #selector(refreshNow), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

        menu.addItem(NSMenuItem.separator())

        let quit = NSMenuItem(title: "Quit Agent Usage Bar", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    @objc private func refreshNow() { refresh() }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
