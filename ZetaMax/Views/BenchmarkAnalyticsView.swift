import Charts
import SwiftUI

struct BenchmarkAnalyticsView: View {
    let snapshot: DashboardSnapshot
    @State private var selectedDuration = 120
    @State private var selectedResultDate: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: ZetaTheme.sectionSpacing) {
            outlookCard
            profileCards
            actualResultsCard
        }
    }

    private var outlookCard: some View {
        ZetaChartCard(title: "Benchmark outlook", subtitle: "Expected scores come only from empirical time-to-correct draws. The 120-second standard profile is highlighted.") {
            VStack(alignment: .leading, spacing: 13) {
                Picker("Duration", selection: $selectedDuration) {
                    ForEach(snapshot.benchmarkProjections) { projection in
                        Text(DurationText.compact(projection.durationSeconds)).tag(projection.durationSeconds)
                    }
                }
                .pickerStyle(.segmented)

                if let selectedProjection, let expected = selectedProjection.expected {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("\(expected.median)").font(.system(size: 44, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(selectedProjection.isStandard ? ZetaTheme.brand : .primary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("expected score").font(.headline)
                            Text("Likely range \(expected.lower)–\(expected.upper)").font(.callout).foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Label("Complete at least 20 matching timings to simulate a score.", systemImage: "info.circle").foregroundStyle(.secondary)
                }

                Chart {
                    ForEach(snapshot.benchmarkProjections) { projection in
                        if let expected = projection.expected {
                            BarMark(
                                x: .value("Duration", DurationText.compact(projection.durationSeconds)),
                                yStart: .value("Lower", expected.lower),
                                yEnd: .value("Upper", expected.upper),
                                width: .fixed(projection.isStandard ? 15 : 10)
                            )
                            .foregroundStyle(projection.isStandard ? ZetaTheme.brand.opacity(0.48) : ZetaTheme.cyan.opacity(0.32))
                            PointMark(x: .value("Duration", DurationText.compact(projection.durationSeconds)), y: .value("Expected", expected.median))
                                .foregroundStyle(projection.isStandard ? ZetaTheme.brand : ZetaTheme.cyan)
                                .symbol(projection.isStandard ? .diamond : .circle)
                                .symbolSize(projection.isStandard ? 90 : 52)
                                .annotation(position: .top) { Text("\(expected.median)").font(.caption.bold().monospacedDigit()) }
                        }
                    }
                }
                .chartYAxisLabel("Expected completed questions")
                .frame(height: 275)
                .accessibilityLabel("Benchmark expected scores by duration")
                .accessibilityValue(projectionAccessibility)
            }
        }
    }

    @ViewBuilder private var profileCards: some View {
        if snapshot.benchmarkProfiles.isEmpty {
            ZetaCard {
                HStack(spacing: 12) {
                    Image(systemName: "flag.checkered").font(.title2).foregroundStyle(ZetaTheme.brand)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("No completed benchmark profiles in this view").font(.headline)
                        Text("Projections remain available from comparable practice timings; run a benchmark to establish a personal best.").foregroundStyle(.secondary)
                    }
                }
            }
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 225, maximum: 360))], spacing: 10) {
                ForEach(snapshot.benchmarkProfiles) { profile in
                    ZetaCard {
                        VStack(alignment: .leading, spacing: 11) {
                            HStack {
                                Label(profile.profileName, systemImage: "stopwatch.fill").font(.headline).lineLimit(1).help(profile.profileName)
                                Spacer()
                                ZetaStatusChip(title: "v\(profile.version)", color: ZetaTheme.brand)
                            }
                            HStack(alignment: .firstTextBaseline) {
                                Text("\(profile.personalBest)").font(.largeTitle.bold()).monospacedDigit()
                                Text("PB").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                Spacer()
                                Text(DurationText.compact(profile.durationSeconds)).font(.callout.weight(.semibold)).foregroundStyle(.secondary)
                            }
                            Divider()
                            LabeledContent("Recent", value: profile.recentScore.map(String.init) ?? "—")
                            LabeledContent("Projected", value: profile.projectedScore.map(String.init) ?? "—")
                            LabeledContent("Sessions", value: String(profile.sampleCount))
                        }
                    }
                }
            }
        }
    }

    private var actualResultsCard: some View {
        ZetaChartCard(title: "Actual benchmark history", subtitle: "Scores stay isolated by immutable benchmark profile and version.") {
            if snapshot.benchmarkResults.isEmpty {
                ContentUnavailableView("No benchmark results", systemImage: "stopwatch", description: Text("Complete a benchmark matching the current filters to build this chart."))
                    .frame(height: 220)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Chart {
                        ForEach(snapshot.benchmarkResults) { result in
                            LineMark(x: .value("Date", result.date), y: .value("Score", result.score), series: .value("Profile", result.profileKey))
                                .foregroundStyle(by: .value("Profile", result.profileName))
                                .symbol(by: .value("Profile", result.profileName))
                                .lineStyle(StrokeStyle(lineWidth: 2.2))
                            PointMark(x: .value("Date", result.date), y: .value("Score", result.score))
                                .foregroundStyle(by: .value("Profile", result.profileName))
                                .symbol(by: .value("Profile", result.profileName))
                        }
                        if let selectedResult {
                            RuleMark(x: .value("Selected", selectedResult.date))
                                .foregroundStyle(.secondary.opacity(0.55))
                                .annotation(position: .top, overflowResolution: .init(x: .fit, y: .disabled)) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(selectedResult.profileName).font(.caption.bold())
                                        Text("\(selectedResult.score) · \(selectedResult.date.formatted(date: .abbreviated, time: .omitted))").font(.caption2).monospacedDigit()
                                    }.padding(7).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 7))
                                }
                        }
                    }
                    .chartXSelection(value: $selectedResultDate)
                    .chartYAxisLabel("Score")
                    .frame(height: 280)
                    .accessibilityLabel("Actual benchmark score history")
                    .accessibilityValue("\(snapshot.benchmarkResults.count) benchmark sessions")

                    HStack {
                        Button { moveResult(-1) } label: { Label("Previous", systemImage: "chevron.left") }
                        Button { moveResult(1) } label: { Label("Next", systemImage: "chevron.right") }
                        Spacer()
                        if let selectedResult { Text("\(selectedResult.profileName) · \(selectedResult.score)").font(.caption).foregroundStyle(.secondary) }
                    }.buttonStyle(.borderless)
                }
            }
        }
    }

    private var selectedProjection: BenchmarkProjection? { snapshot.benchmarkProjections.first { $0.durationSeconds == selectedDuration } }
    private var selectedResult: BenchmarkResultPoint? {
        guard let selectedResultDate else { return nil }
        return snapshot.benchmarkResults.min { abs($0.date.timeIntervalSince(selectedResultDate)) < abs($1.date.timeIntervalSince(selectedResultDate)) }
    }
    private func moveResult(_ direction: Int) {
        let values = snapshot.benchmarkResults
        guard !values.isEmpty else { return }
        let current = selectedResult.flatMap { result in values.firstIndex(where: { $0.id == result.id }) } ?? (direction > 0 ? -1 : values.count)
        selectedResultDate = values[min(max(current + direction, 0), values.count - 1)].date
    }
    private var projectionAccessibility: String {
        snapshot.benchmarkProjections.compactMap { projection in
            projection.expected.map { "\(DurationText.compact(projection.durationSeconds)), expected \($0.median), range \($0.lower) to \($0.upper)" }
        }.joined(separator: ". ")
    }
}
