import AppKit
import Observation
import SwiftData
import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case practice, recommendations, analytics, history, settings
    var id: String { rawValue }
    var title: String {
        switch self {
        case .practice: "Practice"
        case .recommendations: "What should I practise?"
        case .analytics: "Analytics"
        case .history: "History"
        case .settings: "Settings"
        }
    }
    var icon: String {
        switch self {
        case .practice: "bolt.fill"
        case .recommendations: "wand.and.stars"
        case .analytics: "chart.xyaxis.line"
        case .history: "clock.arrow.circlepath"
        case .settings: "gearshape"
        }
    }
}

@MainActor
@Observable
final class NavigationModel {
    var selection: AppSection = .practice
}

struct AppRootView: View {
    @Bindable var engine: SessionEngine
    @Bindable var navigation: NavigationModel
    let repository: SwiftDataRepository

    var body: some View {
        Group {
            switch engine.phase {
            case .running:
                ActivePracticeView(engine: engine)
            case .results:
                SessionResultsView(engine: engine)
            case .idle:
                NavigationSplitView {
                    List(AppSection.allCases, selection: $navigation.selection) { section in
                        Label(section.title, systemImage: section.icon)
                            .tag(section)
                            .accessibilityIdentifier("navigation-\(section.rawValue)")
                    }
                    .listStyle(.sidebar)
                    .navigationSplitViewColumnWidth(min: 205, ideal: 225, max: 250)
                } detail: {
                    destination
                }
                .navigationSplitViewStyle(.balanced)
            }
        }
        .frame(minWidth: 860, minHeight: 620)
        .tint(.blue)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear(perform: configureUITestWindowIfNeeded)
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification)) { _ in
            engine.interruptForSleep()
        }
        .alert("ZetaMax couldn’t complete that action", isPresented: errorPresented) {
            Button("OK") { engine.errorMessage = nil }
        } message: {
            Text(engine.errorMessage ?? "Unknown error")
        }
    }

    @ViewBuilder
    private var destination: some View {
        switch navigation.selection {
        case .practice:
            PracticeSetupView(engine: engine)
        case .recommendations:
            RecommendationsView(engine: engine)
        case .analytics:
            AnalyticsDashboardView()
        case .history:
            HistoryView(repository: repository)
        case .settings:
            SettingsView(repository: repository)
        }
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { engine.errorMessage != nil },
            set: { if !$0 { engine.errorMessage = nil } }
        )
    }

    private func configureUITestWindowIfNeeded() {
        guard ProcessInfo.processInfo.arguments.contains("-ui-testing-compact") else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NSApplication.shared.keyWindow?.setContentSize(NSSize(width: 860, height: 620))
        }
    }
}

enum ZetaVisuals {
    static let cornerRadius: CGFloat = 16
    static let screenWidth: CGFloat = 1_180
    static let compactSpacing: CGFloat = 12
}

struct ZetaScreen<Content: View>: View {
    let maxWidth: CGFloat
    @ViewBuilder let content: Content

    init(maxWidth: CGFloat = ZetaVisuals.screenWidth, @ViewBuilder content: () -> Content) {
        self.maxWidth = maxWidth
        self.content = content()
    }

    var body: some View {
        ScrollView {
            content
                .padding(24)
                .frame(maxWidth: maxWidth, alignment: .leading)
                .frame(maxWidth: .infinity)
        }
        .background(
            LinearGradient(
                colors: [Color.accentColor.opacity(0.045), .clear],
                startPoint: .topLeading,
                endPoint: .center
            )
        )
    }
}

struct ZetaCard<Content: View>: View {
    @ViewBuilder let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: ZetaVisuals.cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: ZetaVisuals.cornerRadius, style: .continuous)
                    .strokeBorder(.primary.opacity(0.08))
            }
    }
}

struct ZetaMetricTile: View {
    let title: String
    let value: String
    var detail: String? = nil
    var tint: Color = .accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .tracking(0.5)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: detail == nil ? 78 : 96, alignment: .leading)
        .background(tint.opacity(0.075), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(tint.opacity(0.13))
        }
    }
}

struct ZetaStatusChip: View {
    let title: String
    let color: Color

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12), in: Capsule())
    }
}

struct ZetaResponsivePair<First: View, Second: View>: View {
    private let first: () -> First
    private let second: () -> Second

    init(@ViewBuilder first: @escaping () -> First, @ViewBuilder second: @escaping () -> Second) {
        self.first = first
        self.second = second
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 16) {
                first().frame(maxWidth: .infinity)
                second().frame(maxWidth: .infinity)
            }
            VStack(spacing: 16) {
                first()
                second()
            }
        }
    }
}

struct ZetaGroupBoxStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            configuration.label
                .font(.headline)
            configuration.content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: ZetaVisuals.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ZetaVisuals.cornerRadius, style: .continuous)
                .strokeBorder(.primary.opacity(0.08))
        }
    }
}
