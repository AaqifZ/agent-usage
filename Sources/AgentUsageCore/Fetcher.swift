import Foundation

/// Fires all enabled providers in parallel and collects results.
/// One provider failing never blocks the other.
public enum Fetcher {

    public static func fetchAll(providers: [Provider] = Provider.allCases) async -> AgentSnapshot {
        var results: [Provider: Result<Usage, Swift.Error>] = [:]

        await withTaskGroup(of: (Provider, Result<Usage, Swift.Error>).self) { group in
            for p in providers {
                group.addTask { (p, await fetchOne(p)) }
            }
            for await (p, r) in group {
                results[p] = r
            }
        }

        return AgentSnapshot(results: results)
    }

    private static func fetchOne(_ p: Provider) async -> Result<Usage, Swift.Error> {
        let fetcher: any UsageFetcher
        switch p {
        case .claude: fetcher = ClaudeProvider()
        case .codex:  fetcher = CodexProvider()
        }
        do {
            return .success(try await fetcher.fetch())
        } catch {
            return .failure(error)
        }
    }
}
