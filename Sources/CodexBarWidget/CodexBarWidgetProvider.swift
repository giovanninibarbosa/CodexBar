import AppIntents
import CodexBarCore
import SwiftUI
import WidgetKit

extension UsageProvider: AppEnum {
    public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Provider")

    public static var caseDisplayRepresentations: [UsageProvider: DisplayRepresentation] {
        Dictionary(uniqueKeysWithValues: self.allCases.map { provider in
            (provider, DisplayRepresentation(title: WidgetProviderDisplayName.localizedResource(for: provider)))
        })
    }
}

enum WidgetProviderDisplayName {
    private static let resources: [UsageProvider: LocalizedStringResource] = [
        .codex: "Codex",
        .claude: "Claude",
        .cursor: "Cursor",
        .opencode: "OpenCode",
        .alibaba: "Alibaba",
        .factory: "Factory",
        .gemini: "Gemini",
        .antigravity: "Antigravity",
        .copilot: "Copilot",
        .zai: "z.ai",
        .minimax: "MiniMax",
        .kimi: "Kimi",
        .kilo: "Kilo",
        .kiro: "Kiro",
        .vertexai: "Vertex AI",
        .augment: "Augment",
        .jetbrains: "JetBrains",
        .kimik2: "Kimi K2",
        .amp: "Amp",
        .ollama: "Ollama",
        .synthetic: "Synthetic",
        .warp: "Warp",
        .openrouter: "OpenRouter",
        .perplexity: "Perplexity",
    ]

    static func localizedResource(for provider: UsageProvider) -> LocalizedStringResource {
        self.resources[provider] ?? "Provider"
    }
}

enum CompactMetric: String, AppEnum {
    case credits
    case todayCost
    case last30DaysCost

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Metric")

    static let caseDisplayRepresentations: [CompactMetric: DisplayRepresentation] = [
        .credits: DisplayRepresentation(title: "Credits left"),
        .todayCost: DisplayRepresentation(title: "Today cost"),
        .last30DaysCost: DisplayRepresentation(title: "30d cost"),
    ]
}

struct ProviderSelectionIntent: AppIntent, WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Provider"
    static let description = IntentDescription("Select the provider to display in the widget.")

    @Parameter(title: "Provider", optionsProvider: AvailableWidgetProviderOptions())
    var provider: UsageProvider

    init() {
        self.provider = WidgetProviderCatalog.defaultProvider(from: WidgetPreviewData.snapshot())
    }
}

struct SwitchWidgetProviderIntent: AppIntent {
    static let title: LocalizedStringResource = "Switch Provider"
    static let description = IntentDescription("Switch the provider shown in the widget.")

    @Parameter(title: "Provider")
    var provider: UsageProvider

    init() {}

    init(provider: UsageProvider) {
        self.provider = provider
    }

    func perform() async throws -> some IntentResult {
        WidgetSelectionStore.saveSelectedProvider(self.provider)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

struct CompactMetricSelectionIntent: AppIntent, WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Provider + Metric"
    static let description = IntentDescription("Select the provider and metric to display.")

    @Parameter(title: "Provider", optionsProvider: AvailableWidgetProviderOptions())
    var provider: UsageProvider

    @Parameter(title: "Metric")
    var metric: CompactMetric

    init() {
        self.provider = WidgetProviderCatalog.defaultProvider(from: WidgetPreviewData.snapshot())
        self.metric = .credits
    }
}

struct CodexBarWidgetEntry: TimelineEntry {
    let date: Date
    let provider: UsageProvider
    let snapshot: WidgetSnapshot
}

struct CodexBarCompactEntry: TimelineEntry {
    let date: Date
    let provider: UsageProvider
    let metric: CompactMetric
    let snapshot: WidgetSnapshot
}

struct CodexBarSwitcherEntry: TimelineEntry {
    let date: Date
    let provider: UsageProvider
    let availableProviders: [UsageProvider]
    let snapshot: WidgetSnapshot
}

struct CodexBarOverviewEntry: TimelineEntry {
    let date: Date
    let providers: [UsageProvider]
    let snapshot: WidgetSnapshot
}

struct AvailableWidgetProviderOptions: DynamicOptionsProvider {
    func results() async throws -> [UsageProvider] {
        WidgetProviderCatalog.availableProviders(from: WidgetSnapshotStore.load() ?? WidgetPreviewData.snapshot())
    }
}

struct CodexBarTimelineProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> CodexBarWidgetEntry {
        CodexBarWidgetEntry(
            date: Date(),
            provider: .codex,
            snapshot: WidgetPreviewData.snapshot())
    }

    func snapshot(for configuration: ProviderSelectionIntent, in context: Context) async -> CodexBarWidgetEntry {
        let provider = configuration.provider
        return CodexBarWidgetEntry(
            date: Date(),
            provider: provider,
            snapshot: WidgetSnapshotStore.load() ?? WidgetPreviewData.snapshot())
    }

    func timeline(
        for configuration: ProviderSelectionIntent,
        in context: Context) async -> Timeline<CodexBarWidgetEntry>
    {
        let provider = configuration.provider
        let snapshot = WidgetSnapshotStore.load() ?? WidgetPreviewData.snapshot()
        let entry = CodexBarWidgetEntry(date: Date(), provider: provider, snapshot: snapshot)
        let refresh = Date().addingTimeInterval(30 * 60)
        return Timeline(entries: [entry], policy: .after(refresh))
    }
}

struct CodexBarSwitcherTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> CodexBarSwitcherEntry {
        let snapshot = WidgetPreviewData.snapshot()
        let providers = WidgetProviderCatalog.availableProviders(from: snapshot)
        return CodexBarSwitcherEntry(
            date: Date(),
            provider: providers.first ?? .codex,
            availableProviders: providers,
            snapshot: snapshot)
    }

    func getSnapshot(in context: Context, completion: @escaping (CodexBarSwitcherEntry) -> Void) {
        completion(self.makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CodexBarSwitcherEntry>) -> Void) {
        let entry = self.makeEntry()
        let refresh = Date().addingTimeInterval(30 * 60)
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }

    private func makeEntry() -> CodexBarSwitcherEntry {
        let snapshot = WidgetSnapshotStore.load() ?? WidgetPreviewData.snapshot()
        let providers = WidgetProviderCatalog.availableProviders(from: snapshot)
        let stored = WidgetSelectionStore.loadSelectedProvider()
        let selected = providers.first { $0 == stored } ?? providers.first ?? .codex
        if selected != stored {
            WidgetSelectionStore.saveSelectedProvider(selected)
        }
        return CodexBarSwitcherEntry(
            date: Date(),
            provider: selected,
            availableProviders: providers,
            snapshot: snapshot)
    }

    static func supportedProviders(from snapshot: WidgetSnapshot) -> [UsageProvider] {
        WidgetProviderCatalog.availableProviders(from: snapshot)
    }
}

struct CodexBarCompactTimelineProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> CodexBarCompactEntry {
        CodexBarCompactEntry(
            date: Date(),
            provider: .codex,
            metric: .credits,
            snapshot: WidgetPreviewData.snapshot())
    }

    func snapshot(for configuration: CompactMetricSelectionIntent, in context: Context) async -> CodexBarCompactEntry {
        let provider = configuration.provider
        return CodexBarCompactEntry(
            date: Date(),
            provider: provider,
            metric: configuration.metric,
            snapshot: WidgetSnapshotStore.load() ?? WidgetPreviewData.snapshot())
    }

    func timeline(
        for configuration: CompactMetricSelectionIntent,
        in context: Context) async -> Timeline<CodexBarCompactEntry>
    {
        let provider = configuration.provider
        let snapshot = WidgetSnapshotStore.load() ?? WidgetPreviewData.snapshot()
        let entry = CodexBarCompactEntry(
            date: Date(),
            provider: provider,
            metric: configuration.metric,
            snapshot: snapshot)
        let refresh = Date().addingTimeInterval(30 * 60)
        return Timeline(entries: [entry], policy: .after(refresh))
    }
}

struct CodexBarOverviewTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> CodexBarOverviewEntry {
        let snapshot = WidgetPreviewData.snapshot()
        return CodexBarOverviewEntry(
            date: Date(),
            providers: WidgetProviderCatalog.overviewProviders(from: snapshot, limit: 3),
            snapshot: snapshot)
    }

    func getSnapshot(in context: Context, completion: @escaping (CodexBarOverviewEntry) -> Void) {
        completion(self.makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CodexBarOverviewEntry>) -> Void) {
        let entry = self.makeEntry()
        let refresh = Date().addingTimeInterval(30 * 60)
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }

    private func makeEntry() -> CodexBarOverviewEntry {
        let snapshot = WidgetSnapshotStore.load() ?? WidgetPreviewData.snapshot()
        return CodexBarOverviewEntry(
            date: Date(),
            providers: WidgetProviderCatalog.overviewProviders(from: snapshot, limit: 3),
            snapshot: snapshot)
    }
}

enum WidgetProviderCatalog {
    static func availableProviders(from snapshot: WidgetSnapshot) -> [UsageProvider] {
        let providers = snapshot.enabledProviders.isEmpty ? snapshot.entries.map(\.provider) : snapshot.enabledProviders
        let ordered = self.uniqueOrdered(providers)
        return ordered.isEmpty ? [.codex] : ordered
    }

    static func defaultProvider(from snapshot: WidgetSnapshot) -> UsageProvider {
        self.availableProviders(from: snapshot).first ?? .codex
    }

    static func overviewProviders(from snapshot: WidgetSnapshot, limit: Int? = nil) -> [UsageProvider] {
        let activeProviders = self.availableProviders(from: snapshot)
        let providers: [UsageProvider]
        if let selectedProviders = snapshot.overviewProviders {
            if selectedProviders.isEmpty {
                providers = []
            } else {
                let selected = Set(selectedProviders)
                providers = activeProviders.filter { selected.contains($0) }
            }
        } else {
            providers = activeProviders
        }

        guard let limit else { return providers }
        return Array(providers.prefix(limit))
    }

    static func providerEntry(for provider: UsageProvider, in snapshot: WidgetSnapshot) -> WidgetSnapshot
    .ProviderEntry? {
        snapshot.entries.first { $0.provider == provider }
    }

    private static func uniqueOrdered(_ providers: [UsageProvider]) -> [UsageProvider] {
        var seen: Set<UsageProvider> = []
        var ordered: [UsageProvider] = []
        for provider in providers where !seen.contains(provider) {
            seen.insert(provider)
            ordered.append(provider)
        }
        return ordered
    }
}

enum WidgetPreviewData {
    static func snapshot() -> WidgetSnapshot {
        let now = Date()

        let codexEntry = WidgetSnapshot.ProviderEntry(
            provider: .codex,
            updatedAt: now,
            primary: RateWindow(usedPercent: 35, windowMinutes: nil, resetsAt: nil, resetDescription: "Resets in 4h"),
            secondary: RateWindow(usedPercent: 60, windowMinutes: nil, resetsAt: nil, resetDescription: "Resets in 3d"),
            tertiary: nil,
            creditsRemaining: 1243.4,
            codeReviewRemainingPercent: 78,
            tokenUsage: WidgetSnapshot.TokenUsageSummary(
                sessionCostUSD: 12.4,
                sessionTokens: 420_000,
                last30DaysCostUSD: 923.8,
                last30DaysTokens: 12_400_000),
            dailyUsage: [
                WidgetSnapshot.DailyUsagePoint(dayKey: "2025-12-01", totalTokens: 120_000, costUSD: 15.2),
                WidgetSnapshot.DailyUsagePoint(dayKey: "2025-12-02", totalTokens: 80000, costUSD: 10.1),
                WidgetSnapshot.DailyUsagePoint(dayKey: "2025-12-03", totalTokens: 140_000, costUSD: 17.9),
                WidgetSnapshot.DailyUsagePoint(dayKey: "2025-12-04", totalTokens: 90000, costUSD: 11.4),
                WidgetSnapshot.DailyUsagePoint(dayKey: "2025-12-05", totalTokens: 160_000, costUSD: 19.8),
                WidgetSnapshot.DailyUsagePoint(dayKey: "2025-12-06", totalTokens: 70000, costUSD: 8.9),
                WidgetSnapshot.DailyUsagePoint(dayKey: "2025-12-07", totalTokens: 110_000, costUSD: 13.7),
            ])

        let claudeEntry = WidgetSnapshot.ProviderEntry(
            provider: .claude,
            updatedAt: now.addingTimeInterval(-8 * 60),
            primary: RateWindow(usedPercent: 54, windowMinutes: nil, resetsAt: nil, resetDescription: "Resets in 2h"),
            secondary: RateWindow(
                usedPercent: 42,
                windowMinutes: nil,
                resetsAt: nil,
                resetDescription: "Resets tomorrow"),
            tertiary: nil,
            creditsRemaining: nil,
            codeReviewRemainingPercent: nil,
            tokenUsage: WidgetSnapshot.TokenUsageSummary(
                sessionCostUSD: 7.9,
                sessionTokens: 210_000,
                last30DaysCostUSD: 318.5,
                last30DaysTokens: 6_200_000),
            dailyUsage: [
                WidgetSnapshot.DailyUsagePoint(dayKey: "2025-12-01", totalTokens: 95000, costUSD: 8.1),
                WidgetSnapshot.DailyUsagePoint(dayKey: "2025-12-02", totalTokens: 76000, costUSD: 6.3),
                WidgetSnapshot.DailyUsagePoint(dayKey: "2025-12-03", totalTokens: 124_000, costUSD: 10.7),
                WidgetSnapshot.DailyUsagePoint(dayKey: "2025-12-04", totalTokens: 88000, costUSD: 7.2),
                WidgetSnapshot.DailyUsagePoint(dayKey: "2025-12-05", totalTokens: 132_000, costUSD: 11.2),
                WidgetSnapshot.DailyUsagePoint(dayKey: "2025-12-06", totalTokens: 81000, costUSD: 6.9),
                WidgetSnapshot.DailyUsagePoint(dayKey: "2025-12-07", totalTokens: 103_000, costUSD: 8.8),
            ])

        let geminiEntry = WidgetSnapshot.ProviderEntry(
            provider: .gemini,
            updatedAt: now.addingTimeInterval(-18 * 60),
            primary: RateWindow(usedPercent: 22, windowMinutes: nil, resetsAt: nil, resetDescription: "Resets in 6h"),
            secondary: RateWindow(
                usedPercent: 48,
                windowMinutes: nil,
                resetsAt: nil,
                resetDescription: "Resets Sunday"),
            tertiary: nil,
            creditsRemaining: nil,
            codeReviewRemainingPercent: nil,
            tokenUsage: WidgetSnapshot.TokenUsageSummary(
                sessionCostUSD: 3.1,
                sessionTokens: 95000,
                last30DaysCostUSD: 102.4,
                last30DaysTokens: 2_480_000),
            dailyUsage: [
                WidgetSnapshot.DailyUsagePoint(dayKey: "2025-12-01", totalTokens: 35000, costUSD: 2.1),
                WidgetSnapshot.DailyUsagePoint(dayKey: "2025-12-02", totalTokens: 44000, costUSD: 2.8),
                WidgetSnapshot.DailyUsagePoint(dayKey: "2025-12-03", totalTokens: 41000, costUSD: 2.6),
                WidgetSnapshot.DailyUsagePoint(dayKey: "2025-12-04", totalTokens: 52000, costUSD: 3.4),
                WidgetSnapshot.DailyUsagePoint(dayKey: "2025-12-05", totalTokens: 39000, costUSD: 2.5),
                WidgetSnapshot.DailyUsagePoint(dayKey: "2025-12-06", totalTokens: 61000, costUSD: 3.9),
                WidgetSnapshot.DailyUsagePoint(dayKey: "2025-12-07", totalTokens: 46000, costUSD: 2.9),
            ])

        return WidgetSnapshot(
            entries: [codexEntry, claudeEntry, geminiEntry],
            enabledProviders: [.codex, .claude, .gemini],
            overviewProviders: [.codex, .claude, .gemini],
            generatedAt: now)
    }
}
