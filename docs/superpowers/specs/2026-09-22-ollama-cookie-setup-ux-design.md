# Ollama cookie setup UX — design spec

- **Date:** 2026-09-22
- **Status:** Approved design, pending implementation plan
- **Scope:** Fork-side design document; the implementation targets an upstream PR to `steipete/CodexBar`
- **Outcome:** A user who is signed in to Ollama in their browser is never told to "sign in" when the real fix is a settings change, and the first Keychain prompt during a Chrome cookie import is expected rather than alarming.

## 1. Problem

Real report from the fork owner, reproduced from source:

1. The user is signed in to ollama.com in Chrome.
2. The Ollama provider's **Cookie source** is set to **Manual** and the cookie field is empty.
3. The Ollama card shows:

   ```
   No Ollama session cookie found. Please sign in at https://ollama.com/signin in your browser.
   ```

4. Signing in again changes nothing. The message never mentions the Manual setting.
5. When the user finally switches to Auto and clicks Refresh, macOS shows a Keychain prompt for "Chrome Safe Storage". Nothing in the UI told them to expect it, so it reads like a bug or malware.

Root cause in code: `OllamaUsageFetcher.resolveManualCookieHeader` throws the single `OllamaUsageError.noSessionCookie` for three different situations:

| Situation | Where it is thrown |
|---|---|
| Manual mode, header empty or whitespace | `resolveManualCookieHeader`, `if manualCookieMode { throw … }` |
| Manual mode, pasted text has no recognized session cookie (`wos-session` or legacy names) | `resolveManualCookieHeader`, `guard hasRecognizedOllamaSessionCookie` |
| Auto mode, no browser produced a session | `OllamaCookieImporter.importSessions` / `selectSessionInfo*` / `fetchUsingCookieCandidates` |

The same collapse exists in Cursor, Abacus, Factory, Kimi and Copilot (budget). MiMo and Mistral already throw a specific "invalid cookie" error. There is no shared manual-header resolver in `CodexBarCore`; every provider calls `CookieHeaderNormalizer.normalize` and then decides on its own.

### Upstream status (checked 2026-09-22)

- Issue #2072 (same message text) is closed. Merged fixes: #2249 (browser-access hints), #2595 (Keychain recovery wording), #2814 (background refresh flicker). None address the Manual + empty field state.
- No open issue or PR mentions the manual-mode empty state. Related: #3660 (Devin, same shape), #2214 (proposal to unify credential policy).

## 2. Goals

- Distinct, actionable messages for the three situations above.
- Inline validation in the provider card when Manual is selected with nothing pasted, with a one-click way back to Auto.
- Set expectations for the Keychain prompt in the Auto subtitle and in `docs/ollama.md`.
- A "Sign in to Ollama…" menu entry, consistent with Devin and Augment.
- Keep the change small and Ollama-scoped, with a follow-up issue for sibling providers.

### Non-goals

- Automatic fallback from Manual to Auto (approach C, rejected below).
- An interactive login runner that polls browser cookies (Cursor style) or an in-app `WKWebView` sign-in window. Both are follow-ups if wanted.
- A once-dismissible Keychain explainer banner. There is no "seen" persistence pattern in `SettingsStore`, and the prompt only fires on a user-initiated refresh.
- Touching sibling providers' fetch paths.

## 3. Alternatives considered

| Approach | Decision | Reason |
|---|---|---|
| A. Distinct error states | **Adopt** | Removes the misleading message at its source. Ollama-only enum cases; a shared Core error would need five more fetch paths and mappers. |
| B. Inline settings validation | **Adopt (lite)** | Existing `trailingText` and `trailingActions` slots on the Cookie source picker carry a status and a "Use Auto" button. No new views. |
| C. Graceful fallback to Auto | **Reject** | Users pick Manual to avoid the Keychain prompt or because their session is only in Safari. A silent fallback re-triggers the prompt and muddles the CLI `browserSupportExemption` rule. Cursor resets to `.auto` only after the user completes a login, never silently. |
| D. Ollama login flow | **Adopt (lite)** | Menu action opens `https://ollama.com/signin`, same as Devin/Augment. A polling runner like `CursorLoginRunner` (~580 lines) or a `WKWebView` window would be large and, for the polling variant, still hit the same Keychain prompt. |
| E. Keychain expectation-setting | **Adopt (copy only)** | Auto subtitle names Chrome and the prompt; docs troubleshooting updated. No persisted "seen" flag. |

## 4. Design

### 4.1 Error model (`Sources/CodexBarCore/Providers/Ollama/OllamaUsageFetcher.swift`)

Add two cases to `OllamaUsageError`; keep `noSessionCookie` for the browser-search path only.

| Situation | Before | After |
|---|---|---|
| Manual, header empty or whitespace, no token accounts | `noSessionCookie` | `manualCookieHeaderEmpty` |
| Manual, pasted text lacks a recognized session cookie | `noSessionCookie` | `manualCookieHeaderUnrecognized` |
| Auto, no browser produced a session | `noSessionCookie` | `noSessionCookie` with new copy |

`resolveManualCookieHeader` is the only place that throws the two new cases. The non-macOS `#else` branches in `resolveCookieCandidates` and `resolveCookieHeader` keep `noSessionCookie`.

Token accounts force `.manual` and inject their own header through `ProviderCookieSettingsResolver`, so the empty case never fires while an account is selected. An account whose token normalizes to a header without a session cookie hits `manualCookieHeaderUnrecognized`; the wording "pasted" is acceptable there because the account value was pasted too.

`OllamaStatusFetchStrategy.fetchAutomatic`, `shouldRetryWithNextCookieCandidate`, `isActionableBrowserAccessError` and the cached-cookie recovery are untouched. Manual mode bypasses them.

### 4.2 Copy: Core strings and localized keys

Core strings are English. `OllamaUIErrorMapper.userFacingMessage` matches each string by equality and returns a localized key, following the existing `ollama_*` pattern. The CLI shows the Core strings.

**Before, all three situations:**

```
No Ollama session cookie found. Please sign in at https://ollama.com/signin in your browser.
```

**After, `manualCookieHeaderEmpty` → key `ollama_manual_cookie_empty`:**

```
Cookie source is set to Manual, but no cookie header is pasted. Paste a Cookie header from https://ollama.com/settings, or switch Cookie source to Auto to import browser cookies.
```

**After, `manualCookieHeaderUnrecognized` → key `ollama_manual_cookie_unrecognized`:**

```
The pasted Ollama cookie header has no session cookie (wos-session). Copy the full Cookie header from https://ollama.com/settings while signed in, then paste it again.
```

**After, `noSessionCookie` → key `ollama_no_browser_session`:**

```
No Ollama session cookie found in your browsers. Sign in at https://ollama.com/signin in Chrome, then click Refresh (⌘R). If your session is only in Safari or another browser, set Cookie source to Manual and paste a cookie header.
```

The signin URL stays in the `noSessionCookie` string; an existing test pins it.

### 4.3 Settings card (`Sources/CodexBar/Providers/Ollama/OllamaProviderImplementation.swift`)

**Auto subtitle.** The current key `Automatic imports browser cookies.` is shared by 19 providers, so Ollama gets its own key `ollama_cookie_source_auto_subtitle`. The `SettingsRowLabel` subtitle wraps, so two sentences fit.

```
Before: Automatic imports browser cookies.
After:  Imports your ollama.com session from Chrome, then other browsers. The first import may show a macOS Keychain prompt for “Chrome Safe Storage”; click Always Allow.
```

The Manual and Off subtitles are unchanged.

**Manual-empty state.** Condition: `ollamaCookieSource == .manual`, `ollamaCookieHeader` is blank after trimming, and `tokenAccounts(for: .ollama)` is empty. The condition lives in one pure helper so sibling providers can reuse it:

```swift
// Sources/CodexBar/Providers/Shared/ProviderCookieSourceUI.swift
static func manualHeaderMissing(
    source: ProviderCookieSource,
    header: String?,
    hasTokenAccounts: Bool) -> Bool
```

When the condition holds:

- `trailingText` returns `L("ollama_manual_cookie_missing_status")` = `No cookie pasted`. Today the Manual branch returns nil; Auto keeps the refresh status or cache text.
- A new `trailingActions` entry with id `ollama-use-auto-cookie`, title key `Use Auto`, style `.bordered`. Visible when the condition holds, `ollamaUsageDataSource != .api`, and `debugDisableKeychainAccess == false` (the Auto option is hidden from the picker in that case). `perform` sets `ollamaCookieSource = .auto`. `UsageStore.observeSettingsChanges` already reacts to the change; the action does not call refresh itself.

The existing Refresh action (`ollama-reimport-cookie`) keeps its Auto-only visibility.

### 4.4 Menu entry (D-lite)

In `OllamaProviderImplementation`:

- `supportsLoginFlow = true`.
- `loginMenuAction(context:)` returns `("Sign in to Ollama…", .loginToProvider(url: "https://ollama.com/signin"))`. The label goes through the catalogs as key `Sign in to Ollama…`.
- `runLoginFlow(context:)` opens the signin URL with `NSWorkspace.shared.open` and returns `false`, same as Devin.

The entry shows regardless of usage source. `MenuDescriptor` already renders `loginMenuAction` overrides when `supportsLoginFlow` is true; no menu code changes.

### 4.5 Documentation and changelog

- `docs/ollama.md`
  - Setup step 4: mention that the first Auto import may show a Keychain prompt for "Chrome Safe Storage" and that Always Allow is the expected answer.
  - Troubleshooting: replace the "No Ollama session cookie found" entry with three entries whose headings match the three new messages, plus one line describing the "No cookie pasted" status and the "Use Auto" button.
- `CHANGELOG.md`, under `0.64.2 — Unreleased`: one line, for example "Ollama: distinct messages for Manual cookie mode, one-click switch back to Auto, and a Sign in menu entry."

### 4.6 Localization

Seven new keys in all 23 `Sources/CodexBar/Resources/*.lproj/Localizable.strings` catalogs, with real translations (the repo has no generator; `Scripts/check-app-locales.mjs` errors when a complete locale lacks a key):

| Key | English |
|---|---|
| `ollama_manual_cookie_empty` | see 4.2 |
| `ollama_manual_cookie_unrecognized` | see 4.2 |
| `ollama_no_browser_session` | see 4.2 |
| `ollama_cookie_source_auto_subtitle` | see 4.3 |
| `ollama_manual_cookie_missing_status` | `No cookie pasted` |
| `Use Auto` | `Use Auto` |
| `Sign in to Ollama…` | `Sign in to Ollama…` |

## 5. Testing

All tests use stubs and settings fixtures. Nothing touches the real Keychain or a live browser cookie store.

- `Tests/CodexBarTests/OllamaUsageFetcherTests.swift`
  - `manual mode without valid header throws no session cookie` → expects `manualCookieHeaderEmpty`.
  - `manual mode without recognized session cookie throws no session cookie` → expects `manualCookieHeaderUnrecognized`.
  - New: whitespace-only header in manual mode → `manualCookieHeaderEmpty`.
  - New: copy assertions — `manualCookieHeaderEmpty` mentions "Manual" and "Auto"; `noSessionCookie` still contains `https://ollama.com/signin` and mentions "Manual".
- `Tests/CodexBarTests/OllamaUIErrorMapperTests.swift`
  - Three new mapping tests, one per key.
  - `preserves generic Ollama errors` switches its sample to `networkError`, since `noSessionCookie` is now mapped.
- `Tests/CodexBarTests/OllamaUsageFetcherRetryMappingTests.swift`: expected unchanged; the plan verifies with a filtered run.
- `Tests/CodexBarTests/ProviderSettingsDescriptorTests.swift`
  - "Use Auto" visible only in the Manual-empty-no-accounts state; hidden when a header is set, when a token account exists, when usage source is API, and when Keychain access is disabled.
  - `perform` flips `ollamaCookieSource` to `.auto`.
  - `trailingText` shows the status in the Manual-empty state and the cache text in Auto.
- New `Tests/CodexBarTests/ProviderCookieSourceUITests.swift` for `manualHeaderMissing` (nil, empty, whitespace, header present, accounts present, source Auto).
- Menu entry through the `MenuDescriptor` seam: the Ollama section contains `Sign in to Ollama…` with `.loginToProvider(url: "https://ollama.com/signin")`. No live `NSStatusBar`/`NSMenu`.
- `node Scripts/check-app-locales.mjs`, `make check`, `make test`.

## 6. PR evidence

Screenshots from a freshly built bundle, taken without clicking Refresh so no Keychain prompt fires:

1. Providers pane, Ollama card, Cookie source = Manual with empty field: "No cookie pasted" status and "Use Auto" button.
2. Same card with Cookie source = Auto: new subtitle.
3. Menu card showing the `ollama_manual_cookie_empty` message and the "Sign in to Ollama…" entry.

## 7. Follow-up issue (draft)

Title: "Manual cookie mode with an empty field reports a generic 'no session' error in Cursor, Abacus, Factory, Kimi and Copilot"

Body: The Ollama provider now distinguishes "Manual selected but nothing pasted" from "no browser session found" (link to this PR). The same collapse exists in `CursorStatusProbe+SessionResolution.swift`, `AbacusProviderDescriptor.swift`, `FactoryStatusProbe.swift`, `KimiProviderDescriptor.swift` and `CopilotBudgetWebFetcher.swift`. A shared `CodexBarCore` error plus a shared mapper hook in `UsageStore.userFacingError` would let each provider adopt the split with a one-line change at its manual-header guard. `ProviderCookieSourceUI.manualHeaderMissing` is already shared and can drive the same "Use Auto" action on their cards.
