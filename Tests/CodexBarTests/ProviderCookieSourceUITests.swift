import CodexBarCore
import Testing
@testable import CodexBar

struct ProviderCookieSourceUITests {
    @Test(arguments: [nil, "", "   ", "\n\t"] as [String?])
    func `manual source with blank header is missing`(header: String?) {
        #expect(ProviderCookieSourceUI.manualHeaderMissing(
            source: .manual,
            header: header,
            hasTokenAccounts: false))
    }

    @Test
    func `manual source with a header is not missing`() {
        #expect(!ProviderCookieSourceUI.manualHeaderMissing(
            source: .manual,
            header: "wos-session=abc",
            hasTokenAccounts: false))
    }

    @Test
    func `manual source with token accounts is not missing`() {
        #expect(!ProviderCookieSourceUI.manualHeaderMissing(
            source: .manual,
            header: nil,
            hasTokenAccounts: true))
    }

    @Test(arguments: [ProviderCookieSource.auto, .off])
    func `non manual sources are never missing`(source: ProviderCookieSource) {
        #expect(!ProviderCookieSourceUI.manualHeaderMissing(
            source: source,
            header: nil,
            hasTokenAccounts: false))
    }
}
