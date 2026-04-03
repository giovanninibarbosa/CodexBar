import SwiftUI
import WidgetKit

@main
struct CodexBarWidgetBundle: WidgetBundle {
    var body: some Widget {
        CodexBarOverviewWidget()
        CodexBarSwitcherWidget()
        CodexBarUsageWidget()
        CodexBarHistoryWidget()
        CodexBarCompactWidget()
    }
}

struct CodexBarOverviewWidget: Widget {
    private let kind = "CodexBarOverviewWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: self.kind,
            provider: CodexBarOverviewTimelineProvider())
        { entry in
            CodexBarOverviewWidgetView(entry: entry)
        }
        .configurationDisplayName("CodexBar Overview")
        .description("Multiple providers in one widget.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct CodexBarSwitcherWidget: Widget {
    private let kind = "CodexBarSwitcherWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: self.kind,
            provider: CodexBarSwitcherTimelineProvider())
        { entry in
            CodexBarSwitcherWidgetView(entry: entry)
        }
        .configurationDisplayName("CodexBar Switcher")
        .description("Usage widget with a provider switcher.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct CodexBarUsageWidget: Widget {
    private let kind = "CodexBarUsageWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: self.kind,
            intent: ProviderSelectionIntent.self,
            provider: CodexBarTimelineProvider())
        { entry in
            CodexBarUsageWidgetView(entry: entry)
        }
        .configurationDisplayName("CodexBar Provider")
        .description("Single-provider usage with credits and costs.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct CodexBarHistoryWidget: Widget {
    private let kind = "CodexBarHistoryWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: self.kind,
            intent: ProviderSelectionIntent.self,
            provider: CodexBarTimelineProvider())
        { entry in
            CodexBarHistoryWidgetView(entry: entry)
        }
        .configurationDisplayName("CodexBar History")
        .description("Usage history chart with recent totals.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct CodexBarCompactWidget: Widget {
    private let kind = "CodexBarCompactWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: self.kind,
            intent: CompactMetricSelectionIntent.self,
            provider: CodexBarCompactTimelineProvider())
        { entry in
            CodexBarCompactWidgetView(entry: entry)
        }
        .configurationDisplayName("CodexBar Metric")
        .description("Compact widget for credits or cost.")
        .supportedFamilies([.systemSmall])
    }
}
