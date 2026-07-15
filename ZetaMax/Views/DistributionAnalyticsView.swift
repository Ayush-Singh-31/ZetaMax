import Charts
import SwiftUI

struct DistributionAnalyticsView: View {
    let snapshot: DashboardSnapshot
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.zetaReduceMotionOverride) private var reduceMotionOverride
    @State private var selectedBinLabel: String?
    @State private var selectedPaceLabel: String?
    @State private var selectedSlowID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: ZetaTheme.sectionSpacing) {
            histogramCard
            paceThroughSessionCard
            slowestCard
        }
    }

    private var histogramCard: some View {
        ZetaChartCard(title: "Response-time histogram") {
            VStack(alignment: .leading, spacing: 12) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110, maximum: 190))], spacing: 8) {
                    summaryTile("Minimum", snapshot.distributionSummary.minimumMilliseconds)
                    summaryTile("Q1", snapshot.distributionSummary.q1Milliseconds)
                    summaryTile("Median", snapshot.distributionSummary.medianMilliseconds)
                    summaryTile("Q3", snapshot.distributionSummary.q3Milliseconds)
                    summaryTile("P90", snapshot.distributionSummary.p90Milliseconds)
                    summaryTile("Maximum", snapshot.distributionSummary.maximumMilliseconds)
                }

                Chart {
                    ForEach(snapshot.distribution) { bin in
                        BarMark(
                            x: .value("Response time", bin.label),
                            y: .value("Completed questions", bin.count)
                        )
                        .foregroundStyle(
                            selectedBinLabel == nil || selectedBinLabel == bin.label
                                ? ZetaTheme.brand
                                : ZetaTheme.brand.opacity(0.28)
                        )
                    }
                }
                .chartXSelection(value: $selectedBinLabel)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 8)) { value in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel {
                            if let label = value.as(String.self) {
                                Text(label).rotationEffect(.degrees(-35)).fixedSize()
                            }
                        }
                    }
                }
                .chartXAxisLabel("Response time (seconds)")
                .chartYAxisLabel("Completed questions")
                .chartLegend(.hidden)
                .frame(height: 330)
                .animation(reduceMotion || reduceMotionOverride ? nil : .easeOut(duration: 0.16), value: selectedBinLabel)
                .accessibilityLabel("Response-time histogram")
                .accessibilityValue("\(snapshot.distributionSummary.count) questions, median \(AnalyticsFormatting.time(snapshot.distributionSummary.medianMilliseconds)), P90 \(AnalyticsFormatting.time(snapshot.distributionSummary.p90Milliseconds))")

                HStack {
                    Label("Completed questions", systemImage: "chart.bar.fill").foregroundStyle(ZetaTheme.brand)
                    Spacer()
                    if let selectedBin {
                        Text("\(selectedBin.label) · \(selectedBin.count) completed")
                            .monospacedDigit()
                    } else {
                        Text("Select a bar")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(minHeight: 22)
            }
        }
    }

    private var paceThroughSessionCard: some View {
        ZetaChartCard(title: "Pace through a session") {
            VStack(alignment: .leading, spacing: 12) {
                Text(paceSummary)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(paceSummaryColor)

                Chart {
                    RuleMark(y: .value("Personal baseline", 1))
                        .foregroundStyle(.secondary.opacity(0.65))
                        .lineStyle(StrokeStyle(dash: [5, 4]))
                    ForEach(snapshot.sessionPace) { point in
                        BarMark(
                            x: .value("Session progress", point.label),
                            y: .value("Response time vs typical", point.normalizedEffort)
                        )
                        .foregroundStyle(point.normalizedEffort <= 1 ? ZetaTheme.positive : ZetaTheme.caution)
                        .opacity(selectedPaceLabel == nil || selectedPaceLabel == point.label ? 1 : 0.32)
                    }
                }
                .chartXSelection(value: $selectedPaceLabel)
                .chartXAxisLabel("Session progress")
                .chartYAxisLabel("Response time vs typical")
                .chartYScale(domain: paceDomain)
                .chartLegend(.hidden)
                .frame(height: 320)
                .animation(reduceMotion || reduceMotionOverride ? nil : .easeOut(duration: 0.16), value: selectedPaceLabel)
                .accessibilityLabel("Pace through a session")
                .accessibilityValue(paceSummary)

                HStack(spacing: 16) {
                    Label("At or faster than typical", systemImage: "square.fill").foregroundStyle(ZetaTheme.positive)
                    Label("Slower than typical", systemImage: "square.fill").foregroundStyle(ZetaTheme.caution)
                    Spacer()
                    if let selectedPace {
                        Text("\(selectedPace.label) · \(String(format: "%.2f×", selectedPace.normalizedEffort)) · n=\(selectedPace.sampleCount)")
                            .monospacedDigit()
                    } else {
                        Text("Select a bar")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(minHeight: 22)
            }
        }
    }

    private var slowestCard: some View {
        ZetaChartCard(title: "Slowest completions") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Question").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Vs baseline").frame(width: 92, alignment: .trailing)
                    Text("Time").frame(width: 72, alignment: .trailing)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

                ForEach(snapshot.slowestCompletions) { completion in
                    Button { selectedSlowID = completion.id } label: {
                        HStack(spacing: 12) {
                            Text("#\(completion.position + 1)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 34, alignment: .trailing)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(completion.prompt).font(.body.weight(.semibold).monospacedDigit())
                                Text(sessionDetail(completion))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 8)
                            Text(String(format: "%.1f×", completion.baselineMultiple))
                                .foregroundStyle(completion.baselineMultiple >= 1.5 ? ZetaTheme.caution : .secondary)
                                .monospacedDigit()
                                .frame(width: 92, alignment: .trailing)
                            Text(AnalyticsFormatting.time(Double(completion.responseMilliseconds)))
                                .bold()
                                .monospacedDigit()
                                .frame(width: 72, alignment: .trailing)
                        }
                        .padding(9)
                        .background(selectedSlowID == completion.id ? ZetaTheme.selectionGradient : LinearGradient(colors: [.clear], startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 9))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                HStack {
                    if let selectedSlow {
                        Text("\(selectedSlow.categoryName) · question \(selectedSlow.position + 1) · \(String(format: "%.1f×", selectedSlow.baselineMultiple)) baseline · \(AnalyticsFormatting.time(Double(selectedSlow.responseMilliseconds)))")
                            .monospacedDigit()
                            .lineLimit(1)
                    } else {
                        Text("Select a completion")
                    }
                    Spacer()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(minHeight: 24)
            }
        }
    }

    private func summaryTile(_ title: String, _ value: Double) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            Text(AnalyticsFormatting.time(value)).font(.headline.monospacedDigit())
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 9))
    }

    private var selectedBin: DistributionBin? {
        snapshot.distribution.first { $0.label == selectedBinLabel }
    }

    private var selectedPace: SessionPacePoint? {
        snapshot.sessionPace.first { $0.label == selectedPaceLabel }
    }

    private var selectedSlow: SlowCompletion? {
        snapshot.slowestCompletions.first { $0.id == selectedSlowID }
    }

    private var paceDomain: ClosedRange<Double> {
        let values = snapshot.sessionPace.filter { $0.normalizedEffort > 0 }.map(\.normalizedEffort) + [1]
        let lower = max((values.min() ?? 0.8) - 0.12, 0)
        let upper = (values.max() ?? 1.2) + 0.12
        return lower...max(upper, lower + 0.25)
    }

    private var paceSummary: String {
        guard let change = snapshot.sessionPaceChangePercent else {
            return "More sessions are needed to compare the first and final fifths."
        }
        return change >= 0
            ? "The final fifth is \(Int(abs(change).rounded()))% slower than the first."
            : "The final fifth is \(Int(abs(change).rounded()))% faster than the first."
    }

    private var paceSummaryColor: Color {
        (snapshot.sessionPaceChangePercent ?? 0) > 0 ? ZetaTheme.caution : ZetaTheme.positive
    }

    private func sessionDetail(_ completion: SlowCompletion) -> String {
        let date = completion.sessionStartedAt?.formatted(date: .abbreviated, time: .shortened) ?? "Session"
        let mode = completion.sessionMode?.title ?? "Practice"
        return "\(completion.categoryName) · \(mode) · \(date)"
    }
}
