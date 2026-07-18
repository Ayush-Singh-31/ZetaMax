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
    @State private var trendMetric: OverviewTrendMetric = .median
    @State private var selectedDate: Date?
    @State private var selectedPaceID: UUID?
    @State private var selectedDistributionSeconds: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: ZetaTheme.sectionSpacing) {
            metrics
            trendCard
            supportingCharts
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
                value: snapshot.completedCount >= Statistics.reliableTailSampleCount
                    ? AnalyticsFormatting.time(snapshot.p90Milliseconds)
                    : "—",
                detail: snapshot.completedCount >= Statistics.reliableTailSampleCount
                    ? "Slow-tail time"
                    : "Needs \(Statistics.reliableTailSampleCount) timings",
                change: snapshot.completedCount >= Statistics.reliableTailSampleCount
                    ? comparison(.p90Time)
                    : nil,
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
                        if let value = trendValue(point) {
                            LineMark(
                                x: .value(xAxisTitle, point.date),
                                y: .value(axisLabel, value)
                            )
                            .foregroundStyle(ZetaTheme.brand)
                            .interpolationMethod(.linear)
                            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                            PointMark(
                                x: .value(xAxisTitle, point.date),
                                y: .value(axisLabel, value)
                            )
                            .foregroundStyle(ZetaTheme.brand)
                            .symbolSize(selectedTrend?.id == point.id ? 75 : 34)
                        }
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
                .chartXScale(domain: trendDateDomain)
                .chartYScale(domain: trendValueDomain)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: min(max(trendPlotPoints.count, 2), 6))) { value in
                        AxisGridLine().foregroundStyle(.secondary.opacity(0.18))
                        AxisTick()
                        if snapshot.trendResolution == .daily {
                            AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                        } else {
                            AxisValueLabel(format: .dateTime.month(.abbreviated).day().hour().minute())
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine().foregroundStyle(.secondary.opacity(0.18))
                        AxisTick()
                        AxisValueLabel()
                    }
                }
                .chartXAxisLabel(xAxisTitle)
                .chartYAxisLabel(axisLabel)
                .chartLegend(.hidden)
                .chartPlotStyle { plotArea in
                    plotArea.padding(.horizontal, 8)
                }
                .frame(height: 320)
                .accessibilityLabel("Performance trend, \(trendMetric.rawValue)")
                .accessibilityValue(trendAccessibilitySummary)
                .id(trendMetric)

                HStack(spacing: 16) {
                    Label(trendMetric.rawValue, systemImage: "line.diagonal")
                        .foregroundStyle(ZetaTheme.brand)
                    Spacer()
                    if let selectedTrend {
                        Text("\(selectedTrend.date.formatted(date: .abbreviated, time: .omitted)) · \(formattedTrendValue(selectedTrend))")
                            .monospacedDigit()
                    } else {
                        Text(trendSummary)
                            .monospacedDigit()
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(minHeight: 22)
            }
        }
    }

    private var supportingCharts: some View {
        ZetaResponsivePair {
            operationComparisonCard
                .frame(minWidth: 410)
        } second: {
            distributionCard
                .frame(minWidth: 410)
        }
    }

    private var operationComparisonCard: some View {
        ZetaChartCard(
            title: "Operation response times",
            subtitle: "Bar: median · dot: slow-tail P90"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Chart {
                    RuleMark(x: .value("Overall median", snapshot.medianMilliseconds / 1_000))
                        .foregroundStyle(.secondary.opacity(0.7))
                        .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
                    ForEach(snapshot.operations) { operation in
                        BarMark(
                            x: .value("Median seconds", operation.medianMilliseconds / 1_000),
                            y: .value("Operation", operation.operation.title)
                        )
                        .foregroundStyle(ZetaTheme.color(for: operation.operation).opacity(0.72))
                        .cornerRadius(3)
                        if operation.attempts >= Statistics.reliableTailSampleCount {
                            PointMark(
                                x: .value("P90 seconds", operation.p90Milliseconds / 1_000),
                                y: .value("Operation", operation.operation.title)
                            )
                            .foregroundStyle(ZetaTheme.color(for: operation.operation))
                            .symbol(.diamond)
                            .symbolSize(52)
                        }
                    }
                }
                .chartXScale(domain: operationDomain)
                .chartXAxisLabel("Response time (seconds)")
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .chartLegend(.hidden)
                .frame(height: 250)
                .accessibilityIdentifier("overviewOperationChart")
                .accessibilityLabel("Response time by operation")
                .accessibilityValue(operationAccessibilitySummary)

                HStack(spacing: 14) {
                    Label("Median", systemImage: "rectangle.fill")
                        .foregroundStyle(ZetaTheme.brand)
                    Label("P90", systemImage: "diamond.fill")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(operationSummary)
                        .monospacedDigit()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(minHeight: 22)
            }
        }
    }

    private var distributionCard: some View {
        ZetaChartCard(
            title: "Response-time mix",
            subtitle: "How often answers land in each half-second band"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Chart {
                    RuleMark(x: .value("Median", snapshot.distributionSummary.medianMilliseconds / 1_000))
                        .foregroundStyle(.secondary.opacity(0.75))
                        .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
                    ForEach(visibleDistributionBins) { bin in
                        BarMark(
                            xStart: .value("Response time start", Double(bin.lowerMilliseconds) / 1_000),
                            xEnd: .value("Response time end", distributionUpperBound(bin)),
                            y: .value("Questions", bin.count)
                        )
                        .foregroundStyle(distributionColor(bin))
                        .opacity(selectedDistributionBin == nil || selectedDistributionBin?.id == bin.id ? 1 : 0.28)
                    }
                    RuleMark(x: .value("Overflow threshold", 10))
                        .foregroundStyle(ZetaTheme.caution.opacity(0.55))
                        .lineStyle(StrokeStyle(dash: [3, 3]))
                        .annotation(position: .top, alignment: .leading) {
                            Text("10s+")
                                .font(.caption2)
                                .foregroundStyle(ZetaTheme.caution)
                        }
                }
                .chartXSelection(value: $selectedDistributionSeconds)
                .chartXScale(domain: distributionDomain)
                .chartXAxis {
                    AxisMarks(values: [0, 2, 4, 6, 8, 10]) { value in
                        AxisGridLine().foregroundStyle(.secondary.opacity(0.18))
                        AxisTick()
                        AxisValueLabel {
                            if let seconds = value.as(Int.self) {
                                Text("\(seconds)s")
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .chartXAxisLabel("Response time")
                .chartYAxisLabel("Questions")
                .chartLegend(.hidden)
                .frame(height: 250)
                .accessibilityIdentifier("overviewDistributionChart")
                .accessibilityLabel("Response-time distribution overview")
                .accessibilityValue("Median \(AnalyticsFormatting.time(snapshot.distributionSummary.medianMilliseconds)); P90 \(AnalyticsFormatting.time(snapshot.distributionSummary.p90Milliseconds))")

                HStack(spacing: 14) {
                    Label("Typical", systemImage: "rectangle.fill")
                        .foregroundStyle(ZetaTheme.brand)
                    Label("Slow tail", systemImage: "rectangle.fill")
                        .foregroundStyle(ZetaTheme.caution)
                    Spacer()
                    if let selectedDistributionBin {
                        Text("\(selectedDistributionBin.label) · \(selectedDistributionBin.count) questions")
                            .monospacedDigit()
                    } else {
                        Text("Median \(AnalyticsFormatting.time(snapshot.distributionSummary.medianMilliseconds)) · P90 \(AnalyticsFormatting.time(snapshot.distributionSummary.p90Milliseconds))")
                            .monospacedDigit()
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
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
                .accessibilityLabel("Previous trend point")
            Button { moveTrendSelection(1) } label: { Image(systemName: "chevron.right") }
                .help("Next point")
                .accessibilityLabel("Next trend point")
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
            title: "Session pace checkpoints",
            subtitle: "Questions completed after each quarter of the session"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        pacePicker
                        Spacer()
                        Text(paceSummary)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(paceSummaryColor)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        pacePicker
                        Text(paceSummary)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(paceSummaryColor)
                    }
                }

                if let selectedPace {
                    Chart {
                        ForEach(paceCheckpoints) { checkpoint in
                            BarMark(
                                x: .value("Elapsed session", checkpoint.label),
                                y: .value("Completed questions", checkpoint.selectedCount)
                            )
                            .foregroundStyle(ZetaTheme.brand)
                            .position(by: .value("Pace", "Selected session"))
                            .cornerRadius(4)
                            if let representativeCount = checkpoint.representativeCount {
                                BarMark(
                                    x: .value("Elapsed session", checkpoint.label),
                                    y: .value("Completed questions", representativeCount)
                                )
                                .foregroundStyle(Color.gray.opacity(0.52))
                                .position(by: .value("Pace", "Typical session"))
                                .cornerRadius(4)
                            }
                        }
                    }
                    .chartXAxisLabel("Elapsed session")
                    .chartYAxisLabel("Completed questions")
                    .chartYAxis {
                        AxisMarks(position: .leading) { value in
                            AxisGridLine().foregroundStyle(.secondary.opacity(0.18))
                            AxisTick()
                            AxisValueLabel()
                        }
                    }
                    .chartLegend(.hidden)
                    .frame(height: 290)
                    .accessibilityIdentifier("overviewPaceChart")
                    .accessibilityLabel("Session pace checkpoints for \(selectedPace.label)")
                    .accessibilityValue(paceAccessibilitySummary)

                    HStack(spacing: 16) {
                        Label("Selected session", systemImage: "rectangle.fill").foregroundStyle(ZetaTheme.brand)
                        if !snapshot.pace.representative.isEmpty {
                            Label("Typical session", systemImage: "rectangle.fill").foregroundStyle(Color.gray)
                        }
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

    private var pacePicker: some View {
        Picker("Session", selection: $selectedPaceID) {
            ForEach(snapshot.pace.sessions) { pace in
                Text("\(pace.label) · \(pace.mode.title)").tag(Optional(pace.id))
            }
        }
        .pickerStyle(.menu)
        .frame(maxWidth: 340, alignment: .leading)
    }

    private func comparison(_ metric: DashboardMetric) -> Double? {
        snapshot.priorPeriod[metric]?.improvementPercent
    }

    private var availableTrendMetrics: [OverviewTrendMetric] {
        snapshot.trends.contains(where: { $0.benchmarkScore != nil })
            ? OverviewTrendMetric.allCases
            : OverviewTrendMetric.allCases.filter { $0 != .benchmark }
    }

    private func trendValue(_ point: TrendPoint) -> Double? {
        switch trendMetric {
        case .median: point.medianMilliseconds / 1_000
        case .p90:
            point.sampleCount >= Statistics.reliableTailSampleCount
                ? point.p90Milliseconds / 1_000
                : nil
        case .throughput: point.questionsPerMinute
        case .speed: point.speedIndex
        case .benchmark: point.benchmarkScore
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
        return trendPlotPoints.min {
            abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate))
        }
    }

    private func moveTrendSelection(_ direction: Int) {
        let values = trendPlotPoints
        guard !values.isEmpty else { return }
        let current = selectedTrend.flatMap { selected in
            values.firstIndex(where: { $0.id == selected.id })
        } ?? (direction > 0 ? -1 : values.count)
        selectedDate = values[min(max(current + direction, 0), values.count - 1)].date
    }

    private func formattedTrendValue(_ point: TrendPoint) -> String {
        guard let value = trendValue(point) else { return "—" }
        return switch trendMetric {
        case .median, .p90: String(format: "%.2fs", value)
        case .throughput: String(format: "%.1f questions/minute", value)
        case .speed: String(format: "%.0f", value)
        case .benchmark: String(format: "%.0f completed", value)
        }
    }

    private var trendAccessibilitySummary: String {
        guard let latest = trendPlotPoints.last else { return "No points" }
        return "\(trendPlotPoints.count) points. Latest \(formattedTrendValue(latest))."
    }

    private var selectedPace: SessionPaceSeries? {
        snapshot.pace.sessions.first { $0.id == selectedPaceID } ?? snapshot.pace.sessions.first
    }

    private var recentSpeedValue: String {
        guard let value = snapshot.recentSpeedChange else { return "—" }
        return "\(Int(abs(value).rounded()))% \(value >= 0 ? "faster" : "slower")"
    }

    private var trendPlotPoints: [TrendPoint] {
        snapshot.trends.filter { trendValue($0) != nil }
    }

    private var trendDateDomain: ClosedRange<Date> {
        guard let first = snapshot.trends.first?.date, let last = snapshot.trends.last?.date else {
            let now = Date.now
            return now.addingTimeInterval(-3_600)...now.addingTimeInterval(3_600)
        }
        if first == last {
            let padding: TimeInterval = snapshot.trendResolution == .daily ? 43_200 : 1_800
            return first.addingTimeInterval(-padding)...first.addingTimeInterval(padding)
        }
        let span = max(last.timeIntervalSince(first), 3_600)
        let padding = span * 0.035
        return first.addingTimeInterval(-padding)...last.addingTimeInterval(padding)
    }

    private var trendValueDomain: ClosedRange<Double> {
        var values = trendPlotPoints.compactMap(trendValue)
        if trendMetric == .speed { values.append(100) }
        guard let minimum = values.min(), let maximum = values.max() else { return 0...1 }
        let span = maximum - minimum
        let minimumPadding: Double
        switch trendMetric {
        case .median, .p90: minimumPadding = 0.08
        case .throughput: minimumPadding = 0.5
        case .speed: minimumPadding = 4
        case .benchmark: minimumPadding = 1
        }
        let padding = max(span * 0.14, minimumPadding)
        return max(0, minimum - padding)...max(maximum + padding, minimum + padding * 2)
    }

    private var trendSummary: String {
        guard let first = trendPlotPoints.first, let latest = trendPlotPoints.last else { return "No trend points" }
        if first.id == latest.id {
            return "Latest \(formattedTrendValue(latest)) · n=\(latest.sampleCount)"
        }
        return "\(formattedTrendValue(first)) → \(formattedTrendValue(latest)) · n=\(latest.sampleCount) latest"
    }

    private var operationDomain: ClosedRange<Double> {
        let tailValues = snapshot.operations
            .filter { $0.attempts >= Statistics.reliableTailSampleCount }
            .map { $0.p90Milliseconds / 1_000 }
        let maximum = (tailValues + snapshot.operations.map { $0.medianMilliseconds / 1_000 }).max() ?? 1
        return 0...max(maximum * 1.12, 1)
    }

    private var operationSummary: String {
        guard let fastest = snapshot.operations.min(by: { $0.medianMilliseconds < $1.medianMilliseconds }) else {
            return "No operation data"
        }
        return "Fastest: \(fastest.operation.title) · \(AnalyticsFormatting.time(fastest.medianMilliseconds))"
    }

    private var operationAccessibilitySummary: String {
        snapshot.operations.map {
            let p90 = $0.attempts >= Statistics.reliableTailSampleCount
                ? AnalyticsFormatting.time($0.p90Milliseconds)
                : "needs \(Statistics.reliableTailSampleCount) samples"
            return "\($0.operation.title), median \(AnalyticsFormatting.time($0.medianMilliseconds)), P90 \(p90)"
        }.joined(separator: ". ")
    }

    private func distributionUpperBound(_ bin: DistributionBin) -> Double {
        bin.isOverflow ? 11 : Double(bin.upperMilliseconds) / 1_000
    }

    private func distributionColor(_ bin: DistributionBin) -> Color {
        Double(bin.upperMilliseconds) >= snapshot.distributionSummary.p90Milliseconds
            ? ZetaTheme.caution
            : ZetaTheme.brand
    }

    private var distributionDomain: ClosedRange<Double> {
        let lastNonempty = snapshot.distribution.last(where: { $0.count > 0 })
        let upper = lastNonempty.map(distributionUpperBound) ?? 3
        return 0...max(min(upper, 11), 3)
    }

    private var visibleDistributionBins: [DistributionBin] {
        snapshot.distribution.filter {
            $0.count > 0 && Double($0.lowerMilliseconds) / 1_000 < distributionDomain.upperBound
        }
    }

    private var selectedDistributionBin: DistributionBin? {
        guard let selectedDistributionSeconds else { return nil }
        let milliseconds = selectedDistributionSeconds * 1_000
        return snapshot.distribution.first {
            milliseconds >= Double($0.lowerMilliseconds)
                && milliseconds < ($0.isOverflow ? .infinity : Double($0.upperMilliseconds))
        }
    }

    private var paceCheckpoints: [PaceCheckpoint] {
        [0.25, 0.5, 0.75, 1].map { fraction in
            PaceCheckpoint(
                fraction: fraction,
                selectedCount: cumulativeCount(in: selectedPace?.points ?? [], at: fraction),
                representativeCount: snapshot.pace.representative.isEmpty
                    ? nil
                    : cumulativeCount(in: snapshot.pace.representative, at: fraction)
            )
        }
    }

    private func cumulativeCount(in points: [CumulativePacePoint], at fraction: Double) -> Double {
        points.last(where: { $0.elapsedFraction <= fraction + 0.000_1 })?.completedCount ?? 0
    }

    private var paceSummary: String {
        guard let last = paceCheckpoints.last else { return "No pace data" }
        guard let representative = last.representativeCount else {
            return "Complete 3 sessions to unlock a typical comparison."
        }
        let difference = Int((last.selectedCount - representative).rounded())
        if difference == 0 { return "This session matched your typical finish." }
        return "This session finished \(abs(difference)) question\(abs(difference) == 1 ? "" : "s") \(difference > 0 ? "ahead of" : "behind") typical."
    }

    private var paceSummaryColor: Color {
        guard let last = paceCheckpoints.last, let representative = last.representativeCount else { return .secondary }
        return last.selectedCount >= representative ? ZetaTheme.positive : ZetaTheme.caution
    }

    private var paceAccessibilitySummary: String {
        paceCheckpoints.map { checkpoint in
            if let representative = checkpoint.representativeCount {
                return "\(checkpoint.label): \(Int(checkpoint.selectedCount)) selected, \(Int(representative)) typical"
            }
            return "\(checkpoint.label): \(Int(checkpoint.selectedCount)) selected"
        }.joined(separator: ". ")
    }
}

private struct PaceCheckpoint: Identifiable {
    let fraction: Double
    let selectedCount: Double
    let representativeCount: Double?

    var id: Double { fraction }
    var label: String { "\(Int(fraction * 100))%" }
}
