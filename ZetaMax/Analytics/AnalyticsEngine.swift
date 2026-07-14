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
}

struct TrendPoint: Identifiable, Hashable {
    let date: Date
    let medianMilliseconds: Double
    let speedIndex: Double
    let questionsPerMinute: Double
    var id: Date { date }
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
}

struct SlowCompletion: Identifiable, Hashable {
    let id: UUID
    let prompt: String
    let categoryName: String
    let responseMilliseconds: Int
    let baselineMultiple: Double
    let completedAt: Date
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

struct DashboardSnapshot {
    var sessionCount = 0
    var completedCount = 0
    var questionsPerMinute = 0.0
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
    var distribution: [DistributionBin] = []
    var fatigue: [FatiguePoint] = []
    var heatmap: [HeatmapCell] = []
    var slowestCompletions: [SlowCompletion] = []
    var personalBests: [String: Int] = [:]
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

enum AnalyticsEngine {
    static func snapshot(
        sessions: [PracticeSession],
        baselineSessions: [PracticeSession]? = nil,
        operation: ArithmeticOperation? = nil,
        calendar: Calendar = .current
    ) -> DashboardSnapshot {
        let comparableSessions = sessions.filter(\.isComparable)
        let referenceSessions = (baselineSessions ?? sessions).filter(\.isComparable)
        let baselines = timingBaselines(referenceSessions)
        let timed = timedAttempts(comparableSessions, operation: operation)
        let responseTimes = timed.map(\.milliseconds)
        let normalized = normalizedEfforts(timed, baselines: baselines)
        let totalDuration = comparableSessions.reduce(0) {
            $0 + Double($1.activeElapsedMilliseconds ?? ($1.durationSeconds * 1_000)) / 1_000
        }

        var snapshot = DashboardSnapshot()
        snapshot.sessionCount = comparableSessions.count
        snapshot.completedCount = timed.count
        snapshot.questionsPerMinute = totalDuration > 0 ? Double(timed.count) / (totalDuration / 60) : 0
        snapshot.medianMilliseconds = Statistics.median(responseTimes) ?? 0
        snapshot.p90Milliseconds = Statistics.percentile(responseTimes, 0.9) ?? 0
        snapshot.speedIndex = speedIndex(normalized)
        snapshot.consistency = consistency(normalized)
        snapshot.recentSpeedChange = recentSpeedChange(timed, baselines: baselines)
        snapshot.globalBaselineMilliseconds = baselines.globalMedian
        snapshot.categoryBaselines = baselines.categories
        snapshot.operations = operationMetrics(timed, baselines: baselines)
        snapshot.categories = categoryMetrics(timed, baselines: baselines)
        snapshot.trends = trends(comparableSessions, operation: operation, baselines: baselines, calendar: calendar)
        snapshot.distribution = distribution(responseTimes)
        snapshot.fatigue = fatigue(comparableSessions, operation: operation, baselines: baselines)
        snapshot.heatmap = heatmap(timed)
        snapshot.slowestCompletions = slowestCompletions(timed, baselines: baselines)
        snapshot.personalBests = personalBests(comparableSessions)
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
            let relativeCopy: String
            if relative >= 1 {
                relativeCopy = "\(Int(((relative - 1) * 100).rounded()))% slower than your typical category"
            } else {
                relativeCopy = "\(Int(((1 - relative) * 100).rounded()))% faster than your typical category"
            }
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
        if let first = fatiguePoints.first, let last = fatiguePoints.last, first.normalizedEffort > 0 {
            let deterioration = last.normalizedEffort / first.normalizedEffort - 1
            if deterioration >= 0.10 {
                recommendations.append(Recommendation(
                    id: "fatigue",
                    title: "Use shorter intervals",
                    explanation: "Time-to-correct slows about \(Int((deterioration * 100).rounded()))% from the first to last fifth of a session. Try a focused 45-second interval.",
                    categoryKey: nil,
                    severity: min(deterioration, 1)
                ))
            }
        }
        return Array(recommendations.sorted { $0.severity > $1.severity }.prefix(3))
    }

    static func expectedScore(durationSeconds: Int, sessions: [PracticeSession], seed: UInt64 = 0x5A455441) -> ExpectedScore? {
        let times = timedAttempts(sessions.filter(\.isComparable), operation: nil).map { Int($0.milliseconds) }
        guard times.count >= 20 else { return nil }
        var random = SplitMix64(seed: seed)
        var simulated: [Int] = []
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
                  let milliseconds = attempt.responseTimeMilliseconds else { return nil }
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
    ) -> [TrendPoint] {
        let grouped = Dictionary(grouping: sessions) { calendar.startOfDay(for: $0.startedAt) }
        return grouped.compactMap { date, values in
            let timed = timedAttempts(values, operation: operation)
            guard !timed.isEmpty else { return nil }
            let duration = values.reduce(0) {
                $0 + Double($1.activeElapsedMilliseconds ?? ($1.durationSeconds * 1_000)) / 1_000
            }
            return TrendPoint(
                date: date,
                medianMilliseconds: Statistics.median(timed.map(\.milliseconds)) ?? 0,
                speedIndex: speedIndex(normalizedEfforts(timed, baselines: baselines)),
                questionsPerMinute: duration > 0 ? Double(timed.count) / (duration / 60) : 0
            )
        }.sorted { $0.date < $1.date }
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
        let overflow = DistributionBin(
            lowerMilliseconds: 10_000,
            upperMilliseconds: Int.max,
            count: values.filter { $0 >= 10_000 }.count,
            isOverflow: true
        )
        return regular + [overflow]
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
                    let fraction = value.attempt.presentedAt.timeIntervalSince(session.startedAt) / Double(max(1, session.durationSeconds))
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
        }
    }

    private static func slowestCompletions(_ timed: [TimedAttempt], baselines: TimingBaselines) -> [SlowCompletion] {
        timed.sorted { $0.milliseconds > $1.milliseconds }.prefix(10).map { value in
            SlowCompletion(
                id: value.attempt.id,
                prompt: value.attempt.prompt,
                categoryName: value.attempt.categoryName,
                responseMilliseconds: Int(value.milliseconds),
                baselineMultiple: value.milliseconds / max(baselines.value(for: value.attempt.categoryKey), 1),
                completedAt: value.attempt.answeredAt ?? value.attempt.presentedAt
            )
        }
    }

    private static func personalBests(_ sessions: [PracticeSession]) -> [String: Int] {
        let benchmarks = sessions.filter { $0.mode == .benchmark && $0.benchmarkID != nil }
        let grouped = Dictionary(grouping: benchmarks) { "\($0.benchmarkID ?? "unknown")-v\($0.benchmarkVersion ?? 0)" }
        return grouped.mapValues { $0.map(\.correctCount).max() ?? 0 }
    }
}
