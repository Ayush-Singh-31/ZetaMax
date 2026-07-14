import Foundation

enum AdaptiveModel {
    static let algorithmVersion = 2

    static func estimates(from sessions: [PracticeSession], now: Date = .now) -> [SkillEstimate] {
        let attempts = sessions.filter(\.isComparable).flatMap(\.attempts).filter {
            $0.wasEventuallyCorrect && $0.responseTimeMilliseconds != nil
        }
        let grouped = Dictionary(grouping: attempts, by: \QuestionAttempt.categoryKey)
        return grouped.compactMap { key, values in
            guard let first = values.first else { return nil }
            let ordered = values.sorted { $0.presentedAt < $1.presentedAt }
            let responseTimes = ordered.compactMap(\.responseTimeMilliseconds).map(Double.init)
            let medianResponse = Statistics.median(responseTimes) ?? 1_500
            let recent = Array(responseTimes.suffix(10))
            let previous = Array(responseTimes.dropLast(min(10, responseTimes.count)).suffix(20))
            let deterioration: Double
            if recent.count >= 5, previous.count >= 5,
               let recentMedian = Statistics.median(recent),
               let previousMedian = Statistics.median(previous), previousMedian > 0 {
                deterioration = min(max(recentMedian / previousMedian - 1, 0), 1)
            } else {
                deterioration = 0
            }
            return SkillEstimate(
                category: QuestionCategory(
                    key: key,
                    displayName: first.categoryName,
                    operation: first.operation
                ),
                estimatedAccuracy: 1,
                estimatedResponseMilliseconds: medianResponse,
                uncertainty: 1 / sqrt(Double(max(1, ordered.count))),
                deterioration: deterioration,
                lastPractisedAt: ordered.last?.presentedAt,
                attemptCount: ordered.count,
                algorithmVersion: algorithmVersion
            )
        }
    }

    static func categoryWeights(estimates: [SkillEstimate], focus: Double, now: Date = .now) -> [String: Double] {
        guard !estimates.isEmpty else { return [:] }
        let globalMedian = Statistics.median(estimates.map(\.estimatedResponseMilliseconds)) ?? 1_500
        let temperature = 1.0 - min(max(focus, 0), 1) * 0.85
        let weaknesses = estimates.map { estimate -> (String, Double) in
            let slowness = min(max(estimate.estimatedResponseMilliseconds / max(1, globalMedian) - 1, 0), 1)
            let days = estimate.lastPractisedAt.map { now.timeIntervalSince($0) / 86_400 } ?? 14
            let recency = min(max(days / 14, 0), 1)
            let uncertainty = min(max(estimate.uncertainty, 0), 1)
            let weakness = 0.50 * slowness
                + 0.25 * min(max(estimate.deterioration, 0), 1)
                + 0.15 * recency
                + 0.10 * uncertainty
            return (estimate.categoryKey, weakness)
        }
        let exponentials = weaknesses.map { ($0.0, exp($0.1 / temperature)) }
        let total = exponentials.reduce(0) { $0 + $1.1 }
        let uniform = 1 / Double(exponentials.count)
        return Dictionary(uniqueKeysWithValues: exponentials.map { key, value in
            (key, 0.9 * value / max(total, 0.0001) + 0.1 * uniform)
        })
    }
}

enum Statistics {
    static func mean(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }

    static func percentile(_ values: [Double], _ percentile: Double) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let index = min(sorted.count - 1, max(0, Int(ceil(percentile * Double(sorted.count))) - 1))
        return sorted[index]
    }

    static func standardDeviation(_ values: [Double]) -> Double? {
        guard let mean = mean(values), !values.isEmpty else { return nil }
        return sqrt(values.reduce(0) { $0 + pow($1 - mean, 2) } / Double(values.count))
    }

    static func medianAbsoluteDeviation(_ values: [Double]) -> Double? {
        guard let median = median(values) else { return nil }
        return self.median(values.map { abs($0 - median) })
    }
}
