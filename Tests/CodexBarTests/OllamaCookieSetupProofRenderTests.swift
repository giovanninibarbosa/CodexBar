import AppKit
import SwiftUI
import Testing
@testable import CodexBar
@testable import CodexBarCore

/// Developer tool, skipped by default: renders the Ollama cookie-source settings row (Manual with an empty
/// field, then Auto) and the Manual-empty menu card through the real shared views, with synthetic in-memory
/// settings only.
///
/// Run with:
///   CODEXBAR_OLLAMA_COOKIE_PROOF_DIR=/tmp/ollama-proof swift test --filter OllamaCookieSetupProofRenderTests
@MainActor
@Suite(.serialized)
struct OllamaCookieSetupProofRenderTests {
    @Test
    func `render synthetic Ollama cookie setup proof when requested`() throws {
        guard let dir = ProcessInfo.processInfo.environment["CODEXBAR_OLLAMA_COOKIE_PROOF_DIR"] else { return }
        let directory = URL(fileURLWithPath: NSString(string: dir).expandingTildeInPath, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let (settings, store) = Self.makeStores(suiteName: #function)
        let context = Self.context(settings: settings, store: store)

        settings.ollamaCookieSource = .manual
        settings.ollamaCookieHeader = ""
        let manualPicker = try Self.cookieSourcePicker(context: context)
        let manualURL = try Self.writePNG(
            name: "ollama-cookie-source-manual-empty",
            directory: directory,
            content: Self.proofFrame(caption: "Synthetic settings · Cookie source Manual, empty field") {
                Self.connectionSection(picker: manualPicker)
            })

        settings.ollamaCookieSource = .auto
        let autoPicker = try Self.cookieSourcePicker(context: context)
        // Auto's trailing text consults the cookie cache; keep that read on the in-memory test store and an
        // empty temporary legacy directory so the render never reaches the Keychain or real cookie files.
        let legacyDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OllamaCookieSetupProof-\(UUID().uuidString)", isDirectory: true)
        CookieHeaderCache.resetDisplayCacheForTesting()
        defer { CookieHeaderCache.resetDisplayCacheForTesting() }
        let autoURL = try CookieHeaderCache.withLegacyBaseURLOverrideForTesting(legacyDirectory) {
            try KeychainCacheStore.withImplicitTestStoreForTesting {
                try Self.writePNG(
                    name: "ollama-cookie-source-auto",
                    directory: directory,
                    content: Self.proofFrame(caption: "Synthetic settings · Cookie source Auto") {
                        Self.connectionSection(picker: autoPicker)
                    })
            }
        }

        settings.ollamaCookieSource = .manual
        settings.ollamaCookieHeader = ""
        store.errors[.ollama] = OllamaUsageError.manualCookieHeaderEmpty.localizedDescription
        let model = store.menuCardModel(for: .ollama)
        #expect(model.subtitleText == L("ollama_manual_cookie_empty"))
        let cardURL = try Self.writePNG(
            name: "ollama-menu-card-manual-empty",
            directory: directory,
            content: Self.proofFrame(caption: "Synthetic menu card · Manual cookie source with empty field") {
                UsageMenuCardView(model: model, width: 360)
                    .padding(12)
                    .frame(width: 384)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            })

        for url in [manualURL, autoURL, cardURL] {
            #expect(FileManager.default.fileExists(atPath: url.path))
            print("Wrote \(url.path)")
        }
    }

    @Test
    func `ollama cookie source row exposes manual empty state`() throws {
        let (settings, store) = Self.makeStores(suiteName: #function)
        let context = Self.context(settings: settings, store: store)
        settings.ollamaCookieSource = .manual
        settings.ollamaCookieHeader = ""
        let picker = try Self.cookieSourcePicker(context: context)
        let useAuto = try #require(picker.trailingActions.first { $0.id == "ollama-use-auto-cookie" })

        #expect(picker.trailingText?() == L("ollama_manual_cookie_missing_status"))
        #expect(useAuto.isVisible?() == true)

        settings.ollamaCookieSource = .auto
        #expect(picker.dynamicSubtitle?() == L("ollama_cookie_source_auto_subtitle"))
    }

    private static func makeStores(suiteName: String) -> (SettingsStore, UsageStore) {
        let settings = testSettingsStore(suiteName: suiteName, userDefaults: InMemoryUserDefaults())
        settings.setProviderEnabled(provider: .ollama, metadata: ProviderDefaults.metadata[.ollama]!, enabled: true)
        let store = UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings)
        return (settings, store)
    }

    private static func cookieSourcePicker(context: ProviderSettingsContext) throws
        -> ProviderSettingsPickerDescriptor
    {
        try #require(OllamaProviderImplementation().settingsPickers(context: context).first {
            $0.id == "ollama-cookie-source"
        })
    }

    /// Mirrors the provider detail pane: the row lives in the grouped-form Connection section, which is what
    /// gives the trailing buttons their room next to a wrapping subtitle.
    private static func connectionSection(picker: ProviderSettingsPickerDescriptor) -> some View {
        Form {
            Section {
                ProviderSettingsPickerRowView(picker: picker)
            } header: {
                Text(L("provider_section_connection"))
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .frame(height: 130)
    }

    private static func proofFrame(
        caption: String,
        @ViewBuilder content: () -> some View) -> some View
    {
        VStack(alignment: .leading, spacing: 18) {
            Text("Ollama").font(.title2.bold())
            Text(caption).font(.caption).foregroundStyle(.secondary)
            content()
        }
        .padding(24)
        .frame(width: 700, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    /// `ImageRenderer` cannot draw the grouped `Form` the settings pane uses, so this hosts the view in an
    /// offscreen window and caches its display into a 2x bitmap instead.
    private static func writePNG(name: String, directory: URL, content: some View) throws -> URL {
        let scale: CGFloat = 2
        let data = try autoreleasepool {
            let hosting = NSHostingView(rootView: content)
            hosting.appearance = NSAppearance(named: .aqua)
            let size = hosting.fittingSize
            try #require(size.width > 0 && size.height > 0)
            hosting.frame = CGRect(origin: .zero, size: size)
            let window = NSWindow(
                contentRect: hosting.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false)
            window.appearance = NSAppearance(named: .aqua)
            window.contentView = hosting
            defer { window.contentView = nil }
            window.layoutIfNeeded()
            hosting.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))

            let bitmap = try #require(NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: Int(size.width * scale),
                pixelsHigh: Int(size.height * scale),
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0))
            bitmap.size = size
            hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
            return try #require(bitmap.representation(using: .png, properties: [:]))
        }
        let url = directory.appendingPathComponent("\(name).png")
        try data.write(to: url, options: .atomic)
        return url
    }

    private static func context(settings: SettingsStore, store: UsageStore) -> ProviderSettingsContext {
        ProviderSettingsContext(
            provider: .ollama,
            settings: settings,
            store: store,
            statusText: { _ in nil },
            setStatusText: { _, _ in },
            lastAppActiveRunAt: { _ in nil },
            setLastAppActiveRunAt: { _, _ in },
            requestConfirmation: { _ in })
    }
}
