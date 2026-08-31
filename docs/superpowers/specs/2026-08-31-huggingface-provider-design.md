# Hugging Face provider — design spec

- **Date:** 2026-08-31
- **Status:** Approved design, pending implementation plan
- **Scope:** Fork-side design document; not part of the upstream PR
- **Outcome:** A new `huggingface` provider in CodexBar showing Inference Providers credit usage (primary), ZeroGPU quota (secondary), dollar spend, and account identity — delivered as a PR to upstream `main`.

## 1. Goals

- Add Hugging Face to the provider list with the same lifecycle as other first-party providers (enable in Settings → Providers, menu gauge, detail rows, debug pane attempts).
- Primary gauge: **Inference Providers monthly credits** — used vs included ($0.10 Free / $2.00 PRO / $2.00 per seat Team/Enterprise), matching the gauge on `huggingface.co/settings/billing`.
- Secondary gauge: **ZeroGPU quota** (GPU-seconds remaining, reset time).
- Show dollar spend via `providerCost` and account identity (username, PRO/Free plan) from `whoami-v2`.
- Token sources: Settings paste, `HF_TOKEN` / `HUGGING_FACE_HUB_TOKEN` env vars, and the `hf auth login` CLI token file.

### Non-goals (v1)

- Organization billing (`/api/organizations/{name}/billing/*` — needs org-admin; larger settings surface).
- Purchased/prepaid credit balance (no API exists).
- Jobs / Spaces / Inference Endpoints usage breakdowns (v1 covers Inference Providers + ZeroGPU only).
- Widget selectability (`widgetSelectable: false`, like Fireworks/Venice/IBM Bob).
- Cost history / token cost tracking (`supportsTokenCost: false`).

## 2. External API reference

All endpoints on `https://huggingface.co`, `Authorization: Bearer hf_…`. Paths verified against the official OpenAPI spec (`https://huggingface.co/.well-known/openapi.json`, fetched 2026-08-31).

| Endpoint | Role | Contract status |
|---|---|---|
| `GET /api/settings/billing/usage-v2?startDate=<epoch s>&endDate=<epoch s>` | **Required.** Inference credits: `usage.inferenceProviders.{usedNanoUsd, includedNanoUsd, limitNanoUsd, numRequests, periodStart, periodEnd}` | Path in spec; response shape undocumented (pinned by HF's own `ml-intern` client). **Fail soft on drift.** |
| `GET /api/spaces/zero-gpu/quota` | Best-effort. `{base, current, resetsAt, overquotaUsed, runs{…}}` (GPU-seconds) | Fully documented |
| `GET /api/whoami-v2` | Best-effort, **cached**. `{name, fullname, isPro, periodEnd (epoch s), orgs[], auth{…}}` | Fully documented; heavily rate-limited by HF — must not be polled |

Facts that inform the design:

- Included monthly credits: Free $0.10, PRO $2.00, Team/Enterprise $2.00 per seat (docs/inference-providers/pricing, 2026-08-31). Values come from the API response, never hardcoded.
- Hub API rate limits: 5-minute windows (Free 1,000 / PRO 2,500 requests); 429 responses carry IETF `RateLimit` headers (`r=remaining; t=seconds-to-reset`).
- Auth: classic `read` tokens work for everything above. Fine-grained tokens 403 on `/api/settings/billing/*` unless the "Billing → read" (`user.billing.read`) permission is granted.
- Tokens are created at `https://huggingface.co/settings/tokens`.

## 3. Architecture

First-party Swift provider (Fireworks/IBM Bob pattern), not a bundled JS plugin: the probe is multi-endpoint with per-endpoint policies (required vs best-effort vs cached) and needs rich fixture-based tests — both are much better served in Swift.

### Files

Core — `Sources/CodexBarCore/Providers/HuggingFace/`:

| File | Contents |
|---|---|
| `HuggingFaceProviderDescriptor.swift` | `public enum HuggingFaceProviderDescriptor { public static let descriptor … }` + `HuggingFaceAPIFetchStrategy` (kind `.apiToken`). Must match the manifest generator's grep shapes (`id: .huggingface,` in a `*ProviderDescriptor.swift`). |
| `HuggingFaceUsageFetcher.swift` | Probe orchestration + snapshot mapping; testable entry point taking an injected `ProviderHTTPTransport` (mirror `IBMBobUsageFetcher._fetchUsageForTesting`). |
| `HuggingFaceModels.swift` | Tolerant `Codable` response models — every interesting field optional, unknown keys ignored. |
| `HuggingFaceSettingsReader.swift` | Token resolution (see §5). |

App — `Sources/CodexBar/Providers/HuggingFace/`:

| File | Contents |
|---|---|
| `HuggingFaceProviderImplementation.swift` | `struct HuggingFaceProviderImplementation` with `let id: UsageProvider = .huggingface` (generator regex), `settingsFields`, `isAvailable`. App owns UI; no custom pane code. |
| `HuggingFaceSettingsStore.swift` (only if needed) | `extension SettingsStore { var huggingFaceAPIToken: String }` for the settings field binding. |

Resources: `Sources/CodexBar/Resources/ProviderIcon-huggingface.svg` — original monochrome 18×18 template mark (simplified hugging-face outline; `isTemplate` rendering, no color).

### Registration

1. Append `case huggingface` to `UsageProvider` (`Sources/CodexBarCore/Providers/Providers.swift`), last position.
2. Run `Scripts/regenerate-provider-manifests.sh` — regenerates `ProviderManifest.swift`, `ProviderImplementationManifest.swift`, `ProviderInstanceIDAliases.generated.swift`, `docs/provider-ids.md`. Never hand-edit those.
3. No WidgetKit changes (`widgetSelectable: false`).

### Fetch sequence

Sequential awaits — one required call plus two contained best-effort calls; per AGENTS.md, no sibling `async let` mixing required and optional children.

1. **usage-v2** (required): `startDate` = start of current UTC month in epoch seconds, `endDate` = now. Any failure fails the probe with a typed error.
2. **ZeroGPU quota** (best-effort): failure drops the secondary window and is recorded as a diagnostic string on the fetch result.
3. **whoami-v2** (best-effort, cached): global actor cache keyed by SHA-256 of the token, TTL ≈ 12 h. On cache miss failure, proceed without identity; never fail the probe. `now` is injectable for tests.

All requests timeout-bounded through `ProviderHTTPClient` defaults.

## 4. Data mapping

| Snapshot field | Source | Rule |
|---|---|---|
| `primary: RateWindow` | usage-v2 `inferenceProviders` | `usedPercent = clamp(usedNanoUsd / includedNanoUsd × 100, 0…100)`. If `includedNanoUsd` ≤ 0 and `limitNanoUsd` > 0, gauge against `limitNanoUsd` instead. If both are absent/zero, primary window has `usedPercent = 0` with spend still visible via `providerCost` and details. `resetsAt` = whoami-v2 `periodEnd` (epoch s) when available, else parsed usage-v2 `periodEnd`. `windowMinutes = nil`. |
| `secondary: RateWindow` | zero-gpu quota | `usedPercent = clamp((base − current) / base × 100)` when `base > 0`; `resetsAt` from `resetsAt`. Omitted (nil) when the call fails or `base ≤ 0`. |
| `providerCost` | usage-v2 | used = `usedNanoUsd / 1e9` USD; limit = included (or user limit) in USD, so the menu card shows dollar figures (Fireworks-style presenter). |
| `identity` | whoami-v2 (cached) | Username (`name`), plan label (`PRO` / `Free`; org plan names not shown in v1). HuggingFace-only fields — identity silo guardrail. |
| `details` | both | Section "Inference Providers": spend, included credits, requests. Section "ZeroGPU" (only when quota present): GPU-time used/remaining, reset. Within `ProviderDetailSection.maximumSectionsPerSnapshot`. |
| `updatedAt` | probe time | — |

### Descriptor metadata

- `displayName: "Hugging Face"`, `sessionLabel: "Credits"`, `weeklyLabel: "ZeroGPU"`, `supportsOpus: false`, `supportsCredits: false`, `toggleTitle: "Show Hugging Face usage"`, `cliName: "huggingface"` (alias `"hf"`), `defaultEnabled: false`, `widgetSelectable: false`, `isPrimaryProvider: false`, `balanceOnly: false`, `dashboardURL: "https://huggingface.co/settings/billing"`, `statusPageURL: "https://status.huggingface.co"`.
- Branding: brand yellow `ProviderColor(hex: 0xFFD21E)`; confetti palette 2–3 colors (yellow + warm accents); `iconResourceName: "ProviderIcon-huggingface"`.
- `tokenCost: supportsTokenCost: false` with a clear no-data message.
- `fetchPlan: sourceModes [.auto, .api]`, single `HuggingFaceAPIFetchStrategy`, `shouldFallback = false`.

## 5. Auth & settings

### Token resolution (`HuggingFaceSettingsReader`)

Precedence, first non-empty wins; trim whitespace and strip matched quotes at each step:

1. `CODEXBAR_HUGGINGFACE_API_KEY` — config-projected env key (`configAPIKeyEnvironmentKey`).
2. `HF_TOKEN` — official env var.
3. `HUGGING_FACE_HUB_TOKEN` — legacy `huggingface_hub` var.
4. CLI token file written by `hf auth login`: `$HF_TOKEN_PATH` if set, else `$HF_HOME/token` if `HF_HOME` set, else `~/.cache/huggingface/token`.

File access goes through the codebase's established host seam for reading CLI credential files (as used by CLI-credential providers); the guardrail forbids ad-hoc `FileManager`/`Security` calls inside providers. The implementation locates the exact seam; if none fits file-reads from a settings reader, follow the closest existing precedent in-tree rather than inventing a new mechanism.

### Credential adapter

`ProviderCredentialAdapter.apiKey(environmentKey: …, resolve: HuggingFaceSettingsReader.apiKey, tokenAccountSupport: …)` with token-account support (title "API tokens", paste placeholder, `.environment(key: CODEXBAR_HUGGINGFACE_API_KEY)` injection) so multiple accounts work like Venice. This requires adding `(.huggingface, "CODEXBAR_HUGGINGFACE_API_KEY")`-shaped rows to both tables in `ProviderCredentialCharacterizationTests` (exact expected env key confirmed against how those tables record other providers).

### Settings UI

Registry-driven only: one secure `ProviderSettingsFieldDescriptor` ("Hugging Face token", placeholder "hf_…") bound via the settings store, plus an action linking to `https://huggingface.co/settings/tokens`. `isAvailable` = token resolvable.

## 6. Error handling

| Condition | Behavior |
|---|---|
| No token anywhere | Strategy `isAvailable` false; missing-credential message points at Settings field and `https://huggingface.co/settings/tokens`. |
| 401 | "Hugging Face token is invalid or expired." |
| 403 | "Token lacks billing access — use a classic read token, or enable Billing → read on your fine-grained token." |
| 429 | Error surfaces the `RateLimit` header's seconds-to-reset when parseable; app keeps showing the cached snapshot (degradation guardrail). |
| usage-v2 shape drift (missing `inferenceProviders` or unparseable) | Typed decode error: "Hugging Face billing response format changed." Probe fails soft — clear error, no crash, no partial garbage. |
| ZeroGPU / whoami failures | Contained: snapshot still produced; failure noted in the fetch diagnostic. |

## 7. Testing

Swift-testing (`@Test`, backticked sentence names), no XCTest. No live probes, no Keychain-visible calls — stub `ProviderHTTPTransport` and temp dirs only.

- `Tests/CodexBarTests/HuggingFaceUsageFetcherTests.swift` + fixtures in `Tests/CodexBarTests/Fixtures/Providers/HuggingFace/`:
  - PRO account with spend (percent + dollars + reset mapping)
  - Free tier ($0.10 included)
  - `includedNanoUsd` zero → limit fallback → both-absent behavior
  - Drifted/unknown response shape → typed error
  - ZeroGPU quota present / absent / failing (secondary window contained)
  - whoami-v2 cached across two fetches (single HTTP call), failure contained
  - 401 / 403 / 429 mapping (429 includes reset seconds)
  - Auth header assertion (`Bearer` on every request)
  - Descriptor metadata assertions (displayName, iconResourceName)
- `Tests/CodexBarTests/HuggingFaceSettingsReaderTests.swift`: precedence chain (config → `HF_TOKEN` → legacy → file), quote/whitespace stripping, `HF_TOKEN_PATH`/`HF_HOME` overrides with temp dirs.
- Registry sweeps: bump fingerprint constants in `ProviderArchitectureGatekeeperTests` (~lines 148–158); add credential characterization rows; SVG loadability is covered by the existing gatekeeper.
- Gates: `make check` (SwiftFormat, SwiftLint strict, manifest `--check`) and `make test` green before handoff; one `./Scripts/compile_and_run.sh` bundle validation at the end.

## 8. Docs & delivery

- Docs: `docs/huggingface.md` (standard `summary:`/`read_when:` front-matter; token setup, fine-grained billing permission, what each gauge shows, endpoint contract status), row in `docs/providers.md`, README bullet + all provider-count strings (69 → 70, incl. `docs/index.html`, `docs/llms.txt`, `docs/social.html`, `docs/site-locales.mjs`), `CHANGELOG.md` entry.
- Branch: feature branch in an isolated worktree, started from the fork's `main` at the commit **before** this spec (spec stays out of the PR).
- Build: subagent-driven development over the implementation plan; TDD per task.
- PR: fork → upstream `main`, with summary, commands run, screenshots of the Providers pane and menu card.

## 9. Risks

- **usage-v2 response drift** — undocumented shape; mitigated by tolerant models, typed drift error, fail-soft probing, fixtures pinning today's shape.
- **whoami-v2 rate limiting** — mitigated by the TTL cache; probe never depends on it.
- **Gatekeeper fingerprints** — descriptor-list changes require recomputing pinned constants; the test failure message provides them.
- **Icon** — must be an original monochrome template SVG that renders at 18×18; validated by the gatekeeper's loadable-SVG test.
