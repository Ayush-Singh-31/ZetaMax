import Charts
import SwiftData
import SwiftUI

struct RecommendationsView: View {
    @Bindable var engine: SessionEngine
    @Query(sort: \PracticeSession.startedAt, order: .reverse) private var sessions: [PracticeSession]
    @Query private var estimates: [SkillEstimate]

    private var recommendations: [Recommendation] {
        AnalyticsEngine.recommendations(sessions: sessions, estimates: estimates)
    }

    var body: some View {
        ZetaScreen(maxWidth: 920) {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Label("PERSONAL COACH", systemImage: "scope")
                        .font(.caption.weight(.bold))
                        .tracking(0.8)
                        .foregroundStyle(.blue)
                    Text("What should I practise?").font(.largeTitle.bold())
                    Text("A transparent diagnosis based on your saved questions—not a black box.")
                        .font(.title3).foregroundStyle(.secondary)
                }

                if recommendations.isEmpty {
                    ContentUnavailableView {
                        Label("Build your baseline", systemImage: "chart.bar.doc.horizontal")
                    } description: {
                        Text("Complete at least ten questions in a category. ZetaMax will then identify skills that are slow, deteriorating, or due for practice.")
                    } actions: {
                        Button("Start a 45-second baseline") {
                            engine.prepareRecommendedSession(categoryKey: nil)
                            engine.start()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(minHeight: 360)
                } else {
                    ForEach(Array(recommendations.enumerated()), id: \.element.id) { index, recommendation in
                        GroupBox {
                            ViewThatFits(in: .horizontal) {
                                HStack(alignment: .top, spacing: 16) {
                                    recommendationCopy(index: index, recommendation: recommendation)
                                    Spacer(minLength: 12)
                                    recommendationButton(recommendation)
                                }
                                VStack(alignment: .leading, spacing: 14) {
                                    recommendationCopy(index: index, recommendation: recommendation)
                                    recommendationButton(recommendation)
                                }
                            }
                            .padding(10)
                        }
                    }
                }

                Text("Recommendations use time-to-correct relative to your baseline, recent slowdown, recency, and confidence. Categories with fewer than ten completed timings are not diagnosed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .groupBoxStyle(ZetaGroupBoxStyle())
        .navigationTitle("Recommendations")
    }

    private func recommendationCopy(index: Int, recommendation: Recommendation) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(index + 1)")
                .font(.title2.bold())
                .foregroundStyle(.blue)
                .frame(width: 42, height: 42)
                .background(Color.blue.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 7) {
                Text(recommendation.title).font(.title3.bold())
                Text(recommendation.explanation).foregroundStyle(.secondary)
            }
        }
    }

    private func recommendationButton(_ recommendation: Recommendation) -> some View {
        Button("Practise 45s") {
            engine.prepareRecommendedSession(categoryKey: recommendation.categoryKey)
            engine.start()
        }
        .buttonStyle(.borderedProminent)
    }
}

private enum AnalyticsDateRange: String, CaseIterable, Identifiable {
    case week = "7 days", month = "30 days", quarter = "90 days", all = "All time"
    var id: String { rawValue }
    var days: Int? {
        switch self { case .week: 7; case .month: 30; case .quarter: 90; case .all: nil }
    }
}

private enum HeatmapMetric: String, CaseIterable, Identifiable {
    case median = "Median time", p90 = "P90 time", count = "Attempts"
    var id: String { rawValue }
}

private enum TrendGranularity: String, CaseIterable, Identifiable {
    case daily = "Daily", weekly = "Weekly"
    var id: String { rawValue }
}

struct AnalyticsDashboardView: View {
    @Query(sort: \PracticeSession.startedAt, order: .reverse) private var allSessions: [PracticeSession]
    @State private var dateRange: AnalyticsDateRange = .month
    @State private var mode: PracticeMode?
    @State private var operation: ArithmeticOperation?
    @State private var targetedPreset: TargetedPreset?
    @State private var benchmarkID: String?
    @State private var heatmapMetric: HeatmapMetric = .median
    @State private var trendGranularity: TrendGranularity = .daily

    private var sessions: [PracticeSession] {
        allSessions.filter { session in
            let dateMatches = dateRange.days.map { session.startedAt >= Calendar.current.date(byAdding: .day, value: -$0, to: .now)! } ?? true
            let modeMatches = mode == nil || session.mode == mode
            let targetMatches = targetedPreset == nil || session.configuration.targetedPreset == targetedPreset
            let benchmarkMatches = benchmarkID == nil || session.benchmarkID == benchmarkID
            return dateMatches && modeMatches && targetMatches && benchmarkMatches
        }
    }

    private var snapshot: DashboardSnapshot {
        AnalyticsEngine.snapshot(sessions: sessions, baselineSessions: allSessions, operation: operation)
    }

    var body: some View {
        ZetaScreen {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 5) {
                    Label("PERFORMANCE LAB", systemImage: "chart.xyaxis.line")
                        .font(.caption.weight(.bold))
                        .tracking(0.8)
                        .foregroundStyle(.blue)
                    Text("Analytics").font(.largeTitle.bold())
                }
                filterBar

                if snapshot.sessionCount == 0 {
                    ContentUnavailableView("No matching sessions", systemImage: "chart.xyaxis.line", description: Text("Complete a session or broaden the filters."))
                        .frame(minHeight: 360)
                } else {
                    summaryCards
                    trendSection
                    operationSection
                    categorySection
                    responseSection
                    heatmapSection
                    fatigueAndConsistency
                    missedAndBenchmarks
                }
            }
        }
        .groupBoxStyle(ZetaGroupBoxStyle())
        .navigationTitle("Analytics")
    }

    private var filterBar: some View {
        ZetaCard {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 135, maximum: 220))], alignment: .leading, spacing: 10) {
                Picker("Range", selection: $dateRange) {
                    ForEach(AnalyticsDateRange.allCases) { Text($0.rawValue).tag($0) }
                }
                Picker("Mode", selection: $mode) {
                    Text("All modes").tag(PracticeMode?.none)
                    ForEach(PracticeMode.allCases) { Text($0.title).tag(Optional($0)) }
                }
                Picker("Operation", selection: $operation) {
                    Text("All operations").tag(ArithmeticOperation?.none)
                    ForEach(ArithmeticOperation.allCases) { Text($0.title).tag(Optional($0)) }
                }
                Picker("Target", selection: $targetedPreset) {
                    Text("All targets").tag(TargetedPreset?.none)
                    ForEach(TargetedPreset.allCases) { Text($0.title).tag(Optional($0)) }
                }
                if !benchmarkIDs.isEmpty {
                    Picker("Benchmark", selection: $benchmarkID) {
                        Text("All benchmarks").tag(String?.none)
                        ForEach(benchmarkIDs, id: \.self) { Text($0).tag(Optional($0)) }
                    }
                }
            }
            .labelsHidden()
        }
    }

    private var summaryCards: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 135, maximum: 210))], spacing: 10) {
            ZetaMetricTile(title: "Completed", value: String(snapshot.completedCount), detail: "\(snapshot.sessionCount) sessions", tint: .blue)
            ZetaMetricTile(title: "Questions/min", value: String(format: "%.1f", snapshot.questionsPerMinute), detail: "throughput", tint: .cyan)
            ZetaMetricTile(title: "Median", value: time(snapshot.medianMilliseconds), detail: "time to correct", tint: .orange)
            ZetaMetricTile(title: "P90", value: time(snapshot.p90Milliseconds), detail: "slow-tail time", tint: .purple)
            ZetaMetricTile(title: "Consistency", value: index(snapshot.consistency), detail: "timing stability", tint: .indigo)
            ZetaMetricTile(title: "Recent change", value: signedPercent(snapshot.recentSpeedChange), detail: "positive is faster", tint: changeColor(snapshot.recentSpeedChange))
        }
    }

    private var trendSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Performance over time").font(.headline)
                    Spacer()
                    Picker("Granularity", selection: $trendGranularity) {
                        ForEach(TrendGranularity.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 170)
                }
                Chart(displayedTrends) { point in
                    LineMark(x: .value("Date", point.date), y: .value("Median seconds", point.medianMilliseconds / 1_000))
                        .interpolationMethod(.catmullRom)
                    PointMark(x: .value("Date", point.date), y: .value("Median seconds", point.medianMilliseconds / 1_000))
                }
                .chartYAxisLabel("Median seconds")
                .frame(height: 190)
                Chart(displayedTrends) { point in
                    RuleMark(y: .value("Baseline", 100))
                        .foregroundStyle(.secondary.opacity(0.4))
                    LineMark(x: .value("Date", point.date), y: .value("Speed index", point.speedIndex))
                        .foregroundStyle(.green)
                        .interpolationMethod(.catmullRom)
                    PointMark(x: .value("Date", point.date), y: .value("Speed index", point.speedIndex))
                        .foregroundStyle(.green)
                }
                .chartYAxisLabel("Adjusted speed index")
                .frame(height: 150)
            }
            .padding(8)
        }
    }

    private var categorySection: some View {
        GroupBox("Category difficulty") {
            Chart(Array(snapshot.categories.prefix(12))) { metric in
                BarMark(
                    x: .value("Median seconds", metric.medianMilliseconds / 1_000),
                    y: .value("Category", metric.name)
                )
                PointMark(
                    x: .value("P90 seconds", metric.p90Milliseconds / 1_000),
                    y: .value("Category", metric.name)
                )
                .symbol(.diamond)
                .annotation(position: .trailing) {
                    Text("D\(Int(metric.difficultyIndex.rounded())) · n=\(metric.attempts)").font(.caption2)
                }
            }
            .chartXAxisLabel("Median seconds")
            .frame(height: max(220, CGFloat(min(12, snapshot.categories.count)) * 28))
            .padding(8)
        }
    }

    private var operationSection: some View {
        GroupBox("Performance by operation") {
            Chart(snapshot.operations) { metric in
                BarMark(x: .value("Operation", metric.operation.title), y: .value("Median seconds", metric.medianMilliseconds / 1_000))
                    .foregroundStyle(by: .value("Operation", metric.operation.title))
                PointMark(x: .value("Operation", metric.operation.title), y: .value("P90 seconds", metric.p90Milliseconds / 1_000))
                    .foregroundStyle(.primary)
                    .symbol(.diamond)
                    .annotation(position: .top) { Text("D\(Int(metric.difficultyIndex.rounded()))").font(.caption2) }
            }
            .chartYAxisLabel("Median seconds")
            .frame(height: 220)
            .padding(8)
        }
    }

    private var responseSection: some View {
        ZetaResponsivePair {
            GroupBox("Response-time distribution") {
                Chart {
                    ForEach(snapshot.distribution) { bin in
                        BarMark(
                            x: .value("Seconds", Double(bin.lowerMilliseconds) / 1_000),
                            y: .value("Questions", bin.count),
                            width: .fixed(8)
                        )
                    }
                    RuleMark(x: .value("Median", snapshot.medianMilliseconds / 1_000))
                        .foregroundStyle(.orange)
                    RuleMark(x: .value("P90", snapshot.p90Milliseconds / 1_000))
                        .foregroundStyle(.purple)
                }
                .chartXScale(domain: 0...10)
                .chartXAxisLabel("Seconds · final bar includes 10s+")
                .frame(height: 220)
                .padding(8)
            }
        } second: {
            GroupBox("Category effort map") {
                Chart(snapshot.categories.filter { $0.attempts >= 10 && $0.recentSpeedChange != nil }) { metric in
                    RuleMark(x: .value("Typical difficulty", 100))
                        .foregroundStyle(.secondary.opacity(0.35))
                    RuleMark(y: .value("No change", 0))
                        .foregroundStyle(.secondary.opacity(0.35))
                    PointMark(
                        x: .value("Difficulty index", metric.difficultyIndex),
                        y: .value("Recent speed change", metric.recentSpeedChange ?? 0)
                    )
                    .foregroundStyle(by: .value("Operation", metric.operation.title))
                    .symbolSize(by: .value("Samples", metric.attempts))
                }
                .chartXAxisLabel("Difficulty index · 100 is typical")
                .chartYAxisLabel("Recent change % · positive is faster")
                .frame(height: 220)
                .padding(8)
            }
        }
    }

    @ViewBuilder
    private var heatmapSection: some View {
        if !snapshot.heatmap.isEmpty {
            GroupBox {
                VStack(alignment: .leading) {
                    HStack {
                        Text("Multiplication heatmap").font(.headline)
                        Spacer()
                        Picker("Metric", selection: $heatmapMetric) {
                            ForEach(HeatmapMetric.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .frame(width: 170)
                    }
                    Chart(snapshot.heatmap) { cell in
                        RectangleMark(
                            xStart: .value("Left start", Double(cell.left) - 0.45),
                            xEnd: .value("Left end", Double(cell.left) + 0.45),
                            yStart: .value("Right start", Double(cell.right) - 0.45),
                            yEnd: .value("Right end", Double(cell.right) + 0.45)
                        )
                        .foregroundStyle(Color.accentColor.opacity(heatmapOpacity(cell)))
                        .annotation(position: .overlay) {
                            Text(heatmapLabel(cell)).font(.caption2).foregroundStyle(.primary)
                        }
                    }
                    .frame(height: 360)
                }
                .padding(8)
            }
        }
    }

    private var fatigueAndConsistency: some View {
        GroupBox("Session fatigue") {
            Chart(snapshot.fatigue) { point in
                RuleMark(y: .value("Baseline", 1))
                    .foregroundStyle(.secondary.opacity(0.35))
                LineMark(x: .value("Session", point.label), y: .value("Normalized effort", point.normalizedEffort))
                    .interpolationMethod(.catmullRom)
                PointMark(x: .value("Session", point.label), y: .value("Normalized effort", point.normalizedEffort))
                    .annotation(position: .top) { Text("n=\(point.sampleCount)").font(.caption2) }
            }
            .chartYAxisLabel("Effort vs category baseline")
            .frame(height: 210)
            .padding(8)
        }
    }

    private var missedAndBenchmarks: some View {
        ZetaResponsivePair {
            GroupBox("Slowest completions") {
                VStack(spacing: 8) {
                    if snapshot.slowestCompletions.isEmpty { Text("No completed timings in this view.").foregroundStyle(.secondary) }
                    ForEach(snapshot.slowestCompletions) { completion in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(completion.prompt).monospacedDigit()
                                Text(completion.categoryName).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            Text(String(format: "%.1f×", completion.baselineMultiple))
                                .foregroundStyle(.secondary)
                            Text(time(Double(completion.responseMilliseconds))).bold().monospacedDigit()
                        }
                    }
                }.padding(8)
            }
        } second: {
            GroupBox("Benchmark outlook") {
                VStack(alignment: .leading, spacing: 10) {
                    if let expected = AnalyticsEngine.expectedScore(durationSeconds: 120, sessions: sessions) {
                        Text("Expected 2-minute score").font(.caption).foregroundStyle(.secondary)
                        Text("\(expected.median)").font(.largeTitle.bold()).monospacedDigit()
                        Text("Likely range \(expected.lower)–\(expected.upper)").foregroundStyle(.secondary)
                    } else {
                        Text("Complete 20 questions to estimate a benchmark score.").foregroundStyle(.secondary)
                    }
                    Divider()
                    ForEach(snapshot.personalBests.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                        HStack { Text(key); Spacer(); Text("PB \(value)").bold() }
                    }
                    if !benchmarkSessions.isEmpty {
                        Chart(benchmarkSessions) { session in
                            LineMark(
                                x: .value("Date", session.startedAt),
                                y: .value("Score", session.correctCount)
                            )
                            .foregroundStyle(by: .value("Profile", session.benchmarkID ?? "Benchmark"))
                            PointMark(
                                x: .value("Date", session.startedAt),
                                y: .value("Score", session.correctCount)
                            )
                            .foregroundStyle(by: .value("Profile", session.benchmarkID ?? "Benchmark"))
                        }
                        .frame(height: 130)
                    }
                }.padding(8)
            }
        }
    }

    private var benchmarkIDs: [String] { Array(Set(allSessions.compactMap(\.benchmarkID))).sorted() }
    private var comparableSessions: [PracticeSession] { sessions.filter(\.isComparable) }
    private var benchmarkSessions: [PracticeSession] {
        comparableSessions.filter { $0.mode == .benchmark }.sorted { $0.startedAt < $1.startedAt }
    }
    private var displayedTrends: [TrendPoint] {
        switch trendGranularity {
        case .daily:
            return snapshot.trends.enumerated().map { index, point in
                let window = Array(snapshot.trends[max(0, index - 6)...index])
                return TrendPoint(
                    date: point.date,
                    medianMilliseconds: Statistics.median(window.map(\.medianMilliseconds)) ?? point.medianMilliseconds,
                    speedIndex: Statistics.median(window.map(\.speedIndex)) ?? point.speedIndex,
                    questionsPerMinute: Statistics.mean(window.map(\.questionsPerMinute)) ?? point.questionsPerMinute
                )
            }
        case .weekly:
            let calendar = Calendar.current
            let grouped = Dictionary(grouping: snapshot.trends) { point in
                calendar.dateInterval(of: .weekOfYear, for: point.date)?.start ?? point.date
            }
            return grouped.map { date, values in
                TrendPoint(
                    date: date,
                    medianMilliseconds: Statistics.median(values.map(\.medianMilliseconds)) ?? 0,
                    speedIndex: Statistics.median(values.map(\.speedIndex)) ?? 0,
                    questionsPerMinute: Statistics.mean(values.map(\.questionsPerMinute)) ?? 0
                )
            }.sorted { $0.date < $1.date }
        }
    }
    private func time(_ milliseconds: Double) -> String { milliseconds > 0 ? String(format: "%.2fs", milliseconds / 1_000) : "—" }
    private func index(_ value: Double) -> String { value > 0 ? String(format: "%.0f", value) : "—" }
    private func signedPercent(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%+.0f%%", value)
    }
    private func changeColor(_ value: Double?) -> Color {
        guard let value else { return .secondary }
        return value >= 0 ? .green : .orange
    }
    private func heatmapLabel(_ cell: HeatmapCell) -> String {
        switch heatmapMetric {
        case .median: time(cell.medianMilliseconds)
        case .p90: time(cell.p90Milliseconds)
        case .count: String(cell.count)
        }
    }
    private func heatmapOpacity(_ cell: HeatmapCell) -> Double {
        switch heatmapMetric {
        case .median: min(max(cell.medianMilliseconds / 5_000, 0.12), 0.9)
        case .p90: min(max(cell.p90Milliseconds / 7_500, 0.12), 0.9)
        case .count: min(max(Double(cell.count) / Double(snapshot.heatmap.map(\.count).max() ?? 1), 0.12), 0.9)
        }
    }
}
