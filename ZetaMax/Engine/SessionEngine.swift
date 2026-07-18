import Foundation
import Observation

protocol MonotonicClock: Sendable {
    var nowSeconds: TimeInterval { get }
}

struct SystemMonotonicClock: MonotonicClock {
    var nowSeconds: TimeInterval { ProcessInfo.processInfo.systemUptime }
}

enum SessionPhase: Equatable {
    case idle, running, results
}

@MainActor
@Observable
final class SessionEngine {
    var phase: SessionPhase = .idle
    var configuration: PracticeConfiguration = .classicDefault
    var currentQuestion: GeneratedQuestion?
    var answerText = ""
    var score = 0
    var remainingSeconds: TimeInterval = 0
    var errorMessage: String?
    var completedSession: PracticeSession?

    @ObservationIgnored private let repository: AttemptRepository
    @ObservationIgnored private let clock: MonotonicClock
    @ObservationIgnored private var generator: QuestionGenerating?
    @ObservationIgnored private var session: PracticeSession?
    @ObservationIgnored private var currentAttempt: QuestionAttempt?
    @ObservationIgnored private var sessionStartMonotonic: TimeInterval = 0
    @ObservationIgnored private var attemptStartMonotonic: TimeInterval = 0
    @ObservationIgnored private var deadline: TimeInterval = 0
    @ObservationIgnored private var timerTask: Task<Void, Never>?
    @ObservationIgnored private var categoryWeights: [String: Double] = [:]
    @ObservationIgnored private var recommendedCategoryKey: String?
    @ObservationIgnored private var submittingAttemptID: UUID?

    init(repository: AttemptRepository, clock: MonotonicClock = SystemMonotonicClock()) {
        self.repository = repository
        self.clock = clock
    }

    func applyBenchmark(_ profile: BenchmarkProfile) {
        guard phase == .idle else { return }
        configuration = profile.configuration
    }

    func prepareRecommendedSession(categoryKey: String?) {
        var recommended = PracticeConfiguration.classicDefault
        recommended.mode = .adaptive
        recommended.durationSeconds = 45
        if let operationName = categoryKey?.split(separator: "/").first,
           let operation = ArithmeticOperation(rawValue: String(operationName)),
           [.addition, .subtraction, .multiplication, .division].contains(operation) {
            recommended.operations = [operation]
        }
        configuration = recommended
        recommendedCategoryKey = categoryKey
    }

    func start(seed: UInt64? = nil) {
        guard phase == .idle || phase == .results else { return }
        errorMessage = nil
        let validated = configuration.validated
        configuration = validated
        // SwiftData persists the seed as a signed 64-bit database integer.
        let seed = seed ?? UInt64.random(in: 0...UInt64(Int64.max))
        do {
            let now = Date.now
            let session = try repository.createSession(configuration: validated, seed: seed, startedAt: now)
            self.session = session
            generator = QuestionGenerator(seed: seed)
            score = 0
            answerText = ""
            completedSession = nil
            sessionStartMonotonic = clock.nowSeconds
            deadline = sessionStartMonotonic + Double(validated.durationSeconds)
            remainingSeconds = Double(validated.durationSeconds)
            if validated.mode == .adaptive {
                let estimates = try repository.fetchSkillEstimates()
                categoryWeights = AdaptiveModel.categoryWeights(estimates: estimates, focus: validated.adaptiveFocus)
                if let recommendedCategoryKey { categoryWeights[recommendedCategoryKey] = 10 }
            } else {
                categoryWeights = [:]
            }
            phase = .running
            presentNextQuestion()
            startTimer()
        } catch {
            errorMessage = error.localizedDescription
            phase = .idle
        }
    }

    func answerDidChange(_ rawInput: String) {
        guard let attempt = currentAttempt,
              let normalized = DecimalText.parse(rawInput),
              normalized == attempt.correctAnswer else { return }
        completeCorrectAnswer(rawInput: rawInput, normalized: normalized, expectedAttemptID: attempt.id)
    }

    func submitCurrentAnswer() {
        guard phase == .running,
              let session,
              let attempt = currentAttempt,
              submittingAttemptID != attempt.id else { return }
        let rawInput = answerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawInput.isEmpty else { return }
        let normalized = DecimalText.parse(rawInput)
        if normalized == attempt.correctAnswer, let normalized {
            completeCorrectAnswer(
                rawInput: rawInput,
                normalized: normalized,
                expectedAttemptID: attempt.id
            )
            return
        }

        tick()
        guard phase == .running, currentAttempt?.id == attempt.id else { return }
        let responseMilliseconds = max(0, Int((clock.nowSeconds - attemptStartMonotonic) * 1_000))
        submittingAttemptID = attempt.id
        defer { submittingAttemptID = nil }
        let submission = AnswerSubmission(
            rawInput: rawInput,
            normalizedAnswer: normalized,
            submittedAt: .now,
            elapsedMilliseconds: responseMilliseconds,
            isCorrect: false
        )
        do {
            try repository.addSubmission(submission, to: attempt, session: session)
            answerText = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func completeCorrectAnswer(rawInput: String, normalized: Decimal, expectedAttemptID: UUID) {
        guard phase == .running,
              let session,
              let attempt = currentAttempt,
              attempt.id == expectedAttemptID,
              submittingAttemptID != attempt.id else { return }
        tick()
        guard phase == .running,
              currentAttempt?.id == attempt.id else { return }

        let nowMonotonic = clock.nowSeconds
        let responseMilliseconds = max(0, Int((nowMonotonic - attemptStartMonotonic) * 1_000))
        guard normalized == attempt.correctAnswer else { return }
        submittingAttemptID = attempt.id
        defer { submittingAttemptID = nil }
        let submission = AnswerSubmission(
            rawInput: rawInput,
            normalizedAnswer: normalized,
            submittedAt: .now,
            elapsedMilliseconds: responseMilliseconds,
            isCorrect: true
        )
        attempt.wasEventuallyCorrect = true
        attempt.answeredAt = submission.submittedAt
        attempt.responseTimeMilliseconds = responseMilliseconds
        do {
            try repository.addSubmission(submission, to: attempt, session: session)
            answerText = ""
            score = session.correctCount
            refreshAdaptiveWeightsIfNeeded()
            presentNextQuestion()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func tick() {
        guard phase == .running else { return }
        remainingSeconds = max(0, deadline - clock.nowSeconds)
        if remainingSeconds <= 0 {
            finish(status: .completed, reason: .timerExpired)
        }
    }

    func endEarly() {
        guard phase == .running else { return }
        finish(status: .interrupted, reason: .userEnded)
    }

    func interruptForSleep() {
        guard phase == .running else { return }
        finish(status: .interrupted, reason: .systemSleep)
    }

    func dismissResults() {
        timerTask?.cancel()
        phase = .idle
        session = nil
        currentAttempt = nil
        currentQuestion = nil
        answerText = ""
        recommendedCategoryKey = nil
    }

    private func presentNextQuestion() {
        guard let session, let generator else { return }
        let question = generator.nextQuestion(configuration: configuration, categoryWeights: categoryWeights)
        let attempt = QuestionAttempt(question: question, position: session.attempts.count, presentedAt: .now)
        do {
            try repository.addAttempt(attempt, to: session)
            currentQuestion = question
            currentAttempt = attempt
            attemptStartMonotonic = clock.nowSeconds
            answerText = ""
        } catch {
            errorMessage = error.localizedDescription
            finish(status: .interrupted, reason: .userEnded)
        }
    }

    private func startTimer() {
        timerTask?.cancel()
        timerTask = Task { @MainActor [weak self] in
            while !Task.isCancelled, self?.phase == .running {
                try? await Task.sleep(for: .milliseconds(50))
                self?.tick()
            }
        }
    }

    private func refreshAdaptiveWeightsIfNeeded() {
        guard configuration.mode == .adaptive else { return }
        do {
            let estimates = AdaptiveModel.estimates(from: try repository.fetchSessions())
            categoryWeights = AdaptiveModel.categoryWeights(estimates: estimates, focus: configuration.adaptiveFocus)
            if let recommendedCategoryKey { categoryWeights[recommendedCategoryKey] = 10 }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func finish(status: SessionStatus, reason: SessionEndReason) {
        guard phase == .running, let session else { return }
        timerTask?.cancel()
        let elapsed = max(0, min(Double(configuration.durationSeconds), clock.nowSeconds - sessionStartMonotonic))
        if status == .completed,
           reason == .timerExpired,
           let currentAttempt,
           !currentAttempt.wasEventuallyCorrect {
            currentAttempt.isCensored = true
            currentAttempt.responseTimeMilliseconds = max(
                0,
                Int((deadline - attemptStartMonotonic) * 1_000)
            )
        }
        do {
            try repository.finish(
                session,
                status: status,
                reason: reason,
                at: .now,
                elapsedMilliseconds: Int(elapsed * 1_000)
            )
            let estimates = AdaptiveModel.estimates(from: try repository.fetchSessions())
            try repository.replaceSkillEstimates(with: estimates)
            score = session.correctCount
            completedSession = session
            remainingSeconds = 0
            phase = .results
        } catch {
            errorMessage = error.localizedDescription
            phase = .results
        }
    }
}
