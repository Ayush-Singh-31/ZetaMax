import Foundation
import SwiftData
import XCTest
@testable import ZetaMax

final class QuestionGeneratorTests: XCTestCase {
    func testAppearanceDefaultsToSystemAndPersists() throws {
        let suiteName = "ZetaMaxTests.Appearance.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertEqual(AppAppearance.persisted(in: defaults), .system)
        AppAppearance.dark.persist(in: defaults)
        XCTAssertEqual(AppAppearance.persisted(in: defaults), .dark)
        AppAppearance.light.persist(in: defaults)
        XCTAssertEqual(AppAppearance.persisted(in: defaults), .light)
    }

    func testAnalyticsFilterKeysCaptureEveryFilter() {
        let baseline = AnalyticsFilterKey.default30Days
        XCTAssertEqual(baseline, AnalyticsFilterKey())
        XCTAssertNotEqual(baseline, AnalyticsFilterKey(dateRange: .week))
        XCTAssertNotEqual(baseline, AnalyticsFilterKey(mode: .adaptive))
        XCTAssertNotEqual(baseline, AnalyticsFilterKey(operation: .division))
        XCTAssertNotEqual(baseline, AnalyticsFilterKey(targetedPreset: .percentages))
        XCTAssertNotEqual(baseline, AnalyticsFilterKey(benchmarkProfileKey: "standard-v1"))
        XCTAssertEqual(Set([baseline, baseline]).count, 1)
    }

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

    func testAdditionCategoryDetectsCarryInAnyDigitPosition() {
        var configuration = PracticeConfiguration.classicDefault
        configuration.operations = [.addition]
        configuration.additionLeft = OperandRange(91, 91)
        configuration.additionRight = OperandRange(92, 92)
        let question = QuestionGenerator(seed: 10).nextQuestion(
            configuration: configuration,
            categoryWeights: [:]
        )
        XCTAssertEqual(question.category.key, "addition/carrying-required")
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
        let operand = snapshot.operandExplorers.first { $0.operation == .multiplication }?.cells.first
        XCTAssertEqual(operand?.primaryLabel, "7")
        XCTAssertEqual(operand?.secondaryLabel, "8")
        XCTAssertEqual(snapshot.slowestCompletions.first?.responseMilliseconds, 2_000)

        let csv = ExportService.csv(sessions: fetched)
        XCTAssertTrue(csv.contains("\"schema_version\""))
        XCTAssertTrue(csv.contains("\n\"2\","))
        XCTAssertTrue(csv.contains("\"7 × 8\""))
        XCTAssertTrue(csv.contains("\"54|56\""))
        let json = try ExportService.document(for: fetched, format: .json).data
        let object = try JSONSerialization.jsonObject(with: json) as? [String: Any]
        XCTAssertEqual(object?["schemaVersion"] as? Int, 2)
        XCTAssertTrue(fetched[0].searchableText.contains("7 × 8"))
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
        XCTAssertEqual(Statistics.percentile([1, 2, 3, 4, 5], 0.9) ?? 0, 4.6, accuracy: 0.001)
        XCTAssertEqual(Statistics.percentile([1, 2, 3, 4], 0.5), Statistics.median([1, 2, 3, 4]))
        XCTAssertEqual(
            Statistics.rightCensoredPercentile(
                [
                    .init(value: 1_000, isEvent: true),
                    .init(value: 2_000, isEvent: true),
                    .init(value: 5_000, isEvent: false)
                ],
                0.9
            ),
            5_000,
            "An unobservable tail quantile should report the censoring lower bound, not a biased completed-only value"
        )
        XCTAssertEqual(Statistics.medianAbsoluteDeviation([1, 1, 1, 2]), 0)
    }

    func testTimingAnalyticsBaselinesSessionPaceAndLegacyErrors() throws {
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
        XCTAssertEqual(snapshot.operandExplorers.first { $0.operation == .multiplication }?.cells.first { $0.primaryLabel == "7" && $0.secondaryLabel == "8" }?.p90Milliseconds, 2_000)
        XCTAssertEqual(snapshot.slowestCompletions.first?.prompt, "12 × 99")
        XCTAssertGreaterThan(snapshot.slowestCompletions.first?.baselineMultiple ?? 0, 5)
        XCTAssertEqual(snapshot.sessionPace.count, 5)
        XCTAssertTrue(snapshot.sessionPace.contains { $0.sampleCount > 0 })
        XCTAssertEqual(session.incorrectSubmissionCount, 7, "Fixture proves legacy errors exist but timing analytics ignore them")
    }

    func testAdaptiveVersionThreeUsesTimingAndRecordedAccuracyAndRebuildsLegacyEstimates() throws {
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
        XCTAssertEqual(estimate.algorithmVersion, 3)
        XCTAssertEqual(estimate.estimatedAccuracy, 0.5)
        XCTAssertEqual(estimate.estimatedResponseMilliseconds, 1_500)
        XCTAssertEqual(estimate.deterioration, 1)

        estimate.algorithmVersion = 1
        try repository.replaceSkillEstimates(with: [estimate])
        try repository.rebuildSkillEstimatesIfNeeded()
        XCTAssertEqual(try repository.fetchSkillEstimates().first?.algorithmVersion, 3)
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
        XCTAssertEqual(recommendations.first?.categoryName, slow.categoryName)
        XCTAssertEqual(recommendations.first?.medianMilliseconds, 3_000)
        XCTAssertEqual(recommendations.first?.sampleCount, 20)
        XCTAssertEqual(recommendations.first?.sessionDurationSeconds, 45)
        let weights = AdaptiveModel.categoryWeights(estimates: [fast, slow], focus: 0.5, now: now)
        XCTAssertGreaterThan(weights[slow.categoryKey] ?? 0, weights[fast.categoryKey] ?? 0)
    }

    func testHistoryLayoutPolicySwitchesWithoutAmbiguousBoundary() {
        XCTAssertEqual(HistoryLayoutPolicy.mode(for: 480), .compact)
        XCTAssertEqual(HistoryLayoutPolicy.mode(for: HistoryLayoutPolicy.wideThreshold - 0.5), .compact)
        XCTAssertEqual(HistoryLayoutPolicy.mode(for: HistoryLayoutPolicy.wideThreshold), .wide)
        XCTAssertEqual(HistoryLayoutPolicy.mode(for: 1_200), .wide)
    }

    func testDashboardUsesStableBaselinePriorPeriodAndHonestOperationRateLabel() throws {
        let container = try DataStore.makeContainer(inMemory: true)
        let repository = SwiftDataRepository(context: container.mainContext)
        let anchor = Date(timeIntervalSince1970: 100_000)
        var current: [PracticeSession] = []
        var previous: [PracticeSession] = []

        for day in 0..<3 {
            let old = try repository.createSession(configuration: .classicDefault, seed: UInt64(100 + day), startedAt: anchor.addingTimeInterval(Double(day - 10) * 86_400))
            for position in 0..<10 {
                try addTimedAttempt(repository: repository, session: old, categoryKey: "multiplication/core", categoryName: "Multiplication · core", prompt: "7 × 8", milliseconds: 2_000, position: position, presentedAt: old.startedAt.addingTimeInterval(Double(position) * 5))
            }
            try repository.finish(old, status: .completed, reason: .timerExpired, at: old.startedAt.addingTimeInterval(120), elapsedMilliseconds: 120_000)
            previous.append(old)

            let recent = try repository.createSession(configuration: .classicDefault, seed: UInt64(200 + day), startedAt: anchor.addingTimeInterval(Double(day) * 86_400))
            for position in 0..<10 {
                try addTimedAttempt(repository: repository, session: recent, categoryKey: "multiplication/core", categoryName: "Multiplication · core", prompt: "7 × 8", milliseconds: 1_000, position: position, presentedAt: recent.startedAt.addingTimeInterval(Double(position) * 5))
            }
            try repository.finish(recent, status: .completed, reason: .timerExpired, at: recent.startedAt.addingTimeInterval(120), elapsedMilliseconds: 120_000)
            current.append(recent)
        }

        let snapshot = AnalyticsEngine.snapshot(
            sessions: current,
            baselineSessions: current + previous,
            previousSessions: previous,
            operation: .multiplication,
            calendar: Calendar(identifier: .gregorian)
        )
        XCTAssertEqual(snapshot.throughputLabel, "Multiplication/min")
        XCTAssertEqual(snapshot.questionsPerMinute, 5, accuracy: 0.001)
        XCTAssertEqual(snapshot.trendResolution, .daily)
        XCTAssertEqual(snapshot.trends.count, 3)
        XCTAssertEqual(snapshot.priorPeriod[.medianTime]?.improvementPercent ?? 0, 100, accuracy: 0.001)
        XCTAssertEqual(snapshot.speedIndex, 150, accuracy: 0.001, "Normalization must use all-time category baselines, not the filtered median")
        XCTAssertEqual(snapshot.pace.sessions.count, 3)
        XCTAssertFalse(snapshot.pace.representative.isEmpty)
        XCTAssertNotNil(snapshot.benchmarkProjections.first { $0.durationSeconds == 120 }?.expected)
        XCTAssertNotNil(snapshot.priorPeriod[.projectedScore])
    }

    func testEmptyAndOneSessionSnapshotsUseFallbacksAndRequireComparableProjectionSessions() throws {
        let empty = AnalyticsEngine.snapshot(sessions: [])
        XCTAssertEqual(empty.sessionCount, 0)
        XCTAssertEqual(empty.completedCount, 0)
        XCTAssertEqual(empty.distributionSummary, .empty)
        XCTAssertTrue(empty.trends.isEmpty)
        XCTAssertTrue(empty.pace.sessions.isEmpty)
        XCTAssertEqual(empty.benchmarkProjections.map(\.durationSeconds), [30, 60, 120, 300, 600])
        XCTAssertTrue(empty.benchmarkProjections.allSatisfy { $0.expected == nil })
        XCTAssertTrue([empty.questionsPerMinute, empty.medianMilliseconds, empty.p90Milliseconds, empty.speedIndex, empty.consistency].allSatisfy(\.isFinite))

        let container = try DataStore.makeContainer(inMemory: true)
        let repository = SwiftDataRepository(context: container.mainContext)
        let start = Date(timeIntervalSince1970: 150_000)
        let completed = try repository.createSession(configuration: .classicDefault, seed: 301, startedAt: start)
        for position in 0..<20 {
            try addTimedAttempt(
                repository: repository,
                session: completed,
                categoryKey: "multiplication/core",
                categoryName: "Multiplication · core",
                prompt: "7 × 8",
                milliseconds: 500 + position * 100,
                position: position,
                presentedAt: start.addingTimeInterval(Double(position) * 5)
            )
        }
        try repository.finish(completed, status: .completed, reason: .timerExpired, at: start.addingTimeInterval(120), elapsedMilliseconds: 120_000)

        let interrupted = try repository.createSession(configuration: .classicDefault, seed: 302, startedAt: start.addingTimeInterval(86_400))
        try addTimedAttempt(
            repository: repository,
            session: interrupted,
            categoryKey: "multiplication/core",
            categoryName: "Multiplication · core",
            prompt: "7 × 8",
            milliseconds: 60_000,
            position: 0,
            presentedAt: interrupted.startedAt
        )
        try repository.finish(interrupted, status: .interrupted, reason: .systemSleep, at: interrupted.startedAt.addingTimeInterval(60), elapsedMilliseconds: 60_000)

        let snapshot = AnalyticsEngine.snapshot(sessions: [completed, interrupted], baselineSessions: [completed, interrupted])
        XCTAssertEqual(snapshot.sessionCount, 1, "Interrupted sessions must stay out of comparable analytics")
        XCTAssertEqual(snapshot.completedCount, 20)
        XCTAssertEqual(snapshot.trendResolution, .session)
        XCTAssertEqual(snapshot.trends.map(\.sessionID), [completed.id])
        XCTAssertEqual(snapshot.distributionSummary.q1Milliseconds, 975)
        XCTAssertEqual(snapshot.distributionSummary.medianMilliseconds, 1_450)
        XCTAssertEqual(snapshot.distributionSummary.q3Milliseconds, 1_925)
        XCTAssertEqual(snapshot.distributionSummary.p90Milliseconds, 2_210)
        XCTAssertEqual(snapshot.pace.sessions.count, 1)
        XCTAssertTrue(snapshot.pace.representative.isEmpty, "A representative pace needs at least three sessions")
        XCTAssertEqual(snapshot.benchmarkProjections.map(\.durationSeconds), [30, 60, 120, 300, 600])
        XCTAssertTrue(
            snapshot.benchmarkProjections.allSatisfy { $0.expected == nil },
            "One session cannot express between-session uncertainty"
        )
    }

    func testOperationFilterAppliesToEveryAttemptDerivedDashboardValue() throws {
        let container = try DataStore.makeContainer(inMemory: true)
        let repository = SwiftDataRepository(context: container.mainContext)
        let start = Date(timeIntervalSince1970: 175_000)
        let session = try repository.createSession(configuration: .classicDefault, seed: 303, startedAt: start)

        for position in 0..<10 {
            try addTimedAttempt(
                repository: repository,
                session: session,
                categoryKey: "multiplication/core",
                categoryName: "Multiplication · core",
                prompt: "7 × 8",
                milliseconds: 8_000,
                position: position,
                presentedAt: start.addingTimeInterval(Double(position) * 5)
            )
        }
        for position in 10..<14 {
            try addTimedAttempt(
                repository: repository,
                session: session,
                categoryKey: "addition/core",
                categoryName: "Addition · core",
                prompt: "2 + 3",
                milliseconds: 1_000,
                position: position,
                presentedAt: start.addingTimeInterval(Double(position) * 5),
                operation: .addition
            )
        }
        try repository.finish(session, status: .completed, reason: .timerExpired, at: start.addingTimeInterval(120), elapsedMilliseconds: 120_000)

        let snapshot = AnalyticsEngine.snapshot(sessions: [session], baselineSessions: [session], operation: .addition)
        XCTAssertEqual(snapshot.completedCount, 4)
        XCTAssertEqual(snapshot.questionsPerMinute, 2, accuracy: 0.001)
        XCTAssertEqual(snapshot.throughputLabel, "Addition/min")
        XCTAssertEqual(snapshot.medianMilliseconds, 1_000)
        XCTAssertEqual(snapshot.distributionSummary.count, 4)
        XCTAssertEqual(snapshot.operations.map(\.operation), [.addition])
        XCTAssertTrue(snapshot.categories.allSatisfy { $0.operation == .addition })
        XCTAssertTrue(snapshot.slowestCompletions.allSatisfy { $0.categoryName == "Addition · core" })
        XCTAssertTrue(snapshot.operandExplorers.allSatisfy { $0.operation == .addition })
        XCTAssertEqual(snapshot.trends.first?.sampleCount, 4)
        XCTAssertEqual(snapshot.pace.sessions.first?.points.last?.completedCount, 4)
        XCTAssertTrue(snapshot.benchmarkResults.isEmpty)
    }

    func testSparseOperandResultsAndBenchmarkVersionsNeverImplyMissingData() throws {
        let container = try DataStore.makeContainer(inMemory: true)
        let repository = SwiftDataRepository(context: container.mainContext)
        let start = Date(timeIntervalSince1970: 200_000)

        for version in [1, 2] {
            var configuration = BenchmarkProfile.builtIns.first { $0.durationSeconds == 120 }!.configuration
            configuration.benchmarkVersion = version
            let session = try repository.createSession(configuration: configuration, seed: UInt64(version), startedAt: start.addingTimeInterval(Double(version) * 86_400))
            for position in 0..<(version == 1 ? 9 : 11) {
                try addTimedAttempt(repository: repository, session: session, categoryKey: "multiplication/core", categoryName: "Multiplication · core", prompt: "7 × 8", milliseconds: 1_000 + position * 10, position: position, presentedAt: session.startedAt.addingTimeInterval(Double(position) * 4))
            }
            try repository.finish(session, status: .completed, reason: .timerExpired, at: session.startedAt.addingTimeInterval(120), elapsedMilliseconds: 120_000)
        }

        let snapshot = AnalyticsEngine.snapshot(sessions: try repository.fetchSessions())
        XCTAssertEqual(snapshot.operandExplorers.first { $0.operation == .multiplication }?.presentation, .rankedPairs)
        XCTAssertEqual(snapshot.benchmarkProfiles.count, 2)
        XCTAssertEqual(Set(snapshot.personalBests.keys).count, 2)
        XCTAssertTrue(snapshot.benchmarkProfiles.contains { $0.version == 1 && $0.personalBest == 9 })
        XCTAssertTrue(snapshot.benchmarkProfiles.contains { $0.version == 2 && $0.personalBest == 11 })
        XCTAssertEqual(snapshot.benchmarkResults.map(\.activeDurationSeconds), [120, 120])
        XCTAssertEqual(snapshot.benchmarkResults.first?.questionsPerMinute ?? 0, 4.5, accuracy: 0.001)
        XCTAssertNil(snapshot.benchmarkProjections.first { $0.durationSeconds == 120 }?.expected)
        XCTAssertTrue(snapshot.benchmarkProfiles.allSatisfy { $0.projectedScore == nil })
    }

    func testGeneralizedOperandExplorerUsesDenseGridsAndRankedUnaryFallbacks() throws {
        let container = try DataStore.makeContainer(inMemory: true)
        let repository = SwiftDataRepository(context: container.mainContext)
        let start = Date(timeIntervalSince1970: 240_000)
        let session = try repository.createSession(configuration: .classicDefault, seed: 401, startedAt: start)
        var position = 0

        for left in 2...3 {
            for right in 4...7 {
                try addCustomTimedAttempt(
                    repository: repository,
                    session: session,
                    operation: .addition,
                    kind: .standard,
                    categoryKey: "addition/grid",
                    categoryName: "Addition · grid",
                    left: Decimal(left),
                    right: Decimal(right),
                    answer: Decimal(left + right),
                    prompt: "\(left) + \(right)",
                    position: position,
                    presentedAt: start.addingTimeInterval(Double(position)),
                    milliseconds: 700 + position * 10
                )
                position += 1
            }
        }

        for base in 2...5 {
            try addCustomTimedAttempt(
                repository: repository,
                session: session,
                operation: .power,
                kind: .square,
                categoryKey: "power/squares",
                categoryName: "Powers · squares",
                left: Decimal(base),
                right: nil,
                answer: Decimal(base * base),
                prompt: "\(base)²",
                position: position,
                presentedAt: start.addingTimeInterval(Double(position)),
                milliseconds: 900 + position * 10
            )
            position += 1
        }

        for value in 2...13 {
            try addCustomTimedAttempt(
                repository: repository,
                session: session,
                operation: .division,
                kind: .standard,
                categoryKey: "division/sparse",
                categoryName: "Division · sparse",
                left: Decimal(value * value),
                right: Decimal(value),
                answer: Decimal(value),
                prompt: "\(value * value) ÷ \(value)",
                position: position,
                presentedAt: start.addingTimeInterval(Double(position)),
                milliseconds: 1_000 + position * 10
            )
            position += 1
        }

        try repository.finish(session, status: .completed, reason: .timerExpired, at: start.addingTimeInterval(120), elapsedMilliseconds: 120_000)
        let snapshot = AnalyticsEngine.snapshot(sessions: [session])
        let addition = try XCTUnwrap(snapshot.operandExplorers.first { $0.operation == .addition })
        XCTAssertEqual(addition.horizontalAxis, .firstAddend)
        XCTAssertEqual(addition.verticalAxis, .secondAddend)
        XCTAssertEqual(addition.cells.count, 8)
        XCTAssertEqual(addition.presentation, .grid)

        let powers = try XCTUnwrap(snapshot.operandExplorers.first { $0.operation == .power })
        XCTAssertEqual(powers.horizontalAxis, .base)
        XCTAssertNil(powers.verticalAxis)
        XCTAssertEqual(powers.presentation, .rankedPairs)

        let division = try XCTUnwrap(snapshot.operandExplorers.first { $0.operation == .division })
        XCTAssertEqual(division.presentation, .rankedPairs, "A sparse 12×12 diagonal must not imply unobserved cells")
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
        legacyWrongSubmission: Bool = false,
        operation: ArithmeticOperation = .multiplication
    ) throws {
        let isRareMultiplication = operation == .multiplication && prompt == "12 × 99"
        let question = GeneratedQuestion(
            operation: operation,
            kind: .standard,
            category: QuestionCategory(key: categoryKey, displayName: categoryName, operation: operation),
            leftOperand: operation == .addition ? 2 : (isRareMultiplication ? 12 : 7),
            rightOperand: operation == .addition ? 3 : (isRareMultiplication ? 99 : 8),
            prompt: prompt,
            correctAnswer: operation == .addition ? 5 : (isRareMultiplication ? 1_188 : 56)
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

    private func addCustomTimedAttempt(
        repository: SwiftDataRepository,
        session: PracticeSession,
        operation: ArithmeticOperation,
        kind: QuestionKind,
        categoryKey: String,
        categoryName: String,
        left: Decimal,
        right: Decimal?,
        answer: Decimal,
        prompt: String,
        position: Int,
        presentedAt: Date,
        milliseconds: Int
    ) throws {
        let question = GeneratedQuestion(
            operation: operation,
            kind: kind,
            category: QuestionCategory(key: categoryKey, displayName: categoryName, operation: operation),
            leftOperand: left,
            rightOperand: right,
            prompt: prompt,
            correctAnswer: answer
        )
        let attempt = QuestionAttempt(question: question, position: position, presentedAt: presentedAt)
        attempt.wasEventuallyCorrect = true
        attempt.answeredAt = presentedAt.addingTimeInterval(Double(milliseconds) / 1_000)
        attempt.responseTimeMilliseconds = milliseconds
        try repository.addAttempt(attempt, to: session)
        try repository.addSubmission(
            AnswerSubmission(
                rawInput: DecimalText.canonical(answer),
                normalizedAnswer: answer,
                submittedAt: attempt.answeredAt!,
                elapsedMilliseconds: milliseconds,
                isCorrect: true
            ),
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
    func testCorrectOneDigitAnswerClearsFieldAndAdvancesOnce() throws {
        let container = try DataStore.makeContainer(inMemory: true)
        let repository = SwiftDataRepository(context: container.mainContext)
        let engine = SessionEngine(repository: repository, clock: ManualClock())
        var configuration = PracticeConfiguration.classicDefault
        configuration.operations = [.addition]
        configuration.additionLeft = OperandRange(2, 3)
        configuration.additionRight = OperandRange(2, 3)
        engine.configuration = configuration
        engine.start(seed: 70)
        let originalAttemptID = try XCTUnwrap(try repository.fetchSessions().first?.sortedAttempts.first?.id)
        let answer = try XCTUnwrap(engine.currentQuestion?.answerCanonical)
        XCTAssertEqual(answer.count, 1)

        engine.answerText = answer
        engine.answerDidChange(answer)

        let session = try XCTUnwrap(try repository.fetchSessions().first)
        XCTAssertEqual(engine.answerText, "")
        XCTAssertEqual(engine.score, 1)
        XCTAssertEqual(session.sortedAttempts.count, 2)
        XCTAssertEqual(session.sortedAttempts.first { $0.id == originalAttemptID }?.submissions.count, 1)
    }

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

    func testWrongTypingRemainsEditableUntilReturnRecordsSubmission() throws {
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

        engine.submitCurrentAnswer()
        XCTAssertEqual(attempt.submissions.count, 1)
        XCTAssertEqual(attempt.submissions.first?.isCorrect, false)
        XCTAssertEqual(engine.answerText, "")

        clock.value += 3.25
        let correct = attempt.correctAnswerText
        engine.answerText = correct
        engine.answerDidChange(correct)
        XCTAssertEqual(attempt.submissions.count, 2)
        XCTAssertEqual(attempt.submissions.filter(\.isCorrect).count, 1)
        XCTAssertEqual(attempt.responseTimeMilliseconds, 3_250)
        XCTAssertEqual(attempt.incorrectAttempts, 1)
        XCTAssertEqual(try repository.fetchSessions().first?.incorrectSubmissionCount, 1)
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
        let censored = try XCTUnwrap(try repository.fetchSessions().first?.sortedAttempts.first)
        XCTAssertTrue(censored.isCensored)
        XCTAssertEqual(censored.responseTimeMilliseconds, 15_000)
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

@MainActor
final class AnalyticsServiceTests: XCTestCase {
    func testConcurrentRequestsReuseOneSnapshotCalculation() async throws {
        let service = AnalyticsService(testingSessions: [])
        async let first = service.snapshot(for: .default30Days, revision: 0)
        async let second = service.snapshot(for: .default30Days, revision: 0)
        let results = try await [first, second]
        XCTAssertEqual(results.filter(\.wasCacheHit).count, 1)
        let metrics = await service.metrics()
        XCTAssertEqual(metrics.coldCalculations, 1)
        XCTAssertEqual(metrics.cacheHits, 1)
    }

    func testCancellingOneWaiterDoesNotCancelSharedSnapshotCalculation() async throws {
        let service = AnalyticsService(
            testingSessions: [],
            calculationDelay: .milliseconds(80)
        )
        let cancelledWaiter = Task {
            try await service.snapshot(for: .default30Days, revision: 0)
        }
        try await Task.sleep(for: .milliseconds(10))
        let survivingWaiter = Task {
            try await service.snapshot(for: .default30Days, revision: 0)
        }
        cancelledWaiter.cancel()

        do {
            _ = try await cancelledWaiter.value
            XCTFail("The explicitly cancelled waiter should stop")
        } catch is CancellationError {
            // Expected.
        }
        let result = try await survivingWaiter.value
        XCTAssertFalse(result.wasCacheHit)
        let metrics = await service.metrics()
        XCTAssertEqual(metrics.coldCalculations, 1)
        XCTAssertGreaterThanOrEqual(metrics.cancelledCalculations, 1)
    }

    func testRevisionMismatchUsesDistinctStaleRevisionError() async throws {
        let service = AnalyticsService(
            testingSessions: [],
            calculationDelay: .milliseconds(80)
        )
        let stale = Task {
            try await service.snapshot(for: .default30Days, revision: 0)
        }
        try await Task.sleep(for: .milliseconds(10))
        let current = Task {
            try await service.snapshot(for: .default30Days, revision: 1)
        }

        do {
            _ = try await stale.value
            XCTFail("The superseded request should report a stale revision")
        } catch let error as AnalyticsStaleRevisionError {
            XCTAssertEqual(error.requestedRevision, 0)
            XCTAssertEqual(error.currentRevision, 1)
        }
        _ = try await current.value
    }

    func testSnapshotCacheIsBounded() async throws {
        let service = AnalyticsService(testingSessions: [])
        for index in 0..<24 {
            let filter = AnalyticsFilterKey(
                dateRange: AnalyticsDateRange.allCases[index % AnalyticsDateRange.allCases.count],
                mode: PracticeMode.allCases[(index / 4) % PracticeMode.allCases.count],
                operation: ArithmeticOperation.allCases[(index / 16) % ArithmeticOperation.allCases.count]
            )
            _ = try await service.snapshot(for: filter, revision: 0)
        }
        let cachedCount = await service.cachedSnapshotCount()
        XCTAssertLessThanOrEqual(cachedCount, 16)
    }

    func testBackgroundContextConvertsSwiftDataToImmutableInputs() async throws {
        let container = try DataStore.makeContainer(inMemory: true)
        let repository = SwiftDataRepository(context: container.mainContext)
        let startedAt = Date.now
        let session = try repository.createSession(configuration: .classicDefault, seed: 450, startedAt: startedAt)
        let question = GeneratedQuestion(
            operation: .addition,
            kind: .standard,
            category: QuestionCategory(key: "addition/background", displayName: "Addition · background", operation: .addition),
            leftOperand: 2,
            rightOperand: 3,
            prompt: "2 + 3",
            correctAnswer: 5
        )
        let attempt = QuestionAttempt(question: question, position: 0, presentedAt: startedAt)
        attempt.wasEventuallyCorrect = true
        attempt.responseTimeMilliseconds = 800
        attempt.answeredAt = startedAt.addingTimeInterval(0.8)
        try repository.addAttempt(attempt, to: session)
        try repository.addSubmission(
            AnswerSubmission(rawInput: "5", normalizedAnswer: 5, submittedAt: attempt.answeredAt!, elapsedMilliseconds: 800, isCorrect: true),
            to: attempt,
            session: session
        )
        try repository.finish(session, status: .completed, reason: .timerExpired, at: startedAt.addingTimeInterval(60), elapsedMilliseconds: 60_000)

        let service = AnalyticsService(container: container)
        let result = try await service.snapshot(for: .default30Days, revision: repository.revision.value)
        XCTAssertEqual(result.value.sessionCount, 1)
        XCTAssertEqual(result.value.completedCount, 1)
        XCTAssertEqual(result.value.medianMilliseconds, 800)
        XCTAssertEqual(result.value.operandExplorers.first?.operation, .addition)
    }

    func testDateWindowBaselineExcludesTheEvaluatedWindow() async throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        func session(startedAt: Date, milliseconds: Int) -> AnalyticsSessionInput {
            let sessionID = UUID()
            let attempts = (0..<10).map { position in
                let presentedAt = startedAt.addingTimeInterval(Double(position) * 3)
                return AnalyticsAttemptInput(
                    operation: .addition,
                    kind: .standard,
                    categoryKey: "addition/core",
                    categoryName: "Addition · core",
                    leftOperandText: "2",
                    rightOperandText: "3",
                    prompt: "2 + 3",
                    presentedAt: presentedAt,
                    answeredAt: presentedAt.addingTimeInterval(Double(milliseconds) / 1_000),
                    responseTimeMilliseconds: milliseconds,
                    wasEventuallyCorrect: true,
                    position: position,
                    sessionID: sessionID,
                    sessionStartedAt: startedAt,
                    sessionMode: .classic
                )
            }
            return AnalyticsSessionInput(
                id: sessionID,
                startedAt: startedAt,
                durationSeconds: 120,
                isComparable: true,
                mode: .classic,
                configuration: .classicDefault,
                correctCount: attempts.count,
                activeElapsedMilliseconds: 120_000,
                attempts: attempts
            )
        }

        let historical = session(
            startedAt: now.addingTimeInterval(-40 * 86_400),
            milliseconds: 2_000
        )
        let current = session(
            startedAt: now.addingTimeInterval(-86_400),
            milliseconds: 1_000
        )
        let service = AnalyticsService(testingSessions: [historical, current])
        let result = try await service.snapshot(
            for: .default30Days,
            revision: 0,
            now: now
        )
        XCTAssertEqual(result.value.globalBaselineMilliseconds, 2_000)
        XCTAssertEqual(result.value.speedIndex, 200, accuracy: 0.001)
    }

    func testCacheHitsFilterKeysRevisionInvalidationAndDerivedCaches() async throws {
        let container = try DataStore.makeContainer(inMemory: true)
        let service = AnalyticsService(container: container)

        let first = try await service.snapshot(for: .default30Days, revision: 0)
        let second = try await service.snapshot(for: .default30Days, revision: 0)
        XCTAssertFalse(first.wasCacheHit)
        XCTAssertTrue(second.wasCacheHit)

        let week = try await service.snapshot(for: AnalyticsFilterKey(dateRange: .week), revision: 0)
        XCTAssertFalse(week.wasCacheHit)

        let firstRecommendations = try await service.recommendations(revision: 0)
        let secondRecommendations = try await service.recommendations(revision: 0)
        XCTAssertFalse(firstRecommendations.wasCacheHit)
        XCTAssertTrue(secondRecommendations.wasCacheHit)

        let firstHistory = try await service.historyBaseline(revision: 0)
        let secondHistory = try await service.historyBaseline(revision: 0)
        XCTAssertFalse(firstHistory.wasCacheHit)
        XCTAssertTrue(secondHistory.wasCacheHit)

        await service.invalidate(for: 1)
        let afterRevision = try await service.snapshot(for: .default30Days, revision: 1)
        XCTAssertFalse(afterRevision.wasCacheHit)

        let metrics = await service.metrics()
        XCTAssertEqual(metrics.coldCalculations, 3)
        XCTAssertGreaterThanOrEqual(metrics.cacheHits, 3)
        XCTAssertEqual(metrics.datasetFetches, 2)
        XCTAssertEqual(metrics.recommendationCalculations, 1)
        XCTAssertEqual(metrics.historyBaselineCalculations, 1)
    }

    func testCancelledSnapshotDoesNotPopulateCache() async throws {
        let container = try DataStore.makeContainer(inMemory: true)
        let service = AnalyticsService(container: container)
        let filter = AnalyticsFilterKey(dateRange: .quarter, operation: .multiplication)
        let task = Task { try await service.snapshot(for: filter, revision: 0) }
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("A cancelled snapshot request should throw CancellationError")
        } catch is CancellationError {
            // Expected.
        }

        let retry = try await service.snapshot(for: filter, revision: 0)
        XCTAssertFalse(retry.wasCacheHit)
        let metrics = await service.metrics()
        XCTAssertGreaterThanOrEqual(metrics.cancelledCalculations, 1)
    }

    func testTenThousandAttemptFixtureHasImmediateCachedPresentation() async throws {
        var configuration = PracticeConfiguration.classicDefault
        configuration.durationSeconds = 600
        let sessionID = UUID()
        let startedAt = Date.now
        let attempts = (0..<10_000).map { index in
            let left = 2 + index % 20
            let right = 2 + (index / 20) % 20
            let presentedAt = startedAt.addingTimeInterval(Double(index) * 0.05)
            let milliseconds = 650 + index % 900
            return AnalyticsAttemptInput(
                operation: .multiplication,
                kind: .standard,
                categoryKey: "multiplication/performance-fixture",
                categoryName: "Multiplication · performance fixture",
                leftOperandText: String(left),
                rightOperandText: String(right),
                prompt: "\(left) × \(right)",
                presentedAt: presentedAt,
                answeredAt: presentedAt.addingTimeInterval(Double(milliseconds) / 1_000),
                responseTimeMilliseconds: milliseconds,
                wasEventuallyCorrect: true,
                position: index,
                sessionID: sessionID,
                sessionStartedAt: startedAt,
                sessionMode: .classic
            )
        }
        let session = AnalyticsSessionInput(
            id: sessionID,
            startedAt: startedAt,
            durationSeconds: 600,
            isComparable: true,
            mode: .classic,
            configuration: configuration,
            correctCount: 10_000,
            activeElapsedMilliseconds: 600_000,
            attempts: attempts
        )

        let service = AnalyticsService(testingSessions: [session])
        let cold = Task { try await service.snapshot(for: .default30Days, revision: 0) }
        let mainThreadPingStart = Date()
        await Task.yield()
        XCTAssertLessThan(Date().timeIntervalSince(mainThreadPingStart), 0.1)
        let coldResult = try await cold.value
        XCTAssertEqual(coldResult.value.completedCount, 10_000)

        let cachedStart = Date()
        let cached = try await service.snapshot(for: .default30Days, revision: 0)
        let cachedElapsed = Date().timeIntervalSince(cachedStart)
        XCTAssertTrue(cached.wasCacheHit)
        XCTAssertLessThan(cachedElapsed, 0.2)
        XCTAssertEqual(cached.value.completedCount, 10_000)
    }

    func testRepositoryPublishesRevisionForCompletedAndRebuiltData() throws {
        let container = try DataStore.makeContainer(inMemory: true)
        let repository = SwiftDataRepository(context: container.mainContext)
        let initialRevision = repository.revision.value
        let session = try repository.createSession(configuration: .classicDefault, seed: 500, startedAt: .now)
        XCTAssertEqual(repository.revision.value, initialRevision)

        try repository.finish(session, status: .completed, reason: .timerExpired, at: .now, elapsedMilliseconds: 1_000)
        XCTAssertEqual(repository.revision.value, initialRevision + 1)
        try repository.replaceSkillEstimates(with: [])
        XCTAssertEqual(repository.revision.value, initialRevision + 2)
        try repository.delete(session)
        XCTAssertEqual(repository.revision.value, initialRevision + 3)
        try repository.resetAllData()
        XCTAssertEqual(repository.revision.value, initialRevision + 4)
    }
}
