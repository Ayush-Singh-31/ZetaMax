import Charts
import SwiftUI

private enum CategoryRankMetric: String, CaseIterable, Identifiable {
    case median = "Median", p90 = "P90", difficulty = "Difficulty", change = "Recent change"
    var id: String { rawValue }
}

private enum CategorySort: String, CaseIterable, Identifiable {
    case slowest = "Slowest first", mostSamples = "Most samples", recentSlowdown = "Recent slowdown"
    var id: String { rawValue }
}

private enum SkillHeatmapMetric: String, CaseIterable, Identifiable {
    case median = "Median", p90 = "P90", count = "Samples"
    var id: String { rawValue }
}

struct SkillsAnalyticsView: View {
    let snapshot: DashboardSnapshot
    @State private var selectedOperation: ArithmeticOperation?
    @State private var categoryMetric: CategoryRankMetric = .median
    @State private var categorySort: CategorySort = .slowest
    @State private var minimumSamples = 1.0
    @State private var selectedCategoryID: String?
    @State private var selectedDifficulty: Double?
    @State private var heatmapMetric: SkillHeatmapMetric = .median

    var body: some View {
        VStack(alignment: .leading, spacing: ZetaTheme.sectionSpacing) {
            operationCard
            categoryCard
            effortMapCard
            heatmapCard
        }
    }

    private var operationCard: some View {
        ZetaChartCard(title: "Operation timing", subtitle: "Each line spans median to P90. Pick an operation to cross-filter the category panels.") {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Selected operation", selection: $selectedOperation) {
                    Text("All operations").tag(ArithmeticOperation?.none)
                    ForEach(ArithmeticOperation.allCases) { operation in
                        Label(operation.title, systemImage: ZetaTheme.systemImage(for: operation)).tag(Optional(operation))
                    }
                }
                .pickerStyle(.segmented)

                Chart(snapshot.operations) { metric in
                    BarMark(
                        xStart: .value("Median", metric.medianMilliseconds / 1_000),
                        xEnd: .value("P90", metric.p90Milliseconds / 1_000),
                        y: .value("Operation", metric.operation.title),
                        height: .fixed(7)
                    )
                    .foregroundStyle(ZetaTheme.color(for: metric.operation).opacity(selectedOperation == nil || selectedOperation == metric.operation ? 0.78 : 0.22))
                    PointMark(x: .value("Median", metric.medianMilliseconds / 1_000), y: .value("Operation", metric.operation.title))
                        .foregroundStyle(ZetaTheme.color(for: metric.operation)).symbol(.circle)
                    PointMark(x: .value("P90", metric.p90Milliseconds / 1_000), y: .value("Operation", metric.operation.title))
                        .foregroundStyle(ZetaTheme.color(for: metric.operation)).symbol(.diamond)
                        .annotation(position: .trailing) { Text("n=\(metric.attempts)").font(.caption2).foregroundStyle(.secondary) }
                }
                .chartXAxisLabel("Seconds · ● median  ◆ P90")
                .chartLegend(.hidden)
                .frame(height: max(180, CGFloat(snapshot.operations.count) * 46))
                .accessibilityLabel("Operation timing ranges")
                .accessibilityValue(snapshot.operations.map { "\($0.operation.title), median \(AnalyticsFormatting.time($0.medianMilliseconds)), P90 \(AnalyticsFormatting.time($0.p90Milliseconds)), \($0.attempts) samples" }.joined(separator: ". "))
            }
        }
    }

    private var categoryCard: some View {
        ZetaChartCard(title: "Ranked categories", subtitle: "Low-sample categories are shown for exploration but are not diagnosed as weaknesses.") {
            VStack(alignment: .leading, spacing: 13) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { categoryControls }
                    VStack(alignment: .leading, spacing: 9) { categoryControls }
                }
                if rankedCategories.isEmpty {
                    Text("No categories match the current minimum sample count.").foregroundStyle(.secondary).padding(.vertical, 28)
                } else {
                    VStack(spacing: 7) {
                        ForEach(Array(rankedCategories.prefix(14).enumerated()), id: \.element.id) { index, metric in
                            Button { selectedCategoryID = metric.id } label: {
                                CategoryRankRow(rank: index + 1, metric: metric, value: categoryValue(metric), valueLabel: categoryValueLabel(metric), maximum: categoryMaximum, isSelected: selectedCategoryID == metric.id)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private var categoryControls: some View {
        Picker("Metric", selection: $categoryMetric) { ForEach(CategoryRankMetric.allCases) { Text($0.rawValue).tag($0) } }.frame(maxWidth: 190)
        Picker("Sort", selection: $categorySort) { ForEach(CategorySort.allCases) { Text($0.rawValue).tag($0) } }.frame(maxWidth: 190)
        HStack {
            Text("Min n").font(.caption).foregroundStyle(.secondary)
            Slider(value: $minimumSamples, in: 1...30, step: 1).frame(width: 100)
            Text("\(Int(minimumSamples))").font(.caption.monospacedDigit()).frame(width: 22)
        }
    }

    private var effortMapCard: some View {
        ZetaChartCard(title: "Difficulty and momentum", subtitle: "Right is slower than your typical question; above zero is recent improvement. Bubble size reflects sample count.") {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Category to inspect", selection: $selectedCategoryID) {
                    Text("Choose a category").tag(String?.none)
                    ForEach(effortCategories) { Text($0.name).tag(Optional($0.id)) }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 340, alignment: .leading)

                Chart {
                    RuleMark(x: .value("Typical difficulty", 100)).foregroundStyle(.secondary.opacity(0.45)).lineStyle(StrokeStyle(dash: [5, 4]))
                    RuleMark(y: .value("No change", 0)).foregroundStyle(.secondary.opacity(0.45)).lineStyle(StrokeStyle(dash: [5, 4]))
                    ForEach(effortCategories) { metric in
                        PointMark(x: .value("Difficulty index", metric.difficultyIndex), y: .value("Recent change", metric.recentSpeedChange ?? 0))
                            .foregroundStyle(ZetaTheme.color(for: metric.operation))
                            .symbolSize(selectedCategoryID == metric.id ? 180 : min(max(Double(metric.attempts) * 5, 45), 135))
                            .annotation(position: .top, overflowResolution: .init(x: .fit, y: .fit)) {
                                if selectedCategoryID == metric.id { categoryTooltip(metric) }
                            }
                    }
                }
                .chartXSelection(value: $selectedDifficulty)
                .onChange(of: selectedDifficulty) { _, value in
                    guard let value else { return }
                    selectedCategoryID = effortCategories.min(by: { abs($0.difficultyIndex - value) < abs($1.difficultyIndex - value) })?.id
                }
                .chartXAxisLabel("Difficulty index · 100 is typical")
                .chartYAxisLabel("Recent pace change %")
                .chartLegend(.hidden)
                .chartBackground { _ in
                    GeometryReader { proxy in
                        ZStack {
                            Text("Improving · easier").position(x: 66, y: 12)
                            Text("Improving · harder").position(x: max(proxy.size.width - 68, 68), y: 12)
                            Text("Slowing · easier").position(x: 62, y: max(proxy.size.height - 12, 12))
                            Text("Slowing · harder").position(x: max(proxy.size.width - 66, 66), y: max(proxy.size.height - 12, 12))
                        }.font(.caption2).foregroundStyle(.tertiary)
                    }
                }
                .frame(height: 310)
                .accessibilityLabel("Category difficulty and momentum map")
                .accessibilityValue("\(effortCategories.count) statistically supported categories")
            }
        }
    }

    private var heatmapCard: some View {
        ZetaChartCard(title: snapshot.heatmapPresentation == .grid ? "Multiplication heatmap" : "Multiplication pairs", subtitle: snapshot.heatmapPresentation == .grid ? "Color and labels show the selected timing metric." : "Sparse data is ranked as observed pairs instead of implying a complete grid.") {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Heatmap metric", selection: $heatmapMetric) { ForEach(SkillHeatmapMetric.allCases) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.segmented).frame(maxWidth: 360)
                switch snapshot.heatmapPresentation {
                case .grid:
                    Chart(snapshot.heatmap) { cell in
                        RectangleMark(xStart: .value("Left start", Double(cell.left) - 0.45), xEnd: .value("Left end", Double(cell.left) + 0.45), yStart: .value("Right start", Double(cell.right) - 0.45), yEnd: .value("Right end", Double(cell.right) + 0.45))
                            .foregroundStyle(ZetaTheme.color(for: .multiplication).opacity(heatmapOpacity(cell)))
                            .annotation(position: .overlay) { Text(heatmapLabel(cell)).font(.caption2).monospacedDigit() }
                    }
                    .chartXAxisLabel("Left operand").chartYAxisLabel("Right operand").frame(height: 340)
                    .accessibilityLabel("Multiplication heatmap, \(heatmapMetric.rawValue)")
                case .rankedPairs:
                    VStack(spacing: 7) {
                        ForEach(snapshot.heatmap.sorted { heatmapValue($0) > heatmapValue($1) }.prefix(14)) { cell in
                            HStack {
                                Label("\(cell.left) × \(cell.right)", systemImage: "multiply").font(.body.monospacedDigit())
                                Spacer(); Text(heatmapLabel(cell)).bold().monospacedDigit()
                                Text("n=\(cell.count)").font(.caption).foregroundStyle(.secondary).frame(width: 46, alignment: .trailing)
                            }.padding(.vertical, 5)
                            Divider()
                        }
                    }
                case .insufficient:
                    ContentUnavailableView("Not enough multiplication data", systemImage: "square.grid.3x3", description: Text("Complete multiplication questions to build this view.")).frame(height: 190)
                }
            }
        }
    }

    private var filteredCategories: [CategoryMetric] { snapshot.categories.filter { ($0.operation == selectedOperation || selectedOperation == nil) && $0.attempts >= Int(minimumSamples) } }
    private var rankedCategories: [CategoryMetric] {
        filteredCategories.sorted {
            switch categorySort {
            case .slowest: categoryValue($0) > categoryValue($1)
            case .mostSamples: $0.attempts > $1.attempts
            case .recentSlowdown: ($0.recentSpeedChange ?? 0) < ($1.recentSpeedChange ?? 0)
            }
        }
    }
    private var categoryMaximum: Double { max(rankedCategories.map(categoryValue).max() ?? 1, 1) }
    private func categoryValue(_ metric: CategoryMetric) -> Double {
        switch categoryMetric { case .median: metric.medianMilliseconds; case .p90: metric.p90Milliseconds; case .difficulty: metric.difficultyIndex; case .change: abs(metric.recentSpeedChange ?? 0) }
    }
    private func categoryValueLabel(_ metric: CategoryMetric) -> String {
        switch categoryMetric { case .median: AnalyticsFormatting.time(metric.medianMilliseconds); case .p90: AnalyticsFormatting.time(metric.p90Milliseconds); case .difficulty: "D\(Int(metric.difficultyIndex.rounded()))"; case .change: AnalyticsFormatting.signedPercent(metric.recentSpeedChange) }
    }
    private var effortCategories: [CategoryMetric] { snapshot.categories.filter { $0.attempts >= 10 && $0.recentSpeedChange != nil && (selectedOperation == nil || $0.operation == selectedOperation) } }
    private func categoryTooltip(_ metric: CategoryMetric) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(metric.name).font(.caption.bold()).lineLimit(2)
            Text("D\(Int(metric.difficultyIndex.rounded())) · \(AnalyticsFormatting.signedPercent(metric.recentSpeedChange)) · n=\(metric.attempts)").font(.caption2).monospacedDigit()
        }.padding(7).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 7))
    }
    private func heatmapValue(_ cell: HeatmapCell) -> Double { switch heatmapMetric { case .median: cell.medianMilliseconds; case .p90: cell.p90Milliseconds; case .count: Double(cell.count) } }
    private func heatmapLabel(_ cell: HeatmapCell) -> String { switch heatmapMetric { case .median: AnalyticsFormatting.time(cell.medianMilliseconds); case .p90: AnalyticsFormatting.time(cell.p90Milliseconds); case .count: String(cell.count) } }
    private func heatmapOpacity(_ cell: HeatmapCell) -> Double { min(max(heatmapValue(cell) / max(snapshot.heatmap.map(heatmapValue).max() ?? 1, 1), 0.14), 0.9) }
}

private struct CategoryRankRow: View {
    let rank: Int; let metric: CategoryMetric; let value: Double; let valueLabel: String; let maximum: Double; let isSelected: Bool
    var body: some View {
        HStack(spacing: 10) {
            Text("\(rank)").font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 22, alignment: .trailing)
            Image(systemName: ZetaTheme.systemImage(for: metric.operation)).foregroundStyle(ZetaTheme.color(for: metric.operation)).frame(width: 18)
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(metric.name).lineLimit(1).help(metric.name)
                    if metric.isLowSample { Image(systemName: "exclamationmark.circle").foregroundStyle(ZetaTheme.caution).help("Low sample: n=\(metric.attempts)") }
                    Spacer(); Text(valueLabel).bold().monospacedDigit(); Text("n=\(metric.attempts)").font(.caption2).foregroundStyle(.secondary).frame(width: 45, alignment: .trailing)
                }
                GeometryReader { geometry in
                    Capsule().fill(.quaternary).overlay(alignment: .leading) { Capsule().fill(ZetaTheme.color(for: metric.operation)).frame(width: geometry.size.width * min(max(value / maximum, 0.02), 1)) }
                }.frame(height: 5)
            }
        }
        .padding(9).background(isSelected ? ZetaTheme.brand.opacity(0.10) : Color.clear, in: RoundedRectangle(cornerRadius: 9)).contentShape(Rectangle()).accessibilityElement(children: .combine)
    }
}
