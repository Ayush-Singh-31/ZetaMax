import Charts
import SwiftUI

private enum OverviewTrendMetric: String, CaseIterable, Identifiable {
    case median = "Median"
    case p90 = "P90"
    case throughput = "Questions/minute"
    case speed = "Speed index"
    case benchmark = "Benchmark"
    var id: String { rawValue }
}

struct AnalyticsOverviewView: View {
    let snapshot: DashboardSnapshot
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.zetaReduceMotionOverride) private var reduceMotionOverride
    @State private var trendMetric: OverviewTrendMetric = .median
    @State private var selectedDate: Date?
    @State private var selectedPaceID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: ZetaTheme.sectionSpacing) {
            metrics
            trendCard
            paceCard
        }
        .onAppear {
            if selectedPaceID == nil { selectedPaceID = snapshot.pace.sessions.first?.id }
        }
    }

    private var metrics: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 175, maximum: 300))], spacing: 10) {
            ZetaMetricTile(
                title: "Completed",
                value: String(snapshot.completedCount),
                detail: "\(snapshot.sessionCount) sessions",
                change: comparison(.completedQuestions),
                tint: ZetaTheme.brand
            )
            ZetaMetricTile(
                title: "Questions/minute",
                value: String(format: "%.1f", snapshot.questionsPerMinute),
                detail: snapshot.throughputLabel == "Questions/min" ? "All questions" : snapshot.throughputLabel,
                change: comparison(.questionsPerMinute),
                tint: ZetaTheme.cyan
            )
            ZetaMetricTile(
                title: "Median",
                value: AnalyticsFormatting.time(snapshot.medianMilliseconds),
                detail: "Time to correct",
                change: comparison(.medianTime),
                tint: ZetaTheme.caution
            )
            ZetaMetricTile(
                title: "P90",
                value: AnalyticsFormatting.time(snapshot.p90Milliseconds),
                detail: "Slow-tail time",
                change: comparison(.p90Time),
                tint: Color(red: 0.62, green: 0.34, blue: 0.92)
            )
            ZetaMetricTile(
                title: "Consistency",
                value: AnalyticsFormatting.index(snapshot.consistency),
                detail: "Timing stability",
                change: comparison(.consistency),
                tint: ZetaTheme.positive
            )
            ZetaMetricTile(
                title: "Recent speed",
                value: recentSpeedValue,
                detail: snapshot.recentSpeedChange == nil ? "More timings needed" : "Recent vs previous",
                tint: AnalyticsFormatting.changeColor(snapshot.recentSpeedChange)
            )
        }
    }

    private var trendCard: some View {
        ZetaChartCard(
            title: "Performance trend",
            subtitle: snapshot.trendResolution == .daily ? "Daily aggregation" : "Per-session aggregation"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                ViewThatFits(in: .horizontal) {
                    HStack { trendPicker; Spacer(); trendNavigator }
                    VStack(alignment: .leading, spacing: 9) { trendPicker; trendNavigator }
                }

                Chart {
                    ForEach(snapshot.trends) { point in
                        LineMark(
                            x: .value(xAxisTitle, point.date),
                            y: .value(axisLabel, trendValue(point))
                        )
                        .foregroundStyle(ZetaTheme.brand)
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 2.5))
                        PointMark(
                            x: .value(xAxisTitle, point.date),
                            y: .value(axisLabel, trendValue(point))
                        )
                        .foregroundStyle(ZetaTheme.brand)
                        .symbolSize(selectedTrend?.id == point.id ? 75 : 30)
                    }
                    if trendMetric == .speed {
                        RuleMark(y: .value("Personal baseline", 100))
                            .foregroundStyle(.secondary.opacity(0.55))
                            .lineStyle(StrokeStyle(dash: [5, 4]))
                    }
                    if let selectedTrend {
                        RuleMark(x: .value("Selected", selectedTrend.date))
                            .foregroundStyle(.secondary.opacity(0.55))
                    }
                }
                .chartXSelection(value: $selectedDate)
                .chartXAxisLabel(xAxisTitle)
                .chartYAxisLabel(axisLabel)
                .chartLegend(.hidden)
                .frame(height: 320)
                .animation(reduceMotion || reduceMotionOverride ? nil : .easeOut(duration: 0.16), value: trendMetric)
                .accessibilityLabel("Performance trend, \(trendMetric.rawValue)")
                .accessibilityValue(trendAccessibilitySummary)

                HStack(spacing: 16) {
                    Label(trendMetric.rawValue, systemImage: "line.diagonal")
                        .foregroundStyle(ZetaTheme.brand)
                    Spacer()
                    if let selectedTrend {
                        Text("\(selectedTrend.date.formatted(date: .abbreviated, time: .omitted)) · \(formattedTrendValue(selectedTrend))")
                            .monospacedDigit()
                    } else {
                        Text("Select a point")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(minHeight: 22)
            }
        }
    }

    private var trendPicker: some View {
        Picker("Metric", selection: $trendMetric) {
            ForEach(availableTrendMetrics) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 520)
        .onChange(of: trendMetric) { _, _ in selectedDate = nil }
    }

    private var trendNavigator: some View {
        HStack(spacing: 5) {
            Button { moveTrendSelection(-1) } label: { Image(systemName: "chevron.left") }
                .help("Previous point")
            Button { moveTrendSelection(1) } label: { Image(systemName: "chevron.right") }
                .help("Next point")
            if let selectedTrend {
                Text(selectedTrend.date, format: .dateTime.month(.abbreviated).day())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.borderless)
    }

    private var paceCard: some View {
        ZetaChartCard(
            title: "Cumulative session pace",
            subtitle: "Solid: selected session · dashed: representative pace"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Session", selection: $selectedPaceID) {
                    ForEach(snapshot.pace.sessions) { pace in
                        Text("\(pace.label) · \(pace.mode.title)").tag(Optional(pace.id))
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 320, alignment: .leading)

                if let selectedPace {
                    Chart {
                        ForEach(selectedPace.points) { point in
                            LineMark(
                                x: .value("Elapsed session percentage", point.elapsedFraction * 100),
                                y: .value("Completed questions", point.completedCount)
                            )
                            .foregroundStyle(ZetaTheme.brand)
                            .lineStyle(StrokeStyle(lineWidth: 2.5))
                        }
                        ForEach(snapshot.pace.representative) { point in
                            LineMark(
                                x: .value("Elapsed session percentage", point.elapsedFraction * 100),
                                y: .value("Completed questions", point.completedCount)
                            )
                            .foregroundStyle(.secondary)
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                        }
                    }
                    .chartXAxisLabel("Elapsed session percentage")
                    .chartYAxisLabel("Completed questions")
                    .chartLegend(.hidden)
                    .frame(height: 310)
                    .accessibilityLabel("Cumulative session pace for \(selectedPace.label)")
                    .accessibilityValue("\(Int(selectedPace.points.last?.completedCount ?? 0)) questions in \(selectedPace.durationSeconds) seconds")

                    HStack(spacing: 16) {
                        Label("Selected session", systemImage: "line.diagonal").foregroundStyle(ZetaTheme.brand)
                        Label("Representative", systemImage: "line.diagonal").foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(selectedPace.points.last?.completedCount ?? 0)) completed · \(DurationText.compact(selectedPace.durationSeconds))")
                            .monospacedDigit()
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else {
                    ContentUnavailableView(
                        "No pace series",
                        systemImage: "chart.line.uptrend.xyaxis",
                        description: Text("Complete a matching session.")
                    )
                    .frame(height: 250)
                }
            }
        }
    }

    private func comparison(_ metric: DashboardMetric) -> Double? {
        snapshot.priorPeriod[metric]?.improvementPercent
    }

    private var availableTrendMetrics: [OverviewTrendMetric] {
        snapshot.trends.contains(where: { $0.benchmarkScore != nil })
            ? OverviewTrendMetric.allCases
            : OverviewTrendMetric.allCases.filter { $0 != .benchmark }
    }

    private func trendValue(_ point: TrendPoint) -> Double {
        switch trendMetric {
        case .median: point.medianMilliseconds / 1_000
        case .p90: point.p90Milliseconds / 1_000
        case .throughput: point.questionsPerMinute
        case .speed: point.speedIndex
        case .benchmark: point.benchmarkScore ?? 0
        }
    }

    private var xAxisTitle: String {
        snapshot.trendResolution == .daily ? "Date" : "Session"
    }

    private var axisLabel: String {
        switch trendMetric {
        case .median, .p90: "Seconds"
        case .throughput: "Questions per minute"
        case .speed: "Speed index"
        case .benchmark: "Completed questions"
        }
    }

    private var selectedTrend: TrendPoint? {
        guard let selectedDate else { return nil }
        return snapshot.trends.min {
            abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate))
        }
    }

    private func moveTrendSelection(_ direction: Int) {
        let values = snapshot.trends
        guard !values.isEmpty else { return }
        let current = selectedTrend.flatMap { selected in
            values.firstIndex(where: { $0.id == selected.id })
        } ?? (direction > 0 ? -1 : values.count)
        selectedDate = values[min(max(current + direction, 0), values.count - 1)].date
    }

    private func formattedTrendValue(_ point: TrendPoint) -> String {
        switch trendMetric {
        case .median, .p90: String(format: "%.2fs", trendValue(point))
        case .throughput: String(format: "%.1f questions/minute", trendValue(point))
        case .speed: String(format: "%.0f", trendValue(point))
        case .benchmark: String(format: "%.0f completed", trendValue(point))
        }
    }

    private var trendAccessibilitySummary: String {
        guard let latest = snapshot.trends.last else { return "No points" }
        return "\(snapshot.trends.count) points. Latest \(formattedTrendValue(latest))."
    }

    private var selectedPace: SessionPaceSeries? {
        snapshot.pace.sessions.first { $0.id == selectedPaceID } ?? snapshot.pace.sessions.first
    }

    private var recentSpeedValue: String {
        guard let value = snapshot.recentSpeedChange else { return "—" }
        return "\(Int(abs(value).rounded()))% \(value >= 0 ? "faster" : "slower")"
    }
}
