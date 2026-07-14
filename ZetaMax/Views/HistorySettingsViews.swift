import AppKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct HistoryView: View {
    let repository: SwiftDataRepository
    @Query(sort: \PracticeSession.startedAt, order: .reverse) private var sessions: [PracticeSession]
    @State private var selectedID: UUID?
    @State private var deleteCandidate: PracticeSession?
    @State private var exportDocument: ExportDocument?
    @State private var exportFormat: ExportFormat = .csv
    @State private var isExporting = false
    @State private var messageTitle = "ZetaMax"
    @State private var message: String?

    private var selected: PracticeSession? { sessions.first { $0.id == selectedID } }

    var body: some View {
        HSplitView {
            List(selection: $selectedID) {
                ForEach(sessions) { session in
                    SessionHistoryRow(session: session)
                        .tag(session.id)
                        .accessibilityIdentifier("historySessionRow")
                        .contextMenu {
                            Button("Export CSV") { export([session], as: .csv) }
                            Button("Export JSON") { export([session], as: .json) }
                            Divider()
                            Button("Delete", role: .destructive) { deleteCandidate = session }
                        }
                }
            }
            .frame(minWidth: 240, idealWidth: 285, maxWidth: 340)
            .overlay {
                if sessions.isEmpty { ContentUnavailableView("No sessions", systemImage: "clock", description: Text("Completed sessions appear here.")) }
            }

            Group {
                if let selected {
                    SessionDetailView(
                        session: selected,
                        baselineSessions: sessions,
                        onExport: { export([selected], as: $0) },
                        onDelete: { deleteCandidate = selected }
                    )
                }
                else { ContentUnavailableView("Select a session", systemImage: "list.bullet.rectangle") }
            }
            .frame(minWidth: 430, maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle("History")
        .toolbar {
            Menu("Export all", systemImage: "square.and.arrow.up") {
                Button("CSV") { export(sessions, as: .csv) }
                Button("JSON") { export(sessions, as: .json) }
            }
            .disabled(sessions.isEmpty)
        }
        .confirmationDialog("Delete this session?", isPresented: deletePresented) {
            Button("Delete session", role: .destructive) {
                guard let deleteCandidate else { return }
                do {
                    try repository.delete(deleteCandidate)
                    if selectedID == deleteCandidate.id { selectedID = nil }
                    messageTitle = "Session deleted"
                    message = "The session and its question timings were removed. Adaptive estimates were rebuilt."
                } catch {
                    messageTitle = "Couldn’t delete session"
                    message = error.localizedDescription
                }
                self.deleteCandidate = nil
            }
            Button("Cancel", role: .cancel) { deleteCandidate = nil }
        } message: {
            Text("Question attempts and timings in this session will be permanently removed, then adaptive estimates will be rebuilt.")
        }
        .fileExporter(
            isPresented: $isExporting,
            document: exportDocument,
            contentType: exportFormat == .csv ? .commaSeparatedText : .json,
            defaultFilename: "zetamax-\(dateStamp).\(exportFormat.rawValue)"
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

    private var deletePresented: Binding<Bool> {
        Binding(get: { deleteCandidate != nil }, set: { if !$0 { deleteCandidate = nil } })
    }

    private func export(_ sessions: [PracticeSession], as format: ExportFormat) {
        exportFormat = format
        exportDocument = ExportService.document(for: sessions, format: format)
        isExporting = true
    }

    private var dateStamp: String { Date.now.formatted(.dateTime.year().month().day()) }
}

private struct SessionHistoryRow: View {
    let session: PracticeSession
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(session.startedAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                    .font(.headline)
                Spacer()
                Text("\(session.correctCount)").font(.title3.bold()).monospacedDigit()
            }
            HStack {
                Text(session.mode.title)
                Text("·")
                Text(DurationText.compact(session.durationSeconds))
                if session.status == .interrupted {
                    ZetaStatusChip(title: "Interrupted", color: .orange)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

private struct SessionDetailView: View {
    let session: PracticeSession
    let baselineSessions: [PracticeSession]
    let onExport: (ExportFormat) -> Void
    let onDelete: () -> Void
    @State private var selectedAttemptID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120, maximum: 210))], spacing: 10) {
                ZetaMetricTile(title: "Completed", value: String(completedTimings.count), tint: .blue)
                ZetaMetricTile(title: "Questions/min", value: String(format: "%.1f", questionsPerMinute), tint: .green)
                ZetaMetricTile(title: "Median", value: medianText, tint: .orange)
                ZetaMetricTile(title: "P90", value: p90Text, tint: .purple)
            }

            if let selectedAttempt {
                attemptInspector(selectedAttempt)
            }

            HStack {
                Text("Question timings").font(.title3.bold())
                Spacer()
                Text("\(session.sortedAttempts.count) total")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Table(session.sortedAttempts, selection: $selectedAttemptID) {
                TableColumn("#") { attempt in
                    Text("\(attempt.position + 1)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .width(34)

                TableColumn("Question") { attempt in
                    Text(attempt.prompt)
                        .font(.body.monospacedDigit())
                        .lineLimit(1)
                }
                .width(min: 90, ideal: 150, max: 240)

                TableColumn("Answer") { attempt in
                    Text(attempt.correctAnswerText)
                        .bold()
                        .monospacedDigit()
                        .lineLimit(1)
                }
                .width(min: 58, ideal: 72, max: 96)

                TableColumn("Time") { attempt in
                    Text(responseTime(attempt))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .width(min: 62, ideal: 76, max: 90)

                TableColumn("Vs typical") { attempt in
                    Text(relativeTime(attempt))
                        .lineLimit(1)
                        .monospacedDigit()
                        .foregroundStyle(relativeColor(attempt))
                }
                .width(min: 78, ideal: 92, max: 112)
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))
            .frame(minHeight: 210)
            .accessibilityIdentifier("attemptTable")
        }
        .padding(22)
        .background(
            LinearGradient(colors: [Color.accentColor.opacity(0.045), .clear], startPoint: .topLeading, endPoint: .center)
        )
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 16) {
                heading
                Spacer(minLength: 12)
                actions
            }
            VStack(alignment: .leading, spacing: 12) {
                heading
                actions
            }
        }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(session.startedAt, format: .dateTime.weekday(.wide).month(.wide).day().year())
                .font(.title.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.78)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { metadata }
                VStack(alignment: .leading, spacing: 7) { metadata }
            }
        }
    }

    @ViewBuilder
    private var metadata: some View {
        ZetaStatusChip(title: session.mode.title, color: .blue)
        ZetaStatusChip(title: DurationText.compact(session.durationSeconds), color: .secondary)
        if session.status == .interrupted {
            ZetaStatusChip(title: "Interrupted", color: .orange)
        }
        HStack(spacing: 4) {
            Text("Seed \(session.randomSeed)")
                .lineLimit(1)
                .truncationMode(.middle)
                .help("Seed \(session.randomSeed)")
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(String(session.randomSeed), forType: .string)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.plain)
            .help("Copy random seed")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Menu("Export", systemImage: "square.and.arrow.up") {
                Button("CSV") { onExport(.csv) }
                Button("JSON") { onExport(.json) }
            }
            Button("Delete", role: .destructive, action: onDelete)
        }
    }

    private var selectedAttempt: QuestionAttempt? {
        session.sortedAttempts.first { $0.id == selectedAttemptID }
    }

    private func attemptInspector(_ attempt: QuestionAttempt) -> some View {
        ZetaCard {
            VStack(alignment: .leading, spacing: 10) {
                ViewThatFits(in: .horizontal) {
                    HStack {
                        Text("Question \(attempt.position + 1)").font(.headline)
                        Text(attempt.prompt).font(.headline.monospacedDigit())
                        Spacer()
                        Text("Answer \(attempt.correctAnswerText)")
                            .font(.callout.bold().monospacedDigit())
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Question \(attempt.position + 1) · \(attempt.prompt)").font(.headline.monospacedDigit())
                        Text("Answer \(attempt.correctAnswerText)").font(.callout.bold().monospacedDigit())
                    }
                }
                HStack(spacing: 8) {
                    ZetaStatusChip(title: responseTime(attempt), color: .blue)
                    ZetaStatusChip(title: relativeTime(attempt), color: relativeColor(attempt))
                    ZetaStatusChip(title: difficultyText(attempt), color: .orange)
                    Spacer()
                }
                Text(attempt.categoryName).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var completedTimings: [Int] {
        session.sortedAttempts.compactMap { attempt in
            guard attempt.wasEventuallyCorrect else { return nil }
            return attempt.responseTimeMilliseconds
        }
    }
    private var medianText: String {
        let median = Statistics.median(completedTimings.map(Double.init))
        return median.map { String(format: "%.2fs", $0 / 1_000) } ?? "—"
    }
    private var p90Text: String {
        let p90 = Statistics.percentile(completedTimings.map(Double.init), 0.9)
        return p90.map { String(format: "%.2fs", $0 / 1_000) } ?? "—"
    }
    private var questionsPerMinute: Double {
        let elapsed = Double(session.activeElapsedMilliseconds ?? session.durationSeconds * 1_000) / 1_000
        return elapsed > 0 ? Double(completedTimings.count) / (elapsed / 60) : 0
    }
    private var baselineSnapshot: DashboardSnapshot {
        AnalyticsEngine.snapshot(sessions: baselineSessions, baselineSessions: baselineSessions)
    }
    private func categoryBaseline(_ attempt: QuestionAttempt) -> Double {
        baselineSnapshot.categoryBaselines[attempt.categoryKey] ?? max(baselineSnapshot.globalBaselineMilliseconds, 1)
    }
    private func responseTime(_ attempt: QuestionAttempt) -> String {
        attempt.responseTimeMilliseconds.map { String(format: "%.2fs", Double($0) / 1_000) } ?? "—"
    }
    private func relativeTime(_ attempt: QuestionAttempt) -> String {
        guard let milliseconds = attempt.responseTimeMilliseconds else { return "—" }
        return String(format: "%.1f×", Double(milliseconds) / categoryBaseline(attempt))
    }
    private func relativeColor(_ attempt: QuestionAttempt) -> Color {
        guard let milliseconds = attempt.responseTimeMilliseconds else { return .secondary }
        let multiple = Double(milliseconds) / categoryBaseline(attempt)
        if multiple >= 1.25 { return .orange }
        if multiple <= 0.8 { return .green }
        return .secondary
    }
    private func difficultyText(_ attempt: QuestionAttempt) -> String {
        let global = max(baselineSnapshot.globalBaselineMilliseconds, 1)
        return "Difficulty \(Int((categoryBaseline(attempt) / global * 100).rounded()))"
    }
}

struct SettingsView: View {
    let repository: SwiftDataRepository
    @Query private var sessions: [PracticeSession]
    @State private var resetPresented = false
    @State private var exportDocument: ExportDocument?
    @State private var exportFormat: ExportFormat = .json
    @State private var isExporting = false
    @State private var messageTitle = "ZetaMax"
    @State private var message: String?

    var body: some View {
        ZetaScreen(maxWidth: 820) {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 5) {
                    Label("LOCAL CONTROL", systemImage: "lock.shield.fill")
                        .font(.caption.weight(.bold))
                        .tracking(0.8)
                        .foregroundStyle(.blue)
                    Text("Settings").font(.largeTitle.bold())
                }

                ZetaCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Label("Data and privacy", systemImage: "externaldrive.fill")
                            .font(.headline)
                        LabeledContent("Storage", value: "Local SwiftData database")
                        LabeledContent("Network", value: "No accounts or backend")
                        LabeledContent("Recorded sessions", value: String(sessions.count))
                        Divider()
                        ViewThatFits(in: .horizontal) {
                            HStack {
                                Button("Export all as CSV") { export(.csv) }
                                Button("Export all as JSON") { export(.json) }
                                Spacer()
                                deleteAllButton
                            }
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Button("Export all as CSV") { export(.csv) }
                                    Button("Export all as JSON") { export(.json) }
                                }
                                deleteAllButton
                            }
                        }
                    }
                }

                ZetaCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Adaptive practice", systemImage: "scope")
                            .font(.headline)
                        Text("Weights combine relative time-to-correct (50%), recent slowdown (25%), recency (15%), and confidence (10%). Ten percent of sampling remains exploratory.")
                        Text("Skill estimates are derived caches. Deleting data automatically rebuilds them from the remaining raw attempts.")
                            .foregroundStyle(.secondary)
                    }
                }

                ZetaCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("About", systemImage: "info.circle.fill")
                            .font(.headline)
                        LabeledContent("ZetaMax", value: "1.0")
                        LabeledContent("Minimum system", value: "macOS 14")
                    }
                }
            }
        }
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

    private func export(_ format: ExportFormat) {
        exportFormat = format
        exportDocument = ExportService.document(for: sessions, format: format)
        isExporting = true
    }

    private var deleteAllButton: some View {
        Button("Delete all practice data", role: .destructive) { resetPresented = true }
            .disabled(sessions.isEmpty)
            .accessibilityIdentifier("deleteAllPracticeDataButton")
    }
}
