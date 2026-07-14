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
        .tint(ZetaTheme.brand)
        .preferredColorScheme(uiTestColorScheme)
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

    private var uiTestColorScheme: ColorScheme? {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-ui-testing-light") { return .light }
        if arguments.contains("-ui-testing-dark") { return .dark }
        return nil
    }

    private func configureUITestWindowIfNeeded() {
        let arguments = ProcessInfo.processInfo.arguments
        let size: NSSize?
        if arguments.contains("-ui-testing-compact") { size = NSSize(width: 860, height: 620) }
        else if arguments.contains("-ui-testing-medium") { size = NSSize(width: 1_100, height: 760) }
        else if arguments.contains("-ui-testing-wide") { size = NSSize(width: 1_500, height: 900) }
        else { size = nil }
        guard let size else { return }
        for delay in [0.1, 0.35, 0.75] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                let window = NSApplication.shared.keyWindow
                    ?? NSApplication.shared.windows.first(where: \.isVisible)
                    ?? NSApplication.shared.windows.first
                window?.setContentSize(size)
            }
        }
    }
}
