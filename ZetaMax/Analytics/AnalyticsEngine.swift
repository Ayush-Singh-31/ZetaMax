import Foundation

struct AnalyticsAttemptInput: Identifiable, Hashable, Sendable {
    let id: UUID
    let operation: ArithmeticOperation
    let kind: QuestionKind
    let categoryKey: String
    let categoryName: String
    let leftOperandText: String
    let rightOperandText: String?
    let prompt: String
    let presentedAt: Date
    let answeredAt: Date?
    let responseTimeMilliseconds: Int?
    let wasEventuallyCorrect: Bool
    let isCensored: Bool
    let position: Int
    let sessionID: UUID
    let sessionStartedAt: Date
    let sessionMode: PracticeMode

    init(
        id: UUID = UUID(),
        operation: ArithmeticOperation,
        kind: QuestionKind,
        categoryKey: String,
        categoryName: String,
        leftOperandText: String,
        rightOperandText: String?,
        prompt: String,
        presentedAt: Date,
        answeredAt: Date?,
        responseTimeMilliseconds: Int?,
        wasEventuallyCorrect: Bool,
        isCensored: Bool = false,
        position: Int,
        sessionID: UUID,
        sessionStartedAt: Date,
        sessionMode: PracticeMode
    ) {
        self.id = id
        self.operation = operation
        self.kind = kind
        self.categoryKey = categoryKey
        self.categoryName = categoryName
        self.leftOperandText = leftOperandText
        self.rightOperandText = rightOperandText
        self.prompt = prompt
        self.presentedAt = presentedAt
        self.answeredAt = answeredAt
        self.responseTimeMilliseconds = responseTimeMilliseconds
        self.wasEventuallyCorrect = wasEventuallyCorrect
        self.isCensored = isCensored
        self.position = position
        self.sessionID = sessionID
        self.sessionStartedAt = sessionStartedAt
        self.sessionMode = sessionMode
    }

    init(_ attempt: QuestionAttempt, session: PracticeSession) {
        id = attempt.id
        operation = attempt.operation
        kind = attempt.kind
        categoryKey = attempt.categoryKey
        categoryName = attempt.categoryName
        leftOperandText = attempt.leftOperandText
        rightOperandText = attempt.rightOperandText
        prompt = attempt.prompt
        presentedAt = attempt.presentedAt
        answeredAt = attempt.answeredAt
        responseTimeMilliseconds = attempt.responseTimeMilliseconds
        wasEventuallyCorrect = attempt.wasEventuallyCorrect
        isCensored = attempt.isCensored
        position = attempt.position
        sessionID = session.id
        sessionStartedAt = session.startedAt
        sessionMode = session.mode
    }
}

struct AnalyticsSessionInput: Identifiable, Hashable, Sendable {
    let id: UUID
    let startedAt: Date
    let durationSeconds: Int
    let isComparable: Bool
    let mode: PracticeMode
    let configuration: PracticeConfiguration
    let benchmarkID: String?
    let benchmarkVersion: Int?
    let correctCount: Int
    let activeElapsedMilliseconds: Int?
    let attempts: [AnalyticsAttemptInput]

    init(
        id: UUID = UUID(),
        startedAt: Date,
        durationSeconds: Int,
        isComparable: Bool,
        mode: PracticeMode,
        configuration: PracticeConfiguration,
        benchmarkID: String? = nil,
        benchmarkVersion: Int? = nil,
        correctCount: Int,
        activeElapsedMilliseconds: Int?,
        attempts: [AnalyticsAttemptInput]
    ) {
        self.id = id
        self.startedAt = startedAt
        self.durationSeconds = durationSeconds
        self.isComparable = isComparable
        self.mode = mode
        self.configuration = configuration
        self.benchmarkID = benchmarkID
        self.benchmarkVersion = benchmarkVersion
        self.correctCount = correctCount
        self.activeElapsedMilliseconds = activeElapsedMilliseconds
        self.attempts = attempts
    }

    init(_ session: PracticeSession) {
        id = session.id
        startedAt = session.startedAt
        durationSeconds = session.durationSeconds
        isComparable = session.isComparable
        mode = session.mode
        configuration = session.configuration
        benchmarkID = session.benchmarkID
        benchmarkVersion = session.benchmarkVersion
        correctCount = session.correctCount
        activeElapsedMilliseconds = session.activeElapsedMilliseconds
        attempts = session.attempts.map { AnalyticsAttemptInput($0, session: session) }
    }
}

struct AnalyticsSkillEstimateInput: Hashable, Sendable {
    let categoryKey: String
    let categoryName: String
    let operation: ArithmeticOperation
    let estimatedResponseMilliseconds: Double
    let uncertainty: Double
    let deterioration: Double
    let lastPracticedAt: Date?
    let attemptCount: Int

    init(_ estimate: SkillEstimate) {
        categoryKey = estimate.categoryKey
        categoryName = estimate.categoryName
        operation = ArithmeticOperation(rawValue: estimate.operationRaw) ?? .addition
        estimatedResponseMilliseconds = estimate.estimatedResponseMilliseconds
        uncertainty = estimate.uncertainty
        deterioration = estimate.deterioration
        lastPracticedAt = estimate.lastPractisedAt
        attemptCount = estimate.attemptCount
    }
}

struct OperationMetric: Identifiable, Hashable, Sendable {
    let operation: ArithmeticOperation
    let attempts: Int
    let medianMilliseconds: Double
    let p90Milliseconds: Double
    let baselineMilliseconds: Double
    let difficultyIndex: Double
    var id: String { operation.rawValue }
}

struct CategoryMetric: Identifiable, Hashable, Sendable {
    let key: String
    let name: String
    let operation: ArithmeticOperation
    let attempts: Int
    let medianMilliseconds: Double
    let p90Milliseconds: Double
    let baselineMilliseconds: Double
    let difficultyIndex: Double
    let recentSpeedChange: Double?
    var id: String { key }
    var isLowSample: Bool { attempts < Statistics.reliableTailSampleCount }
}

enum TrendResolution: String, Hashable, Sendable {
    case daily
    case session
}

struct TrendPoint: Identifiable, Hashable, Sendable {
    let id: String
    let date: Date
    let medianMilliseconds: Double
    let p90Milliseconds: Double
    let speedIndex: Double
    let questionsPerMinute: Double
    let benchmarkScore: Double?
    let sampleCount: Int
    let sessionID: UUID?
}

struct DistributionBin: Identifiable, Hashable, Sendable {
    let lowerMilliseconds: Int
    let upperMilliseconds: Int
    let count: Int
    let isOverflow: Bool
    var id: Int { lowerMilliseconds }
    var label: String {
        if isOverflow { return "10s+" }
        return String(format: "%.1f–%.1fs", Double(lowerMilliseconds) / 1_000, Double(upperMilliseconds) / 1_000)
    }
}

struct DistributionSummary: Hashable, Sendable {
    let count: Int
    let minimumMilliseconds: Double
    let q1Milliseconds: Double
    let medianMilliseconds: Double
    let q3Milliseconds: Double
    let p90Milliseconds: Double
    let maximumMilliseconds: Double

    static let empty = DistributionSummary(
        count: 0,
        minimumMilliseconds: 0,
        q1Milliseconds: 0,
        medianMilliseconds: 0,
        q3Milliseconds: 0,
        p90Milliseconds: 0,
        maximumMilliseconds: 0
    )
}

struct SessionPacePoint: Identifiable, Hashable, Sendable {
    let bucket: Int
    let startFraction: Double
    let endFraction: Double
    let normalizedEffort: Double
    let sampleCount: Int
    var id: Int { bucket }
    var label: String { "\(Int(startFraction * 100))–\(Int(endFraction * 100))%" }
}

enum OperandPresentation: String, Hashable, Sendable {
    case grid
    case rankedPairs
    case insufficient
}

enum OperandAxisRole: String, Hashable, Sendable {
    case firstAddend
    case secondAddend
    case minuend
    case subtrahend
    case firstFactor
    case secondFactor
    case dividend
    case divisor
    case percentage
    case value
    case base

    var title: String {
        switch self {
        case .firstAddend: "First addend"
        case .secondAddend: "Second addend"
        case .minuend: "Minuend"
        case .subtrahend: "Subtrahend"
        case .firstFactor: "First factor"
        case .secondFactor: "Second factor"
        case .dividend: "Dividend"
        case .divisor: "Divisor"
        case .percentage: "Percentage"
        case .value: "Value"
        case .base: "Base"
        }
    }
}

struct OperandMetricCell: Identifiable, Hashable, Sendable {
    let operation: ArithmeticOperation
    let primaryLabel: String
    let secondaryLabel: String?
    let primaryValue: Double?
    let secondaryValue: Double?
    let medianMilliseconds: Double
    let p90Milliseconds: Double
    let count: Int

    var id: String { "\(operation.rawValue)|\(primaryLabel)|\(secondaryLabel ?? "unary")" }
    var pairLabel: String {
        guard let secondaryLabel else { return primaryLabel }
        return "\(primaryLabel) \(operation.symbol) \(secondaryLabel)"
    }
}

struct OperandExplorerResult: Identifiable, Hashable, Sendable {
    let operation: ArithmeticOperation
    let horizontalAxis: OperandAxisRole
    let verticalAxis: OperandAxisRole?
    let cells: [OperandMetricCell]
    let presentation: OperandPresentation
    var id: ArithmeticOperation { operation }
}

struct SlowCompletion: Identifiable, Hashable, Sendable {
    let id: UUID
    let sessionID: UUID?
    let sessionStartedAt: Date?
    let sessionMode: PracticeMode?
    let position: Int
    let prompt: String
    let categoryName: String
    let responseMilliseconds: Int
    let baselineMultiple: Double
    let completedAt: Date
}

struct CumulativePacePoint: Identifiable, Hashable, Sendable {
    let elapsedFraction: Double
    let elapsedSeconds: Double
    let completedCount: Double
    var id: String { "\(elapsedFraction)-\(completedCount)" }
}

struct SessionPaceSeries: Identifiable, Hashable, Sendable {
    let sessionID: UUID
    let startedAt: Date
    let mode: PracticeMode
    let durationSeconds: Int
    let points: [CumulativePacePoint]
    var id: UUID { sessionID }
    var label: String { startedAt.formatted(.dateTime.month(.abbreviated).day().hour().minute()) }
}

struct CumulativePace: Hashable, Sendable {
    let sessions: [SessionPaceSeries]
    let representative: [CumulativePacePoint]
}

enum RecommendationKind: Hashable, Sendable {
    case category(categoryKey: String)
    case shortSession
}

struct Recommendation: Identifiable, Hashable, Sendable {
    let id: String
    let kind: RecommendationKind
    let categoryName: String
    let medianMilliseconds: Double?
    let baselineDifferencePercent: Double?
    let recentChangePercent: Double?
    let sampleCount: Int
    let sessionDurationSeconds: Int
    let severity: Double

    var categoryKey: String? {
        if case let .category(categoryKey) = kind { return categoryKey }
        return nil
    }

    var title: String {
        switch kind {
        case .category: categoryName
        case .shortSession: "Short session"
        }
    }
}

struct ExpectedScore: Hashable, Sendable {
    let lower: Int
    let median: Int
    let upper: Int
}

struct BenchmarkProjection: Identifiable, Hashable, Sendable {
    let durationSeconds: Int
    let expected: ExpectedScore?
    var id: Int { durationSeconds }
    var isStandard: Bool { durationSeconds == 120 }
}

struct BenchmarkResultPoint: Identifiable, Hashable, Sendable {
    let sessionID: UUID
    let profileKey: String
    let profileName: String
    let date: Date
    let score: Int
    let activeDurationSeconds: Double
    let questionsPerMinute: Double
    var id: UUID { sessionID }
}

struct BenchmarkProfileSummary: Identifiable, Hashable, Sendable {
    let profileKey: String
    let profileName: String
    let durationSeconds: Int
    let version: Int
    let personalBest: Int
    let recentScore: Int?
    let projectedScore: Int?
    let sampleCount: Int
    var id: String { profileKey }
}

struct BenchmarkProfileOption: Identifiable, Hashable, Sendable {
    let key: String
    let title: String
    var id: String { key }
}

enum DashboardMetric: String, CaseIterable, Hashable, Sendable {
    case projectedScore
    case questionsPerMinute
    case medianTime
    case p90Time
    case completedQuestions
    case consistency
}

struct PriorPeriodComparison: Hashable, Sendable {
    let metric: DashboardMetric
    let currentValue: Double
    let previousValue: Double
    /// Positive values always mean improvement, regardless of whether a lower raw value is better.
    let improvementPercent: Double
}

struct DashboardSnapshot: Sendable {
    var sessionCount = 0
    var completedCount = 0
    var questionsPerMinute = 0.0
    var throughputLabel = "Questions/min"
    var medianMilliseconds = 0.0
    var p90Milliseconds = 0.0
    var speedIndex = 0.0
    var consistency = 0.0
    var recentSpeedChange: Double?
    var globalBaselineMilliseconds = 0.0
    var categoryBaselines: [String: Double] = [:]
    var operations: [OperationMetric] = []
    var categories: [CategoryMetric] = []
    var trends: [TrendPoint] = []
    var trendResolution: TrendResolution = .daily
    var distribution: [DistributionBin] = []
    var distributionSummary: DistributionSummary = .empty
    var sessionPace: [SessionPacePoint] = []
    var sessionPaceChangePercent: Double?
    var operandExplorers: [OperandExplorerResult] = []
    var slowestCompletions: [SlowCompletion] = []
    var pace = CumulativePace(sessions: [], representative: [])
    var benchmarkProjections: [BenchmarkProjection] = []
    var benchmarkResults: [BenchmarkResultPoint] = []
    var benchmarkProfiles: [BenchmarkProfileSummary] = []
    var benchmarkFilterOptions: [BenchmarkProfileOption] = []
    var personalBests: [String: Int] = [:]
    var priorPeriod: [DashboardMetric: PriorPeriodComparison] = [:]
    var insight = "Complete a few questions to establish a performance baseline."
}

struct TimingBaselineResult: Hashable, Sendable {
    let globalMilliseconds: Double
    let categoryMilliseconds: [String: Double]

    static let empty = TimingBaselineResult(globalMilliseconds: 1_500, categoryMilliseconds: [:])

    func value(for categoryKey: String) -> Double {
        categoryMilliseconds[categoryKey] ?? max(globalMilliseconds, 1)
    }
}

private struct TimedAttempt: Sendable {
    let attempt: AnalyticsAttemptInput
    let milliseconds: Double
}

private struct TimingObservation: Sendable {
    let attempt: AnalyticsAttemptInput
    let milliseconds: Double
    let isEvent: Bool
}

private struct ProjectionObservation: Sendable {
    let milliseconds: Int
    let isCompleted: Bool
}

private struct TimingBaselines: Sendable {
    let globalMedian: Double
    let categories: [String: Double]

    func value(for categoryKey: String) -> Double {
        categories[categoryKey] ?? globalMedian
    }
}

private struct CoreMetrics: Sendable {
    let completed: Int
    let questionsPerMinute: Double
    let medianMilliseconds: Double
    let p90Milliseconds: Double
    let consistency: Double
    let projectedScore: Double?
}

enum AnalyticsEngine {
    @MainActor
    static func snapshot(
        sessions: [PracticeSession],
        baselineSessions: [PracticeSession]? = nil,
        previousSessions: [PracticeSession]? = nil,
        operation: ArithmeticOperation? = nil,
        calendar: Calendar = .current
    ) -> DashboardSnapshot {
        snapshot(
            inputs: sessions.map(AnalyticsSessionInput.init),
            baselineInputs: baselineSessions?.map(AnalyticsSessionInput.init),
            previousInputs: previousSessions?.map(AnalyticsSessionInput.init),
            operation: operation,
            calendar: calendar
        )
    }

    static func snapshot(
        inputs sessions: [AnalyticsSessionInput],
        baselineInputs baselineSessions: [AnalyticsSessionInput]? = nil,
        previousInputs previousSessions: [AnalyticsSessionInput]? = nil,
        operation: ArithmeticOperation? = nil,
        calendar: Calendar = .current
    ) -> DashboardSnapshot {
        let comparableSessions = sessions.filter(\.isComparable)
        let referenceSessions = (baselineSessions ?? sessions).filter(\.isComparable)
        let comparablePrevious = previousSessions?.filter(\.isComparable)
        let baselines = timingBaselines(referenceSessions)
        let timed = timedAttempts(comparableSessions, operation: operation)
        let observations = timingObservations(comparableSessions, operation: operation)
        let responseTimes = timed.map(\.milliseconds)
        let normalized = normalizedEfforts(timed, baselines: baselines)
        let totalDuration = activeDurationSeconds(comparableSessions)
        let qpm = totalDuration > 0 ? Double(timed.count) / (totalDuration / 60) : 0

        var snapshot = DashboardSnapshot()
        snapshot.sessionCount = comparableSessions.count
        snapshot.completedCount = timed.count
        snapshot.questionsPerMinute = qpm
        snapshot.throughputLabel = operation.map { "\($0.title)/min" } ?? "Questions/min"
        snapshot.medianMilliseconds = timingPercentile(observations, 0.5) ?? 0
        snapshot.p90Milliseconds = timingPercentile(observations, 0.9) ?? 0
        snapshot.speedIndex = speedIndex(normalized)
        snapshot.consistency = consistency(normalized)
        snapshot.recentSpeedChange = recentSpeedChange(timed, baselines: baselines)
        snapshot.globalBaselineMilliseconds = baselines.globalMedian
        snapshot.categoryBaselines = baselines.categories
        snapshot.operations = operationMetrics(timed, observations: observations, baselines: baselines)
        snapshot.categories = categoryMetrics(timed, observations: observations, baselines: baselines)
        let trendResult = trends(comparableSessions, operation: operation, baselines: baselines, calendar: calendar)
        snapshot.trends = trendResult.points
        snapshot.trendResolution = trendResult.resolution
        snapshot.distribution = distribution(responseTimes)
        snapshot.distributionSummary = distributionSummary(responseTimes)
        snapshot.sessionPace = paceThroughSession(
            comparableSessions,
            timed: timed,
            baselines: baselines
        )
        snapshot.sessionPaceChangePercent = sessionPaceChange(snapshot.sessionPace)
        snapshot.operandExplorers = operandExplorers(timed)
        snapshot.slowestCompletions = slowestCompletions(timed, baselines: baselines)
        snapshot.pace = cumulativePace(comparableSessions, timed: timed)
        snapshot.benchmarkProjections = BenchmarkProfile.builtIns.map {
            BenchmarkProjection(
                durationSeconds: $0.durationSeconds,
                expected: expectedScore(durationSeconds: $0.durationSeconds, sessions: comparableSessions, operation: operation)
            )
        }
        snapshot.benchmarkResults = benchmarkResultPoints(comparableSessions, operation: operation)
        snapshot.benchmarkProfiles = benchmarkProfileSummaries(
            sessions: comparableSessions,
            projections: snapshot.benchmarkProjections,
            operation: operation
        )
        snapshot.benchmarkFilterOptions = benchmarkProfileOptions(referenceSessions)
        snapshot.personalBests = personalBests(comparableSessions)

        if let comparablePrevious {
            let currentProjection = snapshot.benchmarkProjections.first { $0.durationSeconds == 120 }?.expected
            let previousProjection = expectedScore(durationSeconds: 120, sessions: comparablePrevious, operation: operation)
            let current = coreMetrics(
                comparableSessions,
                operation: operation,
                baselines: baselines,
                projectedScore: currentProjection.map { Double($0.median) }
            )
            let previous = coreMetrics(
                comparablePrevious,
                operation: operation,
                baselines: baselines,
                projectedScore: previousProjection.map { Double($0.median) }
            )
            snapshot.priorPeriod = comparisons(current: current, previous: previous)
        }
        snapshot.insight = generatedInsight(snapshot)
        return snapshot
    }

    @MainActor
    static func recommendations(sessions: [PracticeSession], estimates: [SkillEstimate], now: Date = .now) -> [Recommendation] {
        recommendations(
            sessions: sessions.map(AnalyticsSessionInput.init),
            estimates: estimates.map(AnalyticsSkillEstimateInput.init),
            now: now
        )
    }

    static func recommendations(
        sessions: [AnalyticsSessionInput],
        estimates: [AnalyticsSkillEstimateInput],
        now: Date = .now
    ) -> [Recommendation] {
        let eligible = estimates.filter { $0.attemptCount >= 10 }
        let globalMedian = Statistics.median(eligible.map(\.estimatedResponseMilliseconds)) ?? 1_500
        var recommendations = eligible.map { estimate -> Recommendation in
            let relative = estimate.estimatedResponseMilliseconds / max(globalMedian, 1)
            let slowness = min(max(relative - 1, 0), 1)
            let days = estimate.lastPracticedAt.map { now.timeIntervalSince($0) / 86_400 } ?? 14
            let recency = min(max(days / 14, 0), 1)
            let severity = AdaptiveModelParameters.severity(
                slowness: slowness,
                deterioration: estimate.deterioration,
                recency: recency,
                uncertainty: estimate.uncertainty
            )
            return Recommendation(
                id: estimate.categoryKey,
                kind: .category(categoryKey: estimate.categoryKey),
                categoryName: estimate.categoryName,
                medianMilliseconds: estimate.estimatedResponseMilliseconds,
                baselineDifferencePercent: (relative - 1) * 100,
                recentChangePercent: estimate.deterioration * 100,
                sampleCount: estimate.attemptCount,
                sessionDurationSeconds: 45,
                severity: severity
            )
        }

        let comparableSessions = sessions.filter(\.isComparable)
        let comparableTimed = timedAttempts(comparableSessions, operation: nil)
        let pacePoints = paceThroughSession(
            comparableSessions,
            timed: comparableTimed,
            baselines: timingBaselines(comparableSessions)
        )
        if let deterioration = sessionPaceChange(pacePoints), deterioration >= 10 {
            recommendations.append(Recommendation(
                id: "short-session",
                kind: .shortSession,
                categoryName: "All categories",
                medianMilliseconds: nil,
                baselineDifferencePercent: nil,
                recentChangePercent: deterioration,
                sampleCount: sessions.reduce(0) { $0 + $1.attempts.filter(\.wasEventuallyCorrect).count },
                sessionDurationSeconds: 45,
                severity: min(deterioration / 100, 1)
            ))
        }
        return Array(recommendations.sorted { $0.severity > $1.severity }.prefix(3))
    }

    @MainActor
    static func timingBaseline(sessions: [PracticeSession]) -> TimingBaselineResult {
        timingBaseline(inputs: sessions.map(AnalyticsSessionInput.init))
    }

    static func timingBaseline(inputs sessions: [AnalyticsSessionInput]) -> TimingBaselineResult {
        let baseline = timingBaselines(sessions.filter(\.isComparable))
        return TimingBaselineResult(
            globalMilliseconds: baseline.globalMedian,
            categoryMilliseconds: baseline.categories
        )
    }

    static func expectedScore(
        durationSeconds: Int,
        sessions: [AnalyticsSessionInput],
        operation: ArithmeticOperation? = nil,
        seed: UInt64 = 0x5A455441
    ) -> ExpectedScore? {
        let comparable = sessions.filter(\.isComparable)
        let durationRange = (Double(durationSeconds) * 0.75)...(Double(durationSeconds) * 1.5)
        let blocks = comparable.compactMap { session -> [ProjectionObservation]? in
            let activeDuration = Double(session.activeElapsedMilliseconds ?? session.durationSeconds * 1_000) / 1_000
            guard durationRange.contains(activeDuration) else { return nil }
            let values = timingObservations([session], operation: operation)
                .sorted { $0.attempt.presentedAt < $1.attempt.presentedAt }
                .map {
                    ProjectionObservation(
                        milliseconds: max(Int($0.milliseconds), 1),
                        isCompleted: $0.isEvent
                    )
                }
            return values.isEmpty ? nil : values
        }
        guard blocks.count >= 3,
              blocks.flatMap({ $0 }).filter(\.isCompleted).count >= 20 else { return nil }
        var random = SplitMix64(seed: seed ^ UInt64(durationSeconds))
        var simulated: [Int] = []
        simulated.reserveCapacity(1_000)
        for _ in 0..<1_000 {
            if Task.isCancelled { return nil }
            var elapsed = 0
            var score = 0
            while elapsed < durationSeconds * 1_000 {
                if Task.isCancelled { return nil }
                guard let block = blocks.randomElement(using: &random) else { break }
                for observation in block {
                    elapsed += observation.milliseconds
                    if elapsed <= durationSeconds * 1_000, observation.isCompleted {
                        score += 1
                    }
                    if elapsed > durationSeconds * 1_000 {
                        break
                    }
                }
            }
            simulated.append(score)
        }
        let values = simulated.map(Double.init)
        return ExpectedScore(
            lower: Int(Statistics.percentile(values, 0.1) ?? 0),
            median: Int(Statistics.median(values) ?? 0),
            upper: Int(Statistics.percentile(values, 0.9) ?? 0)
        )
    }

    private static func timedAttempts(_ sessions: [AnalyticsSessionInput], operation: ArithmeticOperation?) -> [TimedAttempt] {
        sessions.flatMap(\.attempts).compactMap { attempt in
            guard (operation == nil || attempt.operation == operation),
                  attempt.wasEventuallyCorrect,
                  let milliseconds = attempt.responseTimeMilliseconds,
                  milliseconds >= 0 else { return nil }
            return TimedAttempt(attempt: attempt, milliseconds: Double(milliseconds))
        }
    }

    private static func timingObservations(
        _ sessions: [AnalyticsSessionInput],
        operation: ArithmeticOperation?
    ) -> [TimingObservation] {
        sessions.flatMap(\.attempts).compactMap { attempt in
            guard (operation == nil || attempt.operation == operation),
                  (attempt.wasEventuallyCorrect || attempt.isCensored),
                  let milliseconds = attempt.responseTimeMilliseconds,
                  milliseconds >= 0 else { return nil }
            return TimingObservation(
                attempt: attempt,
                milliseconds: Double(milliseconds),
                isEvent: attempt.wasEventuallyCorrect
            )
        }
    }

    private static func timingPercentile(
        _ observations: [TimingObservation],
        _ percentile: Double
    ) -> Double? {
        Statistics.rightCensoredPercentile(
            observations.map {
                Statistics.RightCensoredObservation(value: $0.milliseconds, isEvent: $0.isEvent)
            },
            percentile
        )
    }

    private static func timingBaselines(_ sessions: [AnalyticsSessionInput]) -> TimingBaselines {
        let observations = timingObservations(sessions, operation: nil)
        let global = timingPercentile(observations, 0.5) ?? 1_500
        let grouped = Dictionary(grouping: observations) { $0.attempt.categoryKey }
        let categories: [String: Double] = grouped.compactMapValues { values in
            guard values.count >= 5 else { return nil }
            return timingPercentile(values, 0.5) ?? global
        }
        return TimingBaselines(globalMedian: max(global, 1), categories: categories)
    }

    private static func activeDurationSeconds(_ sessions: [AnalyticsSessionInput]) -> Double {
        sessions.reduce(0) {
            $0 + Double($1.activeElapsedMilliseconds ?? ($1.durationSeconds * 1_000)) / 1_000
        }
    }

    private static func normalizedEfforts(_ timed: [TimedAttempt], baselines: TimingBaselines) -> [Double] {
        timed.map { $0.milliseconds / max(baselines.value(for: $0.attempt.categoryKey), 1) }
    }

    private static func speedIndex(_ normalized: [Double]) -> Double {
        guard let median = Statistics.median(normalized), median > 0 else { return 0 }
        return 100 / median
    }

    private static func consistency(_ normalized: [Double]) -> Double {
        guard let median = Statistics.median(normalized), median > 0,
              let deviation = Statistics.medianAbsoluteDeviation(normalized) else { return 0 }
        return 100 * min(max(1 - deviation / median, 0), 1)
    }

    private static func recentSpeedChange(_ timed: [TimedAttempt], baselines: TimingBaselines) -> Double? {
        let ordered = timed.sorted { $0.attempt.presentedAt < $1.attempt.presentedAt }
        let normalized = normalizedEfforts(ordered, baselines: baselines)
        let recent = Array(normalized.suffix(10))
        let previous = Array(normalized.dropLast(min(10, normalized.count)).suffix(20))
        guard recent.count >= 5, previous.count >= 5,
              let recentMedian = Statistics.median(recent), recentMedian > 0,
              let previousMedian = Statistics.median(previous) else { return nil }
        return (previousMedian / recentMedian - 1) * 100
    }

    private static func operationMetrics(
        _ timed: [TimedAttempt],
        observations: [TimingObservation],
        baselines: TimingBaselines
    ) -> [OperationMetric] {
        let observationsByOperation = Dictionary(grouping: observations, by: { $0.attempt.operation })
        return Dictionary(grouping: timed, by: { $0.attempt.operation }).map { operation, values in
            let operationObservations = observationsByOperation[operation] ?? []
            let median = timingPercentile(operationObservations, 0.5) ?? 0
            return OperationMetric(
                operation: operation,
                attempts: values.count,
                medianMilliseconds: median,
                p90Milliseconds: timingPercentile(operationObservations, 0.9) ?? 0,
                baselineMilliseconds: baselines.globalMedian,
                difficultyIndex: median / baselines.globalMedian * 100
            )
        }.sorted { $0.operation.rawValue < $1.operation.rawValue }
    }

    private static func categoryMetrics(
        _ timed: [TimedAttempt],
        observations: [TimingObservation],
        baselines: TimingBaselines
    ) -> [CategoryMetric] {
        let observationsByCategory = Dictionary(grouping: observations, by: { $0.attempt.categoryKey })
        return Dictionary(grouping: timed, by: { $0.attempt.categoryKey }).compactMap { key, values in
            guard let first = values.first else { return nil }
            let categoryObservations = observationsByCategory[key] ?? []
            let median = timingPercentile(categoryObservations, 0.5) ?? 0
            return CategoryMetric(
                key: key,
                name: first.attempt.categoryName,
                operation: first.attempt.operation,
                attempts: values.count,
                medianMilliseconds: median,
                p90Milliseconds: timingPercentile(categoryObservations, 0.9) ?? 0,
                baselineMilliseconds: baselines.value(for: key),
                difficultyIndex: median / baselines.globalMedian * 100,
                recentSpeedChange: recentSpeedChange(values, baselines: baselines)
            )
        }.sorted {
            if $0.medianMilliseconds == $1.medianMilliseconds { return $0.attempts > $1.attempts }
            return $0.medianMilliseconds > $1.medianMilliseconds
        }
    }

    private static func trends(
        _ sessions: [AnalyticsSessionInput],
        operation: ArithmeticOperation?,
        baselines: TimingBaselines,
        calendar: Calendar
    ) -> (points: [TrendPoint], resolution: TrendResolution) {
        let dailyGroups = Dictionary(grouping: sessions) { calendar.startOfDay(for: $0.startedAt) }
        let daily = dailyGroups.compactMap { date, values in
            trendPoint(id: "day-\(date.timeIntervalSince1970)", date: date, sessions: values, operation: operation, baselines: baselines, sessionID: nil)
        }.sorted { $0.date < $1.date }
        if daily.count >= 3 { return (daily, .daily) }

        let perSession = sessions.compactMap { session in
            trendPoint(
                id: session.id.uuidString,
                date: session.startedAt,
                sessions: [session],
                operation: operation,
                baselines: baselines,
                sessionID: session.id
            )
        }.sorted { $0.date < $1.date }
        return (perSession, .session)
    }

    private static func trendPoint(
        id: String,
        date: Date,
        sessions: [AnalyticsSessionInput],
        operation: ArithmeticOperation?,
        baselines: TimingBaselines,
        sessionID: UUID?
    ) -> TrendPoint? {
        let timed = timedAttempts(sessions, operation: operation)
        guard !timed.isEmpty else { return nil }
        let observations = timingObservations(sessions, operation: operation)
        let duration = activeDurationSeconds(sessions)
        let benchmarkScores = operation == nil ? sessions.filter { $0.mode == .benchmark }.map { Double($0.correctCount) } : []
        return TrendPoint(
            id: id,
            date: date,
            medianMilliseconds: timingPercentile(observations, 0.5) ?? 0,
            p90Milliseconds: timingPercentile(observations, 0.9) ?? 0,
            speedIndex: speedIndex(normalizedEfforts(timed, baselines: baselines)),
            questionsPerMinute: duration > 0 ? Double(timed.count) / (duration / 60) : 0,
            benchmarkScore: Statistics.median(benchmarkScores),
            sampleCount: timed.count,
            sessionID: sessionID
        )
    }

    private static func distribution(_ values: [Double]) -> [DistributionBin] {
        guard !values.isEmpty else { return [] }
        var counts = Array(repeating: 0, count: 21)
        for value in values {
            let index = min(max(Int(value) / 500, 0), 20)
            counts[index] += 1
        }
        let regular = stride(from: 0, to: 10_000, by: 500).map { lower in
            DistributionBin(
                lowerMilliseconds: lower,
                upperMilliseconds: lower + 500,
                count: counts[lower / 500],
                isOverflow: false
            )
        }
        return regular + [DistributionBin(
            lowerMilliseconds: 10_000,
            upperMilliseconds: Int.max,
            count: counts[20],
            isOverflow: true
        )]
    }

    private static func distributionSummary(_ values: [Double]) -> DistributionSummary {
        guard let minimum = values.min(), let maximum = values.max() else { return .empty }
        return DistributionSummary(
            count: values.count,
            minimumMilliseconds: minimum,
            q1Milliseconds: Statistics.percentile(values, 0.25) ?? minimum,
            medianMilliseconds: Statistics.percentile(values, 0.5) ?? minimum,
            q3Milliseconds: Statistics.percentile(values, 0.75) ?? maximum,
            p90Milliseconds: Statistics.percentile(values, 0.9) ?? maximum,
            maximumMilliseconds: maximum
        )
    }

    private static func paceThroughSession(
        _ sessions: [AnalyticsSessionInput],
        timed: [TimedAttempt],
        baselines: TimingBaselines
    ) -> [SessionPacePoint] {
        var buckets = Array(repeating: [TimedAttempt](), count: 5)
        let timedBySession = Dictionary(grouping: timed) { $0.attempt.sessionID }
        for session in sessions {
            let duration = Double(max(1, session.activeElapsedMilliseconds ?? session.durationSeconds * 1_000)) / 1_000
            for value in timedBySession[session.id] ?? [] {
                let elapsed = value.attempt.presentedAt.timeIntervalSince(session.startedAt)
                let fraction = min(max(elapsed / duration, 0), 1)
                let bucket = min(Int(fraction * 5), 4)
                buckets[bucket].append(value)
            }
        }
        return (0..<5).map { bucket in
            let lower = Double(bucket) / 5
            let upper = Double(bucket + 1) / 5
            let timed = buckets[bucket]
            return SessionPacePoint(
                bucket: bucket,
                startFraction: lower,
                endFraction: upper,
                normalizedEffort: Statistics.median(normalizedEfforts(timed, baselines: baselines)) ?? 0,
                sampleCount: timed.count
            )
        }
    }

    private static func sessionPaceChange(_ points: [SessionPacePoint]) -> Double? {
        guard let first = points.first(where: { $0.sampleCount > 0 && $0.normalizedEffort > 0 }),
              let last = points.last(where: { $0.sampleCount > 0 && $0.normalizedEffort > 0 }) else { return nil }
        return (last.normalizedEffort / first.normalizedEffort - 1) * 100
    }

    private static func operandExplorers(_ timed: [TimedAttempt]) -> [OperandExplorerResult] {
        Dictionary(grouping: timed, by: { $0.attempt.operation }).map { operation, values in
            let roles = operandAxisRoles(for: operation)
            let grouped = Dictionary(grouping: values) { value in
                "\(value.attempt.leftOperandText)|\(value.attempt.rightOperandText ?? "")"
            }
            let cells = grouped.compactMap { _, pair -> OperandMetricCell? in
                guard let first = pair.first else { return nil }
                let times = pair.map(\.milliseconds)
                return OperandMetricCell(
                    operation: operation,
                    primaryLabel: first.attempt.leftOperandText,
                    secondaryLabel: first.attempt.rightOperandText,
                    primaryValue: Double(first.attempt.leftOperandText),
                    secondaryValue: first.attempt.rightOperandText.flatMap(Double.init),
                    medianMilliseconds: Statistics.median(times) ?? 0,
                    p90Milliseconds: Statistics.percentile(times, 0.9) ?? 0,
                    count: pair.count
                )
            }.sorted {
                ($0.primaryValue ?? .infinity, $0.secondaryValue ?? .infinity, $0.primaryLabel, $0.secondaryLabel ?? "")
                    < ($1.primaryValue ?? .infinity, $1.secondaryValue ?? .infinity, $1.primaryLabel, $1.secondaryLabel ?? "")
            }
            return OperandExplorerResult(
                operation: operation,
                horizontalAxis: roles.horizontal,
                verticalAxis: roles.vertical,
                cells: cells,
                presentation: operandPresentation(cells: cells, isUnary: roles.vertical == nil)
            )
        }.sorted { $0.operation.rawValue < $1.operation.rawValue }
    }

    private static func operandAxisRoles(for operation: ArithmeticOperation) -> (horizontal: OperandAxisRole, vertical: OperandAxisRole?) {
        switch operation {
        case .addition: (.firstAddend, .secondAddend)
        case .subtraction: (.minuend, .subtrahend)
        case .multiplication: (.firstFactor, .secondFactor)
        case .division: (.dividend, .divisor)
        case .percentage: (.percentage, .value)
        case .power: (.base, nil)
        }
    }

    private static func operandPresentation(cells: [OperandMetricCell], isUnary: Bool) -> OperandPresentation {
        guard !cells.isEmpty else { return .insufficient }
        guard !isUnary else { return .rankedPairs }
        let horizontalCount = Set(cells.map(\.primaryLabel)).count
        let verticalCount = Set(cells.compactMap(\.secondaryLabel)).count
        let possibleCellCount = horizontalCount * verticalCount
        let density = possibleCellCount > 0 ? Double(cells.count) / Double(possibleCellCount) : 0
        return horizontalCount <= 15
            && verticalCount <= 15
            && cells.count >= 8
            && density >= 0.40
            ? .grid
            : .rankedPairs
    }

    private static func slowestCompletions(_ timed: [TimedAttempt], baselines: TimingBaselines) -> [SlowCompletion] {
        timed.sorted { $0.milliseconds > $1.milliseconds }.prefix(10).map { value in
            return SlowCompletion(
                id: value.attempt.id,
                sessionID: value.attempt.sessionID,
                sessionStartedAt: value.attempt.sessionStartedAt,
                sessionMode: value.attempt.sessionMode,
                position: value.attempt.position,
                prompt: value.attempt.prompt,
                categoryName: value.attempt.categoryName,
                responseMilliseconds: Int(value.milliseconds),
                baselineMultiple: value.milliseconds / max(baselines.value(for: value.attempt.categoryKey), 1),
                completedAt: value.attempt.answeredAt ?? value.attempt.presentedAt
            )
        }
    }

    private static func cumulativePace(
        _ sessions: [AnalyticsSessionInput],
        timed: [TimedAttempt]
    ) -> CumulativePace {
        let timedBySession = Dictionary(grouping: timed) { $0.attempt.sessionID }
        let series = sessions.compactMap { session -> SessionPaceSeries? in
            let duration = Double(max(1, session.activeElapsedMilliseconds ?? session.durationSeconds * 1_000)) / 1_000
            let attempts = (timedBySession[session.id] ?? [])
                .sorted { $0.attempt.presentedAt < $1.attempt.presentedAt }
            guard !attempts.isEmpty else { return nil }
            var points = [CumulativePacePoint(elapsedFraction: 0, elapsedSeconds: 0, completedCount: 0)]
            for (index, value) in attempts.enumerated() {
                let answeredAt = value.attempt.answeredAt
                    ?? value.attempt.presentedAt.addingTimeInterval(value.milliseconds / 1_000)
                let elapsed = min(max(answeredAt.timeIntervalSince(session.startedAt), 0), duration)
                points.append(CumulativePacePoint(
                    elapsedFraction: elapsed / duration,
                    elapsedSeconds: elapsed,
                    completedCount: Double(index + 1)
                ))
            }
            return SessionPaceSeries(
                sessionID: session.id,
                startedAt: session.startedAt,
                mode: session.mode,
                durationSeconds: Int(duration.rounded()),
                points: points
            )
        }.sorted { $0.startedAt > $1.startedAt }

        guard series.count >= 3 else { return CumulativePace(sessions: series, representative: []) }
        let representative = stride(from: 0.0, through: 1.0, by: 0.05).map { fraction in
            let counts = series.map { pace in
                pace.points.last(where: { $0.elapsedFraction <= fraction })?.completedCount ?? 0
            }
            return CumulativePacePoint(
                elapsedFraction: fraction,
                elapsedSeconds: 0,
                completedCount: Statistics.median(counts) ?? 0
            )
        }
        return CumulativePace(sessions: series, representative: representative)
    }

    private static func benchmarkResultPoints(
        _ sessions: [AnalyticsSessionInput],
        operation: ArithmeticOperation?
    ) -> [BenchmarkResultPoint] {
        guard operation == nil else { return [] }
        return sessions.filter { $0.mode == .benchmark && $0.benchmarkID != nil }.map { session in
            let key = "\(session.benchmarkID ?? "unknown")-v\(session.benchmarkVersion ?? 0)"
            let name = BenchmarkProfile.builtIns.first {
                $0.id == session.benchmarkID && $0.version == session.benchmarkVersion
            }?.name ?? (session.benchmarkID ?? "Benchmark")
            return BenchmarkResultPoint(
                sessionID: session.id,
                profileKey: key,
                profileName: name,
                date: session.startedAt,
                score: session.correctCount,
                activeDurationSeconds: Double(session.activeElapsedMilliseconds ?? session.durationSeconds * 1_000) / 1_000,
                questionsPerMinute: {
                    let duration = Double(session.activeElapsedMilliseconds ?? session.durationSeconds * 1_000) / 1_000
                    return duration > 0 ? Double(session.correctCount) / (duration / 60) : 0
                }()
            )
        }.sorted { $0.date < $1.date }
    }

    private static func benchmarkProfileSummaries(
        sessions: [AnalyticsSessionInput],
        projections: [BenchmarkProjection],
        operation: ArithmeticOperation?
    ) -> [BenchmarkProfileSummary] {
        guard operation == nil else { return [] }
        let actual = sessions.filter { $0.mode == .benchmark && $0.benchmarkID != nil }
        return Dictionary(grouping: actual) { "\($0.benchmarkID ?? "unknown")-v\($0.benchmarkVersion ?? 0)" }
            .compactMap { key, values in
                guard let latest = values.max(by: { $0.startedAt < $1.startedAt }) else { return nil }
                let personalBest = values.map(\.correctCount).max() ?? 0
                let projected = projections.first { $0.durationSeconds == latest.durationSeconds }?.expected?.median
                let profileName = BenchmarkProfile.builtIns.first {
                    $0.id == latest.benchmarkID && $0.version == latest.benchmarkVersion
                }?.name ?? (latest.benchmarkID ?? "Benchmark")
                return BenchmarkProfileSummary(
                    profileKey: key,
                    profileName: profileName,
                    durationSeconds: latest.durationSeconds,
                    version: latest.benchmarkVersion ?? 0,
                    personalBest: personalBest,
                    recentScore: latest.correctCount,
                    projectedScore: projected,
                    sampleCount: values.count
                )
            }
            .sorted { ($0.durationSeconds, $0.version) < ($1.durationSeconds, $1.version) }
    }

    private static func benchmarkProfileOptions(_ sessions: [AnalyticsSessionInput]) -> [BenchmarkProfileOption] {
        let values = sessions.compactMap { session -> BenchmarkProfileOption? in
            guard let benchmarkID = session.benchmarkID else { return nil }
            let key = "\(benchmarkID)-v\(session.benchmarkVersion ?? 0)"
            let title = BenchmarkProfile.builtIns.first {
                $0.id == benchmarkID && $0.version == session.benchmarkVersion
            }?.name ?? "\(benchmarkID) · v\(session.benchmarkVersion ?? 0)"
            return BenchmarkProfileOption(key: key, title: title)
        }
        return Array(Dictionary(values.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first }).values)
            .sorted { $0.title < $1.title }
    }

    private static func personalBests(_ sessions: [AnalyticsSessionInput]) -> [String: Int] {
        let benchmarks = sessions.filter { $0.mode == .benchmark && $0.benchmarkID != nil }
        let grouped = Dictionary(grouping: benchmarks) { "\($0.benchmarkID ?? "unknown")-v\($0.benchmarkVersion ?? 0)" }
        return grouped.mapValues { $0.map(\.correctCount).max() ?? 0 }
    }

    private static func coreMetrics(
        _ sessions: [AnalyticsSessionInput],
        operation: ArithmeticOperation?,
        baselines: TimingBaselines,
        projectedScore: Double?
    ) -> CoreMetrics {
        let timed = timedAttempts(sessions, operation: operation)
        let duration = activeDurationSeconds(sessions)
        return CoreMetrics(
            completed: timed.count,
            questionsPerMinute: duration > 0 ? Double(timed.count) / (duration / 60) : 0,
            medianMilliseconds: Statistics.median(timed.map(\.milliseconds)) ?? 0,
            p90Milliseconds: Statistics.percentile(timed.map(\.milliseconds), 0.9) ?? 0,
            consistency: consistency(normalizedEfforts(timed, baselines: baselines)),
            projectedScore: projectedScore
        )
    }

    private static func comparisons(current: CoreMetrics, previous: CoreMetrics) -> [DashboardMetric: PriorPeriodComparison] {
        var result: [DashboardMetric: PriorPeriodComparison] = [:]
        func insert(_ metric: DashboardMetric, current: Double, previous: Double, lowerIsBetter: Bool = false) {
            guard current.isFinite, previous.isFinite, previous > 0 else { return }
            let improvement = lowerIsBetter
                ? (previous / max(current, 0.000_001) - 1) * 100
                : (current / previous - 1) * 100
            result[metric] = PriorPeriodComparison(
                metric: metric,
                currentValue: current,
                previousValue: previous,
                improvementPercent: improvement
            )
        }
        insert(.questionsPerMinute, current: current.questionsPerMinute, previous: previous.questionsPerMinute)
        insert(.medianTime, current: current.medianMilliseconds, previous: previous.medianMilliseconds, lowerIsBetter: true)
        insert(.p90Time, current: current.p90Milliseconds, previous: previous.p90Milliseconds, lowerIsBetter: true)
        insert(.completedQuestions, current: Double(current.completed), previous: Double(previous.completed))
        insert(.consistency, current: current.consistency, previous: previous.consistency)
        if let currentScore = current.projectedScore, let previousScore = previous.projectedScore {
            insert(.projectedScore, current: currentScore, previous: previousScore)
        }
        return result
    }

    private static func generatedInsight(_ snapshot: DashboardSnapshot) -> String {
        if let comparison = snapshot.priorPeriod[.medianTime], abs(comparison.improvementPercent) >= 4 {
            let direction = comparison.improvementPercent > 0 ? "improved" : "slowed"
            return "Median time \(direction) by \(Int(abs(comparison.improvementPercent).rounded()))% versus the preceding equivalent window."
        }
        if let category = snapshot.categories.first(where: { $0.attempts >= 10 && $0.difficultyIndex >= 115 }) {
            return "\(category.name) is the clearest bottleneck: median \(String(format: "%.2f", category.medianMilliseconds / 1_000))s, difficulty index \(Int(category.difficultyIndex.rounded())), n=\(category.attempts)."
        }
        if let change = snapshot.sessionPaceChangePercent, change >= 8 {
            return "The final session fifth is \(Int(change.rounded()))% slower than the first."
        }
        if snapshot.completedCount > 0 {
            return "Pace is currently stable across \(snapshot.completedCount) completed questions; collect more sessions to strengthen comparisons."
        }
        return "Complete a few questions to establish a performance baseline."
    }
}
