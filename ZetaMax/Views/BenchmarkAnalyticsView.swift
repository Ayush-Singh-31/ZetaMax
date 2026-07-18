import Charts
import SwiftUI

struct BenchmarkAnalyticsView: View {
    let snapshot: DashboardSnapshot
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.zetaReduceMotionOverride) private var reduceMotionOverride
    @State private var selectedDuration = 120
    @State private var selectedResultDuration: Double?
    @State private var selectedResultID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: ZetaTheme.sectionSpacing) {
            outlookCard
            resultsCard
            profileCards
        }
    }

    private var outlookCard: some View {
        ZetaChartCard(title: "Benchmark outlook") {
            VStack(alignment: .leading, spacing: 13) {
                Picker("Duration", selection: $selectedDuration) {
                    ForEach(snapshot.benchmarkProjections) { projection in
                        Text(DurationText.compact(projection.durationSeconds)).tag(projection.durationSeconds)
                    }
                }
                .pickerStyle(.segmented)

                if let selectedProjection, let expected = selectedProjection.expected {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("\(expected.median)")
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(selectedProjection.isStandard ? ZetaTheme.brand : .primary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("projected questions").font(.headline)
                            Text("Likely range \(expected.lower)–\(expected.upper)")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Label(
                        "At least 20 timings across 3 similar-duration sessions are required.",
                        systemImage: "info.circle"
                    )
                        .foregroundStyle(.secondary)
                }

                Chart {
                    ForEach(snapshot.benchmarkProjections) { projection in
                        if let expected = projection.expected {
                            BarMark(
                                x: .value("Duration", DurationText.compact(projection.durationSeconds)),
                                yStart: .value("Likely lower", expected.lower),
                                yEnd: .value("Likely upper", expected.upper),
                                width: .fixed(projection.isStandard ? 15 : 10)
                            )
                            .foregroundStyle(projection.isStandard ? ZetaTheme.brand.opacity(0.48) : ZetaTheme.cyan.opacity(0.32))
                            PointMark(
                                x: .value("Duration", DurationText.compact(projection.durationSeconds)),
                                y: .value("Projected questions", expected.median)
                            )
                            .foregroundStyle(projection.isStandard ? ZetaTheme.brand : ZetaTheme.cyan)
                            .symbol(projection.isStandard ? .diamond : .circle)
                            .symbolSize(projection.isStandard ? 90 : 52)
                        }
                    }
                }
                .chartXAxisLabel("Duration")
                .chartYAxisLabel("Completed questions")
                .chartLegend(.hidden)
                .frame(height: 320)
                .accessibilityLabel("Benchmark outlook by duration")
                .accessibilityValue(projectionAccessibility)

                HStack(spacing: 16) {
                    Label("Likely range", systemImage: "rectangle.fill").foregroundStyle(ZetaTheme.cyan)
                    Label("Projection", systemImage: "circle.fill").foregroundStyle(ZetaTheme.brand)
                    Spacer()
                    if let selectedProjection, let expected = selectedProjection.expected {
                        Text("\(DurationText.compact(selectedProjection.durationSeconds)) · \(expected.median) projected · \(expected.lower)–\(expected.upper) likely")
                            .monospacedDigit()
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(minHeight: 22)
            }
        }
    }

    private var resultsCard: some View {
        ZetaChartCard(title: "Benchmark results") {
            if snapshot.benchmarkResults.isEmpty {
                ContentUnavailableView(
                    "No benchmark results",
                    systemImage: "stopwatch",
                    description: Text("Complete a benchmark to build this chart.")
                )
                .frame(height: 260)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Chart(snapshot.benchmarkResults) { result in
                        PointMark(
                            x: .value("Active duration", result.activeDurationSeconds),
                            y: .value("Completed questions", result.score)
                        )
                        .foregroundStyle(by: .value("Profile", result.profileName))
                        .symbol(by: .value("Profile", result.profileName))
                        .symbolSize(selectedResult?.id == result.id ? 115 : 60)
                    }
                    .chartXSelection(value: $selectedResultDuration)
                    .chartXAxisLabel("Active duration (seconds)")
                    .chartYAxisLabel("Completed questions")
                    .chartLegend(position: .bottom, alignment: .leading, spacing: 12)
                    .frame(height: 330)
                    .animation(reduceMotion || reduceMotionOverride ? nil : .easeOut(duration: 0.16), value: selectedResultID)
                    .onChange(of: selectedResultDuration) { _, duration in
                        guard let duration else { return }
                        selectedResultID = snapshot.benchmarkResults.min {
                            abs($0.activeDurationSeconds - duration) < abs($1.activeDurationSeconds - duration)
                        }?.id
                    }
                    .accessibilityLabel("Benchmark results scatter plot")
                    .accessibilityValue("\(snapshot.benchmarkResults.count) benchmark sessions")

                    HStack(spacing: 8) {
                        Button { moveResult(-1) } label: { Label("Previous", systemImage: "chevron.left") }
                        Button { moveResult(1) } label: { Label("Next", systemImage: "chevron.right") }
                        Spacer()
                        if let selectedResult {
                            Text("\(selectedResult.date.formatted(date: .abbreviated, time: .omitted)) · \(String(format: "%.0fs", selectedResult.activeDurationSeconds)) · \(selectedResult.score) completed · \(String(format: "%.1f questions/minute", selectedResult.questionsPerMinute))")
                                .monospacedDigit()
                                .lineLimit(1)
                        } else {
                            Text("Select a result")
                        }
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(minHeight: 24)
                }
            }
        }
    }

    @ViewBuilder
    private var profileCards: some View {
        if snapshot.benchmarkProfiles.isEmpty {
            ZetaCard {
                Label("No completed benchmark profiles", systemImage: "flag.checkered")
                    .foregroundStyle(.secondary)
            }
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 250, maximum: 390))], spacing: 10) {
                ForEach(snapshot.benchmarkProfiles) { profile in
                    ZetaCard {
                        VStack(alignment: .leading, spacing: 9) {
                            HStack {
                                Label(profile.profileName, systemImage: "stopwatch.fill")
                                    .font(.headline)
                                    .lineLimit(1)
                                Spacer()
                                Text(DurationText.compact(profile.durationSeconds))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            HStack(spacing: 18) {
                                profileMetric("Personal best", String(profile.personalBest))
                                profileMetric("Recent", profile.recentScore.map(String.init) ?? "—")
                                profileMetric("Projection", profile.projectedScore.map(String.init) ?? "—")
                                profileMetric("Sessions", String(profile.sampleCount))
                            }
                        }
                    }
                }
            }
        }
    }

    private func profileMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            Text(value).font(.headline.monospacedDigit())
        }
    }

    private var selectedProjection: BenchmarkProjection? {
        snapshot.benchmarkProjections.first { $0.durationSeconds == selectedDuration }
    }

    private var selectedResult: BenchmarkResultPoint? {
        snapshot.benchmarkResults.first { $0.id == selectedResultID }
    }

    private func moveResult(_ direction: Int) {
        let values = snapshot.benchmarkResults.sorted { $0.date < $1.date }
        guard !values.isEmpty else { return }
        let current = selectedResult.flatMap { result in
            values.firstIndex(where: { $0.id == result.id })
        } ?? (direction > 0 ? -1 : values.count)
        let result = values[min(max(current + direction, 0), values.count - 1)]
        selectedResultID = result.id
        selectedResultDuration = result.activeDurationSeconds
    }

    private var projectionAccessibility: String {
        snapshot.benchmarkProjections.compactMap { projection in
            projection.expected.map {
                "\(DurationText.compact(projection.durationSeconds)), projected \($0.median), likely range \($0.lower) to \($0.upper)"
            }
        }.joined(separator: ". ")
    }
}
