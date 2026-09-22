import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
struct OllamaMenuLoginActionTests {
    @Test
    func `ollama implementation declares a login flow`() {
        #expect(OllamaProviderImplementation().supportsLoginFlow)
    }

    @Test
    func `ollama menu offers a sign in link instead of add account`() {
        let settings = testSettingsStore(suiteName: "OllamaMenuLoginActionTests")
        let store = UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings)

        let actions = MenuDescriptor.build(
            provider: .ollama,
            store: store,
            settings: settings,
            account: AccountInfo(email: nil, plan: nil),
            updateReady: false)
            .sections
            .flatMap(\.entries)
            .compactMap { entry -> (String, MenuDescriptor.MenuAction)? in
                guard case let .action(label, action) = entry else { return nil }
                return (label, action)
            }

        #expect(actions.contains {
            $0.0 == "Sign in to Ollama…" && $0.1 == .loginToProvider(url: "https://ollama.com/signin")
        })
        #expect(!actions.contains { $0.0 == "Add Account..." })
    }
}
