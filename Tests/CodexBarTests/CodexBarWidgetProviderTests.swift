import Foundation
import Testing
@testable import CodexBarCore
@testable import CodexBarWidget

struct CodexBarWidgetProviderTests {
    @Test
    func `widget provider catalog exposes providers beyond previous hardcoded subset`() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let warpEntry = WidgetSnapshot.ProviderEntry(
            provider: .warp,
            updatedAt: now,
            primary: nil,
            secondary: nil,
            tertiary: nil,
            creditsRemaining: nil,
            codeReviewRemainingPercent: nil,
            tokenUsage: nil,
            dailyUsage: [])
        let snapshot = WidgetSnapshot(entries: [warpEntry], enabledProviders: [.warp], generatedAt: now)

        #expect(WidgetProviderCatalog.availableProviders(from: snapshot) == [.warp])
    }

    @Test
    func `supported providers keep alibaba when it is the only enabled provider`() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let entry = WidgetSnapshot.ProviderEntry(
            provider: .alibaba,
            updatedAt: now,
            primary: nil,
            secondary: nil,
            tertiary: nil,
            creditsRemaining: nil,
            codeReviewRemainingPercent: nil,
            tokenUsage: nil,
            dailyUsage: [])
        let snapshot = WidgetSnapshot(entries: [entry], enabledProviders: [.alibaba], generatedAt: now)

        #expect(CodexBarSwitcherTimelineProvider.supportedProviders(from: snapshot) == [.alibaba])
    }

    @Test
    func `overview providers respect explicit empty snapshot selection`() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let codexEntry = WidgetSnapshot.ProviderEntry(
            provider: .codex,
            updatedAt: now,
            primary: nil,
            secondary: nil,
            tertiary: nil,
            creditsRemaining: nil,
            codeReviewRemainingPercent: nil,
            tokenUsage: nil,
            dailyUsage: [])
        let claudeEntry = WidgetSnapshot.ProviderEntry(
            provider: .claude,
            updatedAt: now,
            primary: nil,
            secondary: nil,
            tertiary: nil,
            creditsRemaining: nil,
            codeReviewRemainingPercent: nil,
            tokenUsage: nil,
            dailyUsage: [])
        let snapshot = WidgetSnapshot(
            entries: [codexEntry, claudeEntry],
            enabledProviders: [.codex, .claude],
            overviewProviders: [],
            generatedAt: now)

        #expect(WidgetProviderCatalog.overviewProviders(from: snapshot, limit: 3).isEmpty)
    }

    @Test
    func `overview providers follow enabled order while honoring selected set`() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let codexEntry = WidgetSnapshot.ProviderEntry(
            provider: .codex,
            updatedAt: now,
            primary: nil,
            secondary: nil,
            tertiary: nil,
            creditsRemaining: nil,
            codeReviewRemainingPercent: nil,
            tokenUsage: nil,
            dailyUsage: [])
        let claudeEntry = WidgetSnapshot.ProviderEntry(
            provider: .claude,
            updatedAt: now,
            primary: nil,
            secondary: nil,
            tertiary: nil,
            creditsRemaining: nil,
            codeReviewRemainingPercent: nil,
            tokenUsage: nil,
            dailyUsage: [])
        let opencodeEntry = WidgetSnapshot.ProviderEntry(
            provider: .opencode,
            updatedAt: now,
            primary: nil,
            secondary: nil,
            tertiary: nil,
            creditsRemaining: nil,
            codeReviewRemainingPercent: nil,
            tokenUsage: nil,
            dailyUsage: [])
        let snapshot = WidgetSnapshot(
            entries: [codexEntry, claudeEntry, opencodeEntry],
            enabledProviders: [.codex, .claude, .opencode],
            overviewProviders: [.opencode, .codex],
            generatedAt: now)

        #expect(WidgetProviderCatalog.overviewProviders(from: snapshot, limit: 3) == [.codex, .opencode])
    }

    @Test
    func `codex weekly only widget rows omit session`() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let entry = WidgetSnapshot.ProviderEntry(
            provider: .codex,
            updatedAt: now,
            primary: nil,
            secondary: RateWindow(usedPercent: 25, windowMinutes: 10080, resetsAt: nil, resetDescription: nil),
            tertiary: nil,
            creditsRemaining: nil,
            codeReviewRemainingPercent: nil,
            tokenUsage: nil,
            dailyUsage: [])

        let rows = WidgetUsageRow.rows(for: entry)

        #expect(rows.count == 1)
        #expect(rows.first?.title == "Weekly")
        #expect(rows.first?.percentLeft == 75)
    }
}
