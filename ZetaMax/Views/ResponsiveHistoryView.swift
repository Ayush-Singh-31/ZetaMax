import AppKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

enum HistoryLayoutMode: Equatable {
    case compact
    case wide
}

enum HistoryLayoutPolicy {
    static let wideThreshold: CGFloat = 720
    static func mode(for width: CGFloat) -> HistoryLayoutMode {
        width >= wideThreshold ? .wide : .compact
    }
}

struct HistoryView: View {
    let repository: SwiftDataRepository
    @Bindable var analyticsStore: AnalyticsStore
    @Query(sort: \PracticeSession.startedAt, order: .reverse) private var sessions: [PracticeSession]
    @State private var selectedID: UUID?
    @State private var searchText = ""
    @State private var effectiveSearchText = ""
    @State private var deleteCandidate: PracticeSession?
    @State private var exportDocument: ExportDocument?
    @State private var exportFormat: ExportFormat = .csv
    @State private var isExporting = false
    @State private var messageTitle = "ZetaMax"
    @State private var message: String?

    private var selected: PracticeSession? { sessions.first { $0.id == selectedID } }
    private var filteredSessions: [PracticeSession] {
        let query = effectiveSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return sessions }
        return sessions.filter { session in
            let searchable = [
                session.mode.title,
                session.benchmarkID ?? "",
                session.startedAt.formatted(date: .long, time: .shortened),
                session.searchableText
            ].joined(separator: " ")
            return searchable.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let layout = HistoryLayoutPolicy.mode(for: geometry.size.width)
            Group {
                if layout == .wide {
                    HStack(spacing: 0) {
                        sessionList(layout: layout)
                            .frame(width: min(max(geometry.size.width * 0.31, 250), 310))
                        Divider()
                        detailOrPlaceholder(layout: layout)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else if selected != nil {
                    detailOrPlaceholder(layout: layout)
                } else {
                    sessionList(layout: layout)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: ZetaTheme.cornerRadius, style: .continuous))
            .zetaLayeredSurface(cornerRadius: ZetaTheme.cornerRadius)
            .padding(12)
            .background(ZetaBackground())
            .task(id: layout) {
                if layout == .wide { selectNewestIfNeeded() }
            }
        }
        .navigationTitle("History")
        .onAppear { analyticsStore.requestHistoryBaseline() }
        .task(id: searchText) {
            if !searchText.isEmpty {
                try? await Task.sleep(for: .milliseconds(180))
            }
            guard !Task.isCancelled else { return }
            effectiveSearchText = searchText
        }
        .toolbar {
            Menu("Export all", systemImage: "square.and.arrow.up") {
                Button("CSV") { export(sessions, as: .csv) }
                Button("JSON") { export(sessions, as: .json) }
            }
            .disabled(sessions.isEmpty)
            .accessibilityIdentifier("historyExportAll")
        }
        .onChange(of: sessions.map(\.id)) { _, ids in
            if let selectedID, !ids.contains(selectedID) { self.selectedID = nil }
        }
        .confirmationDialog("Delete this session?", isPresented: deletePresented) {
            Button("Delete session", role: .destructive) { deleteSelectedSession() }
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

    private func sessionList(layout: HistoryLayoutMode) -> some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                if layout == .compact {
                    ZetaPageHeader(title: "History", systemImage: "clock.arrow.circlepath")
                } else {
                    Text("Sessions").font(.title2.bold())
                    Text("\(filteredSessions.count) of \(sessions.count)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                TextField("Search date, mode, benchmark or question", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("historySearchField")
            }
            .padding(16)

            List(selection: $selectedID) {
                ForEach(filteredSessions) { session in
                    SessionHistoryRow(session: session)
                        .tag(session.id)
                        .accessibilityIdentifier("historySessionRow-\(session.id.uuidString)")
                        .contentShape(Rectangle())
                        .onTapGesture { selectedID = session.id }
                        .contextMenu {
                            Button("Export CSV") { export([session], as: .csv) }
                            Button("Export JSON") { export([session], as: .json) }
                            Divider()
                            Button("Delete", role: .destructive) { deleteCandidate = session }
                        }
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay {
                if sessions.isEmpty {
                    ContentUnavailableView("No sessions", systemImage: "clock", description: Text("Completed sessions appear here."))
                } else if filteredSessions.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                }
            }
            .accessibilityIdentifier(layout == .compact ? "historyCompactList" : "historyWideList")
        }
    }

    @ViewBuilder
    private func detailOrPlaceholder(layout: HistoryLayoutMode) -> some View {
        if let selected {
            SessionDetailView(
                session: selected,
                baseline: analyticsStore.historyBaseline,
                isCompact: layout == .compact,
                onBack: layout == .compact ? { selectedID = nil } : nil,
                onExport: { export([selected], as: $0) },
                onDelete: { deleteCandidate = selected }
            )
            .id(selected.id)
        } else {
            ContentUnavailableView("Select a session", systemImage: "list.bullet.rectangle")
        }
    }

    private func selectNewestIfNeeded() {
        if let selectedID, sessions.contains(where: { $0.id == selectedID }) { return }
        selectedID = sessions.first?.id
    }

    private var deletePresented: Binding<Bool> {
        Binding(get: { deleteCandidate != nil }, set: { if !$0 { deleteCandidate = nil } })
    }

    private func deleteSelectedSession() {
        guard let candidate = deleteCandidate else { return }
        do {
            try repository.delete(candidate)
            if selectedID == candidate.id { selectedID = nil }
            messageTitle = "Session deleted"
            message = "The session and its question timings were removed. Adaptive estimates were rebuilt."
        } catch {
            messageTitle = "Couldn’t delete session"
            message = error.localizedDescription
        }
        deleteCandidate = nil
    }

    private func export(_ sessions: [PracticeSession], as format: ExportFormat) {
        do {
            exportFormat = format
            exportDocument = try ExportService.document(for: sessions, format: format)
            isExporting = true
        } catch {
            messageTitle = "Export failed"
            message = error.localizedDescription
        }
    }

    private var dateStamp: String { Date.now.formatted(.dateTime.year().month().day()) }
}

private struct SessionHistoryRow: View {
    let session: PracticeSession

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(session.startedAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                    .font(.headline).lineLimit(1)
                Spacer(minLength: 8)
                Text("\(session.correctCount)").font(.title3.bold()).monospacedDigit()
            }
            HStack(spacing: 6) {
                Label(session.mode.title, systemImage: modeImage)
                Text("· \(DurationText.compact(session.durationSeconds))")
                if session.status == .interrupted {
                    Image(systemName: "moon.zzz.fill").foregroundStyle(ZetaTheme.caution).help("Interrupted")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 5)
    }

    private var modeImage: String {
        switch session.mode {
        case .classic: "number"
        case .adaptive: "scope"
        case .targeted: "target"
        case .benchmark: "stopwatch"
        }
    }
}

private struct SessionDetailView: View {
    let session: PracticeSession
    let baseline: TimingBaselineResult
    let isCompact: Bool
    let onBack: (() -> Void)?
    let onExport: (ExportFormat) -> Void
    let onDelete: () -> Void
    @State private var selectedAttemptID: UUID?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                LazyVGrid(columns: [GridItem(.adaptive(minimum: isCompact ? 112 : 128, maximum: 220))], spacing: 10) {
                    ZetaMetricTile(title: "Completed", value: String(completedTimings.count), tint: ZetaTheme.brand)
                    ZetaMetricTile(title: "Questions/min", value: String(format: "%.1f", questionsPerMinute), tint: ZetaTheme.cyan)
                    ZetaMetricTile(title: "Median", value: medianText, tint: ZetaTheme.caution)
                    ZetaMetricTile(title: "P90", value: p90Text, tint: Color(red: 0.62, green: 0.34, blue: 0.92))
                }

                if let selectedAttempt { attemptInspector(selectedAttempt) }

                HStack {
                    Text("Question timings").font(.title3.bold())
                    Spacer()
                    Text("\(session.sortedAttempts.count) total").font(.caption).foregroundStyle(.secondary)
                }

                Table(session.sortedAttempts, selection: $selectedAttemptID) {
                    TableColumn("#") { attempt in
                        Text("\(attempt.position + 1)").foregroundStyle(.secondary).monospacedDigit()
                    }.width(30)
                    TableColumn("Question") { attempt in
                        Text(attempt.prompt).font(.body.monospacedDigit()).lineLimit(1).help(attempt.prompt)
                    }.width(min: 90, ideal: 160, max: 280)
                    TableColumn("Answer") { attempt in
                        Text(attempt.correctAnswerText).bold().monospacedDigit().lineLimit(1)
                    }.width(min: 54, ideal: 70, max: 84)
                    TableColumn("Time") { attempt in
                        Text(responseTime(attempt)).monospacedDigit().foregroundStyle(.secondary)
                    }.width(min: 58, ideal: 68, max: 78)
                    TableColumn("Vs typical") { attempt in
                        Text(relativeTime(attempt)).monospacedDigit().foregroundStyle(relativeColor(attempt))
                    }.width(min: 70, ideal: 80, max: 92)
                }
                .tableStyle(.inset(alternatesRowBackgrounds: true))
                .frame(minHeight: 220, idealHeight: 300)
                .accessibilityIdentifier("attemptTable")
            }
            .padding(isCompact ? 16 : 22)
        }
        .background(Color.clear)
        .accessibilityIdentifier("historySessionDetail")
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 16) { heading; Spacer(minLength: 10); actions }
            VStack(alignment: .leading, spacing: 12) { heading; actions }
        }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let onBack {
                Button(action: onBack) { Label("All sessions", systemImage: "chevron.left") }
                    .buttonStyle(.plain)
                    .foregroundStyle(ZetaTheme.brand)
                    .accessibilityIdentifier("historyBackButton")
            }
            Text(session.startedAt, format: .dateTime.weekday(.wide).month(.wide).day().year())
                .font(.title.bold()).lineLimit(1).minimumScaleFactor(0.74)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 7) { metadata }
                VStack(alignment: .leading, spacing: 7) { metadata }
            }
        }
    }

    @ViewBuilder private var metadata: some View {
        ZetaStatusChip(title: session.mode.title, color: ZetaTheme.brand)
        ZetaStatusChip(title: DurationText.compact(session.durationSeconds), color: .secondary)
        if session.status == .interrupted { ZetaStatusChip(title: "Interrupted", color: ZetaTheme.caution, systemImage: "moon.zzz.fill") }
        HStack(spacing: 5) {
            Text("Seed \(session.randomSeed)").lineLimit(1).truncationMode(.middle).help("Seed \(session.randomSeed)")
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(String(session.randomSeed), forType: .string)
            } label: { Image(systemName: "doc.on.doc") }
            .buttonStyle(.plain).help("Copy random seed")
        }
        .font(.caption).foregroundStyle(.secondary)
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Menu("Export", systemImage: "square.and.arrow.up") {
                Button("CSV") { onExport(.csv) }
                Button("JSON") { onExport(.json) }
            }
            .accessibilityIdentifier("historyDetailExport")
            Button("Delete", role: .destructive, action: onDelete)
        }
    }

    private var selectedAttempt: QuestionAttempt? { session.sortedAttempts.first { $0.id == selectedAttemptID } }

    private func attemptInspector(_ attempt: QuestionAttempt) -> some View {
        ZetaCard {
            VStack(alignment: .leading, spacing: 10) {
                ViewThatFits(in: .horizontal) {
                    HStack { Text("Question \(attempt.position + 1)").font(.headline); Text(attempt.prompt).font(.headline.monospacedDigit()); Spacer(); Text("Answer \(attempt.correctAnswerText)").font(.callout.bold().monospacedDigit()) }
                    VStack(alignment: .leading, spacing: 6) { Text("Question \(attempt.position + 1) · \(attempt.prompt)").font(.headline.monospacedDigit()); Text("Answer \(attempt.correctAnswerText)").font(.callout.bold().monospacedDigit()) }
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { inspectorChips(attempt); Spacer() }
                    VStack(alignment: .leading, spacing: 7) { inspectorChips(attempt) }
                }
                Text(attempt.categoryName).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private func inspectorChips(_ attempt: QuestionAttempt) -> some View {
        ZetaStatusChip(title: responseTime(attempt), color: ZetaTheme.brand, systemImage: "timer")
        ZetaStatusChip(title: relativeTime(attempt), color: relativeColor(attempt), systemImage: "chart.bar")
        ZetaStatusChip(title: difficultyText(attempt), color: ZetaTheme.caution, systemImage: "gauge.medium")
        ZetaStatusChip(title: "Position \(attempt.position + 1)", color: .secondary, systemImage: "list.number")
    }

    private var completedTimings: [Int] {
        session.sortedAttempts.compactMap { $0.wasEventuallyCorrect ? $0.responseTimeMilliseconds : nil }
    }
    private var medianText: String { Statistics.median(completedTimings.map(Double.init)).map { String(format: "%.2fs", $0 / 1_000) } ?? "—" }
    private var p90Text: String {
        guard completedTimings.count >= Statistics.reliableTailSampleCount else { return "—" }
        return Statistics.percentile(completedTimings.map(Double.init), 0.9)
            .map { String(format: "%.2fs", $0 / 1_000) } ?? "—"
    }
    private var questionsPerMinute: Double {
        let elapsed = Double(session.activeElapsedMilliseconds ?? session.durationSeconds * 1_000) / 1_000
        return elapsed > 0 ? Double(completedTimings.count) / (elapsed / 60) : 0
    }
    private func categoryBaseline(_ attempt: QuestionAttempt) -> Double { baseline.value(for: attempt.categoryKey) }
    private func responseTime(_ attempt: QuestionAttempt) -> String { attempt.responseTimeMilliseconds.map { String(format: "%.2fs", Double($0) / 1_000) } ?? "—" }
    private func relativeTime(_ attempt: QuestionAttempt) -> String {
        guard let milliseconds = attempt.responseTimeMilliseconds else { return "—" }
        return String(format: "%.1f×", Double(milliseconds) / categoryBaseline(attempt))
    }
    private func relativeColor(_ attempt: QuestionAttempt) -> Color {
        guard let milliseconds = attempt.responseTimeMilliseconds else { return .secondary }
        let multiple = Double(milliseconds) / categoryBaseline(attempt)
        if multiple >= 1.25 { return ZetaTheme.caution }
        if multiple <= 0.8 { return ZetaTheme.positive }
        return .secondary
    }
    private func difficultyText(_ attempt: QuestionAttempt) -> String {
        let global = max(baseline.globalMilliseconds, 1)
        return "Difficulty \(Int((categoryBaseline(attempt) / global * 100).rounded()))"
    }
}
