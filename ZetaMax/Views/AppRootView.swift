import AppKit
import Observation
import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case practice, recommendations, analytics, history, settings
    var id: String { rawValue }
    var title: String {
        switch self {
        case .practice: "Practice"
        case .recommendations: "Recommendations"
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
    @Bindable var analyticsStore: AnalyticsStore
    @Binding var appearance: AppAppearance
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            switch engine.phase {
            case .running:
                ActivePracticeView(engine: engine)
            case .results:
                SessionResultsView(engine: engine)
            case .idle:
                NavigationSplitView {
                    VStack(spacing: 12) {
                        VStack(spacing: 5) {
                            ForEach(AppSection.allCases) { section in
                                Button {
                                    withAnimation(motionDisabled ? nil : .easeOut(duration: 0.15)) {
                                        navigation.selection = section
                                    }
                                } label: {
                                    HStack(spacing: 11) {
                                        Image(systemName: section.icon)
                                            .frame(width: 20)
                                        Text(section.title)
                                        Spacer(minLength: 0)
                                    }
                                    .font(.callout.weight(navigation.selection == section ? .semibold : .regular))
                                    .foregroundStyle(navigation.selection == section ? Color.primary : Color.secondary)
                                    .padding(.horizontal, 12)
                                    .frame(height: 38)
                                    .background(
                                        navigation.selection == section ? AnyShapeStyle(ZetaTheme.selectionGradient) : AnyShapeStyle(Color.clear),
                                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    )
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .strokeBorder(navigation.selection == section ? ZetaTheme.brand.opacity(0.22) : .clear)
                                    }
                                    .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("navigation-\(section.rawValue)")
                            }
                        }
                        .padding(8)
                        .zetaLayeredSurface(cornerRadius: 14)

                        Spacer(minLength: 0)

                        Menu {
                            Picker("Appearance", selection: $appearance) {
                                ForEach(AppAppearance.allCases) { option in
                                    Label(option.title, systemImage: option.systemImage).tag(option)
                                }
                            }
                        } label: {
                            HStack {
                                Label(appearance.title, systemImage: appearance.systemImage)
                                Spacer()
                                Image(systemName: "chevron.up.chevron.down").font(.caption2)
                            }
                            .padding(.horizontal, 12)
                            .frame(height: 38)
                        }
                        .menuStyle(.borderlessButton)
                        .accessibilityIdentifier("sidebarAppearanceMenu")
                    }
                    .padding(10)
                    .background(ZetaBackground())
                    .navigationSplitViewColumnWidth(min: 205, ideal: 225, max: 250)
                } detail: {
                    destination
                }
                .navigationSplitViewStyle(.balanced)
            }
        }
        .frame(minWidth: 860, minHeight: 620)
        .modifier(UITestReduceMotionModifier(enabled: ProcessInfo.processInfo.arguments.contains("-ui-testing-reduce-motion")))
        .tint(ZetaTheme.brand)
        .preferredColorScheme(uiTestColorScheme ?? appearance.colorScheme)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear(perform: configureUITestWindowIfNeeded)
        .onAppear { analyticsStore.prewarmDefaultSnapshot() }
        .onChange(of: repository.revision.value) { _, _ in
            analyticsStore.repositoryDidChange()
        }
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
            RecommendationsView(engine: engine, analyticsStore: analyticsStore, revision: repository.revision)
        case .analytics:
            AnalyticsDashboardView(analyticsStore: analyticsStore, revision: repository.revision)
        case .history:
            HistoryView(repository: repository, analyticsStore: analyticsStore, revision: repository.revision)
        case .settings:
            SettingsView(repository: repository, appearance: $appearance)
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

    private var motionDisabled: Bool {
        reduceMotion || ProcessInfo.processInfo.arguments.contains("-ui-testing-reduce-motion")
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

private struct UITestReduceMotionModifier: ViewModifier {
    let enabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content.environment(\.zetaReduceMotionOverride, true)
        } else {
            content
        }
    }
}
