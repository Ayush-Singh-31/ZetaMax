import Charts
import SwiftUI

struct DistributionAnalyticsView: View {
    let snapshot: DashboardSnapshot
    @State private var selectedBinLabel: String?
    @State private var selectedFatigueLabel: String?
    @State private var selectedSlowID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: ZetaTheme.sectionSpacing) {
            histogramCard
            operationRangesCard
            fatigueCard
            slowestCard
        }
    }

    private var histogramCard: some View {
        ZetaChartCard(title: "Response-time distribution", subtitle: "Half-second bins through 10 seconds, plus an overflow bin. Select a bar to inspect its count.") {
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
                        BarMark(x: .value("Time bin", bin.label), y: .value("Questions", bin.count))
                            .foregroundStyle(selectedBinLabel == nil || selectedBinLabel == bin.label ? ZetaTheme.brand : ZetaTheme.brand.opacity(0.28))
                    }
                }
                .chartXSelection(value: $selectedBinLabel)
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 8)) { value in AxisGridLine(); AxisTick(); AxisValueLabel { if let label = value.as(String.self) { Text(label).rotationEffect(.degrees(-35)).fixedSize() } } } }
                .chartYAxisLabel("Completed questions")
                .frame(height: 285)
                .accessibilityLabel("Response time histogram")
                .accessibilityValue("\(snapshot.distributionSummary.count) questions, median \(AnalyticsFormatting.time(snapshot.distributionSummary.medianMilliseconds)), P90 \(AnalyticsFormatting.time(snapshot.distributionSummary.p90Milliseconds))")

                if let selectedBin {
                    Label("\(selectedBin.label): \(selectedBin.count) completed questions", systemImage: "selection.pin.in.out")
                        .font(.callout).foregroundStyle(.secondary).monospacedDigit()
                } else {
                    Text("Select a bin to inspect it.").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var operationRangesCard: some View {
        ZetaChartCard(title: "Timing range by operation", subtitle: "The thin span is Q10–P90, the thick span is Q1–Q3, and the dot is the median.") {
            Chart(snapshot.operationDistributions) { item in
                BarMark(
                    xStart: .value("Q10", item.q10Milliseconds / 1_000),
                    xEnd: .value("P90", item.p90Milliseconds / 1_000),
                    y: .value("Operation", item.operation.title),
                    height: .fixed(3)
                ).foregroundStyle(ZetaTheme.color(for: item.operation).opacity(0.5))
                BarMark(
                    xStart: .value("Q1", item.q1Milliseconds / 1_000),
                    xEnd: .value("Q3", item.q3Milliseconds / 1_000),
                    y: .value("Operation", item.operation.title),
                    height: .fixed(11)
                ).foregroundStyle(ZetaTheme.color(for: item.operation).opacity(0.75))
                PointMark(x: .value("Median", item.medianMilliseconds / 1_000), y: .value("Operation", item.operation.title))
                    .foregroundStyle(.primary).symbol(.circle).symbolSize(45)
                    .annotation(position: .trailing) { Text("n=\(item.count)").font(.caption2).foregroundStyle(.secondary) }
            }
            .chartXAxisLabel("Seconds")
            .chartLegend(.hidden)
            .frame(height: max(190, CGFloat(snapshot.operationDistributions.count) * 50))
            .accessibilityLabel("Timing ranges by operation")
        }
    }

    private var fatigueCard: some View {
        ZetaChartCard(title: "Session fatigue", subtitle: "Category-adjusted effort is compared across five equal elapsed-time buckets; 1.0 is your category baseline.") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label(fatigueChangeCopy, systemImage: fatigueIcon)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(fatigueColor)
                    Spacer()
                    if let selectedFatigue { Text("\(selectedFatigue.label) · \(String(format: "%.2f×", selectedFatigue.normalizedEffort)) · n=\(selectedFatigue.sampleCount)").font(.caption).foregroundStyle(.secondary).monospacedDigit() }
                }
                Chart {
                    RuleMark(y: .value("Category baseline", 1))
                        .foregroundStyle(.secondary.opacity(0.5)).lineStyle(StrokeStyle(dash: [5, 4]))
                    ForEach(snapshot.fatigue) { point in
                        LineMark(x: .value("Session", point.label), y: .value("Normalized effort", point.normalizedEffort))
                            .foregroundStyle(ZetaTheme.caution).interpolationMethod(.catmullRom).lineStyle(StrokeStyle(lineWidth: 2.5))
                        PointMark(x: .value("Session", point.label), y: .value("Normalized effort", point.normalizedEffort))
                            .foregroundStyle(ZetaTheme.caution).symbolSize(selectedFatigueLabel == point.label ? 90 : 38)
                    }
                }
                .chartXSelection(value: $selectedFatigueLabel)
                .chartYScale(domain: fatigueDomain)
                .chartYAxisLabel("Normalized effort")
                .chartXAxisLabel("Elapsed session fifth")
                .frame(height: 245)
                .accessibilityLabel("Session fatigue")
                .accessibilityValue(fatigueChangeCopy)
            }
        }
    }

    private var slowestCard: some View {
        ZetaChartCard(title: "Slowest completions", subtitle: "Individual time-to-correct records ranked against each question’s category baseline.") {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(snapshot.slowestCompletions) { completion in
                    Button { selectedSlowID = completion.id } label: {
                        HStack(spacing: 12) {
                            Text("#\(completion.position + 1)").font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 32, alignment: .trailing)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(completion.prompt).font(.body.weight(.semibold).monospacedDigit())
                                Text(completion.categoryName).font(.caption).foregroundStyle(.secondary).lineLimit(1).help(completion.categoryName)
                            }
                            Spacer(minLength: 8)
                            Text(String(format: "%.1f×", completion.baselineMultiple)).foregroundStyle(completion.baselineMultiple >= 1.5 ? ZetaTheme.caution : .secondary).monospacedDigit()
                            Text(AnalyticsFormatting.time(Double(completion.responseMilliseconds))).bold().monospacedDigit().frame(width: 62, alignment: .trailing)
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }
                        .padding(9)
                        .background(selectedSlowID == completion.id ? ZetaTheme.brand.opacity(0.10) : Color.clear, in: RoundedRectangle(cornerRadius: 9))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Divider()
                }
                if let selectedSlow {
                    ZetaCard {
                        ViewThatFits(in: .horizontal) {
                            HStack { slowInspector(selectedSlow) }
                            VStack(alignment: .leading, spacing: 7) { slowInspector(selectedSlow) }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private func slowInspector(_ completion: SlowCompletion) -> some View {
        Label(completion.sessionStartedAt?.formatted(date: .abbreviated, time: .shortened) ?? "Session", systemImage: "calendar")
        Spacer(minLength: 8)
        if let mode = completion.sessionMode { ZetaStatusChip(title: mode.title, color: ZetaTheme.brand) }
        ZetaStatusChip(title: "\(String(format: "%.1f×", completion.baselineMultiple)) baseline", color: ZetaTheme.caution, systemImage: "gauge.high")
        ZetaStatusChip(title: AnalyticsFormatting.time(Double(completion.responseMilliseconds)), color: ZetaTheme.brand, systemImage: "timer")
    }

    private func summaryTile(_ title: String, _ value: Double) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            Text(AnalyticsFormatting.time(value)).font(.headline.monospacedDigit())
        }.padding(9).frame(maxWidth: .infinity, alignment: .leading).background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 9))
    }
    private var selectedBin: DistributionBin? { snapshot.distribution.first { $0.label == selectedBinLabel } }
    private var selectedFatigue: FatiguePoint? { snapshot.fatigue.first { $0.label == selectedFatigueLabel } }
    private var selectedSlow: SlowCompletion? { snapshot.slowestCompletions.first { $0.id == selectedSlowID } }
    private var fatigueDomain: ClosedRange<Double> {
        let values = snapshot.fatigue.filter { $0.normalizedEffort > 0 }.map(\.normalizedEffort) + [1]
        let lower = max((values.min() ?? 0.8) - 0.12, 0)
        let upper = (values.max() ?? 1.2) + 0.12
        return lower...max(upper, lower + 0.25)
    }
    private var fatigueChangeCopy: String {
        guard let change = snapshot.fatigueChangePercent else { return "More sessions are needed for a fatigue comparison" }
        return change >= 0 ? "Last fifth requires \(Int(change.rounded()))% more effort than the first" : "Last fifth requires \(Int(abs(change).rounded()))% less effort than the first"
    }
    private var fatigueIcon: String { (snapshot.fatigueChangePercent ?? 0) >= 8 ? "battery.25" : "battery.75" }
    private var fatigueColor: Color { (snapshot.fatigueChangePercent ?? 0) >= 8 ? ZetaTheme.caution : ZetaTheme.positive }
}
