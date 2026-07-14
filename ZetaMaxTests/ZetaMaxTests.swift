import Foundation
import SwiftData
import XCTest
@testable import ZetaMax

final class QuestionGeneratorTests: XCTestCase {
    func testSeededGenerationIsDeterministic() {
        let first = QuestionGenerator(seed: 42)
        let second = QuestionGenerator(seed: 42)
        let lhs = (0..<50).map { _ in first.nextQuestion(configuration: .classicDefault, categoryWeights: [:]) }
        let rhs = (0..<50).map { _ in second.nextQuestion(configuration: .classicDefault, categoryWeights: [:]) }
        XCTAssertEqual(lhs, rhs)
    }

    func testDivisionAlwaysHasAnExactNonzeroDivisor() {
        var configuration = PracticeConfiguration.classicDefault
        configuration.operations = [.division]
        configuration.multiplicationLeft = OperandRange(-4, 4)
        configuration.multiplicationRight = OperandRange(2, 50)
        let generator = QuestionGenerator(seed: 7)
        for _ in 0..<500 {
            let question = generator.nextQuestion(configuration: configuration, categoryWeights: [:])
            XCTAssertNotEqual(question.rightOperand, 0)
            XCTAssertEqual(question.leftOperand / (question.rightOperand ?? 1), question.correctAnswer)
        }
    }

    func testTargetedNegativeSubtractionIsNegative() {
        var configuration = PracticeConfiguration.classicDefault
        configuration.mode = .targeted
        configuration.targetedPreset = .negativeSubtraction
        let generator = QuestionGenerator(seed: 11)
        for _ in 0..<100 {
            let question = generator.nextQuestion(configuration: configuration, categoryWeights: [:])
            XCTAssertLessThan(question.correctAnswer, 0)
        }
    }

    func testDecimalAndPercentageAnswersHaveAtMostTwoPlaces() {
        for preset in [TargetedPreset.decimalArithmetic, .percentages] {
            var configuration = PracticeConfiguration.classicDefault
            configuration.mode = .targeted
            configuration.targetedPreset = preset
            let generator = QuestionGenerator(seed: 99)
            for _ in 0..<250 {
                let text = generator.nextQuestion(configuration: configuration, categoryWeights: [:]).answerCanonical
                XCTAssertLessThanOrEqual(text.split(separator: ".").dropFirst().first?.count ?? 0, 2)
            }
        }
    }

    func testDecimalInputNormalization() {
        XCTAssertEqual(DecimalText.parse(" -1.50 "), Decimal(string: "-1.5"))
        XCTAssertEqual(DecimalText.parse(".25"), Decimal(string: "0.25"))
        XCTAssertNil(DecimalText.parse("1/2"))
        XCTAssertNil(DecimalText.parse("--2"))
    }

    func testBenchmarkProfilesAreVersionedAndLocked() {
        XCTAssertEqual(BenchmarkProfile.builtIns.map(\.durationSeconds), [30, 60, 120, 300, 600])
        let standard = BenchmarkProfile.builtIns.first { $0.durationSeconds == 120 }!.configuration
        XCTAssertEqual(standard.mode, .benchmark)
        XCTAssertEqual(standard.operations, [.addition, .subtraction, .multiplication, .division])
        XCTAssertEqual(standard.additionLeft, OperandRange(2, 100))
        XCTAssertEqual(standard.multiplicationLeft, OperandRange(2, 12))
        XCTAssertEqual(standard.benchmarkVersion, 1)
    }
}

@MainActor
final class PersistenceAndAnalyticsTests: XCTestCase {
    func testPersistenceRelationshipsMetricsAndExports() throws {
        let container = try DataStore.makeContainer(inMemory: true)
        let repository = SwiftDataRepository(context: container.mainContext)
        let session = try repository.createSession(configuration: .classicDefault, seed: 1, startedAt: Date(timeIntervalSince1970: 100))
        let question = GeneratedQuestion(
            operation: .multiplication,
            kind: .standard,
            category: QuestionCategory(key: "multiplication/1-digit-x-1-digit", displayName: "Multiplication · 1-digit × 1-digit", operation: .multiplication),
            leftOperand: 7,
            rightOperand: 8,
            prompt: "7 × 8",
            correctAnswer: 56
        )
        let attempt = QuestionAttempt(question: question, position: 0, presentedAt: Date(timeIntervalSince1970: 101))
        try repository.addAttempt(attempt, to: session)
        try repository.addSubmission(AnswerSubmission(rawInput: "54", normalizedAnswer: 54, submittedAt: Date(timeIntervalSince1970: 102), elapsedMilliseconds: 1_000, isCorrect: false), to: attempt, session: session)
        attempt.wasEventuallyCorrect = true
        attempt.answeredAt = Date(timeIntervalSince1970: 103)
        attempt.responseTimeMilliseconds = 2_000
        try repository.addSubmission(AnswerSubmission(rawInput: "56", normalizedAnswer: 56, submittedAt: Date(timeIntervalSince1970: 103), elapsedMilliseconds: 2_000, isCorrect: true), to: attempt, session: session)
        try repository.finish(session, status: .completed, reason: .timerExpired, at: Date(timeIntervalSince1970: 220), elapsedMilliseconds: 120_000)

        let fetched = try repository.fetchSessions()
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched[0].attempts.count, 1)
        XCTAssertEqual(fetched[0].attempts[0].submissions.count, 2)
        XCTAssertEqual(fetched[0].correctCount, 1)
        XCTAssertEqual(fetched[0].incorrectSubmissionCount, 1)

        let snapshot = AnalyticsEngine.snapshot(sessions: fetched)
        XCTAssertEqual(snapshot.completedCount, 1)
        XCTAssertEqual(snapshot.medianMilliseconds, 2_000)
        XCTAssertEqual(snapshot.p90Milliseconds, 2_000)
        XCTAssertEqual(snapshot.consistency, 100)
        XCTAssertEqual(snapshot.heatmap.first?.left, 7)
        XCTAssertEqual(snapshot.slowestCompletions.first?.responseMilliseconds, 2_000)

        let csv = ExportService.csv(sessions: fetched)
        XCTAssertTrue(csv.contains("\"7 × 8\""))
        XCTAssertTrue(csv.contains("\"54|56\""))
        let json = ExportService.document(for: fetched, format: .json).data
        let object = try JSONSerialization.jsonObject(with: json) as? [String: Any]
        XCTAssertEqual(object?["schemaVersion"] as? Int, 1)
    }

    func testRecoveryAndCascadeDeletion() throws {
        let container = try DataStore.makeContainer(inMemory: true)
        let repository = SwiftDataRepository(context: container.mainContext)
        let session = try repository.createSession(configuration: .classicDefault, seed: 2, startedAt: .now)
        try repository.recoverInterruptedSessions()
        XCTAssertEqual(session.status, .interrupted)
        XCTAssertEqual(session.endReason, .recoveredAfterLaunch)
        try repository.delete(session)
        XCTAssertTrue(try repository.fetchSessions().isEmpty)
    }

    func testOnDiskResetDeletesRelationshipGraphAndSurvivesReopen() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "ZetaMax-reset-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appending(path: "Test.store")

        do {
            let container = try DataStore.makeContainer(storeURL: storeURL)
            let repository = SwiftDataRepository(context: container.mainContext)
            let session = try repository.createSession(configuration: .classicDefault, seed: 31, startedAt: .now)
            let attempt = QuestionAttempt(question: testQuestion(prompt: "7 × 8", answer: 56), position: 0)
            try repository.addAttempt(attempt, to: session)
            try repository.addSubmission(
                AnswerSubmission(rawInput: "54", normalizedAnswer: 54, submittedAt: .now, elapsedMilliseconds: 800, isCorrect: false),
                to: attempt,
                session: session
            )
            try repository.addSubmission(
                AnswerSubmission(rawInput: "56", normalizedAnswer: 56, submittedAt: .now, elapsedMilliseconds: 1_200, isCorrect: true),
                to: attempt,
                session: session
            )
            attempt.wasEventuallyCorrect = true
            attempt.responseTimeMilliseconds = 1_200
            try repository.finish(session, status: .completed, reason: .timerExpired, at: .now, elapsedMilliseconds: 120_000)
            try repository.replaceSkillEstimates(with: AdaptiveModel.estimates(from: [session]))

            XCTAssertNoThrow(try repository.resetAllData())
            XCTAssertTrue(try repository.fetchSessions().isEmpty)
            XCTAssertTrue(try repository.fetchSkillEstimates().isEmpty)
            XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<QuestionAttempt>()).isEmpty)
            XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<AnswerSubmission>()).isEmpty)
        }

        do {
            let reopened = try DataStore.makeContainer(storeURL: storeURL)
            let repository = SwiftDataRepository(context: reopened.mainContext)
            XCTAssertTrue(try repository.fetchSessions().isEmpty)
            XCTAssertTrue(try reopened.mainContext.fetch(FetchDescriptor<QuestionAttempt>()).isEmpty)
            XCTAssertTrue(try reopened.mainContext.fetch(FetchDescriptor<AnswerSubmission>()).isEmpty)
        }
    }

    func testOnDiskSessionDeletionPreservesOtherGraphsAndRebuildsEstimates() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "ZetaMax-delete-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let container = try DataStore.makeContainer(storeURL: directory.appending(path: "Test.store"))
        let repository = SwiftDataRepository(context: container.mainContext)

        let deleted = try repository.createSession(configuration: .classicDefault, seed: 41, startedAt: .now)
        let deletedAttempt = QuestionAttempt(question: testQuestion(prompt: "7 × 8", answer: 56), position: 0)
        deletedAttempt.wasEventuallyCorrect = true
        deletedAttempt.responseTimeMilliseconds = 900
        try repository.addAttempt(deletedAttempt, to: deleted)
        try repository.addSubmission(AnswerSubmission(rawInput: "56", normalizedAnswer: 56, submittedAt: .now, elapsedMilliseconds: 900, isCorrect: true), to: deletedAttempt, session: deleted)
        try repository.finish(deleted, status: .completed, reason: .timerExpired, at: .now, elapsedMilliseconds: 120_000)

        let retained = try repository.createSession(configuration: .classicDefault, seed: 42, startedAt: .now)
        let retainedAttempt = QuestionAttempt(question: testQuestion(prompt: "6 × 9", answer: 54), position: 0)
        retainedAttempt.wasEventuallyCorrect = true
        retainedAttempt.responseTimeMilliseconds = 1_100
        try repository.addAttempt(retainedAttempt, to: retained)
        try repository.addSubmission(AnswerSubmission(rawInput: "54", normalizedAnswer: 54, submittedAt: .now, elapsedMilliseconds: 1_100, isCorrect: true), to: retainedAttempt, session: retained)
        try repository.finish(retained, status: .completed, reason: .timerExpired, at: .now, elapsedMilliseconds: 120_000)
        try repository.replaceSkillEstimates(with: AdaptiveModel.estimates(from: [deleted, retained]))

        try repository.delete(deleted)

        XCTAssertEqual(try repository.fetchSessions().map(\.id), [retained.id])
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<QuestionAttempt>()).count, 1)
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<AnswerSubmission>()).count, 1)
        XCTAssertFalse(try repository.fetchSkillEstimates().isEmpty)
    }

    func testStatisticsAndExpectedScore() throws {
        XCTAssertEqual(Statistics.median([1, 2, 3, 4]), 2.5)
        XCTAssertEqual(Statistics.percentile([1, 2, 3, 4, 5], 0.9), 5)
        XCTAssertEqual(Statistics.medianAbsoluteDeviation([1, 1, 1, 2]), 0)
    }

    func testTimingAnalyticsBaselinesTailFatigueAndLegacyErrors() throws {
        let container = try DataStore.makeContainer(inMemory: true)
        let repository = SwiftDataRepository(context: container.mainContext)
        let start = Date(timeIntervalSince1970: 10_000)
        let session = try repository.createSession(configuration: .classicDefault, seed: 90, startedAt: start)

        for index in 0..<20 {
            let milliseconds = index < 10 ? 1_000 : 2_000
            try addTimedAttempt(
                repository: repository,
                session: session,
                categoryKey: "multiplication/core",
                categoryName: "Multiplication · core",
                prompt: "7 × 8",
                milliseconds: milliseconds,
                position: index,
                presentedAt: start.addingTimeInterval(Double(index) * 5),
                legacyWrongSubmission: index.isMultiple(of: 3)
            )
        }
        try addTimedAttempt(
            repository: repository,
            session: session,
            categoryKey: "multiplication/rare",
            categoryName: "Multiplication · rare",
            prompt: "12 × 99",
            milliseconds: 12_000,
            position: 20,
            presentedAt: start.addingTimeInterval(110)
        )
        try repository.finish(session, status: .completed, reason: .timerExpired, at: start.addingTimeInterval(120), elapsedMilliseconds: 120_000)

        let snapshot = AnalyticsEngine.snapshot(sessions: [session], baselineSessions: [session])
        XCTAssertEqual(snapshot.completedCount, 21)
        XCTAssertEqual(snapshot.medianMilliseconds, 2_000)
        XCTAssertEqual(snapshot.p90Milliseconds, 2_000)
        XCTAssertEqual(snapshot.recentSpeedChange ?? 0, -50, accuracy: 0.001)
        XCTAssertEqual(snapshot.distribution.last?.count, 1)
        XCTAssertEqual(snapshot.distribution.last?.isOverflow, true)
        XCTAssertNil(snapshot.categoryBaselines["multiplication/rare"], "Fewer than five timings must use the global fallback")
        XCTAssertEqual(snapshot.heatmap.first { $0.left == 7 && $0.right == 8 }?.p90Milliseconds, 2_000)
        XCTAssertEqual(snapshot.slowestCompletions.first?.prompt, "12 × 99")
        XCTAssertGreaterThan(snapshot.slowestCompletions.first?.baselineMultiple ?? 0, 5)
        XCTAssertEqual(snapshot.fatigue.count, 5)
        XCTAssertTrue(snapshot.fatigue.contains { $0.sampleCount > 0 })
        XCTAssertEqual(session.incorrectSubmissionCount, 7, "Fixture proves legacy errors exist but timing analytics ignore them")
    }

    func testAdaptiveVersionTwoUsesOnlyTimingAndRebuildsLegacyEstimates() throws {
        let container = try DataStore.makeContainer(inMemory: true)
        let repository = SwiftDataRepository(context: container.mainContext)
        let start = Date(timeIntervalSince1970: 20_000)
        let session = try repository.createSession(configuration: .classicDefault, seed: 91, startedAt: start)
        for index in 0..<20 {
            try addTimedAttempt(
                repository: repository,
                session: session,
                categoryKey: "multiplication/core",
                categoryName: "Multiplication · core",
                prompt: "7 × 8",
                milliseconds: index < 10 ? 1_000 : 2_000,
                position: index,
                presentedAt: start.addingTimeInterval(Double(index)),
                legacyWrongSubmission: true
            )
        }
        try repository.finish(session, status: .completed, reason: .timerExpired, at: start.addingTimeInterval(120), elapsedMilliseconds: 120_000)

        let estimate = try XCTUnwrap(AdaptiveModel.estimates(from: [session]).first)
        XCTAssertEqual(estimate.algorithmVersion, 2)
        XCTAssertEqual(estimate.estimatedAccuracy, 1, "Legacy correctness is a compatibility placeholder only")
        XCTAssertEqual(estimate.estimatedResponseMilliseconds, 1_500)
        XCTAssertEqual(estimate.deterioration, 1)

        estimate.algorithmVersion = 1
        try repository.replaceSkillEstimates(with: [estimate])
        try repository.rebuildSkillEstimatesIfNeeded()
        XCTAssertEqual(try repository.fetchSkillEstimates().first?.algorithmVersion, 2)
    }

    func testTimingOnlyRecommendationWeightsPreferSlowSupportedCategory() throws {
        let now = Date(timeIntervalSince1970: 30_000)
        let fast = SkillEstimate(
            category: QuestionCategory(key: "addition/fast", displayName: "Addition · fast", operation: .addition),
            estimatedAccuracy: 0,
            estimatedResponseMilliseconds: 1_000,
            uncertainty: 0.1,
            deterioration: 0,
            lastPractisedAt: now,
            attemptCount: 20,
            algorithmVersion: 1
        )
        let slow = SkillEstimate(
            category: QuestionCategory(key: "multiplication/slow", displayName: "Multiplication · slow", operation: .multiplication),
            estimatedAccuracy: 1,
            estimatedResponseMilliseconds: 3_000,
            uncertainty: 0.1,
            deterioration: 0.4,
            lastPractisedAt: now,
            attemptCount: 20,
            algorithmVersion: 2
        )
        let unsupported = SkillEstimate(
            category: QuestionCategory(key: "division/new", displayName: "Division · new", operation: .division),
            estimatedAccuracy: 0,
            estimatedResponseMilliseconds: 9_000,
            uncertainty: 1,
            deterioration: 1,
            lastPractisedAt: nil,
            attemptCount: 9,
            algorithmVersion: 2
        )

        let recommendations = AnalyticsEngine.recommendations(sessions: [], estimates: [fast, slow, unsupported], now: now)
        XCTAssertEqual(recommendations.first?.categoryKey, slow.categoryKey)
        XCTAssertFalse(recommendations.contains { $0.categoryKey == unsupported.categoryKey })
        XCTAssertFalse(recommendations.first?.explanation.localizedCaseInsensitiveContains("accuracy") == true)
        let weights = AdaptiveModel.categoryWeights(estimates: [fast, slow], focus: 0.5, now: now)
        XCTAssertGreaterThan(weights[slow.categoryKey] ?? 0, weights[fast.categoryKey] ?? 0)
    }

    private func addTimedAttempt(
        repository: SwiftDataRepository,
        session: PracticeSession,
        categoryKey: String,
        categoryName: String,
        prompt: String,
        milliseconds: Int,
        position: Int,
        presentedAt: Date,
        legacyWrongSubmission: Bool = false
    ) throws {
        let question = GeneratedQuestion(
            operation: .multiplication,
            kind: .standard,
            category: QuestionCategory(key: categoryKey, displayName: categoryName, operation: .multiplication),
            leftOperand: prompt == "12 × 99" ? 12 : 7,
            rightOperand: prompt == "12 × 99" ? 99 : 8,
            prompt: prompt,
            correctAnswer: prompt == "12 × 99" ? 1_188 : 56
        )
        let attempt = QuestionAttempt(question: question, position: position, presentedAt: presentedAt)
        try repository.addAttempt(attempt, to: session)
        if legacyWrongSubmission {
            try repository.addSubmission(
                AnswerSubmission(rawInput: "0", normalizedAnswer: 0, submittedAt: presentedAt, elapsedMilliseconds: milliseconds / 2, isCorrect: false),
                to: attempt,
                session: session
            )
        }
        attempt.wasEventuallyCorrect = true
        attempt.answeredAt = presentedAt.addingTimeInterval(Double(milliseconds) / 1_000)
        attempt.responseTimeMilliseconds = milliseconds
        try repository.addSubmission(
            AnswerSubmission(rawInput: question.answerCanonical, normalizedAnswer: question.correctAnswer, submittedAt: attempt.answeredAt!, elapsedMilliseconds: milliseconds, isCorrect: true),
            to: attempt,
            session: session
        )
    }

    private func testQuestion(prompt: String, answer: Decimal) -> GeneratedQuestion {
        GeneratedQuestion(
            operation: .multiplication,
            kind: .standard,
            category: QuestionCategory(key: "multiplication/1-digit-x-1-digit", displayName: "Multiplication · 1-digit × 1-digit", operation: .multiplication),
            leftOperand: 7,
            rightOperand: 8,
            prompt: prompt,
            correctAnswer: answer
        )
    }
}

final class ManualClock: MonotonicClock, @unchecked Sendable {
    var value: TimeInterval = 1_000
    var nowSeconds: TimeInterval { value }
}

@MainActor
final class SessionEngineTests: XCTestCase {
    func testCorrectAnswerAutomaticallySubmitsAndAdvancesExactlyOnce() throws {
        let container = try DataStore.makeContainer(inMemory: true)
        let repository = SwiftDataRepository(context: container.mainContext)
        let engine = SessionEngine(repository: repository, clock: ManualClock())
        engine.start(seed: 71)
        let originalPrompt = try XCTUnwrap(engine.currentQuestion?.prompt)
        let answer = try XCTUnwrap(engine.currentQuestion?.answerCanonical)

        engine.answerText = answer
        engine.answerDidChange(answer)

        XCTAssertEqual(engine.score, 1)
        XCTAssertNotEqual(engine.currentQuestion?.prompt, originalPrompt)
        let completedAttempt = try XCTUnwrap(try repository.fetchSessions().first?.sortedAttempts.first)
        XCTAssertEqual(completedAttempt.submissions.count, 1)
        XCTAssertEqual(completedAttempt.submissions.first?.isCorrect, true)
    }

    func testWrongTypingRemainsEditableAndIsNeverPersisted() throws {
        let container = try DataStore.makeContainer(inMemory: true)
        let repository = SwiftDataRepository(context: container.mainContext)
        let clock = ManualClock()
        let engine = SessionEngine(repository: repository, clock: clock)
        engine.start(seed: 72)
        let attempt = try XCTUnwrap(try repository.fetchSessions().first?.sortedAttempts.first)

        engine.answerText = "999"
        engine.answerDidChange("999")
        XCTAssertTrue(attempt.submissions.isEmpty)
        XCTAssertEqual(engine.answerText, "999")

        clock.value += 3.25
        let correct = attempt.correctAnswerText
        engine.answerText = correct
        engine.answerDidChange(correct)
        XCTAssertEqual(attempt.submissions.count, 1)
        XCTAssertEqual(attempt.submissions.first?.isCorrect, true)
        XCTAssertEqual(attempt.responseTimeMilliseconds, 3_250)
        XCTAssertEqual(attempt.incorrectAttempts, 0)
        XCTAssertEqual(try repository.fetchSessions().first?.incorrectSubmissionCount, 0)
        XCTAssertEqual(engine.score, 1)
    }

    func testNegativeAndEquivalentDecimalAnswersAutoSubmit() throws {
        XCTAssertEqual(DecimalText.parse("1,50", locale: Locale(identifier: "fr_FR")), Decimal(string: "1.5"))
        let container = try DataStore.makeContainer(inMemory: true)
        let repository = SwiftDataRepository(context: container.mainContext)
        let engine = SessionEngine(repository: repository, clock: ManualClock())
        var configuration = PracticeConfiguration.classicDefault
        configuration.mode = .targeted
        configuration.targetedPreset = .negativeSubtraction
        engine.configuration = configuration
        engine.start(seed: 74)
        let canonical = try XCTUnwrap(engine.currentQuestion?.answerCanonical)
        XCTAssertTrue(canonical.hasPrefix("-"))
        let equivalent = canonical.contains(".") ? canonical + "0" : canonical + ".0"
        engine.answerText = equivalent
        engine.answerDidChange(equivalent)
        XCTAssertEqual(engine.score, 1)
    }

    func testAutomaticAnswerAtDeadlineDoesNotSubmit() throws {
        let container = try DataStore.makeContainer(inMemory: true)
        let repository = SwiftDataRepository(context: container.mainContext)
        let clock = ManualClock()
        let engine = SessionEngine(repository: repository, clock: clock)
        var configuration = PracticeConfiguration.classicDefault
        configuration.durationSeconds = 15
        engine.configuration = configuration
        engine.start(seed: 75)
        let answer = try XCTUnwrap(engine.currentQuestion?.answerCanonical)
        clock.value += 15
        engine.answerText = answer
        engine.answerDidChange(answer)
        XCTAssertEqual(engine.phase, .results)
        XCTAssertEqual(engine.score, 0)
        XCTAssertTrue(try repository.fetchSessions().first?.sortedAttempts.first?.submissions.isEmpty == true)
    }

    func testDeadlineUsesInjectedMonotonicClock() throws {
        let container = try DataStore.makeContainer(inMemory: true)
        let repository = SwiftDataRepository(context: container.mainContext)
        let clock = ManualClock()
        let engine = SessionEngine(repository: repository, clock: clock)
        var configuration = PracticeConfiguration.classicDefault
        configuration.durationSeconds = 15
        configuration.operations = [.addition]
        engine.configuration = configuration
        engine.start(seed: 4)
        XCTAssertEqual(engine.phase, .running)
        clock.value += 14.25
        engine.tick()
        XCTAssertEqual(engine.remainingSeconds, 0.75, accuracy: 0.001)
        clock.value += 0.75
        engine.tick()
        XCTAssertEqual(engine.phase, .results)
        XCTAssertEqual(engine.completedSession?.status, .completed)
    }

    func testSleepMarksSessionInterrupted() throws {
        let container = try DataStore.makeContainer(inMemory: true)
        let repository = SwiftDataRepository(context: container.mainContext)
        let engine = SessionEngine(repository: repository, clock: ManualClock())
        engine.start(seed: 5)
        engine.interruptForSleep()
        XCTAssertEqual(engine.completedSession?.status, .interrupted)
        XCTAssertEqual(engine.completedSession?.endReason, .systemSleep)
    }
}
