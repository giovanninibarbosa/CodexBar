import CodexBarCore
import Testing
@testable import CodexBar

struct OllamaUIErrorMapperTests {
    @Test
    func `maps Safari cookie access error to localized hint`() {
        let message = OllamaUIErrorMapper.userFacingMessage(
            OllamaUsageError.safariCookieAccessDenied.localizedDescription,
            localize: { key in "localized:\(key)" })

        #expect(message == "localized:ollama_safari_cookie_access_hint")
    }

    @Test
    func `maps Brave decryption denial with browser name`() {
        #expect(
            OllamaUsageError.browserCookieDecryptionDenied("Brave").localizedDescription ==
                "Brave cookie decryption was declined in Keychain. " +
                "Open the provider card and click Refresh (⌘R) to request Keychain access again.")

        let message = OllamaUIErrorMapper.userFacingMessage(
            OllamaUsageError.browserCookieDecryptionDenied("Brave").localizedDescription,
            localize: { key in
                key == "ollama_browser_cookie_decryption_denied" ? "%@ localized denial" : key
            })

        #expect(message == "Brave localized denial")
    }

    @Test
    func `maps disabled Keychain access with browser name`() {
        let message = OllamaUIErrorMapper.userFacingMessage(
            OllamaUsageError.browserCookieDecryptionDisabled("Brave").localizedDescription,
            localize: { key in
                key == "ollama_browser_cookie_decryption_disabled" ? "%@ localized disabled" : key
            })

        #expect(message == "Brave localized disabled")
    }

    @Test
    func `maps manual cookie header empty to localized hint`() {
        let message = OllamaUIErrorMapper.userFacingMessage(
            OllamaUsageError.manualCookieHeaderEmpty.localizedDescription,
            localize: { key in "localized:\(key)" })

        #expect(message == "localized:ollama_manual_cookie_empty")
    }

    @Test
    func `maps manual cookie header unrecognized to localized hint`() {
        let message = OllamaUIErrorMapper.userFacingMessage(
            OllamaUsageError.manualCookieHeaderUnrecognized.localizedDescription,
            localize: { key in "localized:\(key)" })

        #expect(message == "localized:ollama_manual_cookie_unrecognized")
    }

    @Test
    func `maps missing browser session to localized hint`() {
        let message = OllamaUIErrorMapper.userFacingMessage(
            OllamaUsageError.noSessionCookie.localizedDescription,
            localize: { key in "localized:\(key)" })

        #expect(message == "localized:ollama_no_browser_session")
    }

    @Test
    func `preserves generic Ollama errors`() {
        let raw = OllamaUsageError.networkError("timed out").localizedDescription
        #expect(OllamaUIErrorMapper.userFacingMessage(raw, localize: { $0 }) == raw)
    }
}
