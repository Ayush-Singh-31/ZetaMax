import SwiftData
import SwiftUI

struct RecommendationsView: View {
    @Bindable var engine: SessionEngine
    @Query(sort: \PracticeSession.startedAt, order: .reverse) private var sessions: [PracticeSession]
    @Query private var estimates: [SkillEstimate]

    private var recommendations: [Recommendation] {
        AnalyticsEngine.recommendations(sessions: sessions, estimates: estimates)
    }

    var body: some View {
        ZetaScreen(maxWidth: 920) {
            VStack(alignment: .leading, spacing: 24) {
                ZetaPageHeader(
                    eyebrow: "Personal coach",
                    title: "What should I practise?",
                    subtitle: "Transparent recommendations based on time-to-correct, recent pace, and recency.",
                    systemImage: "scope"
                )

                if recommendations.isEmpty {
                    ContentUnavailableView {
                        Label("Build your baseline", systemImage: "chart.bar.doc.horizontal")
                    } description: {
                        Text("Complete at least ten questions in a category. ZetaMax will identify skills that are slower than your own baseline or recently deteriorating.")
                    } actions: {
                        Button("Start a 45-second baseline") {
                            engine.prepareRecommendedSession(categoryKey: nil)
                            engine.start()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(minHeight: 340)
                } else {
                    ForEach(Array(recommendations.enumerated()), id: \.element.id) { index, recommendation in
                        ZetaCard {
                            ViewThatFits(in: .horizontal) {
                                HStack(alignment: .top, spacing: 16) {
                                    recommendationCopy(index: index, recommendation: recommendation)
                                    Spacer(minLength: 12)
                                    recommendationButton(recommendation)
                                }
                                VStack(alignment: .leading, spacing: 14) {
                                    recommendationCopy(index: index, recommendation: recommendation)
                                    recommendationButton(recommendation)
                                }
                            }
                        }
                    }
                }

                Text("Recommendations use timing only. Categories with fewer than ten completed timings stay exploratory and are never labelled as weaknesses.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier("recommendationsScreen")
        .navigationTitle("Recommendations")
    }

    private func recommendationCopy(index: Int, recommendation: Recommendation) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(index + 1)")
                .font(.title2.bold())
                .foregroundStyle(ZetaTheme.brand)
                .frame(width: 42, height: 42)
                .background(ZetaTheme.brand.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 7) {
                Text(recommendation.title).font(.title3.bold())
                Text(recommendation.explanation).foregroundStyle(.secondary)
            }
        }
    }

    private func recommendationButton(_ recommendation: Recommendation) -> some View {
        Button("Practise 45s") {
            engine.prepareRecommendedSession(categoryKey: recommendation.categoryKey)
            engine.start()
        }
        .buttonStyle(.borderedProminent)
    }
}
