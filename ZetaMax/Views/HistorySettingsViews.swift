import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    let repository: SwiftDataRepository
    @Binding var appearance: AppAppearance
    @Query private var sessions: [PracticeSession]
    @State private var resetPresented = false
    @State private var exportDocument: ExportDocument?
    @State private var exportFormat: ExportFormat = .json
    @State private var isExporting = false
    @State private var messageTitle = "ZetaMax"
    @State private var message: String?

    var body: some View {
        ZetaScreen(maxWidth: 820) {
            VStack(alignment: .leading, spacing: ZetaTheme.sectionSpacing) {
                ZetaPageHeader(
                    title: "Settings",
                    systemImage: "gearshape.fill"
                )

                ZetaCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Appearance", systemImage: "circle.lefthalf.filled").font(.headline)
                        Picker("Appearance", selection: $appearance) {
                            ForEach(AppAppearance.allCases) { option in
                                Label(option.title, systemImage: option.systemImage).tag(option)
                            }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("settingsAppearancePicker")
                    }
                }

                ZetaCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Label("Data and privacy", systemImage: "externaldrive.fill").font(.headline)
                        LabeledContent("Storage", value: "Local SwiftData database")
                        LabeledContent("Network", value: "No accounts or backend")
                        LabeledContent("Recorded sessions", value: String(sessions.count))
                        Divider()
                        ViewThatFits(in: .horizontal) {
                            HStack {
                                exportButtons
                                Spacer()
                                deleteAllButton
                            }
                            VStack(alignment: .leading, spacing: 10) {
                                exportButtons
                                deleteAllButton
                            }
                        }
                    }
                }

                ZetaCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Adaptive practice", systemImage: "scope").font(.headline)
                        Text(AdaptiveModelParameters.explanation)
                        Text("Skill estimates are rebuildable caches. Deleting data automatically recalculates them from the remaining completed timings.")
                            .foregroundStyle(.secondary)
                    }
                }

                ZetaCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("About", systemImage: "info.circle.fill").font(.headline)
                        LabeledContent("ZetaMax", value: "1.0")
                        LabeledContent("Minimum system", value: "macOS 14")
                    }
                }
            }
        }
        .accessibilityIdentifier("settingsScreen")
        .navigationTitle("Settings")
        .confirmationDialog("Delete all practice data?", isPresented: $resetPresented) {
            Button("Delete everything", role: .destructive) {
                do {
                    try repository.resetAllData()
                    messageTitle = "Practice data deleted"
                    message = "All sessions, question timings, and adaptive estimates were removed."
                } catch {
                    messageTitle = "Couldn’t delete practice data"
                    message = error.localizedDescription
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes every session, question timing, and skill estimate. Export first if you want a backup.")
        }
        .fileExporter(
            isPresented: $isExporting,
            document: exportDocument,
            contentType: exportFormat == .csv ? .commaSeparatedText : .json,
            defaultFilename: "zetamax-all.\(exportFormat.rawValue)"
        ) { result in
            if case let .failure(error) = result {
                messageTitle = "Export failed"
                message = error.localizedDescription
            }
        }
        .alert(messageTitle, isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") { message = nil }
        } message: { Text(message ?? "") }
    }

    private var exportButtons: some View {
        HStack {
            Button("Export CSV") { export(.csv) }
            Button("Export JSON") { export(.json) }
        }
    }

    private func export(_ format: ExportFormat) {
        do {
            exportFormat = format
            exportDocument = try ExportService.document(for: sessions, format: format)
            isExporting = true
        } catch {
            messageTitle = "Export failed"
            message = error.localizedDescription
        }
    }

    private var deleteAllButton: some View {
        Button("Delete all practice data", role: .destructive) { resetPresented = true }
            .disabled(sessions.isEmpty)
            .accessibilityIdentifier("deleteAllPracticeDataButton")
    }
}
