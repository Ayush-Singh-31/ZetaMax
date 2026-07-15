import Charts
import SwiftUI

private enum OperandMetric: String, CaseIterable, Identifiable {
    case median = "Median"
    case p90 = "P90"
    case count = "Sample count"
    var id: String { rawValue }
}

struct SkillsAnalyticsView: View {
    let snapshot: DashboardSnapshot
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.zetaReduceMotionOverride) private var reduceMotionOverride
    @State private var selectedChangeValue: Double?
    @State private var selectedOperandOperation: ArithmeticOperation?
    @State private var selectedOperandPrimary: String?
    @State private var selectedOperandCellID: String?
    @State private var operandMetric: OperandMetric = .median

    var body: some View {
        VStack(alignment: .leading, spacing: ZetaTheme.sectionSpacing) {
            hierarchyCard
            recentChangeCard
            operandExplorerCard
        }
        .onAppear {
            if selectedOperandOperation == nil {
                selectedOperandOperation = snapshot.operandExplorers.first?.operation
            }
        }
    }

    private var hierarchyCard: some View {
        ZetaChartCard(title: "Skills by operation and category") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 16) {
                    Label("Median", systemImage: "rectangle.fill").foregroundStyle(ZetaTheme.brand)
                    Label("P90", systemImage: "diamond.fill").foregroundStyle(.secondary)
                    Label("Personal baseline", systemImage: "line.diagonal").foregroundStyle(ZetaTheme.caution)
                    Spacer()
                    Text("Sample count").frame(width: 78, alignment: .trailing)
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Text("Response time (seconds)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)

                ScrollView(.vertical) {
                    LazyVStack(spacing: 7) {
                        ForEach(snapshot.operations) { operation in
                            SkillTimingRow(
                                name: operation.operation.title,
                                operation: operation.operation,
                                medianMilliseconds: operation.medianMilliseconds,
                                p90Milliseconds: operation.p90Milliseconds,
                                baselineMilliseconds: operation.baselineMilliseconds,
                                sampleCount: operation.attempts,
                                maximumMilliseconds: hierarchyMaximum,
                                isSummary: true
                            )
                            ForEach(categories(for: operation.operation)) { category in
                                SkillTimingRow(
                                    name: category.name,
                                    operation: category.operation,
                                    medianMilliseconds: category.medianMilliseconds,
                                    p90Milliseconds: category.p90Milliseconds,
                                    baselineMilliseconds: category.baselineMilliseconds,
                                    sampleCount: category.attempts,
                                    maximumMilliseconds: hierarchyMaximum,
                                    isSummary: false
                                )
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(height: 340)
                .accessibilityLabel("Hierarchical skill timing bars")
            }
        }
    }

    private var recentChangeCard: some View {
        ZetaChartCard(
            title: "Recent category change",
            subtitle: "Faster categories are positive; slower categories are negative."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Chart {
                    RuleMark(x: .value("No change", 0))
                        .foregroundStyle(.secondary.opacity(0.55))
                        .lineStyle(StrokeStyle(lineWidth: 1.2))
                    ForEach(changeCategories) { category in
                        BarMark(
                            xStart: .value("Change", 0),
                            xEnd: .value("Change", category.recentSpeedChange ?? 0),
                            y: .value("Category", shortName(category.name))
                        )
                        .foregroundStyle((category.recentSpeedChange ?? 0) >= 0 ? ZetaTheme.positive : ZetaTheme.caution)
                    }
                }
                .chartXSelection(value: $selectedChangeValue)
                .chartXAxisLabel("Recent speed change (percent)")
                .chartYAxisLabel("Category")
                .chartLegend(.hidden)
                .frame(height: 330)
                .animation(reduceMotion || reduceMotionOverride ? nil : .easeOut(duration: 0.16), value: snapshot.categories)
                .accessibilityLabel("Recent category change")

                HStack(spacing: 16) {
                    Label("Faster", systemImage: "arrow.right").foregroundStyle(ZetaTheme.positive)
                    Label("Slower", systemImage: "arrow.left").foregroundStyle(ZetaTheme.caution)
                    Spacer()
                    if let selectedChangeCategory {
                        Text("\(selectedChangeCategory.name) · \(AnalyticsFormatting.signedPercent(selectedChangeCategory.recentSpeedChange))")
                            .monospacedDigit()
                            .lineLimit(1)
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

    private var operandExplorerCard: some View {
        ZetaChartCard(title: "Operand explorer") {
            VStack(alignment: .leading, spacing: 12) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { operandControls; Spacer() }
                    VStack(alignment: .leading, spacing: 9) { operandControls }
                }

                if let explorer = selectedExplorer {
                    switch explorer.presentation {
                    case .grid:
                        operandGrid(explorer)
                    case .rankedPairs:
                        rankedOperands(explorer)
                    case .insufficient:
                        ContentUnavailableView(
                            "Not enough operand data",
                            systemImage: "square.grid.3x3",
                            description: Text("Complete more questions for this operation.")
                        )
                        .frame(height: 250)
                    }
                } else {
                    ContentUnavailableView(
                        "No operand data",
                        systemImage: "number",
                        description: Text("Complete a session to build this view.")
                    )
                    .frame(height: 250)
                }
            }
        }
    }

    @ViewBuilder
    private var operandControls: some View {
        Picker("Operation", selection: $selectedOperandOperation) {
            ForEach(snapshot.operandExplorers) { explorer in
                Label(explorer.operation.title, systemImage: ZetaTheme.systemImage(for: explorer.operation))
                    .tag(Optional(explorer.operation))
            }
        }
        .frame(maxWidth: 230)
        .onChange(of: selectedOperandOperation) { _, _ in
            selectedOperandPrimary = nil
            selectedOperandCellID = nil
        }
        Picker("Metric", selection: $operandMetric) {
            ForEach(OperandMetric.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 390)
        .onChange(of: operandMetric) { _, _ in
            selectedOperandPrimary = nil
            selectedOperandCellID = nil
        }
    }

    private func operandGrid(_ explorer: OperandExplorerResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Chart(explorer.cells) { cell in
                RectangleMark(
                    x: .value(explorer.horizontalAxis.title, cell.primaryLabel),
                    y: .value(explorer.verticalAxis?.title ?? "Operand", cell.secondaryLabel ?? "")
                )
                .foregroundStyle(ZetaTheme.color(for: explorer.operation).opacity(operandOpacity(cell, in: explorer.cells)))
            }
            .chartXSelection(value: $selectedOperandPrimary)
            .chartXAxisLabel(explorer.horizontalAxis.title)
            .chartYAxisLabel(explorer.verticalAxis?.title ?? "Operand")
            .chartLegend(.hidden)
            .frame(height: 330)
            .animation(reduceMotion || reduceMotionOverride ? nil : .easeOut(duration: 0.16), value: operandMetric)
            .accessibilityLabel("\(explorer.operation.title) operand heatmap, \(operandMetric.rawValue)")

            HStack {
                Label(operandMetric.rawValue, systemImage: "square.fill")
                    .foregroundStyle(ZetaTheme.color(for: explorer.operation))
                Spacer()
                if let cell = selectedGridCell(explorer) {
                    Text("\(cell.pairLabel) · \(operandValueLabel(cell)) · n=\(cell.count)")
                        .monospacedDigit()
                } else {
                    Text("Select a column")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(minHeight: 22)
        }
    }

    private func rankedOperands(_ explorer: OperandExplorerResult) -> some View {
        VStack(spacing: 7) {
            ForEach(rankedCells(explorer)) { cell in
                Button { selectedOperandCellID = cell.id } label: {
                    HStack(spacing: 12) {
                        Label(cell.pairLabel, systemImage: ZetaTheme.systemImage(for: explorer.operation))
                            .font(.body.monospacedDigit())
                        Spacer()
                        Text(operandValueLabel(cell)).bold().monospacedDigit()
                        Text("n=\(cell.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 58, alignment: .trailing)
                    }
                    .padding(9)
                    .background(selectedOperandCellID == cell.id ? ZetaTheme.selectionGradient : LinearGradient(colors: [.clear], startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 9))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            HStack {
                Text("Top 12 by \(operandMetric.rawValue.lowercased())")
                Spacer()
                if let cell = selectedRankedCell(explorer) {
                    Text("\(cell.pairLabel) · median \(AnalyticsFormatting.time(cell.medianMilliseconds)) · P90 \(AnalyticsFormatting.time(cell.p90Milliseconds)) · n=\(cell.count)")
                        .monospacedDigit()
                } else {
                    Text("Select a row")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(minHeight: 24)
        }
    }

    private var hierarchyMaximum: Double {
        max(
            snapshot.operations.flatMap { [$0.medianMilliseconds, $0.p90Milliseconds, $0.baselineMilliseconds] }.max() ?? 1,
            snapshot.categories.flatMap { [$0.medianMilliseconds, $0.p90Milliseconds, $0.baselineMilliseconds] }.max() ?? 1
        )
    }

    private func categories(for operation: ArithmeticOperation) -> [CategoryMetric] {
        snapshot.categories
            .filter { $0.operation == operation }
            .sorted { $0.name < $1.name }
    }

    private var changeCategories: [CategoryMetric] {
        Array(
            snapshot.categories
                .filter { $0.recentSpeedChange != nil }
                .sorted { abs($0.recentSpeedChange ?? 0) > abs($1.recentSpeedChange ?? 0) }
                .prefix(14)
        )
    }

    private var selectedChangeCategory: CategoryMetric? {
        guard let selectedChangeValue else { return nil }
        return changeCategories.min {
            abs(($0.recentSpeedChange ?? 0) - selectedChangeValue)
                < abs(($1.recentSpeedChange ?? 0) - selectedChangeValue)
        }
    }

    private var selectedExplorer: OperandExplorerResult? {
        snapshot.operandExplorers.first { $0.operation == selectedOperandOperation }
            ?? snapshot.operandExplorers.first
    }

    private func operandValue(_ cell: OperandMetricCell) -> Double {
        switch operandMetric {
        case .median: cell.medianMilliseconds
        case .p90: cell.p90Milliseconds
        case .count: Double(cell.count)
        }
    }

    private func operandValueLabel(_ cell: OperandMetricCell) -> String {
        switch operandMetric {
        case .median: AnalyticsFormatting.time(cell.medianMilliseconds)
        case .p90: AnalyticsFormatting.time(cell.p90Milliseconds)
        case .count: String(cell.count)
        }
    }

    private func operandOpacity(_ cell: OperandMetricCell, in cells: [OperandMetricCell]) -> Double {
        let maximum = max(cells.map(operandValue).max() ?? 1, 1)
        return min(max(operandValue(cell) / maximum, 0.14), 0.92)
    }

    private func rankedCells(_ explorer: OperandExplorerResult) -> [OperandMetricCell] {
        Array(explorer.cells.sorted { operandValue($0) > operandValue($1) }.prefix(12))
    }

    private func selectedGridCell(_ explorer: OperandExplorerResult) -> OperandMetricCell? {
        guard let selectedOperandPrimary else { return nil }
        return explorer.cells
            .filter { $0.primaryLabel == selectedOperandPrimary }
            .max { operandValue($0) < operandValue($1) }
    }

    private func selectedRankedCell(_ explorer: OperandExplorerResult) -> OperandMetricCell? {
        explorer.cells.first { $0.id == selectedOperandCellID }
    }

    private func shortName(_ name: String) -> String {
        name.split(separator: "·").last.map { String($0).trimmingCharacters(in: .whitespaces) } ?? name
    }
}

private struct SkillTimingRow: View {
    let name: String
    let operation: ArithmeticOperation
    let medianMilliseconds: Double
    let p90Milliseconds: Double
    let baselineMilliseconds: Double
    let sampleCount: Int
    let maximumMilliseconds: Double
    let isSummary: Bool

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 7) {
                if isSummary {
                    Image(systemName: ZetaTheme.systemImage(for: operation))
                        .foregroundStyle(ZetaTheme.color(for: operation))
                } else {
                    Color.clear.frame(width: 18)
                }
                Text(name)
                    .font(isSummary ? .callout.bold() : .caption)
                    .lineLimit(1)
                    .help(name)
            }
            .frame(width: 220, alignment: .leading)

            GeometryReader { geometry in
                let width = max(geometry.size.width, 1)
                let medianX = width * ratio(medianMilliseconds)
                let p90X = width * ratio(p90Milliseconds)
                let baselineX = width * ratio(baselineMilliseconds)
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule()
                        .fill(ZetaTheme.color(for: operation).opacity(isSummary ? 0.88 : 0.62))
                        .frame(width: max(medianX, 2))
                    Rectangle()
                        .fill(ZetaTheme.caution)
                        .frame(width: 1.5)
                        .offset(x: min(max(baselineX, 0), width - 1))
                    Image(systemName: "diamond.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(.primary)
                        .offset(x: min(max(p90X - 4, 0), width - 8))
                }
            }
            .frame(height: isSummary ? 13 : 9)

            Text("n=\(sampleCount)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 78, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .frame(height: isSummary ? 34 : 28)
        .background(isSummary ? ZetaTheme.color(for: operation).opacity(0.07) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name), median \(AnalyticsFormatting.time(medianMilliseconds)), P90 \(AnalyticsFormatting.time(p90Milliseconds)), baseline \(AnalyticsFormatting.time(baselineMilliseconds)), \(sampleCount) samples")
    }

    private func ratio(_ value: Double) -> CGFloat {
        CGFloat(min(max(value / max(maximumMilliseconds, 1), 0), 1))
    }
}
