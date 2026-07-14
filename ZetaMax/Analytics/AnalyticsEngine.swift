import Foundation

struct OperationMetric: Identifiable, Hashable {
    let operation: ArithmeticOperation
    let attempts: Int
    let medianMilliseconds: Double
    let p90Milliseconds: Double
    let difficultyIndex: Double
    var id: String { operation.rawValue }
}

struct CategoryMetric: Identifiable, Hashable {
    let key: String
    let name: String
    let operation: ArithmeticOperation
    let attempts: Int
    let medianMilliseconds: Double
    let p90Milliseconds: Double
    let difficultyIndex: Double
    let recentSpeedChange: Double?
    var id: String { key }
    var isLowSample: Bool { attempts < 10 }
}

enum TrendResolution: String, Hashable {
    case daily
    case session
}

struct TrendPoint: Identifiable, Hashable {
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

struct DistributionBin: Identifiable, Hashable {
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

struct DistributionSummary: Hashable {
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

struct OperationDistribution: Identifiable, Hashable {
    let operation: ArithmeticOperation
    let count: Int
    let q10Milliseconds: Double
    let q1Milliseconds: Double
    let medianMilliseconds: Double
    let q3Milliseconds: Double
    let p90Milliseconds: Double
    var id: String { operation.rawValue }
}

struct FatiguePoint: Identifiable, Hashable {
    let bucket: Int
    let startFraction: Double
    let endFraction: Double
    let normalizedEffort: Double
    let sampleCount: Int
    var id: Int { bucket }
    var label: String { "\(Int(startFraction * 100))–\(Int(endFraction * 100))%" }
}

struct HeatmapCell: Identifiable, Hashable {
    let left: Int
    let right: Int
    let medianMilliseconds: Double
    let p90Milliseconds: Double
    let count: Int
    var id: String { "\(left)-\(right)" }
    var leftLabel: String { String(left) }
    var rightLabel: String { String(right) }
}

enum HeatmapPresentation: String, Hashable {
    case grid
    case rankedPairs
    case insufficient
}

struct SlowCompletion: Identifiable, Hashable {
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

struct CumulativePacePoint: Identifiable, Hashable {
    let elapsedFraction: Double
    let elapsedSeconds: Double
    let completedCount: Double
    var id: String { "\(elapsedFraction)-\(completedCount)" }
}

struct SessionPaceSeries: Identifiable, Hashable {
    let sessionID: UUID
    let startedAt: Date
    let mode: PracticeMode
    let durationSeconds: Int
    let points: [CumulativePacePoint]
    var id: UUID { sessionID }
    var label: String { startedAt.formatted(.dateTime.month(.abbreviated).day().hour().minute()) }
}

struct CumulativePace: Hashable {
    let sessions: [SessionPaceSeries]
    let representative: [CumulativePacePoint]
}

struct Recommendation: Identifiable, Hashable {
    let id: String
    let title: String
    let explanation: String
    let categoryKey: String?
    let severity: Double
}

struct ExpectedScore: Hashable {
    let lower: Int
    let median: Int
    let upper: Int
}

struct BenchmarkProjection: Identifiable, Hashable {
    let durationSeconds: Int
    let expected: ExpectedScore?
    var id: Int { durationSeconds }
    var isStandard: Bool { durationSeconds == 120 }
}

struct BenchmarkResultPoint: Identifiable, Hashable {
    let sessionID: UUID
    let profileKey: String
    let profileName: String
    let date: Date
    let score: Int
    var id: UUID { sessionID }
}

struct BenchmarkProfileSummary: Identifiable, Hashable {
    let profileKey: String
    let profileName: String
    let durationSeconds: Int
    let version: Int
    let personalBest: Int
    let recentScore: Int?
    let projectedScore: Int?
    let gapToPersonalBest: Int?
    let sampleCount: Int
    var id: String { profileKey }
}

enum DashboardMetric: String, CaseIterable, Hashable {
    case projectedScore
    case questionsPerMinute
    case medianTime
    case p90Time
    case completedQuestions
    case consistency
}

struct PriorPeriodComparison: Hashable {
    let metric: DashboardMetric
    let currentValue: Double
    let previousValue: Double
    /// Positive values always mean improvement, regardless of whether a lower raw value is better.
    let improvementPercent: Double
}

struct DashboardSnapshot {
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
    var operationDistributions: [OperationDistribution] = []
    var fatigue: [FatiguePoint] = []
    var fatigueChangePercent: Double?
    var heatmap: [HeatmapCell] = []
    var heatmapPresentation: HeatmapPresentation = .insufficient
    var slowestCompletions: [SlowCompletion] = []
    var pace = CumulativePace(sessions: [], representative: [])
    var benchmarkProjections: [BenchmarkProjection] = []
    var benchmarkResults: [BenchmarkResultPoint] = []
    var benchmarkProfiles: [BenchmarkProfileSummary] = []
    var personalBests: [String: Int] = [:]
    var priorPeriod: [DashboardMetric: PriorPeriodComparison] = [:]
    var insight = "Complete a few questions to establish a performance baseline."
}

private struct TimedAttempt {
    let attempt: QuestionAttempt
    let milliseconds: Double
}

private struct TimingBaselines {
    let globalMedian: Double
    let categories: [String: Double]

    func value(for categoryKey: String) -> Double {
        categories[categoryKey] ?? globalMedian
    }
}

private struct CoreMetrics {
    let completed: Int
    let questionsPerMinute: Double
    let medianMilliseconds: Double
    let p90Milliseconds: Double
    let consistency: Double
    let projectedScore: Double?
}

enum AnalyticsEngine {
    static func snapshot(
        sessions: [PracticeSession],
        baselineSessions: [PracticeSession]? = nil,
        previousSessions: [PracticeSession]? = nil,
        operation: ArithmeticOperation? = nil,
        calendar: Calendar = .current
    ) -> DashboardSnapshot {
        let comparableSessions = sessions.filter(\.isComparable)
        let referenceSessions = (baselineSessions ?? sessions).filter(\.isComparable)
        let comparablePrevious = previousSessions?.filter(\.isComparable)
        let baselines = timingBaselines(referenceSessions)
        let timed = timedAttempts(comparableSessions, operation: operation)
        let responseTimes = timed.map(\.milliseconds)
        let normalized = normalizedEfforts(timed, baselines: baselines)
        let totalDuration = activeDurationSeconds(comparableSessions)
        let qpm = totalDuration > 0 ? Double(timed.count) / (totalDuration / 60) : 0

        var snapshot = DashboardSnapshot()
        snapshot.sessionCount = comparableSessions.count
        snapshot.completedCount = timed.count
        snapshot.questionsPerMinute = qpm
        snapshot.throughputLabel = operation.map { "\($0.title)/min" } ?? "Questions/min"
        snapshot.medianMilliseconds = Statistics.median(responseTimes) ?? 0
        snapshot.p90Milliseconds = Statistics.percentile(responseTimes, 0.9) ?? 0
        snapshot.speedIndex = speedIndex(normalized)
        snapshot.consistency = consistency(normalized)
        snapshot.recentSpeedChange = recentSpeedChange(timed, baselines: baselines)
        snapshot.globalBaselineMilliseconds = baselines.globalMedian
        snapshot.categoryBaselines = baselines.categories
        snapshot.operations = operationMetrics(timed, baselines: baselines)
        snapshot.categories = categoryMetrics(timed, baselines: baselines)
        let trendResult = trends(comparableSessions, operation: operation, baselines: baselines, calendar: calendar)
        snapshot.trends = trendResult.points
        snapshot.trendResolution = trendResult.resolution
        snapshot.distribution = distribution(responseTimes)
        snapshot.distributionSummary = distributionSummary(responseTimes)
        snapshot.operationDistributions = operationDistributions(timed)
        snapshot.fatigue = fatigue(comparableSessions, operation: operation, baselines: baselines)
        snapshot.fatigueChangePercent = fatigueChange(snapshot.fatigue)
        snapshot.heatmap = heatmap(timed)
        snapshot.heatmapPresentation = heatmapPresentation(snapshot.heatmap)
        snapshot.slowestCompletions = slowestCompletions(timed, baselines: baselines)
        snapshot.pace = cumulativePace(comparableSessions, operation: operation)
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
        snapshot.personalBests = personalBests(comparableSessions)

        if let comparablePrevious {
            let current = coreMetrics(comparableSessions, operation: operation, baselines: baselines)
            let previous = coreMetrics(comparablePrevious, operation: operation, baselines: baselines)
            snapshot.priorPeriod = comparisons(current: current, previous: previous)
        }
        snapshot.insight = generatedInsight(snapshot)
        return snapshot
    }

    static func recommendations(sessions: [PracticeSession], estimates: [SkillEstimate], now: Date = .now) -> [Recommendation] {
        let eligible = estimates.filter { $0.attemptCount >= 10 }
        let globalMedian = Statistics.median(eligible.map(\.estimatedResponseMilliseconds)) ?? 1_500
        var recommendations = eligible.map { estimate -> Recommendation in
            let relative = estimate.estimatedResponseMilliseconds / max(globalMedian, 1)
            let slowness = min(max(relative - 1, 0), 1)
            let days = estimate.lastPractisedAt.map { now.timeIntervalSince($0) / 86_400 } ?? 14
            let recency = min(max(days / 14, 0), 1)
            let severity = 0.50 * slowness
                + 0.25 * min(max(estimate.deterioration, 0), 1)
                + 0.15 * recency
                + 0.10 * min(max(estimate.uncertainty, 0), 1)
            let relativeCopy = relative >= 1
                ? "\(Int(((relative - 1) * 100).rounded()))% slower than your typical category"
                : "\(Int(((1 - relative) * 100).rounded()))% faster than your typical category"
            let changeCopy = estimate.deterioration >= 0.01
                ? ", with a recent \(Int((estimate.deterioration * 100).rounded()))% slowdown"
                : ""
            return Recommendation(
                id: estimate.categoryKey,
                title: "Practise \(estimate.categoryName.lowercased())",
                explanation: "Median \(String(format: "%.2f", estimate.estimatedResponseMilliseconds / 1_000))s · \(relativeCopy)\(changeCopy) across \(estimate.attemptCount) questions.",
                categoryKey: estimate.categoryKey,
                severity: severity
            )
        }

        let fatiguePoints = snapshot(sessions: sessions, baselineSessions: sessions).fatigue
        if let deterioration = fatigueChange(fatiguePoints), deterioration >= 10 {
            recommendations.append(Recommendation(
                id: "fatigue",
                title: "Use shorter intervals",
                explanation: "Time-to-correct slows about \(Int(deterioration.rounded()))% from the first to last fifth of a session. Try a focused 45-second interval.",
                categoryKey: nil,
                severity: min(deterioration / 100, 1)
            ))
        }
        return Array(recommendations.sorted { $0.severity > $1.severity }.prefix(3))
    }

    static func expectedScore(
        durationSeconds: Int,
        sessions: [PracticeSession],
        operation: ArithmeticOperation? = nil,
        seed: UInt64 = 0x5A455441
    ) -> ExpectedScore? {
        let times = timedAttempts(sessions.filter(\.isComparable), operation: operation).map { Int($0.milliseconds) }
        guard times.count >= 20 else { return nil }
        var random = SplitMix64(seed: seed ^ UInt64(durationSeconds))
        var simulated: [Int] = []
        simulated.reserveCapacity(1_000)
        for _ in 0..<1_000 {
            var elapsed = 0
            var score = 0
            while elapsed < durationSeconds * 1_000 {
                elapsed += times.randomElement(using: &random) ?? 1_500
                if elapsed <= durationSeconds * 1_000 { score += 1 }
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

    private static func timedAttempts(_ sessions: [PracticeSession], operation: ArithmeticOperation?) -> [TimedAttempt] {
        sessions.flatMap(\.attempts).compactMap { attempt in
            guard (operation == nil || attempt.operation == operation),
                  attempt.wasEventuallyCorrect,
                  let milliseconds = attempt.responseTimeMilliseconds,
                  milliseconds >= 0 else { return nil }
            return TimedAttempt(attempt: attempt, milliseconds: Double(milliseconds))
        }
    }

    private static func timingBaselines(_ sessions: [PracticeSession]) -> TimingBaselines {
        let timed = timedAttempts(sessions, operation: nil)
        let global = Statistics.median(timed.map(\.milliseconds)) ?? 1_500
        let grouped = Dictionary(grouping: timed) { $0.attempt.categoryKey }
        let categories: [String: Double] = grouped.compactMapValues { values in
            guard values.count >= 5 else { return nil }
            return Statistics.median(values.map(\.milliseconds)) ?? global
        }
        return TimingBaselines(globalMedian: max(global, 1), categories: categories)
    }

    private static func activeDurationSeconds(_ sessions: [PracticeSession]) -> Double {
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

    private static func operationMetrics(_ timed: [TimedAttempt], baselines: TimingBaselines) -> [OperationMetric] {
        Dictionary(grouping: timed, by: { $0.attempt.operation }).map { operation, values in
            let times = values.map(\.milliseconds)
            let median = Statistics.median(times) ?? 0
            return OperationMetric(
                operation: operation,
                attempts: values.count,
                medianMilliseconds: median,
                p90Milliseconds: Statistics.percentile(times, 0.9) ?? 0,
                difficultyIndex: median / baselines.globalMedian * 100
            )
        }.sorted { $0.operation.rawValue < $1.operation.rawValue }
    }

    private static func categoryMetrics(_ timed: [TimedAttempt], baselines: TimingBaselines) -> [CategoryMetric] {
        Dictionary(grouping: timed, by: { $0.attempt.categoryKey }).compactMap { key, values in
            guard let first = values.first else { return nil }
            let times = values.map(\.milliseconds)
            let median = Statistics.median(times) ?? 0
            return CategoryMetric(
                key: key,
                name: first.attempt.categoryName,
                operation: first.attempt.operation,
                attempts: values.count,
                medianMilliseconds: median,
                p90Milliseconds: Statistics.percentile(times, 0.9) ?? 0,
                difficultyIndex: median / baselines.globalMedian * 100,
                recentSpeedChange: recentSpeedChange(values, baselines: baselines)
            )
        }.sorted {
            if $0.medianMilliseconds == $1.medianMilliseconds { return $0.attempts > $1.attempts }
            return $0.medianMilliseconds > $1.medianMilliseconds
        }
    }

    private static func trends(
        _ sessions: [PracticeSession],
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
        sessions: [PracticeSession],
        operation: ArithmeticOperation?,
        baselines: TimingBaselines,
        sessionID: UUID?
    ) -> TrendPoint? {
        let timed = timedAttempts(sessions, operation: operation)
        guard !timed.isEmpty else { return nil }
        let duration = activeDurationSeconds(sessions)
        let benchmarkScores = operation == nil ? sessions.filter { $0.mode == .benchmark }.map { Double($0.correctCount) } : []
        return TrendPoint(
            id: id,
            date: date,
            medianMilliseconds: Statistics.median(timed.map(\.milliseconds)) ?? 0,
            p90Milliseconds: Statistics.percentile(timed.map(\.milliseconds), 0.9) ?? 0,
            speedIndex: speedIndex(normalizedEfforts(timed, baselines: baselines)),
            questionsPerMinute: duration > 0 ? Double(timed.count) / (duration / 60) : 0,
            benchmarkScore: Statistics.median(benchmarkScores),
            sampleCount: timed.count,
            sessionID: sessionID
        )
    }

    private static func distribution(_ values: [Double]) -> [DistributionBin] {
        guard !values.isEmpty else { return [] }
        let regular = stride(from: 0, to: 10_000, by: 500).map { lower in
            DistributionBin(
                lowerMilliseconds: lower,
                upperMilliseconds: lower + 500,
                count: values.filter { Int($0) >= lower && Int($0) < lower + 500 }.count,
                isOverflow: false
            )
        }
        return regular + [DistributionBin(
            lowerMilliseconds: 10_000,
            upperMilliseconds: Int.max,
            count: values.filter { $0 >= 10_000 }.count,
            isOverflow: true
        )]
    }

    private static func distributionSummary(_ values: [Double]) -> DistributionSummary {
        guard let minimum = values.min(), let maximum = values.max() else { return .empty }
        return DistributionSummary(
            count: values.count,
            minimumMilliseconds: minimum,
            q1Milliseconds: Statistics.percentile(values, 0.25) ?? minimum,
            medianMilliseconds: Statistics.median(values) ?? minimum,
            q3Milliseconds: Statistics.percentile(values, 0.75) ?? maximum,
            p90Milliseconds: Statistics.percentile(values, 0.9) ?? maximum,
            maximumMilliseconds: maximum
        )
    }

    private static func operationDistributions(_ timed: [TimedAttempt]) -> [OperationDistribution] {
        Dictionary(grouping: timed, by: { $0.attempt.operation }).map { operation, values in
            let times = values.map(\.milliseconds)
            return OperationDistribution(
                operation: operation,
                count: times.count,
                q10Milliseconds: Statistics.percentile(times, 0.10) ?? 0,
                q1Milliseconds: Statistics.percentile(times, 0.25) ?? 0,
                medianMilliseconds: Statistics.median(times) ?? 0,
                q3Milliseconds: Statistics.percentile(times, 0.75) ?? 0,
                p90Milliseconds: Statistics.percentile(times, 0.90) ?? 0
            )
        }.sorted { $0.operation.rawValue < $1.operation.rawValue }
    }

    private static func fatigue(
        _ sessions: [PracticeSession],
        operation: ArithmeticOperation?,
        baselines: TimingBaselines
    ) -> [FatiguePoint] {
        (0..<5).map { bucket in
            let lower = Double(bucket) / 5
            let upper = Double(bucket + 1) / 5
            let timed = sessions.flatMap { session in
                timedAttempts([session], operation: operation).filter { value in
                    let elapsed = value.attempt.presentedAt.timeIntervalSince(session.startedAt)
                    let duration = Double(max(1, session.activeElapsedMilliseconds ?? session.durationSeconds * 1_000)) / 1_000
                    let fraction = min(max(elapsed / duration, 0), 1)
                    return fraction >= lower && (bucket == 4 ? fraction <= upper : fraction < upper)
                }
            }
            return FatiguePoint(
                bucket: bucket,
                startFraction: lower,
                endFraction: upper,
                normalizedEffort: Statistics.median(normalizedEfforts(timed, baselines: baselines)) ?? 0,
                sampleCount: timed.count
            )
        }
    }

    private static func fatigueChange(_ points: [FatiguePoint]) -> Double? {
        guard let first = points.first(where: { $0.sampleCount > 0 && $0.normalizedEffort > 0 }),
              let last = points.last(where: { $0.sampleCount > 0 && $0.normalizedEffort > 0 }) else { return nil }
        return (last.normalizedEffort / first.normalizedEffort - 1) * 100
    }

    private static func heatmap(_ timed: [TimedAttempt]) -> [HeatmapCell] {
        let multiplication = timed.filter { $0.attempt.operation == .multiplication && $0.attempt.kind == .standard }
        let grouped = Dictionary(grouping: multiplication) {
            "\($0.attempt.leftOperandText)|\($0.attempt.rightOperandText ?? "")"
        }
        return grouped.compactMap { _, values in
            guard let first = values.first,
                  let left = Int(first.attempt.leftOperandText),
                  let rightText = first.attempt.rightOperandText,
                  let right = Int(rightText) else { return nil }
            let times = values.map(\.milliseconds)
            return HeatmapCell(
                left: left,
                right: right,
                medianMilliseconds: Statistics.median(times) ?? 0,
                p90Milliseconds: Statistics.percentile(times, 0.9) ?? 0,
                count: values.count
            )
        }.sorted { ($0.left, $0.right) < ($1.left, $1.right) }
    }

    private static func heatmapPresentation(_ cells: [HeatmapCell]) -> HeatmapPresentation {
        guard !cells.isEmpty else { return .insufficient }
        let leftCount = Set(cells.map(\.left)).count
        let rightCount = Set(cells.map(\.right)).count
        return cells.count >= 8 && leftCount >= 2 && rightCount >= 2 ? .grid : .rankedPairs
    }

    private static func slowestCompletions(_ timed: [TimedAttempt], baselines: TimingBaselines) -> [SlowCompletion] {
        timed.sorted { $0.milliseconds > $1.milliseconds }.prefix(10).map { value in
            let session = value.attempt.session
            return SlowCompletion(
                id: value.attempt.id,
                sessionID: session?.id,
                sessionStartedAt: session?.startedAt,
                sessionMode: session?.mode,
                position: value.attempt.position,
                prompt: value.attempt.prompt,
                categoryName: value.attempt.categoryName,
                responseMilliseconds: Int(value.milliseconds),
                baselineMultiple: value.milliseconds / max(baselines.value(for: value.attempt.categoryKey), 1),
                completedAt: value.attempt.answeredAt ?? value.attempt.presentedAt
            )
        }
    }

    private static func cumulativePace(_ sessions: [PracticeSession], operation: ArithmeticOperation?) -> CumulativePace {
        let series = sessions.compactMap { session -> SessionPaceSeries? in
            let duration = Double(max(1, session.activeElapsedMilliseconds ?? session.durationSeconds * 1_000)) / 1_000
            let attempts = timedAttempts([session], operation: operation).sorted { $0.attempt.presentedAt < $1.attempt.presentedAt }
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
        _ sessions: [PracticeSession],
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
                score: session.correctCount
            )
        }.sorted { $0.date < $1.date }
    }

    private static func benchmarkProfileSummaries(
        sessions: [PracticeSession],
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
                let comparisonScore = latest.correctCount
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
                    gapToPersonalBest: comparisonScore - personalBest,
                    sampleCount: values.count
                )
            }
            .sorted { ($0.durationSeconds, $0.version) < ($1.durationSeconds, $1.version) }
    }

    private static func personalBests(_ sessions: [PracticeSession]) -> [String: Int] {
        let benchmarks = sessions.filter { $0.mode == .benchmark && $0.benchmarkID != nil }
        let grouped = Dictionary(grouping: benchmarks) { "\($0.benchmarkID ?? "unknown")-v\($0.benchmarkVersion ?? 0)" }
        return grouped.mapValues { $0.map(\.correctCount).max() ?? 0 }
    }

    private static func coreMetrics(
        _ sessions: [PracticeSession],
        operation: ArithmeticOperation?,
        baselines: TimingBaselines
    ) -> CoreMetrics {
        let timed = timedAttempts(sessions, operation: operation)
        let duration = activeDurationSeconds(sessions)
        return CoreMetrics(
            completed: timed.count,
            questionsPerMinute: duration > 0 ? Double(timed.count) / (duration / 60) : 0,
            medianMilliseconds: Statistics.median(timed.map(\.milliseconds)) ?? 0,
            p90Milliseconds: Statistics.percentile(timed.map(\.milliseconds), 0.9) ?? 0,
            consistency: consistency(normalizedEfforts(timed, baselines: baselines)),
            projectedScore: expectedScore(durationSeconds: 120, sessions: sessions, operation: operation).map { Double($0.median) }
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
        if let fatigue = snapshot.fatigueChangePercent, fatigue >= 8 {
            return "End-of-session effort is \(Int(fatigue.rounded()))% higher than at the start; shorter focused intervals may preserve pace."
        }
        if snapshot.completedCount > 0 {
            return "Pace is currently stable across \(snapshot.completedCount) completed questions; collect more sessions to strengthen comparisons."
        }
        return "Complete a few questions to establish a performance baseline."
    }
}
