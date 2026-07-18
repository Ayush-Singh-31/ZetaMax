import SwiftUI

enum AnalyticsSection: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case skills = "Skills"
    case distribution = "Distribution"
    case benchmarks = "Benchmarks"
    var id: String { rawValue }
    var systemImage: String {
        switch self {
        case .overview: "waveform.path.ecg"
        case .skills: "square.grid.2x2"
        case .distribution: "chart.bar.xaxis"
        case .benchmarks: "stopwatch"
        }
    }
}

enum AnalyticsFormatting {
    static func time(_ milliseconds: Double) -> String {
        milliseconds > 0 ? String(format: "%.2fs", milliseconds / 1_000) : "—"
    }
    static func index(_ value: Double) -> String { value > 0 ? String(format: "%.0f", value) : "—" }
    static func signedPercent(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%+.0f%%", value)
    }
    static func changeColor(_ value: Double?) -> Color {
        guard let value else { return .secondary }
        return value >= 0 ? ZetaTheme.positive : ZetaTheme.caution
    }
}

struct AnalyticsDashboardView: View {
    @Bindable var analyticsStore: AnalyticsStore
    @State private var section: AnalyticsSection = .overview
    @State private var dateRange: AnalyticsDateRange = .month
    @State private var mode: PracticeMode?
    @State private var operation: ArithmeticOperation?
    @State private var targetedPreset: TargetedPreset?
    @State private var benchmarkProfileKey: String?

    var body: some View {
        let snapshot = analyticsStore.snapshot

        ZetaScreen {
            VStack(alignment: .leading, spacing: ZetaTheme.sectionSpacing) {
                ZetaPageHeader(
                    title: "Analytics",
                    systemImage: "chart.xyaxis.line"
                )

                AnalyticsFilterBar(
                    dateRange: $dateRange,
                    mode: $mode,
                    operation: $operation,
                    targetedPreset: $targetedPreset,
                    benchmarkProfileKey: $benchmarkProfileKey,
                    benchmarkProfiles: benchmarkProfiles,
                    sessionCount: snapshot.sessionCount,
                    questionCount: snapshot.completedCount,
                    onReset: resetFilters
                )

                Picker("Analytics section", selection: $section) {
                    ForEach(AnalyticsSection.allCases) { item in
                        Label(item.rawValue, systemImage: item.systemImage).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("analyticsSectionPicker")

                if snapshot.sessionCount == 0 || snapshot.completedCount == 0 {
                    if analyticsStore.isRefreshingSnapshot {
                        ProgressView("Loading analytics…")
                            .controlSize(.small)
                            .frame(maxWidth: .infinity, minHeight: 340)
                    } else {
                        ContentUnavailableView(
                            "No matching timings",
                            systemImage: "chart.xyaxis.line",
                            description: Text("Complete a session or broaden the filters.")
                        )
                        .frame(minHeight: 340)
                    }
                } else {
                    AnalyticsInsightBanner(text: snapshot.insight)
                    sectionView(snapshot: snapshot)
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            if analyticsStore.isRefreshingSnapshot && snapshot.completedCount > 0 {
                ProgressView()
                    .controlSize(.small)
                    .padding(10)
                    .background(.regularMaterial, in: Capsule())
                    .padding()
                    .accessibilityLabel("Refreshing analytics")
            }
        }
        .navigationTitle("Analytics")
        .onAppear {
            applyUITestSectionIfNeeded()
            analyticsStore.requestSnapshot(for: filterKey, debounce: false)
        }
        .onChange(of: filterKey) { _, key in
            analyticsStore.requestSnapshot(for: key)
        }
    }

    @ViewBuilder
    private func sectionView(snapshot: DashboardSnapshot) -> some View {
        switch section {
        case .overview:
            AnalyticsOverviewView(snapshot: snapshot)
                .accessibilityIdentifier("analyticsOverviewSection")
        case .skills:
            SkillsAnalyticsView(snapshot: snapshot)
                .accessibilityIdentifier("analyticsSkillsSection")
        case .distribution:
            DistributionAnalyticsView(snapshot: snapshot)
                .accessibilityIdentifier("analyticsDistributionSection")
        case .benchmarks:
            BenchmarkAnalyticsView(snapshot: snapshot)
                .accessibilityIdentifier("analyticsBenchmarksSection")
        }
    }

    private var benchmarkProfiles: [(key: String, title: String)] {
        analyticsStore.snapshot.benchmarkFilterOptions.map { ($0.key, $0.title) }
    }

    private var filterKey: AnalyticsFilterKey {
        AnalyticsFilterKey(
            dateRange: dateRange,
            mode: mode,
            operation: operation,
            targetedPreset: targetedPreset,
            benchmarkProfileKey: benchmarkProfileKey
        )
    }

    private func resetFilters() {
        dateRange = .month
        mode = nil
        operation = nil
        targetedPreset = nil
        benchmarkProfileKey = nil
    }

    private func applyUITestSectionIfNeeded() {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-ui-testing-analytics-section"),
              arguments.indices.contains(index + 1),
              let requested = AnalyticsSection.allCases.first(where: { $0.rawValue.lowercased() == arguments[index + 1].lowercased() }) else { return }
        section = requested
    }
}

private struct AnalyticsFilterBar: View {
    @Binding var dateRange: AnalyticsDateRange
    @Binding var mode: PracticeMode?
    @Binding var operation: ArithmeticOperation?
    @Binding var targetedPreset: TargetedPreset?
    @Binding var benchmarkProfileKey: String?
    let benchmarkProfiles: [(key: String, title: String)]
    let sessionCount: Int
    let questionCount: Int
    let onReset: () -> Void

    var body: some View {
        ZetaCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Filters", systemImage: "line.3.horizontal.decrease.circle").font(.headline)
                    Spacer()
                    Text("\(sessionCount) sessions · \(questionCount) questions")
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180, maximum: 230))], alignment: .leading, spacing: 9) {
                    picker("Range", selection: $dateRange) {
                        ForEach(AnalyticsDateRange.allCases) { Text($0.rawValue).tag($0) }
                    }
                    picker("Mode", selection: $mode) {
                        Text("All modes").tag(PracticeMode?.none)
                        ForEach(PracticeMode.allCases) { Text($0.title).tag(Optional($0)) }
                    }
                    picker("Operation", selection: $operation) {
                        Text("All operations").tag(ArithmeticOperation?.none)
                        ForEach(ArithmeticOperation.allCases) { Text($0.title).tag(Optional($0)) }
                    }
                    picker("Target", selection: $targetedPreset) {
                        Text("All targets").tag(TargetedPreset?.none)
                        ForEach(TargetedPreset.allCases) { Text($0.title).tag(Optional($0)) }
                    }
                    if !benchmarkProfiles.isEmpty {
                        picker("Benchmark", selection: $benchmarkProfileKey) {
                            Text("All benchmarks").tag(String?.none)
                            ForEach(benchmarkProfiles, id: \.key) { Text($0.title).tag(Optional($0.key)) }
                        }
                    }
                    Button("Reset filters", systemImage: "arrow.counterclockwise", action: onReset)
                }
            }
        }
        .accessibilityIdentifier("analyticsFilterBar")
    }

    private func picker<Selection: Hashable, Content: View>(
        _ title: String,
        selection: Binding<Selection>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Picker(title, selection: selection, content: content)
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AnalyticsInsightBanner: View {
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: "lightbulb.max.fill").foregroundStyle(ZetaTheme.caution)
            Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(13)
        .background(ZetaTheme.caution.opacity(0.09), in: RoundedRectangle(cornerRadius: ZetaTheme.compactRadius))
        .overlay { RoundedRectangle(cornerRadius: ZetaTheme.compactRadius).strokeBorder(ZetaTheme.caution.opacity(0.18)) }
        .accessibilityLabel("Analytics insight: \(text)")
    }
}
