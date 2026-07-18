import SwiftUI

struct RecommendationsView: View {
    @Bindable var engine: SessionEngine
    @Bindable var analyticsStore: AnalyticsStore

    var body: some View {
        GeometryReader { geometry in
            let compact = geometry.size.width < 760
            ZetaScreen(maxWidth: 1_020) {
                VStack(alignment: .leading, spacing: ZetaTheme.sectionSpacing) {
                    ZetaPageHeader(title: "Recommendations", systemImage: "scope")

                    if analyticsStore.recommendations.isEmpty {
                        if analyticsStore.isRefreshingRecommendations {
                            ProgressView("Loading recommendations…")
                                .controlSize(.small)
                                .frame(maxWidth: .infinity, minHeight: 340)
                        } else {
                            ContentUnavailableView {
                                Label("Build your baseline", systemImage: "chart.bar.doc.horizontal")
                            } description: {
                                Text("Complete at least ten questions in a category.")
                            } actions: {
                                Button("Start session") { startSession(categoryKey: nil) }
                                    .buttonStyle(.borderedProminent)
                            }
                            .frame(minHeight: 340)
                        }
                    } else {
                        VStack(spacing: 12) {
                            ForEach(analyticsStore.recommendations) { recommendation in
                                recommendationCard(recommendation, compact: compact)
                            }
                        }
                    }

                    Label("Categories need at least ten completed timings.", systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityIdentifier("recommendationsScreen")
        .navigationTitle("Recommendations")
        .onAppear { analyticsStore.requestRecommendations() }
    }

    @ViewBuilder
    private func recommendationCard(_ recommendation: Recommendation, compact: Bool) -> some View {
        ZetaCard {
            if compact {
                VStack(alignment: .leading, spacing: 16) {
                    recommendationContent(recommendation)
                    startButton(recommendation)
                        .frame(maxWidth: .infinity)
                }
            } else {
                HStack(alignment: .center, spacing: 22) {
                    recommendationContent(recommendation)
                    Divider().frame(minHeight: 118)
                    startButton(recommendation)
                        .frame(width: 150)
                }
                .frame(minHeight: 178)
            }
        }
        .accessibilityIdentifier("recommendationCard-\(recommendation.id)")
    }

    private func recommendationContent(_ recommendation: Recommendation) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            Label(recommendation.title, systemImage: recommendation.categoryKey == nil ? "timer" : "target")
                .font(.title3.bold())
                .foregroundStyle(recommendation.categoryKey == nil ? ZetaTheme.caution : ZetaTheme.brand)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 118, maximum: 180), alignment: .leading)],
                alignment: .leading,
                spacing: 12
            ) {
                recommendationMetric("Category", recommendation.categoryName)
                recommendationMetric("Median time", recommendation.medianMilliseconds.map(AnalyticsFormatting.time) ?? "—")
                recommendationMetric("Vs baseline", baselineDifference(recommendation.baselineDifferencePercent))
                recommendationMetric("Recent change", recentChange(recommendation.recentChangePercent))
                recommendationMetric("Sample count", String(recommendation.sampleCount))
                recommendationMetric("Session", DurationText.compact(recommendation.sessionDurationSeconds))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func recommendationMetric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .lineLimit(2)
        }
    }

    private func startButton(_ recommendation: Recommendation) -> some View {
        Button("Start session") { startSession(categoryKey: recommendation.categoryKey) }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .frame(maxWidth: .infinity)
    }

    private func startSession(categoryKey: String?) {
        engine.prepareRecommendedSession(categoryKey: categoryKey)
        engine.start()
    }

    private func baselineDifference(_ value: Double?) -> String {
        guard let value else { return "—" }
        return value >= 0
            ? "\(Int(abs(value).rounded()))% slower"
            : "\(Int(abs(value).rounded()))% faster"
    }

    private func recentChange(_ value: Double?) -> String {
        guard let value, abs(value) >= 0.5 else { return "Stable" }
        return value > 0
            ? "\(Int(abs(value).rounded()))% slower"
            : "\(Int(abs(value).rounded()))% faster"
    }
}
