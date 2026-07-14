import Charts
import SwiftUI

private enum OverviewTrendMetric: String, CaseIterable, Identifiable {
    case median = "Median"
    case p90 = "P90"
    case throughput = "Rate"
    case speed = "Speed index"
    case benchmark = "Benchmark"
    var id: String { rawValue }
}

struct AnalyticsOverviewView: View {
    let snapshot: DashboardSnapshot
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
        VStack(spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { primaryMetricTiles }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 190, maximum: 360))], spacing: 10) { primaryMetricTiles }
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { secondaryMetricTiles }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180, maximum: 360))], spacing: 10) { secondaryMetricTiles }
            }
        }
    }

    @ViewBuilder
    private var primaryMetricTiles: some View {
        ZetaMetricTile(
            title: "Projected 2m",
            value: projectedScore,
            detail: "timing simulation",
            change: comparison(.projectedScore),
            tint: ZetaTheme.brand
        )
        .frame(minWidth: 170)
        ZetaMetricTile(
            title: snapshot.throughputLabel,
            value: String(format: "%.1f", snapshot.questionsPerMinute),
            detail: snapshot.throughputLabel == "Questions/min" ? "whole-session pace" : "selected operation rate",
            change: comparison(.questionsPerMinute),
            tint: ZetaTheme.cyan
        )
        .frame(minWidth: 170)
        ZetaMetricTile(title: "Median", value: AnalyticsFormatting.time(snapshot.medianMilliseconds), detail: "time to correct", change: comparison(.medianTime), tint: ZetaTheme.caution)
            .frame(minWidth: 170)
        ZetaMetricTile(title: "P90", value: AnalyticsFormatting.time(snapshot.p90Milliseconds), detail: "slow-tail time", change: comparison(.p90Time), tint: Color(red: 0.62, green: 0.34, blue: 0.92))
            .frame(minWidth: 170)
    }

    @ViewBuilder
    private var secondaryMetricTiles: some View {
        ZetaMetricTile(title: "Completed", value: String(snapshot.completedCount), detail: "\(snapshot.sessionCount) comparable sessions", change: comparison(.completedQuestions), tint: ZetaTheme.brand)
            .frame(minWidth: 175)
        ZetaMetricTile(title: "Consistency", value: AnalyticsFormatting.index(snapshot.consistency), detail: "robust timing stability", change: comparison(.consistency), tint: ZetaTheme.positive)
            .frame(minWidth: 175)
        ZetaMetricTile(title: "Recent pace", value: AnalyticsFormatting.signedPercent(snapshot.recentSpeedChange), detail: "positive is faster", tint: AnalyticsFormatting.changeColor(snapshot.recentSpeedChange))
            .frame(minWidth: 175)
    }

    private var trendCard: some View {
        ZetaChartCard(
            title: "Performance over time",
            subtitle: snapshot.trendResolution == .daily ? "Seven-point rolling view; select or use arrow controls to inspect a day." : "Session view is used until at least three distinct practice days are available."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                ViewThatFits(in: .horizontal) {
                    HStack { trendPicker; Spacer(); trendNavigator }
                    VStack(alignment: .leading, spacing: 9) { trendPicker; trendNavigator }
                }

                Chart {
                    ForEach(rollingTrends) { point in
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value(trendMetric.rawValue, trendValue(point))
                        )
                        .foregroundStyle(ZetaTheme.brand)
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 2.5))
                        PointMark(
                            x: .value("Date", point.date),
                            y: .value(trendMetric.rawValue, trendValue(point))
                        )
                        .foregroundStyle(ZetaTheme.brand)
                        .symbolSize(selectedTrend?.id == point.id ? 75 : 30)
                    }
                    if trendMetric == .speed {
                        RuleMark(y: .value("Personal baseline", 100))
                            .foregroundStyle(.secondary.opacity(0.55))
                            .lineStyle(StrokeStyle(dash: [5, 4]))
                            .annotation(position: .top, alignment: .leading) { Text("Baseline 100").font(.caption2).foregroundStyle(.secondary) }
                    }
                    if let selectedTrend {
                        RuleMark(x: .value("Selected", selectedTrend.date))
                            .foregroundStyle(.secondary.opacity(0.55))
                            .annotation(position: .top, overflowResolution: .init(x: .fit, y: .disabled)) {
                                tooltip(selectedTrend)
                            }
                    }
                }
                .chartXSelection(value: $selectedDate)
                .chartYAxisLabel(axisLabel)
                .chartLegend(.hidden)
                .frame(height: 260)
                .accessibilityLabel("Performance over time, \(trendMetric.rawValue)")
                .accessibilityValue(trendAccessibilitySummary)
            }
        }
    }

    private var trendPicker: some View {
        Picker("Metric", selection: $trendMetric) {
            ForEach(availableTrendMetrics) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 480)
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
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.borderless)
    }

    private var paceCard: some View {
        ZetaChartCard(
            title: "Cumulative pace",
            subtitle: "Completions accumulate across active elapsed time. The dashed line is your representative pace when three or more sessions match."
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
                                x: .value("Elapsed %", point.elapsedFraction * 100),
                                y: .value("Completed", point.completedCount)
                            )
                            .foregroundStyle(ZetaTheme.brand)
                            .lineStyle(StrokeStyle(lineWidth: 2.5))
                        }
                        ForEach(snapshot.pace.representative) { point in
                            LineMark(
                                x: .value("Elapsed %", point.elapsedFraction * 100),
                                y: .value("Representative", point.completedCount)
                            )
                            .foregroundStyle(.secondary)
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                        }
                    }
                    .chartXAxisLabel("Elapsed session %")
                    .chartYAxisLabel("Completed questions")
                    .frame(height: 235)
                    .accessibilityLabel("Cumulative pace for \(selectedPace.label)")
                    .accessibilityValue("\(Int(selectedPace.points.last?.completedCount ?? 0)) questions in \(selectedPace.durationSeconds) seconds")
                } else {
                    ContentUnavailableView("No pace series", systemImage: "chart.line.uptrend.xyaxis", description: Text("Complete a matching session to see its cumulative pace."))
                        .frame(height: 210)
                }
            }
        }
    }

    private var projectedScore: String {
        snapshot.benchmarkProjections.first(where: { $0.durationSeconds == 120 })?.expected.map { String($0.median) } ?? "—"
    }
    private func comparison(_ metric: DashboardMetric) -> Double? { snapshot.priorPeriod[metric]?.improvementPercent }
    private var availableTrendMetrics: [OverviewTrendMetric] {
        snapshot.trends.contains(where: { $0.benchmarkScore != nil }) ? OverviewTrendMetric.allCases : OverviewTrendMetric.allCases.filter { $0 != .benchmark }
    }
    private var rollingTrends: [TrendPoint] {
        snapshot.trends.enumerated().map { index, point in
            let lower = max(0, index - 6)
            let window = Array(snapshot.trends[lower...index])
            return TrendPoint(
                id: point.id,
                date: point.date,
                medianMilliseconds: Statistics.median(window.map(\.medianMilliseconds)) ?? point.medianMilliseconds,
                p90Milliseconds: Statistics.median(window.map(\.p90Milliseconds)) ?? point.p90Milliseconds,
                speedIndex: Statistics.median(window.map(\.speedIndex)) ?? point.speedIndex,
                questionsPerMinute: Statistics.mean(window.map(\.questionsPerMinute)) ?? point.questionsPerMinute,
                benchmarkScore: Statistics.median(window.compactMap(\.benchmarkScore)),
                sampleCount: window.reduce(0) { $0 + $1.sampleCount },
                sessionID: point.sessionID
            )
        }
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
    private var axisLabel: String {
        switch trendMetric {
        case .median, .p90: "Seconds"
        case .throughput: snapshot.throughputLabel
        case .speed: "Speed index"
        case .benchmark: "Score"
        }
    }
    private var selectedTrend: TrendPoint? {
        guard let selectedDate else { return nil }
        return rollingTrends.min { abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate)) }
    }
    private func moveTrendSelection(_ direction: Int) {
        let values = rollingTrends
        guard !values.isEmpty else { return }
        let current = selectedTrend.flatMap { selected in values.firstIndex(where: { $0.id == selected.id }) } ?? (direction > 0 ? -1 : values.count)
        selectedDate = values[min(max(current + direction, 0), values.count - 1)].date
    }
    private func tooltip(_ point: TrendPoint) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(point.date, format: .dateTime.month(.abbreviated).day()).font(.caption.bold())
            Text("\(formattedTrendValue(point)) · n=\(point.sampleCount)").font(.caption2).monospacedDigit()
        }
        .padding(7)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 7))
    }
    private func formattedTrendValue(_ point: TrendPoint) -> String {
        switch trendMetric {
        case .median, .p90: String(format: "%.2fs", trendValue(point))
        case .throughput, .speed, .benchmark: String(format: "%.1f", trendValue(point))
        }
    }
    private var trendAccessibilitySummary: String {
        guard let latest = rollingTrends.last else { return "No points" }
        return "\(rollingTrends.count) points. Latest \(formattedTrendValue(latest))."
    }
    private var selectedPace: SessionPaceSeries? {
        snapshot.pace.sessions.first { $0.id == selectedPaceID } ?? snapshot.pace.sessions.first
    }
}
