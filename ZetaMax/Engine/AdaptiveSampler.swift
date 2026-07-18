import Foundation

enum AdaptiveModelParameters {
    static let slownessWeight = 0.50
    static let deteriorationWeight = 0.25
    static let recencyWeight = 0.15
    static let uncertaintyWeight = 0.10
    static let explorationRate = 0.10

    static let explanation =
        "Weights combine relative time-to-correct (50%), recent slowdown (25%), recency (15%), and uncertainty (10%). Ten percent of sampling remains exploratory."

    static func severity(
        slowness: Double,
        deterioration: Double,
        recency: Double,
        uncertainty: Double
    ) -> Double {
        slownessWeight * min(max(slowness, 0), 1)
            + deteriorationWeight * min(max(deterioration, 0), 1)
            + recencyWeight * min(max(recency, 0), 1)
            + uncertaintyWeight * min(max(uncertainty, 0), 1)
    }
}

enum AdaptiveModel {
    static let algorithmVersion = 3

    static func estimates(from sessions: [PracticeSession], now: Date = .now) -> [SkillEstimate] {
        let attempts = sessions.filter(\.isComparable).flatMap(\.attempts).filter {
            ($0.wasEventuallyCorrect || $0.isCensored) && $0.responseTimeMilliseconds != nil
        }
        let grouped = Dictionary(grouping: attempts, by: \QuestionAttempt.categoryKey)
        return grouped.compactMap { key, values in
            guard let first = values.first else { return nil }
            let ordered = values.sorted { $0.presentedAt < $1.presentedAt }
            let completed = ordered.filter(\.wasEventuallyCorrect)
            let responseTimes = completed.compactMap(\.responseTimeMilliseconds).map(Double.init)
            let observations = ordered.compactMap { attempt -> Statistics.RightCensoredObservation? in
                guard let milliseconds = attempt.responseTimeMilliseconds else { return nil }
                return Statistics.RightCensoredObservation(
                    value: Double(milliseconds),
                    isEvent: attempt.wasEventuallyCorrect
                )
            }
            let medianResponse = Statistics.rightCensoredPercentile(observations, 0.5)
                ?? Statistics.median(responseTimes)
                ?? 1_500
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
            let submissions = ordered.flatMap(\.submissions)
            let estimatedAccuracy = submissions.isEmpty
                ? 1
                : Double(submissions.filter(\.isCorrect).count) / Double(submissions.count)
            return SkillEstimate(
                category: QuestionCategory(
                    key: key,
                    displayName: first.categoryName,
                    operation: first.operation
                ),
                estimatedAccuracy: estimatedAccuracy,
                estimatedResponseMilliseconds: medianResponse,
                uncertainty: 1 / sqrt(Double(max(1, ordered.count))),
                deterioration: deterioration,
                lastPractisedAt: ordered.last?.presentedAt,
                attemptCount: completed.count,
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
            let weakness = AdaptiveModelParameters.severity(
                slowness: slowness,
                deterioration: estimate.deterioration,
                recency: recency,
                uncertainty: uncertainty
            )
            return (estimate.categoryKey, weakness)
        }
        let exponentials = weaknesses.map { ($0.0, exp($0.1 / temperature)) }
        let total = exponentials.reduce(0) { $0 + $1.1 }
        let uniform = 1 / Double(exponentials.count)
        return Dictionary(uniqueKeysWithValues: exponentials.map { key, value in
            (
                key,
                (1 - AdaptiveModelParameters.explorationRate) * value / max(total, 0.0001)
                    + AdaptiveModelParameters.explorationRate * uniform
            )
        })
    }
}

enum Statistics {
    static let reliableTailSampleCount = 10

    struct RightCensoredObservation: Hashable, Sendable {
        let value: Double
        let isEvent: Bool
    }

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
        guard sorted.count > 1 else { return sorted[0] }
        let probability = min(max(percentile, 0), 1)
        let position = probability * Double(sorted.count - 1)
        let lowerIndex = Int(floor(position))
        let upperIndex = Int(ceil(position))
        guard lowerIndex != upperIndex else { return sorted[lowerIndex] }
        let fraction = position - Double(lowerIndex)
        return sorted[lowerIndex] + fraction * (sorted[upperIndex] - sorted[lowerIndex])
    }

    static func rightCensoredPercentile(
        _ observations: [RightCensoredObservation],
        _ percentile: Double
    ) -> Double? {
        let usable = observations.filter { $0.value.isFinite && $0.value >= 0 }
        guard !usable.isEmpty else { return nil }
        if usable.allSatisfy(\.isEvent) {
            return self.percentile(usable.map(\.value), percentile)
        }

        let ordered = usable.sorted { $0.value < $1.value }
        let probability = min(max(percentile, 0), 1)
        var atRisk = ordered.count
        var survival = 1.0
        var index = 0
        while index < ordered.count, atRisk > 0 {
            let value = ordered[index].value
            var events = 0
            var censored = 0
            while index < ordered.count, ordered[index].value == value {
                if ordered[index].isEvent { events += 1 } else { censored += 1 }
                index += 1
            }
            if events > 0 {
                survival *= 1 - Double(events) / Double(atRisk)
                if 1 - survival >= probability { return value }
            }
            atRisk -= events + censored
        }
        // The requested quantile lies beyond the observable event curve. The
        // longest observed/censored time is a conservative lower bound.
        return ordered.last?.value
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
