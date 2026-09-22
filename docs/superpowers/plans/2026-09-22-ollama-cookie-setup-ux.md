# Ollama Cookie Setup UX Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the single misleading "No Ollama session cookie found" message with three actionable states, add inline "No cookie pasted" / "Use Auto" validation to the Ollama card, set expectations for the Chrome Keychain prompt, and add a "Sign in to Ollama…" menu entry.

**Architecture:** Two new cases on `OllamaUsageError` in CodexBarCore are thrown only from `resolveManualCookieHeader`; `OllamaUIErrorMapper` maps the three strings to localized `ollama_*` keys. A shared pure helper `ProviderCookieSourceUI.manualHeaderMissing` drives a status text and a "Use Auto" action on the existing Cookie source picker. The menu entry reuses the Devin-style `loginMenuAction` + `.loginToProvider` path. All copy is localized in the 23 `Localizable.strings` catalogs.

**Tech Stack:** Swift 6, SwiftPM, Swift Testing (`@Test`, backticked sentence names), SwiftFormat/SwiftLint via `make check`, `node Scripts/check-app-locales.mjs`.

**Spec:** `docs/superpowers/specs/2026-09-22-ollama-cookie-setup-ux-design.md`

## Global Constraints

- Follow `AGENTS.md`: 4-space indent, 120-char lines, explicit `self`, keep `MARK` organization, no new dependencies.
- Swift Testing tests use backticked sentence names, no camelCase.
- Never run anything that can show a macOS Keychain prompt. Tests use `testSettingsStore`, in-memory stores, and settings fixtures only. Do not call `refreshProvider`, `CookieHeaderCache` browser reads, or live `codexbar usage`.
- Do not use `FileTokenAccountStore` in a test that adds token accounts; use `testSettingsStore(suiteName:)`, which injects `InMemoryTokenAccountStore()`.
- Localization: every new user-facing string gets an entry in all 23 catalogs under `Sources/CodexBar/Resources/*.lproj/Localizable.strings`. `node Scripts/check-app-locales.mjs` must pass.
- Copy is fixed by the spec (section 4.2 and 4.3). Do not reword.
- Commit messages: `type(scope): short description ending with a dot.` in en-US, no trailers, plain `git commit`.
- Routing (per `~/.claude/CLAUDE.md`): Tasks 1–5 → `implementer` followed by `reviewer`; Tasks 6–7 → `worker`; Task 8 → main thread.
- Run `swift test --filter <Suite>` after every task; run `make check` before every commit.

---

### Task 1: Split `OllamaUsageError.noSessionCookie` into three cases

**Files:**
- Modify: `Sources/CodexBarCore/Providers/Ollama/OllamaUsageFetcher.swift:104-145` (enum) and `:712-740` (`resolveManualCookieHeader`)
- Test: `Tests/CodexBarTests/OllamaUsageFetcherTests.swift:10-16` and `:59-93`

**Interfaces:**
- Consumes: nothing new.
- Produces: `OllamaUsageError.manualCookieHeaderEmpty`, `OllamaUsageError.manualCookieHeaderUnrecognized` (no associated values). New `errorDescription` for `.noSessionCookie`. Task 2 matches these strings by equality.

- [ ] **Step 1: Update the two existing manual-mode tests and add two new ones**

In `Tests/CodexBarTests/OllamaUsageFetcherTests.swift`, replace the test named `manual mode without valid header throws no session cookie` with:

```swift
    @Test
    func `manual mode without header throws manual cookie header empty`() {
        do {
            _ = try OllamaUsageFetcher.resolveManualCookieHeader(
                override: nil,
                manualCookieMode: true)
            Issue.record("Expected OllamaUsageError.manualCookieHeaderEmpty")
        } catch OllamaUsageError.manualCookieHeaderEmpty {
            // expected
        } catch {
            Issue.record("Expected OllamaUsageError.manualCookieHeaderEmpty, got \(error)")
        }
    }

    @Test(arguments: ["", "   ", "\n\t "])
    func `manual mode with blank header throws manual cookie header empty`(header: String) {
        do {
            _ = try OllamaUsageFetcher.resolveManualCookieHeader(
                override: header,
                manualCookieMode: true)
            Issue.record("Expected OllamaUsageError.manualCookieHeaderEmpty")
        } catch OllamaUsageError.manualCookieHeaderEmpty {
            // expected
        } catch {
            Issue.record("Expected OllamaUsageError.manualCookieHeaderEmpty, got \(error)")
        }
    }
```

Replace the test named `manual mode without recognized session cookie throws no session cookie` with:

```swift
    @Test
    func `manual mode without recognized session cookie throws unrecognized header`() {
        do {
            _ = try OllamaUsageFetcher.resolveManualCookieHeader(
                override: "analytics_session_id=noise; theme=dark",
                manualCookieMode: true)
            Issue.record("Expected OllamaUsageError.manualCookieHeaderUnrecognized")
        } catch OllamaUsageError.manualCookieHeaderUnrecognized {
            // expected
        } catch {
            Issue.record("Expected OllamaUsageError.manualCookieHeaderUnrecognized, got \(error)")
        }
    }
```

Directly after the existing test `session authentication errors point to current recovery page` (line 10–16), add:

```swift
    @Test
    func `cookie setup errors name the settings fix`() {
        let empty = OllamaUsageError.manualCookieHeaderEmpty.errorDescription ?? ""
        #expect(empty.contains("Manual"))
        #expect(empty.contains("Auto"))
        #expect(empty.contains("https://ollama.com/settings"))

        let unrecognized = OllamaUsageError.manualCookieHeaderUnrecognized.errorDescription ?? ""
        #expect(unrecognized.contains("wos-session"))
        #expect(unrecognized.contains("https://ollama.com/settings"))

        let browser = OllamaUsageError.noSessionCookie.errorDescription ?? ""
        #expect(browser.contains("https://ollama.com/signin"))
        #expect(browser.contains("Chrome"))
        #expect(browser.contains("Manual"))
        #expect(!browser.contains("Please sign in"))
    }
```

- [ ] **Step 2: Run the suite to verify the new tests fail**

Run: `swift test --filter OllamaUsageFetcherTests`
Expected: compile error `type 'OllamaUsageError' has no member 'manualCookieHeaderEmpty'` (or the four tests above fail).

- [ ] **Step 3: Add the enum cases and copy**

In `Sources/CodexBarCore/Providers/Ollama/OllamaUsageFetcher.swift`, change the enum header and cases:

```swift
public enum OllamaUsageError: LocalizedError, Sendable {
    private static let signInURL = "https://ollama.com/signin"
    private static let settingsURL = "https://ollama.com/settings"

    case missingAPIKey
    case notLoggedIn
    case invalidCredentials
    case apiUnauthorized
    case parseFailed(String)
    case networkError(String)
    case noSessionCookie
    case manualCookieHeaderEmpty
    case manualCookieHeaderUnrecognized
    case safariCookieAccessDenied
    case browserCookieDecryptionDenied(String)
    case browserCookieDecryptionDisabled(String)
```

Replace the `.noSessionCookie` branch of `errorDescription` and add the two new branches directly after it:

```swift
        case .noSessionCookie:
            "No Ollama session cookie found in your browsers. Sign in at \(Self.signInURL) in Chrome, " +
                "then click Refresh (⌘R). If your session is only in Safari or another browser, " +
                "set Cookie source to Manual and paste a cookie header."
        case .manualCookieHeaderEmpty:
            "Cookie source is set to Manual, but no cookie header is pasted. Paste a Cookie header from " +
                "\(Self.settingsURL), or switch Cookie source to Auto to import browser cookies."
        case .manualCookieHeaderUnrecognized:
            "The pasted Ollama cookie header has no session cookie (wos-session). Copy the full Cookie header " +
                "from \(Self.settingsURL) while signed in, then paste it again."
```

- [ ] **Step 4: Throw the new cases from `resolveManualCookieHeader`**

In the same file, inside `static func resolveManualCookieHeader(...)`, change the two throw sites:

```swift
            guard hasRecognizedOllamaSessionCookie(in: normalized) else {
                logger?("[ollama] Manual cookie header missing recognized session cookie")
                throw OllamaUsageError.manualCookieHeaderUnrecognized
            }
            logger?("[ollama] Using manual cookie header")
            return normalized
        }
        if manualCookieMode {
            logger?("[ollama] Manual cookie mode selected but no cookie header is configured")
            throw OllamaUsageError.manualCookieHeaderEmpty
        }
        return nil
```

Leave every other `throw OllamaUsageError.noSessionCookie` in the file unchanged (browser import paths and the non-macOS `#else` branches).

- [ ] **Step 5: Run the Ollama suites to verify they pass**

Run: `swift test --filter "OllamaUsageFetcherTests|OllamaUsageFetcherRetryMappingTests"`
Expected: all PASS. The retry-mapping suite must be unchanged; it only throws `noSessionCookie` from stubbed browser fetches.

- [ ] **Step 6: Format, lint, commit**

```bash
make check
git add Sources/CodexBarCore/Providers/Ollama/OllamaUsageFetcher.swift Tests/CodexBarTests/OllamaUsageFetcherTests.swift
git commit -m "fix(ollama): distinguish manual cookie states from missing browser session."
```

---

### Task 2: Map the three messages to localized hints in `OllamaUIErrorMapper`

**Files:**
- Modify: `Sources/CodexBar/Providers/Ollama/OllamaUIErrorMapper.swift`
- Test: `Tests/CodexBarTests/OllamaUIErrorMapperTests.swift`

**Interfaces:**
- Consumes: `OllamaUsageError.manualCookieHeaderEmpty`, `.manualCookieHeaderUnrecognized`, `.noSessionCookie` from Task 1.
- Produces: localized keys `ollama_manual_cookie_empty`, `ollama_manual_cookie_unrecognized`, `ollama_no_browser_session` (catalog entries added in Task 6).

- [ ] **Step 1: Write the failing mapper tests**

In `Tests/CodexBarTests/OllamaUIErrorMapperTests.swift`, replace the test `preserves generic Ollama errors` with:

```swift
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
```

- [ ] **Step 2: Run to verify the three new tests fail**

Run: `swift test --filter OllamaUIErrorMapperTests`
Expected: 3 FAIL (mapper returns the raw English string), `preserves generic Ollama errors` PASS.

- [ ] **Step 3: Add the three equality mappings**

In `Sources/CodexBar/Providers/Ollama/OllamaUIErrorMapper.swift`, insert directly after the `safariCookieAccessDenied` check:

```swift
        if trimmed == OllamaUsageError.manualCookieHeaderEmpty.localizedDescription {
            return localize("ollama_manual_cookie_empty")
        }
        if trimmed == OllamaUsageError.manualCookieHeaderUnrecognized.localizedDescription {
            return localize("ollama_manual_cookie_unrecognized")
        }
        if trimmed == OllamaUsageError.noSessionCookie.localizedDescription {
            return localize("ollama_no_browser_session")
        }
```

- [ ] **Step 4: Run to verify pass**

Run: `swift test --filter OllamaUIErrorMapperTests`
Expected: 7 PASS.

- [ ] **Step 5: Format, lint, commit**

```bash
make check
git add Sources/CodexBar/Providers/Ollama/OllamaUIErrorMapper.swift Tests/CodexBarTests/OllamaUIErrorMapperTests.swift
git commit -m "fix(ollama): localize manual cookie and browser session hints."
```

---

### Task 3: Shared `manualHeaderMissing` helper on `ProviderCookieSourceUI`

**Files:**
- Modify: `Sources/CodexBar/Providers/Shared/ProviderCookieSourceUI.swift`
- Create: `Tests/CodexBarTests/ProviderCookieSourceUITests.swift`

**Interfaces:**
- Produces:
  ```swift
  static func manualHeaderMissing(source: ProviderCookieSource, header: String?, hasTokenAccounts: Bool) -> Bool
  ```
  Task 4 calls it.

- [ ] **Step 1: Write the failing tests**

Create `Tests/CodexBarTests/ProviderCookieSourceUITests.swift`:

```swift
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
```

- [ ] **Step 2: Run to verify compile failure**

Run: `swift test --filter ProviderCookieSourceUITests`
Expected: compile error `type 'ProviderCookieSourceUI' has no member 'manualHeaderMissing'`.

- [ ] **Step 3: Implement the helper**

In `Sources/CodexBar/Providers/Shared/ProviderCookieSourceUI.swift`, add `import Foundation` after `import CodexBarCore`, and add this static function directly after `static let keychainDisabledPrefixKey`:

```swift
    /// True when the picker is on Manual but nothing supplies a cookie: the pasted header is blank and no
    /// token account is selected. Drives the "No cookie pasted" status and the "Use Auto" action.
    static func manualHeaderMissing(
        source: ProviderCookieSource,
        header: String?,
        hasTokenAccounts: Bool) -> Bool
    {
        guard source == .manual, !hasTokenAccounts else { return false }
        return header?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
    }
```

- [ ] **Step 4: Run to verify pass**

Run: `swift test --filter ProviderCookieSourceUITests`
Expected: 8 PASS (4 + 1 + 1 + 2 parameterized cases).

- [ ] **Step 5: Format, lint, commit**

```bash
make check
git add Sources/CodexBar/Providers/Shared/ProviderCookieSourceUI.swift Tests/CodexBarTests/ProviderCookieSourceUITests.swift
git commit -m "feat(providers): add shared manual cookie header missing check."
```

---

### Task 4: Ollama card: Auto subtitle, "No cookie pasted" status, "Use Auto" action

**Files:**
- Modify: `Sources/CodexBar/Providers/Ollama/OllamaProviderImplementation.swift:48-88` (`settingsPickers`)
- Test: `Tests/CodexBarTests/ProviderSettingsDescriptorTests.swift:196-216` (existing Ollama test) plus new tests next to it

**Interfaces:**
- Consumes: `ProviderCookieSourceUI.manualHeaderMissing` (Task 3).
- Produces: action id `ollama-use-auto-cookie` (title `Use Auto`), status key `ollama_manual_cookie_missing_status`, subtitle key `ollama_cookie_source_auto_subtitle`, and
  ```swift
  @MainActor static func manualCookieMissing(settings: SettingsStore) -> Bool
  ```
  on `OllamaProviderImplementation`.

- [ ] **Step 1: Update the existing Ollama descriptor test and add three new ones**

In `Tests/CodexBarTests/ProviderSettingsDescriptorTests.swift`, in the test `ollama automatic cookie source exposes validated refresh action`, change the manual branch assertion:

```swift
        fixture.settings.ollamaCookieSource = .manual
        #expect(action.isVisible?() == false)
        #expect(picker.trailingText?() == L("ollama_manual_cookie_missing_status"))
```

Keep the rest of that test as is. Directly after it, add:

```swift
    @Test
    func `ollama manual cookie source without header offers use auto`() throws {
        let fixture = try self.makeSettingsFixture(suite: "ProviderSettingsDescriptorTests-ollama-use-auto")
        let context = fixture.settingsContext(provider: .ollama)
        let pickers = OllamaProviderImplementation().settingsPickers(context: context)
        let picker = try #require(pickers.first { $0.id == "ollama-cookie-source" })
        let useAuto = try #require(picker.trailingActions.first { $0.id == "ollama-use-auto-cookie" })

        #expect(useAuto.title == "Use Auto")
        #expect(useAuto.style == .bordered)
        #expect(useAuto.isVisible?() == false)

        fixture.settings.ollamaCookieSource = .manual
        fixture.settings.ollamaCookieHeader = ""
        #expect(useAuto.isVisible?() == true)
        #expect(picker.trailingText?() == L("ollama_manual_cookie_missing_status"))

        fixture.settings.ollamaCookieHeader = "   "
        #expect(useAuto.isVisible?() == true)

        fixture.settings.ollamaCookieHeader = "wos-session=abc"
        #expect(useAuto.isVisible?() == false)
        #expect(picker.trailingText?() == nil)
    }

    @Test
    func `ollama use auto hides in api mode and when keychain is disabled`() throws {
        let fixture = try self.makeSettingsFixture(suite: "ProviderSettingsDescriptorTests-ollama-use-auto-hidden")
        let context = fixture.settingsContext(provider: .ollama)
        let pickers = OllamaProviderImplementation().settingsPickers(context: context)
        let picker = try #require(pickers.first { $0.id == "ollama-cookie-source" })
        let useAuto = try #require(picker.trailingActions.first { $0.id == "ollama-use-auto-cookie" })

        fixture.settings.ollamaCookieSource = .manual
        fixture.settings.ollamaCookieHeader = ""
        #expect(useAuto.isVisible?() == true)

        fixture.settings.ollamaUsageDataSource = .api
        #expect(useAuto.isVisible?() == false)
        #expect(picker.trailingText?() == nil)

        fixture.settings.ollamaUsageDataSource = .auto
        fixture.settings.debugDisableKeychainAccess = true
        defer { fixture.settings.debugDisableKeychainAccess = false }
        #expect(useAuto.isVisible?() == false)
    }

    @Test
    func `ollama use auto action switches cookie source to auto`() async throws {
        let fixture = try self.makeSettingsFixture(suite: "ProviderSettingsDescriptorTests-ollama-use-auto-perform")
        let context = fixture.settingsContext(provider: .ollama)
        let pickers = OllamaProviderImplementation().settingsPickers(context: context)
        let picker = try #require(pickers.first { $0.id == "ollama-cookie-source" })
        let useAuto = try #require(picker.trailingActions.first { $0.id == "ollama-use-auto-cookie" })

        fixture.settings.ollamaCookieSource = .manual
        fixture.settings.ollamaCookieHeader = ""
        await useAuto.perform()

        #expect(fixture.settings.ollamaCookieSource == .auto)
        #expect(useAuto.isVisible?() == false)
    }

    @Test
    func `ollama manual cookie missing ignores token accounts`() {
        let settings = testSettingsStore(suiteName: "ProviderSettingsDescriptorTests-ollama-token-accounts")
        settings.ollamaCookieSource = .manual
        settings.ollamaCookieHeader = ""
        #expect(OllamaProviderImplementation.manualCookieMissing(settings: settings))

        settings.addTokenAccount(provider: .ollama, label: "Work", token: "wos-session=work")
        #expect(!OllamaProviderImplementation.manualCookieMissing(settings: settings))
    }
```

Note: `makeSettingsFixture` uses the default `FileTokenAccountStore`; that is why the token-account case uses `testSettingsStore(suiteName:)` (in-memory token store) and the static helper instead of the fixture.

`ProviderSettingsActionDescriptor.Style` has no associated values, so Swift synthesizes `Equatable` and `#expect(useAuto.style == .bordered)` compiles without changes.

- [ ] **Step 2: Run to verify the new tests fail**

Run: `swift test --filter ProviderSettingsDescriptorTests`
Expected: compile error on `OllamaProviderImplementation.manualCookieMissing`, or the four Ollama tests fail with `#require` on `ollama-use-auto-cookie`.

- [ ] **Step 3: Implement the card changes**

In `Sources/CodexBar/Providers/Ollama/OllamaProviderImplementation.swift`, add this static helper inside the struct, directly before `func settingsPickers`:

```swift
    @MainActor
    static func manualCookieMissing(settings: SettingsStore) -> Bool {
        ProviderCookieSourceUI.manualHeaderMissing(
            source: settings.ollamaCookieSource,
            header: settings.ollamaCookieHeader,
            hasTokenAccounts: !settings.tokenAccounts(for: .ollama).isEmpty)
    }
```

Then replace the `ProviderCookieSourceUI.picker(...)` call in `settingsPickers` with:

```swift
            ProviderCookieSourceUI.picker(
                id: "ollama-cookie-source",
                context: context,
                source: \.ollamaCookieSource,
                allowsOff: false,
                subtitles: {
                    .init(
                        auto: L("ollama_cookie_source_auto_subtitle"),
                        manual: L("Paste a Cookie header or cURL capture from %@.", "Ollama settings"),
                        off: L("%@ cookies are disabled.", "Ollama"))
                },
                trailingText: {
                    guard context.settings.ollamaUsageDataSource != .api else { return nil }
                    if Self.manualCookieMissing(settings: context.settings) {
                        return L("ollama_manual_cookie_missing_status")
                    }
                    return ProviderCookieRefreshAction.trailingText(
                        provider: .ollama,
                        cookieSource: context.settings.ollamaCookieSource,
                        context: context)
                },
                trailingActions: [
                    ProviderCookieRefreshAction.descriptor(
                        provider: .ollama,
                        cookieSource: { context.settings.ollamaCookieSource },
                        additionalVisibility: { context.settings.ollamaUsageDataSource != .api },
                        context: context),
                    ProviderSettingsActionDescriptor(
                        id: "ollama-use-auto-cookie",
                        title: "Use Auto",
                        style: .bordered,
                        isVisible: {
                            context.settings.ollamaUsageDataSource != .api
                                && !context.settings.debugDisableKeychainAccess
                                && Self.manualCookieMissing(settings: context.settings)
                        },
                        perform: { @MainActor in
                            context.settings.ollamaCookieSource = .auto
                        }),
                ]),
```

The refresh that follows the source flip comes from `UsageStore.observeSettingsChanges`; do not call `refreshProvider` here.

- [ ] **Step 4: Run to verify pass**

Run: `swift test --filter ProviderSettingsDescriptorTests`
Expected: all PASS, including the four Ollama tests.

- [ ] **Step 5: Format, lint, commit**

```bash
make check
git add Sources/CodexBar/Providers/Ollama/OllamaProviderImplementation.swift Tests/CodexBarTests/ProviderSettingsDescriptorTests.swift
git commit -m "feat(ollama): flag empty manual cookie and offer one-click switch to Auto."
```

---

### Task 5: "Sign in to Ollama…" menu entry

**Files:**
- Modify: `Sources/CodexBar/Providers/Ollama/OllamaProviderImplementation.swift:1-6` (imports, `supportsLoginFlow`) and add two methods
- Create: `Tests/CodexBarTests/OllamaMenuLoginActionTests.swift`

**Interfaces:**
- Consumes: `ProviderImplementation.loginMenuAction(context:)`, `runLoginFlow(context:)`, `MenuDescriptor.MenuAction.loginToProvider(url:)` (existing).
- Produces: menu label key `Sign in to Ollama…` (catalog entry in Task 6).

- [ ] **Step 1: Write the failing test**

Create `Tests/CodexBarTests/OllamaMenuLoginActionTests.swift`:

```swift
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
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter OllamaMenuLoginActionTests`
Expected: `ollama implementation declares a login flow` FAIL (default is `false`); `ollama menu offers a sign in link` FAIL (no login entry).

- [ ] **Step 3: Implement the login entry**

In `Sources/CodexBar/Providers/Ollama/OllamaProviderImplementation.swift`:

Change the imports and header to:

```swift
import AppKit
import CodexBarCore
import Foundation

struct OllamaProviderImplementation: ProviderImplementation {
    let id: UsageProvider = .ollama
    let supportsLoginFlow: Bool = true

    private static let signInURL = URL(string: "https://ollama.com/signin")!
```

Add these two methods directly after `applyTokenAccountCookieSource(settings:)`:

```swift
    @MainActor
    func loginMenuAction(context _: ProviderMenuLoginContext)
        -> (label: String, action: MenuDescriptor.MenuAction)?
    {
        ("Sign in to Ollama…", .loginToProvider(url: Self.signInURL.absoluteString))
    }

    @MainActor
    func runLoginFlow(context _: ProviderLoginContext) async -> Bool {
        NSWorkspace.shared.open(Self.signInURL)
        return false
    }
```

`runLoginFlow` returns `false` on purpose: nothing is captured, so the caller must not treat it as a completed login. The user clicks Refresh afterwards, exactly like Devin.

- [ ] **Step 4: Run to verify pass**

Run: `swift test --filter "OllamaMenuLoginActionTests|ProviderSettingsDescriptorTests"`
Expected: all PASS.

- [ ] **Step 5: Format, lint, commit**

```bash
make check
git add Sources/CodexBar/Providers/Ollama/OllamaProviderImplementation.swift Tests/CodexBarTests/OllamaMenuLoginActionTests.swift
git commit -m "feat(ollama): add sign-in menu entry that opens the Ollama login page."
```

---

### Task 6: Localize the seven new keys in all 23 catalogs

**Files:**
- Modify: `Sources/CodexBar/Resources/{ar,ca,de,en,es,fa,fr,gl,id,it,ja,ko,nl,pl,pt-BR,ru,sv,th,tr,uk,vi,zh-Hans,zh-Hant}.lproj/Localizable.strings`

**Interfaces:**
- Consumes: keys from Tasks 2, 4, 5.
- Produces: catalog entries. No code.

- [ ] **Step 1: Confirm the check currently passes with the new keys absent**

Run: `node Scripts/check-app-locales.mjs`
Expected: passes (the script compares catalogs to `en`; the keys are not in `en` yet).

- [ ] **Step 2: Insert the seven lines into every catalog**

In each of the 23 files, find the line that starts with `"ollama_browser_cookie_decryption_disabled"` and insert the locale's seven lines directly after it. Every value is one line; do not wrap. Straight double quotes inside a value are not used, so no escaping is needed.

**en**
```
"ollama_manual_cookie_empty" = "Cookie source is set to Manual, but no cookie header is pasted. Paste a Cookie header from https://ollama.com/settings, or switch Cookie source to Auto to import browser cookies.";
"ollama_manual_cookie_unrecognized" = "The pasted Ollama cookie header has no session cookie (wos-session). Copy the full Cookie header from https://ollama.com/settings while signed in, then paste it again.";
"ollama_no_browser_session" = "No Ollama session cookie found in your browsers. Sign in at https://ollama.com/signin in Chrome, then click Refresh (⌘R). If your session is only in Safari or another browser, set Cookie source to Manual and paste a cookie header.";
"ollama_cookie_source_auto_subtitle" = "Imports your ollama.com session from Chrome, then other browsers. The first import may show a macOS Keychain prompt for “Chrome Safe Storage”; click Always Allow.";
"ollama_manual_cookie_missing_status" = "No cookie pasted";
"Use Auto" = "Use Auto";
"Sign in to Ollama…" = "Sign in to Ollama…";
```

**ar**
```
"ollama_manual_cookie_empty" = "مصدر ملفات تعريف الارتباط مضبوط على «يدوي»، لكن لم يتم لصق أي ترويسة Cookie. الصق ترويسة Cookie من https://ollama.com/settings، أو بدّل مصدر ملفات تعريف الارتباط إلى «تلقائي» لاستيرادها من المتصفح.";
"ollama_manual_cookie_unrecognized" = "ترويسة Cookie الملصقة لـ Ollama لا تحتوي على ملف تعريف ارتباط الجلسة (wos-session). انسخ ترويسة Cookie الكاملة من https://ollama.com/settings أثناء تسجيل الدخول، ثم الصقها مجددًا.";
"ollama_no_browser_session" = "لم يتم العثور على ملف تعريف ارتباط جلسة Ollama في متصفحاتك. سجّل الدخول عبر https://ollama.com/signin في Chrome ثم انقر «تحديث» (⌘R). إذا كانت جلستك في Safari أو متصفح آخر فقط، فاضبط مصدر ملفات تعريف الارتباط على «يدوي» والصق ترويسة Cookie.";
"ollama_cookie_source_auto_subtitle" = "يستورد جلسة ollama.com من Chrome ثم من المتصفحات الأخرى. قد يُظهر الاستيراد الأول مطالبة من سلسلة مفاتيح macOS بخصوص “Chrome Safe Storage”؛ انقر «السماح دائمًا».";
"ollama_manual_cookie_missing_status" = "لم يتم لصق أي ملف تعريف ارتباط";
"Use Auto" = "استخدام التلقائي";
"Sign in to Ollama…" = "تسجيل الدخول إلى Ollama…";
```

**ca**
```
"ollama_manual_cookie_empty" = "La font de galetes està definida com a Manual, però no s’ha enganxat cap capçalera Cookie. Enganxa una capçalera Cookie des de https://ollama.com/settings o canvia la font de galetes a Automàtic per importar les galetes del navegador.";
"ollama_manual_cookie_unrecognized" = "La capçalera Cookie d’Ollama enganxada no conté cap galeta de sessió (wos-session). Copia la capçalera Cookie completa des de https://ollama.com/settings amb la sessió iniciada i torna-la a enganxar.";
"ollama_no_browser_session" = "No s’ha trobat cap galeta de sessió d’Ollama als teus navegadors. Inicia la sessió a https://ollama.com/signin amb Chrome i fes clic a Actualitza (⌘R). Si la sessió només és a Safari o a un altre navegador, defineix la font de galetes com a Manual i enganxa una capçalera Cookie.";
"ollama_cookie_source_auto_subtitle" = "Importa la sessió d’ollama.com des de Chrome i després d’altres navegadors. La primera importació pot mostrar un avís del Clauer de macOS per a “Chrome Safe Storage”; fes clic a Permet sempre.";
"ollama_manual_cookie_missing_status" = "Cap galeta enganxada";
"Use Auto" = "Usa Automàtic";
"Sign in to Ollama…" = "Inicia la sessió a Ollama…";
```

**de**
```
"ollama_manual_cookie_empty" = "Die Cookie-Quelle steht auf Manuell, aber es ist kein Cookie-Header eingefügt. Füge einen Cookie-Header von https://ollama.com/settings ein oder stelle die Cookie-Quelle auf Automatisch, um Browser-Cookies zu importieren.";
"ollama_manual_cookie_unrecognized" = "Der eingefügte Ollama-Cookie-Header enthält kein Sitzungs-Cookie (wos-session). Kopiere den vollständigen Cookie-Header von https://ollama.com/settings, während du angemeldet bist, und füge ihn erneut ein.";
"ollama_no_browser_session" = "In deinen Browsern wurde kein Ollama-Sitzungs-Cookie gefunden. Melde dich in Chrome unter https://ollama.com/signin an und klicke dann auf Aktualisieren (⌘R). Wenn deine Sitzung nur in Safari oder einem anderen Browser besteht, stelle die Cookie-Quelle auf Manuell und füge einen Cookie-Header ein.";
"ollama_cookie_source_auto_subtitle" = "Importiert deine ollama.com-Sitzung aus Chrome, danach aus anderen Browsern. Beim ersten Import kann macOS eine Schlüsselbund-Abfrage für “Chrome Safe Storage” anzeigen; klicke auf Immer erlauben.";
"ollama_manual_cookie_missing_status" = "Kein Cookie eingefügt";
"Use Auto" = "Automatisch verwenden";
"Sign in to Ollama…" = "Bei Ollama anmelden…";
```

**es**
```
"ollama_manual_cookie_empty" = "La fuente de cookies está en Manual, pero no se ha pegado ningún encabezado Cookie. Pega un encabezado Cookie desde https://ollama.com/settings o cambia la fuente de cookies a Automático para importar las cookies del navegador.";
"ollama_manual_cookie_unrecognized" = "El encabezado Cookie de Ollama pegado no contiene ninguna cookie de sesión (wos-session). Copia el encabezado Cookie completo desde https://ollama.com/settings con la sesión iniciada y vuelve a pegarlo.";
"ollama_no_browser_session" = "No se encontró ninguna cookie de sesión de Ollama en tus navegadores. Inicia sesión en https://ollama.com/signin con Chrome y haz clic en Actualizar (⌘R). Si tu sesión solo está en Safari u otro navegador, cambia la fuente de cookies a Manual y pega un encabezado Cookie.";
"ollama_cookie_source_auto_subtitle" = "Importa tu sesión de ollama.com desde Chrome y luego desde otros navegadores. La primera importación puede mostrar un aviso del Llavero de macOS para “Chrome Safe Storage”; haz clic en Permitir siempre.";
"ollama_manual_cookie_missing_status" = "Ninguna cookie pegada";
"Use Auto" = "Usar Automático";
"Sign in to Ollama…" = "Iniciar sesión en Ollama…";
```

**fa**
```
"ollama_manual_cookie_empty" = "منبع کوکی روی «دستی» تنظیم شده، اما هیچ سرآیند Cookie جای‌گذاری نشده است. یک سرآیند Cookie از https://ollama.com/settings جای‌گذاری کنید یا منبع کوکی را به «خودکار» تغییر دهید تا کوکی‌های مرورگر وارد شوند.";
"ollama_manual_cookie_unrecognized" = "سرآیند Cookie جای‌گذاری‌شدهٔ Ollama کوکی نشست (wos-session) ندارد. در حالت واردشده، سرآیند Cookie کامل را از https://ollama.com/settings کپی کنید و دوباره جای‌گذاری کنید.";
"ollama_no_browser_session" = "کوکی نشست Ollama در مرورگرهای شما پیدا نشد. در Chrome از طریق https://ollama.com/signin وارد شوید و سپس روی «تازه‌سازی» (⌘R) کلیک کنید. اگر نشست شما فقط در Safari یا مرورگر دیگری است، منبع کوکی را روی «دستی» بگذارید و یک سرآیند Cookie جای‌گذاری کنید.";
"ollama_cookie_source_auto_subtitle" = "نشست ollama.com را از Chrome و سپس از مرورگرهای دیگر وارد می‌کند. نخستین واردکردن ممکن است پیام کی‌چین macOS را برای “Chrome Safe Storage” نشان دهد؛ روی «همیشه اجازه بده» کلیک کنید.";
"ollama_manual_cookie_missing_status" = "کوکی‌ای جای‌گذاری نشده";
"Use Auto" = "استفاده از خودکار";
"Sign in to Ollama…" = "ورود به Ollama…";
```

**fr**
```
"ollama_manual_cookie_empty" = "La source des cookies est réglée sur Manuel, mais aucun en-tête Cookie n’est collé. Collez un en-tête Cookie depuis https://ollama.com/settings, ou passez la source des cookies sur Automatique pour importer les cookies du navigateur.";
"ollama_manual_cookie_unrecognized" = "L’en-tête Cookie Ollama collé ne contient aucun cookie de session (wos-session). Copiez l’en-tête Cookie complet depuis https://ollama.com/settings en étant connecté, puis collez-le à nouveau.";
"ollama_no_browser_session" = "Aucun cookie de session Ollama trouvé dans vos navigateurs. Connectez-vous sur https://ollama.com/signin dans Chrome, puis cliquez sur Actualiser (⌘R). Si votre session n’existe que dans Safari ou un autre navigateur, réglez la source des cookies sur Manuel et collez un en-tête Cookie.";
"ollama_cookie_source_auto_subtitle" = "Importe votre session ollama.com depuis Chrome, puis depuis les autres navigateurs. La première importation peut afficher une demande du trousseau macOS pour “Chrome Safe Storage” ; cliquez sur Toujours autoriser.";
"ollama_manual_cookie_missing_status" = "Aucun cookie collé";
"Use Auto" = "Utiliser Automatique";
"Sign in to Ollama…" = "Se connecter à Ollama…";
```

**gl**
```
"ollama_manual_cookie_empty" = "A fonte de cookies está en Manual, pero non se pegou ningunha cabeceira Cookie. Pega unha cabeceira Cookie desde https://ollama.com/settings ou cambia a fonte de cookies a Automático para importar as cookies do navegador.";
"ollama_manual_cookie_unrecognized" = "A cabeceira Cookie de Ollama pegada non contén ningunha cookie de sesión (wos-session). Copia a cabeceira Cookie completa desde https://ollama.com/settings coa sesión iniciada e volve pegala.";
"ollama_no_browser_session" = "Non se atopou ningunha cookie de sesión de Ollama nos teus navegadores. Inicia sesión en https://ollama.com/signin con Chrome e preme Actualizar (⌘R). Se a túa sesión só está en Safari ou noutro navegador, cambia a fonte de cookies a Manual e pega unha cabeceira Cookie.";
"ollama_cookie_source_auto_subtitle" = "Importa a túa sesión de ollama.com desde Chrome e despois desde outros navegadores. A primeira importación pode mostrar un aviso do Chaveiro de macOS para “Chrome Safe Storage”; preme Permitir sempre.";
"ollama_manual_cookie_missing_status" = "Ningunha cookie pegada";
"Use Auto" = "Usar Automático";
"Sign in to Ollama…" = "Iniciar sesión en Ollama…";
```

**id**
```
"ollama_manual_cookie_empty" = "Sumber cookie disetel ke Manual, tetapi belum ada header Cookie yang ditempel. Tempel header Cookie dari https://ollama.com/settings, atau ubah sumber cookie ke Otomatis untuk mengimpor cookie browser.";
"ollama_manual_cookie_unrecognized" = "Header Cookie Ollama yang ditempel tidak memiliki cookie sesi (wos-session). Salin header Cookie lengkap dari https://ollama.com/settings saat sudah masuk, lalu tempel lagi.";
"ollama_no_browser_session" = "Cookie sesi Ollama tidak ditemukan di browser Anda. Masuk di https://ollama.com/signin melalui Chrome, lalu klik Segarkan (⌘R). Jika sesi Anda hanya ada di Safari atau browser lain, setel sumber cookie ke Manual dan tempel header Cookie.";
"ollama_cookie_source_auto_subtitle" = "Mengimpor sesi ollama.com Anda dari Chrome, lalu dari browser lain. Impor pertama mungkin menampilkan permintaan Keychain macOS untuk “Chrome Safe Storage”; klik Selalu Izinkan.";
"ollama_manual_cookie_missing_status" = "Belum ada cookie yang ditempel";
"Use Auto" = "Gunakan Otomatis";
"Sign in to Ollama…" = "Masuk ke Ollama…";
```

**it**
```
"ollama_manual_cookie_empty" = "L’origine dei cookie è impostata su Manuale, ma non è stato incollato alcun header Cookie. Incolla un header Cookie da https://ollama.com/settings oppure imposta l’origine dei cookie su Automatico per importare i cookie del browser.";
"ollama_manual_cookie_unrecognized" = "L’header Cookie di Ollama incollato non contiene alcun cookie di sessione (wos-session). Copia l’header Cookie completo da https://ollama.com/settings mentre sei connesso, poi incollalo di nuovo.";
"ollama_no_browser_session" = "Nessun cookie di sessione Ollama trovato nei tuoi browser. Accedi su https://ollama.com/signin in Chrome, poi fai clic su Aggiorna (⌘R). Se la tua sessione è solo in Safari o in un altro browser, imposta l’origine dei cookie su Manuale e incolla un header Cookie.";
"ollama_cookie_source_auto_subtitle" = "Importa la tua sessione ollama.com da Chrome, poi dagli altri browser. La prima importazione può mostrare una richiesta del Portachiavi di macOS per “Chrome Safe Storage”; fai clic su Consenti sempre.";
"ollama_manual_cookie_missing_status" = "Nessun cookie incollato";
"Use Auto" = "Usa Automatico";
"Sign in to Ollama…" = "Accedi a Ollama…";
```

**ja**
```
"ollama_manual_cookie_empty" = "Cookie ソースが「手動」に設定されていますが、Cookie ヘッダーが貼り付けられていません。https://ollama.com/settings から Cookie ヘッダーを貼り付けるか、Cookie ソースを「自動」に切り替えてブラウザの Cookie を読み込んでください。";
"ollama_manual_cookie_unrecognized" = "貼り付けられた Ollama の Cookie ヘッダーにセッション Cookie（wos-session）が含まれていません。サインインした状態で https://ollama.com/settings から完全な Cookie ヘッダーをコピーし、もう一度貼り付けてください。";
"ollama_no_browser_session" = "ブラウザに Ollama のセッション Cookie が見つかりません。Chrome で https://ollama.com/signin にサインインしてから「更新」（⌘R）をクリックしてください。セッションが Safari や他のブラウザにしかない場合は、Cookie ソースを「手動」にして Cookie ヘッダーを貼り付けてください。";
"ollama_cookie_source_auto_subtitle" = "ollama.com のセッションを Chrome、次に他のブラウザから読み込みます。初回の読み込み時に macOS のキーチェーンが “Chrome Safe Storage” へのアクセスを求めることがあります。「常に許可」をクリックしてください。";
"ollama_manual_cookie_missing_status" = "Cookie が貼り付けられていません";
"Use Auto" = "自動を使用";
"Sign in to Ollama…" = "Ollama にサインイン…";
```

**ko**
```
"ollama_manual_cookie_empty" = "쿠키 소스가 수동으로 설정되어 있지만 붙여넣은 Cookie 헤더가 없습니다. https://ollama.com/settings 에서 Cookie 헤더를 붙여넣거나, 쿠키 소스를 자동으로 바꿔 브라우저 쿠키를 가져오세요.";
"ollama_manual_cookie_unrecognized" = "붙여넣은 Ollama Cookie 헤더에 세션 쿠키(wos-session)가 없습니다. 로그인한 상태에서 https://ollama.com/settings 의 전체 Cookie 헤더를 복사한 뒤 다시 붙여넣으세요.";
"ollama_no_browser_session" = "브라우저에서 Ollama 세션 쿠키를 찾을 수 없습니다. Chrome에서 https://ollama.com/signin 에 로그인한 다음 새로고침(⌘R)을 클릭하세요. 세션이 Safari나 다른 브라우저에만 있다면 쿠키 소스를 수동으로 설정하고 Cookie 헤더를 붙여넣으세요.";
"ollama_cookie_source_auto_subtitle" = "Chrome에서, 그다음 다른 브라우저에서 ollama.com 세션을 가져옵니다. 처음 가져올 때 macOS 키체인이 “Chrome Safe Storage” 접근을 요청할 수 있습니다. 항상 허용을 클릭하세요.";
"ollama_manual_cookie_missing_status" = "붙여넣은 쿠키 없음";
"Use Auto" = "자동 사용";
"Sign in to Ollama…" = "Ollama에 로그인…";
```

**nl**
```
"ollama_manual_cookie_empty" = "De cookiebron staat op Handmatig, maar er is geen Cookie-header geplakt. Plak een Cookie-header van https://ollama.com/settings of zet de cookiebron op Automatisch om browsercookies te importeren.";
"ollama_manual_cookie_unrecognized" = "De geplakte Ollama-Cookie-header bevat geen sessiecookie (wos-session). Kopieer de volledige Cookie-header van https://ollama.com/settings terwijl je bent ingelogd en plak hem opnieuw.";
"ollama_no_browser_session" = "Geen Ollama-sessiecookie gevonden in je browsers. Log in op https://ollama.com/signin in Chrome en klik daarna op Vernieuwen (⌘R). Staat je sessie alleen in Safari of een andere browser, zet de cookiebron dan op Handmatig en plak een Cookie-header.";
"ollama_cookie_source_auto_subtitle" = "Importeert je ollama.com-sessie uit Chrome en daarna uit andere browsers. Bij de eerste import kan macOS een sleutelhangerprompt voor “Chrome Safe Storage” tonen; klik op Altijd toestaan.";
"ollama_manual_cookie_missing_status" = "Geen cookie geplakt";
"Use Auto" = "Automatisch gebruiken";
"Sign in to Ollama…" = "Inloggen bij Ollama…";
```

**pl**
```
"ollama_manual_cookie_empty" = "Źródło plików cookie jest ustawione na Ręcznie, ale nie wklejono nagłówka Cookie. Wklej nagłówek Cookie z https://ollama.com/settings lub przełącz źródło plików cookie na Automatycznie, aby zaimportować pliki cookie z przeglądarki.";
"ollama_manual_cookie_unrecognized" = "Wklejony nagłówek Cookie Ollama nie zawiera pliku cookie sesji (wos-session). Skopiuj pełny nagłówek Cookie z https://ollama.com/settings po zalogowaniu i wklej go ponownie.";
"ollama_no_browser_session" = "Nie znaleziono pliku cookie sesji Ollama w Twoich przeglądarkach. Zaloguj się na https://ollama.com/signin w Chrome, a następnie kliknij Odśwież (⌘R). Jeśli Twoja sesja jest tylko w Safari lub innej przeglądarce, ustaw źródło plików cookie na Ręcznie i wklej nagłówek Cookie.";
"ollama_cookie_source_auto_subtitle" = "Importuje sesję ollama.com z Chrome, a potem z innych przeglądarek. Pierwszy import może wyświetlić monit pęku kluczy macOS dla “Chrome Safe Storage”; kliknij Zawsze zezwalaj.";
"ollama_manual_cookie_missing_status" = "Nie wklejono pliku cookie";
"Use Auto" = "Użyj Automatycznie";
"Sign in to Ollama…" = "Zaloguj się do Ollama…";
```

**pt-BR**
```
"ollama_manual_cookie_empty" = "A origem dos cookies está definida como Manual, mas nenhum cabeçalho Cookie foi colado. Cole um cabeçalho Cookie de https://ollama.com/settings ou mude a origem dos cookies para Automático para importar os cookies do navegador.";
"ollama_manual_cookie_unrecognized" = "O cabeçalho Cookie do Ollama colado não contém cookie de sessão (wos-session). Copie o cabeçalho Cookie completo de https://ollama.com/settings com a sessão iniciada e cole novamente.";
"ollama_no_browser_session" = "Nenhum cookie de sessão do Ollama foi encontrado nos seus navegadores. Entre em https://ollama.com/signin no Chrome e clique em Atualizar (⌘R). Se a sua sessão estiver apenas no Safari ou em outro navegador, defina a origem dos cookies como Manual e cole um cabeçalho Cookie.";
"ollama_cookie_source_auto_subtitle" = "Importa a sua sessão do ollama.com do Chrome e depois de outros navegadores. A primeira importação pode exibir um aviso das Chaves do macOS para “Chrome Safe Storage”; clique em Sempre Permitir.";
"ollama_manual_cookie_missing_status" = "Nenhum cookie colado";
"Use Auto" = "Usar Automático";
"Sign in to Ollama…" = "Entrar no Ollama…";
```

**ru**
```
"ollama_manual_cookie_empty" = "Источник cookie установлен в «Вручную», но заголовок Cookie не вставлен. Вставьте заголовок Cookie с https://ollama.com/settings или переключите источник cookie на «Авто», чтобы импортировать cookie из браузера.";
"ollama_manual_cookie_unrecognized" = "Во вставленном заголовке Cookie для Ollama нет cookie сессии (wos-session). Скопируйте полный заголовок Cookie с https://ollama.com/settings, войдя в аккаунт, и вставьте его снова.";
"ollama_no_browser_session" = "Cookie сессии Ollama не найден в ваших браузерах. Войдите на https://ollama.com/signin в Chrome и нажмите «Обновить» (⌘R). Если сессия есть только в Safari или другом браузере, установите источник cookie в «Вручную» и вставьте заголовок Cookie.";
"ollama_cookie_source_auto_subtitle" = "Импортирует вашу сессию ollama.com из Chrome, затем из других браузеров. При первом импорте macOS может запросить доступ к связке ключей для “Chrome Safe Storage”; нажмите «Всегда разрешать».";
"ollama_manual_cookie_missing_status" = "Cookie не вставлен";
"Use Auto" = "Использовать Авто";
"Sign in to Ollama…" = "Войти в Ollama…";
```

**sv**
```
"ollama_manual_cookie_empty" = "Cookiekällan är inställd på Manuell, men ingen Cookie-rubrik har klistrats in. Klistra in en Cookie-rubrik från https://ollama.com/settings eller byt cookiekälla till Automatisk för att importera webbläsarens cookies.";
"ollama_manual_cookie_unrecognized" = "Den inklistrade Ollama-Cookie-rubriken saknar sessionscookie (wos-session). Kopiera hela Cookie-rubriken från https://ollama.com/settings medan du är inloggad och klistra in den igen.";
"ollama_no_browser_session" = "Ingen Ollama-sessionscookie hittades i dina webbläsare. Logga in på https://ollama.com/signin i Chrome och klicka sedan på Uppdatera (⌘R). Om din session bara finns i Safari eller en annan webbläsare, ställ in cookiekällan på Manuell och klistra in en Cookie-rubrik.";
"ollama_cookie_source_auto_subtitle" = "Importerar din ollama.com-session från Chrome och därefter från andra webbläsare. Första importen kan visa en nyckelringsfråga i macOS för “Chrome Safe Storage”; klicka på Tillåt alltid.";
"ollama_manual_cookie_missing_status" = "Ingen cookie inklistrad";
"Use Auto" = "Använd Automatisk";
"Sign in to Ollama…" = "Logga in på Ollama…";
```

**th**
```
"ollama_manual_cookie_empty" = "แหล่งคุกกี้ถูกตั้งเป็น ‘ด้วยตนเอง’ แต่ยังไม่ได้วางส่วนหัว Cookie ให้วางส่วนหัว Cookie จาก https://ollama.com/settings หรือเปลี่ยนแหล่งคุกกี้เป็น ‘อัตโนมัติ’ เพื่อนำเข้าคุกกี้จากเบราว์เซอร์";
"ollama_manual_cookie_unrecognized" = "ส่วนหัว Cookie ของ Ollama ที่วางไว้ไม่มีคุกกี้เซสชัน (wos-session) ให้คัดลอกส่วนหัว Cookie ฉบับเต็มจาก https://ollama.com/settings ขณะลงชื่อเข้าใช้อยู่ แล้ววางอีกครั้ง";
"ollama_no_browser_session" = "ไม่พบคุกกี้เซสชันของ Ollama ในเบราว์เซอร์ของคุณ ให้ลงชื่อเข้าใช้ที่ https://ollama.com/signin ใน Chrome แล้วคลิก รีเฟรช (⌘R) หากเซสชันของคุณอยู่ใน Safari หรือเบราว์เซอร์อื่นเท่านั้น ให้ตั้งแหล่งคุกกี้เป็น ‘ด้วยตนเอง’ แล้ววางส่วนหัว Cookie";
"ollama_cookie_source_auto_subtitle" = "นำเข้าเซสชัน ollama.com ของคุณจาก Chrome แล้วจึงจากเบราว์เซอร์อื่น การนำเข้าครั้งแรกอาจแสดงข้อความขอสิทธิ์พวงกุญแจของ macOS สำหรับ “Chrome Safe Storage” ให้คลิก อนุญาตเสมอ";
"ollama_manual_cookie_missing_status" = "ยังไม่ได้วางคุกกี้";
"Use Auto" = "ใช้อัตโนมัติ";
"Sign in to Ollama…" = "ลงชื่อเข้าใช้ Ollama…";
```

**tr**
```
"ollama_manual_cookie_empty" = "Çerez kaynağı Manuel olarak ayarlı, ancak hiçbir Cookie başlığı yapıştırılmamış. https://ollama.com/settings adresinden bir Cookie başlığı yapıştırın veya tarayıcı çerezlerini içe aktarmak için çerez kaynağını Otomatik olarak değiştirin.";
"ollama_manual_cookie_unrecognized" = "Yapıştırılan Ollama Cookie başlığında oturum çerezi (wos-session) yok. Oturum açıkken https://ollama.com/settings adresinden tam Cookie başlığını kopyalayıp yeniden yapıştırın.";
"ollama_no_browser_session" = "Tarayıcılarınızda Ollama oturum çerezi bulunamadı. Chrome’da https://ollama.com/signin adresinden oturum açın, ardından Yenile (⌘R) düğmesine tıklayın. Oturumunuz yalnızca Safari’de veya başka bir tarayıcıdaysa çerez kaynağını Manuel olarak ayarlayın ve bir Cookie başlığı yapıştırın.";
"ollama_cookie_source_auto_subtitle" = "ollama.com oturumunuzu önce Chrome’dan, sonra diğer tarayıcılardan içe aktarır. İlk içe aktarma, “Chrome Safe Storage” için bir macOS Anahtar Zinciri istemi gösterebilir; Her Zaman İzin Ver’e tıklayın.";
"ollama_manual_cookie_missing_status" = "Çerez yapıştırılmadı";
"Use Auto" = "Otomatik Kullan";
"Sign in to Ollama…" = "Ollama’da oturum aç…";
```

**uk**
```
"ollama_manual_cookie_empty" = "Джерело cookie встановлено на «Вручну», але заголовок Cookie не вставлено. Вставте заголовок Cookie з https://ollama.com/settings або перемкніть джерело cookie на «Авто», щоб імпортувати cookie з браузера.";
"ollama_manual_cookie_unrecognized" = "У вставленому заголовку Cookie для Ollama немає cookie сеансу (wos-session). Скопіюйте повний заголовок Cookie з https://ollama.com/settings, увійшовши в обліковий запис, і вставте його знову.";
"ollama_no_browser_session" = "Cookie сеансу Ollama не знайдено у ваших браузерах. Увійдіть на https://ollama.com/signin у Chrome, а потім натисніть «Оновити» (⌘R). Якщо сеанс є лише в Safari чи іншому браузері, установіть джерело cookie на «Вручну» та вставте заголовок Cookie.";
"ollama_cookie_source_auto_subtitle" = "Імпортує ваш сеанс ollama.com із Chrome, а потім з інших браузерів. Під час першого імпорту macOS може запитати доступ до в’язки ключів для “Chrome Safe Storage”; натисніть «Завжди дозволяти».";
"ollama_manual_cookie_missing_status" = "Cookie не вставлено";
"Use Auto" = "Використовувати Авто";
"Sign in to Ollama…" = "Увійти в Ollama…";
```

**vi**
```
"ollama_manual_cookie_empty" = "Nguồn cookie đang đặt là Thủ công nhưng chưa dán tiêu đề Cookie nào. Hãy dán tiêu đề Cookie từ https://ollama.com/settings hoặc chuyển nguồn cookie sang Tự động để nhập cookie từ trình duyệt.";
"ollama_manual_cookie_unrecognized" = "Tiêu đề Cookie Ollama đã dán không có cookie phiên (wos-session). Hãy sao chép toàn bộ tiêu đề Cookie từ https://ollama.com/settings khi đã đăng nhập rồi dán lại.";
"ollama_no_browser_session" = "Không tìm thấy cookie phiên Ollama trong các trình duyệt của bạn. Hãy đăng nhập tại https://ollama.com/signin bằng Chrome rồi bấm Làm mới (⌘R). Nếu phiên của bạn chỉ có trong Safari hoặc trình duyệt khác, hãy đặt nguồn cookie là Thủ công và dán tiêu đề Cookie.";
"ollama_cookie_source_auto_subtitle" = "Nhập phiên ollama.com của bạn từ Chrome, sau đó từ các trình duyệt khác. Lần nhập đầu tiên có thể hiện hộp thoại Keychain của macOS cho “Chrome Safe Storage”; hãy bấm Luôn cho phép.";
"ollama_manual_cookie_missing_status" = "Chưa dán cookie";
"Use Auto" = "Dùng Tự động";
"Sign in to Ollama…" = "Đăng nhập Ollama…";
```

**zh-Hans**
```
"ollama_manual_cookie_empty" = "Cookie 来源已设为“手动”，但尚未粘贴 Cookie 标头。请从 https://ollama.com/settings 粘贴 Cookie 标头，或将 Cookie 来源切换为“自动”以导入浏览器 Cookie。";
"ollama_manual_cookie_unrecognized" = "粘贴的 Ollama Cookie 标头不包含会话 Cookie（wos-session）。请在已登录状态下从 https://ollama.com/settings 复制完整的 Cookie 标头，然后重新粘贴。";
"ollama_no_browser_session" = "在你的浏览器中未找到 Ollama 会话 Cookie。请在 Chrome 中登录 https://ollama.com/signin，然后点击“刷新”（⌘R）。如果你的会话只存在于 Safari 或其他浏览器，请将 Cookie 来源设为“手动”并粘贴 Cookie 标头。";
"ollama_cookie_source_auto_subtitle" = "从 Chrome 导入你的 ollama.com 会话，其次是其他浏览器。首次导入可能会弹出 macOS 钥匙串对 “Chrome Safe Storage” 的访问请求，请点击“始终允许”。";
"ollama_manual_cookie_missing_status" = "尚未粘贴 Cookie";
"Use Auto" = "使用自动";
"Sign in to Ollama…" = "登录 Ollama…";
```

**zh-Hant**
```
"ollama_manual_cookie_empty" = "Cookie 來源已設為「手動」，但尚未貼上 Cookie 標頭。請從 https://ollama.com/settings 貼上 Cookie 標頭，或將 Cookie 來源切換為「自動」以匯入瀏覽器 Cookie。";
"ollama_manual_cookie_unrecognized" = "貼上的 Ollama Cookie 標頭不含工作階段 Cookie（wos-session）。請在已登入狀態下從 https://ollama.com/settings 複製完整的 Cookie 標頭，然後重新貼上。";
"ollama_no_browser_session" = "在你的瀏覽器中找不到 Ollama 工作階段 Cookie。請在 Chrome 登入 https://ollama.com/signin，然後按一下「重新整理」（⌘R）。如果你的工作階段只存在於 Safari 或其他瀏覽器，請將 Cookie 來源設為「手動」並貼上 Cookie 標頭。";
"ollama_cookie_source_auto_subtitle" = "從 Chrome 匯入你的 ollama.com 工作階段，其次是其他瀏覽器。首次匯入時 macOS 鑰匙圈可能會要求存取 “Chrome Safe Storage”，請按一下「永遠允許」。";
"ollama_manual_cookie_missing_status" = "尚未貼上 Cookie";
"Use Auto" = "使用自動";
"Sign in to Ollama…" = "登入 Ollama…";
```

- [ ] **Step 3: Verify every catalog has all seven keys**

Run:
```bash
for key in ollama_manual_cookie_empty ollama_manual_cookie_unrecognized ollama_no_browser_session ollama_cookie_source_auto_subtitle ollama_manual_cookie_missing_status "Use Auto" "Sign in to Ollama…"; do
  count=$(grep -l -F "\"$key\" = " Sources/CodexBar/Resources/*.lproj/Localizable.strings | wc -l | tr -d ' ')
  echo "$count $key"
done
node Scripts/check-app-locales.mjs
```
Expected: seven lines each starting with `23`, then the locale check passes with no errors.

- [ ] **Step 4: Run the tests that read the catalogs and commit**

Run: `swift test --filter "ProviderSettingsDescriptorTests|OllamaMenuLoginActionTests"`
Expected: PASS (the `L(...)` comparisons in those tests resolve through the catalogs now).

```bash
make check
git add Sources/CodexBar/Resources/*.lproj/Localizable.strings
git commit -m "feat(ollama): localize cookie setup hints in all catalogs."
```

---

### Task 7: Update `docs/ollama.md` and `CHANGELOG.md`

**Files:**
- Modify: `docs/ollama.md` (Setup step 4, Manual cookie import, Troubleshooting)
- Modify: `CHANGELOG.md` (under `## 0.64.2 — Unreleased`)

- [ ] **Step 1: Update Setup step 4 in `docs/ollama.md`**

Replace:
```
4. For quota bars, leave **Cookie source** on **Auto** (recommended, imports Chrome cookies by default).
```
with:
```
4. For quota bars, leave **Cookie source** on **Auto** (recommended, imports Chrome cookies first, then other browsers).
   The first import may show a macOS Keychain prompt for “Chrome Safe Storage”. That prompt is expected: CodexBar
   needs the key to decrypt Chrome’s cookie store. Click **Always Allow** so it does not repeat.
```

- [ ] **Step 2: Extend the Manual cookie import section**

Replace:
```
### Manual cookie import (optional)

1. Open `https://ollama.com/settings` in your browser.
2. Copy a `Cookie:` header from the Network tab.
3. Paste it into **Ollama → Cookie source → Manual**.
```
with:
```
### Manual cookie import (optional)

1. Open `https://ollama.com/settings` in your browser.
2. Copy a `Cookie:` header from the Network tab.
3. Paste it into **Ollama → Cookie source → Manual**.

While **Manual** is selected and the field is empty, the Cookie source row shows **No cookie pasted** and a
**Use Auto** button that switches back to browser import. The menu also offers **Sign in to Ollama…**, which opens
`https://ollama.com/signin` in your browser; click **Refresh** afterwards.
```

- [ ] **Step 3: Replace the first troubleshooting entry**

Replace:
```
### “No Ollama session cookie found”

Sign in at `https://ollama.com/signin` in Chrome, then refresh CodexBar.
If your active session is only in Safari (or another browser), use **Cookie source → Manual** and paste a cookie header.
```
with:
```
### “Cookie source is set to Manual, but no cookie header is pasted”

**Cookie source** is **Manual** and the field is empty, so CodexBar never looks at your browser. Either paste a
`Cookie:` header from `https://ollama.com/settings`, or click **Use Auto** on the Cookie source row to import
browser cookies again. Signing in to ollama.com does not change this state.

### “The pasted Ollama cookie header has no session cookie (wos-session)”

The pasted text was recognized but contains no `wos-session` (or legacy session) cookie. Copy the full `Cookie:`
header from a request to `https://ollama.com/settings` while signed in; a single analytics or theme cookie is not
enough.

### “No Ollama session cookie found in your browsers”

**Cookie source** is **Auto** and no supported browser had an Ollama session. Sign in at `https://ollama.com/signin`
in Chrome, then click **Refresh** (⌘R) on the provider card. If your session is only in Safari or another browser,
switch **Cookie source** to **Manual** and paste a cookie header.
```

- [ ] **Step 4: Add the changelog line**

In `CHANGELOG.md`, directly under `## 0.64.2 — Unreleased`, add:

```
### Fixed

- Ollama: distinguish an empty Manual cookie field from a missing browser session, show a “No cookie pasted” status with a one-click **Use Auto** switch, explain the Chrome Keychain prompt in the Auto subtitle, and add a **Sign in to Ollama…** menu entry.
```

The `0.64.2 — Unreleased` section is empty today, so this adds the first heading under it.

- [ ] **Step 5: Run the docs checks and commit**

Run: `make check`
Expected: passes (includes `check-documentation-links.mjs`).

```bash
git add docs/ollama.md CHANGELOG.md
git commit -m "docs(ollama): explain manual cookie states and the Keychain prompt."
```

---

### Task 8: Final verification and PR evidence (main thread)

**Files:** none modified.

- [ ] **Step 1: Full checks**

Run:
```bash
make check
make test
```
Expected: SwiftFormat clean, SwiftLint 0 violations, locale and docs checks pass, full sharded suite green with zero failures.

- [ ] **Step 2: Focused Ollama run for the PR body**

Run: `swift test --filter "Ollama|ProviderCookieSourceUITests|ProviderSettingsDescriptorTests"`
Expected: all PASS. Record the test count for the PR description.

- [ ] **Step 3: Build the bundle and capture screenshots**

Run: `./Scripts/compile_and_run.sh`
Expected: builds, packages, relaunches `CodexBar.app`, reports it stays running.

Then, without clicking **Refresh** (that is the only action that can raise the Keychain prompt):

1. Open Settings → Providers → Ollama. Set Cookie source to **Manual**, clear the field. Capture the row showing **No cookie pasted** and **Use Auto**.
2. Switch Cookie source to **Auto**. Capture the row with the new subtitle.
3. Open the menu on the Ollama card while the Manual-empty error is shown. Capture the message and the **Sign in to Ollama…** entry.

Save captures under `/private/tmp/claude-501/-Volumes-Netac-Users-giovannini-Developer-CodexBar/9bf62247-abb4-4475-b38e-a62e0f7b33d3/scratchpad/screenshots/` and reference them in the PR description.

- [ ] **Step 4: Write the PR description**

Per `AGENTS.md`: summary, commands run (from Steps 1–3 with counts), the three screenshots, `Refs #2072` (closed; same message text), and the follow-up issue draft from spec section 7. Do not push or open the PR until the user says so.
