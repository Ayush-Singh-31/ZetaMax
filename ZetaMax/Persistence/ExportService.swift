import Foundation
import SwiftUI
import UniformTypeIdentifiers

enum ExportFormat: String, CaseIterable, Identifiable {
    case csv, json
    var id: String { rawValue }
}

struct ExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText, .json] }
    var data: Data

    init(data: Data = Data()) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

enum ExportService {
    static func document(for sessions: [PracticeSession], format: ExportFormat) -> ExportDocument {
        switch format {
        case .csv:
            return ExportDocument(data: csv(sessions: sessions).data(using: .utf8) ?? Data())
        case .json:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            return ExportDocument(data: (try? encoder.encode(ExportEnvelope(sessions: sessions))) ?? Data())
        }
    }

    static func csv(sessions: [PracticeSession]) -> String {
        let headers = [
            "schema_version", "session_id", "started_at", "ended_at", "status", "end_reason", "mode",
            "duration_seconds", "benchmark_id", "benchmark_version", "seed", "position", "operation", "kind",
            "category", "left_operand", "right_operand", "prompt", "correct_answer", "presented_at", "answered_at",
            "response_time_ms", "incorrect_attempts", "eventually_correct", "submitted_answers"
        ]
        var rows = [headers.map(csvField).joined(separator: ",")]
        let iso = ISO8601DateFormatter()
        for session in sessions.sorted(by: { $0.startedAt < $1.startedAt }) {
            for attempt in session.sortedAttempts {
                let submissions = attempt.submissions.sorted { $0.submittedAt < $1.submittedAt }.map(\.rawInput).joined(separator: "|")
                let endedAt = session.endedAt.map { iso.string(from: $0) } ?? ""
                let benchmarkVersion = session.benchmarkVersion.map { String($0) } ?? ""
                let answeredAt = attempt.answeredAt.map { iso.string(from: $0) } ?? ""
                let responseTime = attempt.responseTimeMilliseconds.map { String($0) } ?? ""
                var fields: [String] = []
                fields.append(contentsOf: ["1", session.id.uuidString, iso.string(from: session.startedAt), endedAt])
                fields.append(contentsOf: [session.statusRaw, session.endReasonRaw ?? "", session.modeRaw, String(session.durationSeconds)])
                fields.append(contentsOf: [session.benchmarkID ?? "", benchmarkVersion, String(session.randomSeed), String(attempt.position)])
                fields.append(contentsOf: [attempt.operationRaw, attempt.kindRaw, attempt.categoryKey, attempt.leftOperandText])
                fields.append(contentsOf: [attempt.rightOperandText ?? "", attempt.prompt, attempt.correctAnswerText, iso.string(from: attempt.presentedAt)])
                fields.append(contentsOf: [answeredAt, responseTime, String(attempt.incorrectAttempts), String(attempt.wasEventuallyCorrect), submissions])
                rows.append(fields.map(csvField).joined(separator: ","))
            }
        }
        return rows.joined(separator: "\n") + "\n"
    }

    private static func csvField(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}

private struct ExportEnvelope: Encodable {
    let schemaVersion = 1
    let exportedAt = Date.now
    let sessions: [ExportSession]

    init(sessions: [PracticeSession]) {
        self.sessions = sessions.sorted { $0.startedAt < $1.startedAt }.map(ExportSession.init)
    }
}

private struct ExportSession: Encodable {
    let id: UUID
    let startedAt: Date
    let endedAt: Date?
    let durationSeconds: Int
    let status: String
    let endReason: String?
    let mode: String
    let configuration: PracticeConfiguration
    let benchmarkID: String?
    let benchmarkVersion: Int?
    let randomSeed: UInt64
    let correctCount: Int
    let incorrectSubmissionCount: Int
    let attempts: [ExportAttempt]

    init(_ session: PracticeSession) {
        id = session.id
        startedAt = session.startedAt
        endedAt = session.endedAt
        durationSeconds = session.durationSeconds
        status = session.statusRaw
        endReason = session.endReasonRaw
        mode = session.modeRaw
        configuration = session.configuration
        benchmarkID = session.benchmarkID
        benchmarkVersion = session.benchmarkVersion
        randomSeed = session.randomSeed
        correctCount = session.correctCount
        incorrectSubmissionCount = session.incorrectSubmissionCount
        attempts = session.sortedAttempts.map(ExportAttempt.init)
    }
}

private struct ExportAttempt: Encodable {
    let id: UUID
    let position: Int
    let operation: String
    let kind: String
    let categoryKey: String
    let categoryName: String
    let leftOperand: String
    let rightOperand: String?
    let prompt: String
    let correctAnswer: String
    let presentedAt: Date
    let answeredAt: Date?
    let responseTimeMilliseconds: Int?
    let incorrectAttempts: Int
    let wasEventuallyCorrect: Bool
    let submissions: [ExportSubmission]

    init(_ attempt: QuestionAttempt) {
        id = attempt.id
        position = attempt.position
        operation = attempt.operationRaw
        kind = attempt.kindRaw
        categoryKey = attempt.categoryKey
        categoryName = attempt.categoryName
        leftOperand = attempt.leftOperandText
        rightOperand = attempt.rightOperandText
        prompt = attempt.prompt
        correctAnswer = attempt.correctAnswerText
        presentedAt = attempt.presentedAt
        answeredAt = attempt.answeredAt
        responseTimeMilliseconds = attempt.responseTimeMilliseconds
        incorrectAttempts = attempt.incorrectAttempts
        wasEventuallyCorrect = attempt.wasEventuallyCorrect
        submissions = attempt.submissions.sorted { $0.submittedAt < $1.submittedAt }.map(ExportSubmission.init)
    }
}

private struct ExportSubmission: Encodable {
    let rawInput: String
    let normalizedAnswer: String?
    let submittedAt: Date
    let elapsedMilliseconds: Int
    let isCorrect: Bool

    init(_ submission: AnswerSubmission) {
        rawInput = submission.rawInput
        normalizedAnswer = submission.normalizedAnswerText
        submittedAt = submission.submittedAt
        elapsedMilliseconds = submission.elapsedMilliseconds
        isCorrect = submission.isCorrect
    }
}
