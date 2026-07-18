import Foundation
import SwiftData

enum SessionStatus: String, Codable, CaseIterable {
    case inProgress, completed, interrupted
}

enum SessionEndReason: String, Codable {
    case timerExpired, userEnded, systemSleep, recoveredAfterLaunch
}

@Model
final class PracticeSession {
    @Attribute(.unique) var id: UUID
    var startedAt: Date
    var endedAt: Date?
    var durationSeconds: Int
    var statusRaw: String
    var endReasonRaw: String?
    var modeRaw: String
    var configurationJSON: Data
    var benchmarkID: String?
    var benchmarkVersion: Int?
    var randomSeed: UInt64
    var correctCount: Int
    var incorrectSubmissionCount: Int
    var activeElapsedMilliseconds: Int?
    var searchableText: String = ""

    @Relationship(deleteRule: .cascade, inverse: \QuestionAttempt.session)
    var attempts: [QuestionAttempt]

    init(configuration: PracticeConfiguration, seed: UInt64, startedAt: Date = .now) {
        id = UUID()
        self.startedAt = startedAt
        endedAt = nil
        durationSeconds = configuration.durationSeconds
        statusRaw = SessionStatus.inProgress.rawValue
        endReasonRaw = nil
        modeRaw = configuration.mode.rawValue
        configurationJSON = (try? JSONEncoder().encode(configuration)) ?? Data()
        benchmarkID = configuration.benchmarkID
        benchmarkVersion = configuration.benchmarkVersion
        randomSeed = seed
        correctCount = 0
        incorrectSubmissionCount = 0
        activeElapsedMilliseconds = nil
        searchableText = [
            configuration.mode.title,
            configuration.benchmarkID ?? "",
            configuration.mode == .targeted ? configuration.targetedPreset.title : "",
            ISO8601DateFormatter().string(from: startedAt)
        ].joined(separator: " ")
        attempts = []
    }

    var status: SessionStatus {
        get { SessionStatus(rawValue: statusRaw) ?? .interrupted }
        set { statusRaw = newValue.rawValue }
    }

    var endReason: SessionEndReason? {
        get { endReasonRaw.flatMap(SessionEndReason.init(rawValue:)) }
        set { endReasonRaw = newValue?.rawValue }
    }

    var mode: PracticeMode { PracticeMode(rawValue: modeRaw) ?? .classic }

    var configuration: PracticeConfiguration {
        (try? JSONDecoder().decode(PracticeConfiguration.self, from: configurationJSON)) ?? .classicDefault
    }

    var sortedAttempts: [QuestionAttempt] { attempts.sorted { $0.position < $1.position } }
    var isComparable: Bool { status == .completed }

    var completedAttempts: [QuestionAttempt] { attempts.filter(\.wasEventuallyCorrect) }

    var firstAttemptAccuracy: Double {
        let submitted = attempts.filter { !$0.submissions.isEmpty }
        guard !submitted.isEmpty else { return 0 }
        return Double(submitted.filter { $0.wasEventuallyCorrect && $0.incorrectAttempts == 0 }.count) / Double(submitted.count)
    }

    var submissionAccuracy: Double {
        let submissions = attempts.flatMap(\.submissions)
        guard !submissions.isEmpty else { return 0 }
        return Double(submissions.filter(\.isCorrect).count) / Double(submissions.count)
    }

    func rebuildSearchableText() {
        searchableText = [
            mode.title,
            benchmarkID ?? "",
            mode == .targeted ? configuration.targetedPreset.title : "",
            ISO8601DateFormatter().string(from: startedAt),
            attempts.flatMap { [$0.prompt, $0.categoryName] }.joined(separator: " ")
        ].joined(separator: " ")
    }

    func appendToSearchableText(for attempt: QuestionAttempt) {
        searchableText += " \(attempt.prompt) \(attempt.categoryName)"
    }
}

@Model
final class QuestionAttempt {
    @Attribute(.unique) var id: UUID
    var operationRaw: String
    var kindRaw: String
    var categoryKey: String
    var categoryName: String
    var leftOperandText: String
    var rightOperandText: String?
    var prompt: String
    var correctAnswerText: String
    var presentedAt: Date
    var answeredAt: Date?
    var responseTimeMilliseconds: Int?
    var incorrectAttempts: Int
    var wasEventuallyCorrect: Bool
    var isCensored: Bool = false
    var position: Int

    var session: PracticeSession?

    @Relationship(deleteRule: .cascade, inverse: \AnswerSubmission.attempt)
    var submissions: [AnswerSubmission]

    init(question: GeneratedQuestion, position: Int, presentedAt: Date = .now) {
        id = UUID()
        operationRaw = question.operation.rawValue
        kindRaw = question.kind.rawValue
        categoryKey = question.category.key
        categoryName = question.category.displayName
        leftOperandText = question.leftCanonical
        rightOperandText = question.rightCanonical
        prompt = question.prompt
        correctAnswerText = question.answerCanonical
        self.presentedAt = presentedAt
        answeredAt = nil
        responseTimeMilliseconds = nil
        incorrectAttempts = 0
        wasEventuallyCorrect = false
        isCensored = false
        self.position = position
        submissions = []
    }

    var operation: ArithmeticOperation { ArithmeticOperation(rawValue: operationRaw) ?? .addition }
    var kind: QuestionKind { QuestionKind(rawValue: kindRaw) ?? .standard }
    var correctAnswer: Decimal { DecimalText.parse(correctAnswerText, locale: Locale(identifier: "en_US_POSIX")) ?? 0 }
}

@Model
final class AnswerSubmission {
    @Attribute(.unique) var id: UUID
    var rawInput: String
    var normalizedAnswerText: String?
    var submittedAt: Date
    var elapsedMilliseconds: Int
    var isCorrect: Bool
    var attempt: QuestionAttempt?

    init(rawInput: String, normalizedAnswer: Decimal?, submittedAt: Date, elapsedMilliseconds: Int, isCorrect: Bool) {
        id = UUID()
        self.rawInput = rawInput
        normalizedAnswerText = normalizedAnswer.map(DecimalText.canonical)
        self.submittedAt = submittedAt
        self.elapsedMilliseconds = elapsedMilliseconds
        self.isCorrect = isCorrect
    }
}

@Model
final class SkillEstimate {
    @Attribute(.unique) var categoryKey: String
    var categoryName: String
    var operationRaw: String
    var estimatedAccuracy: Double
    var estimatedResponseMilliseconds: Double
    var uncertainty: Double
    var deterioration: Double
    var lastPractisedAt: Date?
    var attemptCount: Int
    var algorithmVersion: Int

    init(
        category: QuestionCategory,
        estimatedAccuracy: Double,
        estimatedResponseMilliseconds: Double,
        uncertainty: Double,
        deterioration: Double,
        lastPractisedAt: Date?,
        attemptCount: Int,
        algorithmVersion: Int = 1
    ) {
        categoryKey = category.key
        categoryName = category.displayName
        operationRaw = category.operation.rawValue
        self.estimatedAccuracy = estimatedAccuracy
        self.estimatedResponseMilliseconds = estimatedResponseMilliseconds
        self.uncertainty = uncertainty
        self.deterioration = deterioration
        self.lastPractisedAt = lastPractisedAt
        self.attemptCount = attemptCount
        self.algorithmVersion = algorithmVersion
    }
}
