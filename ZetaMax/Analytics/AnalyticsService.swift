import Foundation
import Observation
import OSLog
import SwiftData
import SwiftUI

enum AnalyticsDateRange: String, CaseIterable, Identifiable, Hashable, Sendable {
    case week = "7 days"
    case month = "30 days"
    case quarter = "90 days"
    case all = "All time"

    var id: String { rawValue }

    var days: Int? {
        switch self {
        case .week: 7
        case .month: 30
        case .quarter: 90
        case .all: nil
        }
    }
}

struct AnalyticsFilterKey: Hashable, Sendable {
    var dateRange: AnalyticsDateRange = .month
    var mode: PracticeMode?
    var operation: ArithmeticOperation?
    var targetedPreset: TargetedPreset?
    var benchmarkProfileKey: String?

    static let default30Days = AnalyticsFilterKey()
}

enum AppAppearance: String, CaseIterable, Identifiable, Hashable, Sendable {
    case system
    case light
    case dark

    static let defaultsKey = "appAppearance"

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var systemImage: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max.fill"
        case .dark: "moon.fill"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    static func persisted(in defaults: UserDefaults = .standard) -> AppAppearance {
        defaults.string(forKey: defaultsKey).flatMap(AppAppearance.init(rawValue:)) ?? .system
    }

    func persist(in defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.defaultsKey)
    }
}

@MainActor
@Observable
final class RepositoryRevision {
    private(set) var value = 0

    func advance() {
        value &+= 1
    }
}

struct AnalyticsServiceMetrics: Equatable, Sendable {
    var coldCalculations = 0
    var cacheHits = 0
    var cancelledCalculations = 0
    var datasetFetches = 0
    var recommendationCalculations = 0
    var historyBaselineCalculations = 0
}

struct AnalyticsServiceResult<Value: Sendable>: Sendable {
    let value: Value
    let wasCacheHit: Bool
    let calculationMilliseconds: Double
}

struct AnalyticsStaleRevisionError: Error, Equatable, Sendable {
    let requestedRevision: Int
    let currentRevision: Int?
}

private struct AnalyticsDataset: Sendable {
    let sessions: [AnalyticsSessionInput]
    let estimates: [AnalyticsSkillEstimateInput]
}

private struct AnalyticsSnapshotCacheKey: Hashable, Sendable {
    let revision: Int
    let filter: AnalyticsFilterKey
}

private struct InFlightSnapshot: Sendable {
    let task: Task<DashboardSnapshot?, Never>
    var waiterIDs: Set<UUID>
}

actor AnalyticsService {
    private static let snapshotCacheLimit = 16

    private let container: ModelContainer?
    private let testingDataset: AnalyticsDataset?
    private let testingCalculationDelay: Duration?
    private var datasetRevision: Int?
    private var dataset: AnalyticsDataset?
    private var snapshots: [AnalyticsSnapshotCacheKey: DashboardSnapshot] = [:]
    private var snapshotRecency: [AnalyticsSnapshotCacheKey] = []
    private var inFlightSnapshots: [AnalyticsSnapshotCacheKey: InFlightSnapshot] = [:]
    private var recommendationsByRevision: [Int: [Recommendation]] = [:]
    private var historyBaselinesByRevision: [Int: TimingBaselineResult] = [:]
    private var serviceMetrics = AnalyticsServiceMetrics()
    private let logger = Logger(subsystem: "com.ayush.ZetaMax", category: "Analytics")

    init(container: ModelContainer) {
        self.container = container
        testingDataset = nil
        testingCalculationDelay = nil
    }

    init(
        testingSessions: [AnalyticsSessionInput],
        estimates: [AnalyticsSkillEstimateInput] = [],
        calculationDelay: Duration? = nil
    ) {
        container = nil
        testingDataset = AnalyticsDataset(sessions: testingSessions, estimates: estimates)
        testingCalculationDelay = calculationDelay
    }

    func snapshot(
        for filter: AnalyticsFilterKey,
        revision: Int,
        now: Date = .now
    ) async throws -> AnalyticsServiceResult<DashboardSnapshot> {
        let key = AnalyticsSnapshotCacheKey(revision: revision, filter: filter)
        if let cached = cachedSnapshot(for: key) {
            serviceMetrics.cacheHits += 1
            logger.debug("Analytics cache hit revision=\(revision) range=\(filter.dateRange.rawValue, privacy: .public)")
            return AnalyticsServiceResult(value: cached, wasCacheHit: true, calculationMilliseconds: 0)
        }

        let waiterID = UUID()
        let calculation: Task<DashboardSnapshot?, Never>
        if var inFlight = inFlightSnapshots[key] {
            inFlight.waiterIDs.insert(waiterID)
            inFlightSnapshots[key] = inFlight
            calculation = inFlight.task
        } else {
            let source = try loadDataset(revision: revision)
            let intervals = intervals(for: filter.dateRange, now: now)
            let current = filtered(source.sessions, filter: filter, interval: intervals.current)
            let previous = intervals.previous.map { filtered(source.sessions, filter: filter, interval: $0) }
            let filteredBaseline = filtered(source.sessions, filter: filter, interval: intervals.baseline)
            let baseline = filteredBaseline.isEmpty ? current : filteredBaseline
            let operation = filter.operation
            let delay = testingCalculationDelay
            calculation = Task.detached(priority: .userInitiated) {
                if let delay {
                    try? await Task.sleep(for: delay)
                }
                let value = AnalyticsEngine.snapshot(
                    inputs: current,
                    baselineInputs: baseline,
                    previousInputs: previous,
                    operation: operation
                )
                return Task.isCancelled ? nil : value
            }
            inFlightSnapshots[key] = InFlightSnapshot(
                task: calculation,
                waiterIDs: [waiterID]
            )
        }
        let clock = ContinuousClock()
        let start = clock.now

        do {
            let value = try await withTaskCancellationHandler {
                guard let value = await calculation.value else { throw CancellationError() }
                try Task.checkCancellation()
                return value
            } onCancel: {
                Task {
                    await self.cancelSnapshotWaiter(waiterID, for: key)
                }
            }
            finishSnapshotWaiter(waiterID, for: key)
            guard datasetRevision == revision else {
                throw AnalyticsStaleRevisionError(
                    requestedRevision: revision,
                    currentRevision: datasetRevision
                )
            }
            if let cached = cachedSnapshot(for: key) {
                serviceMetrics.cacheHits += 1
                return AnalyticsServiceResult(value: cached, wasCacheHit: true, calculationMilliseconds: 0)
            }
            let elapsed = milliseconds(start.duration(to: clock.now))
            storeSnapshot(value, for: key)
            inFlightSnapshots[key] = nil
            serviceMetrics.coldCalculations += 1
            logger.notice("Analytics cold calculation revision=\(revision) milliseconds=\(elapsed, privacy: .public)")
            return AnalyticsServiceResult(value: value, wasCacheHit: false, calculationMilliseconds: elapsed)
        } catch is CancellationError {
            cancelSnapshotWaiter(waiterID, for: key)
            serviceMetrics.cancelledCalculations += 1
            throw CancellationError()
        } catch let error as AnalyticsStaleRevisionError {
            inFlightSnapshots[key] = nil
            throw error
        }
    }

    func recommendations(
        revision: Int,
        now: Date = .now
    ) async throws -> AnalyticsServiceResult<[Recommendation]> {
        if let cached = recommendationsByRevision[revision] {
            serviceMetrics.cacheHits += 1
            return AnalyticsServiceResult(value: cached, wasCacheHit: true, calculationMilliseconds: 0)
        }
        let source = try loadDataset(revision: revision)
        let clock = ContinuousClock()
        let start = clock.now
        let sessions = source.sessions
        let estimates = source.estimates
        let calculation = Task.detached(priority: .userInitiated) {
            AnalyticsEngine.recommendations(sessions: sessions, estimates: estimates, now: now)
        }
        let value = try await withTaskCancellationHandler {
            let value = await calculation.value
            try Task.checkCancellation()
            return value
        } onCancel: {
            calculation.cancel()
        }
        guard datasetRevision == revision else {
            throw AnalyticsStaleRevisionError(
                requestedRevision: revision,
                currentRevision: datasetRevision
            )
        }
        let elapsed = milliseconds(start.duration(to: clock.now))
        recommendationsByRevision[revision] = value
        serviceMetrics.recommendationCalculations += 1
        return AnalyticsServiceResult(value: value, wasCacheHit: false, calculationMilliseconds: elapsed)
    }

    func historyBaseline(revision: Int) async throws -> AnalyticsServiceResult<TimingBaselineResult> {
        if let cached = historyBaselinesByRevision[revision] {
            serviceMetrics.cacheHits += 1
            return AnalyticsServiceResult(value: cached, wasCacheHit: true, calculationMilliseconds: 0)
        }
        let sessions = try loadDataset(revision: revision).sessions
        let clock = ContinuousClock()
        let start = clock.now
        let calculation = Task.detached(priority: .userInitiated) {
            AnalyticsEngine.timingBaseline(inputs: sessions)
        }
        let value = try await withTaskCancellationHandler {
            let value = await calculation.value
            try Task.checkCancellation()
            return value
        } onCancel: {
            calculation.cancel()
        }
        guard datasetRevision == revision else {
            throw AnalyticsStaleRevisionError(
                requestedRevision: revision,
                currentRevision: datasetRevision
            )
        }
        let elapsed = milliseconds(start.duration(to: clock.now))
        historyBaselinesByRevision[revision] = value
        serviceMetrics.historyBaselineCalculations += 1
        return AnalyticsServiceResult(value: value, wasCacheHit: false, calculationMilliseconds: elapsed)
    }

    func invalidate(for revision: Int) {
        for (key, inFlight) in inFlightSnapshots where key.revision != revision {
            inFlight.task.cancel()
        }
        inFlightSnapshots = inFlightSnapshots.filter { $0.key.revision == revision }
        if datasetRevision != revision {
            datasetRevision = nil
            dataset = nil
        }
        snapshots = snapshots.filter { $0.key.revision == revision }
        snapshotRecency = snapshotRecency.filter { $0.revision == revision }
        recommendationsByRevision = recommendationsByRevision.filter { $0.key == revision }
        historyBaselinesByRevision = historyBaselinesByRevision.filter { $0.key == revision }
    }

    func metrics() -> AnalyticsServiceMetrics {
        serviceMetrics
    }

    func cachedSnapshotCount() -> Int {
        snapshots.count
    }

    private func loadDataset(revision: Int) throws -> AnalyticsDataset {
        if datasetRevision == revision, let dataset { return dataset }
        if let testingDataset {
            datasetRevision = revision
            dataset = testingDataset
            serviceMetrics.datasetFetches += 1
            return testingDataset
        }
        guard let container else { return AnalyticsDataset(sessions: [], estimates: []) }
        let context = ModelContext(container)
        var descriptor = FetchDescriptor<PracticeSession>()
        descriptor.sortBy = [SortDescriptor(\PracticeSession.startedAt, order: .reverse)]
        let sessions = try context.fetch(descriptor).map(AnalyticsSessionInput.init)
        let estimates = try context.fetch(FetchDescriptor<SkillEstimate>()).map(AnalyticsSkillEstimateInput.init)
        let value = AnalyticsDataset(sessions: sessions, estimates: estimates)
        datasetRevision = revision
        dataset = value
        serviceMetrics.datasetFetches += 1
        return value
    }

    private func filtered(
        _ sessions: [AnalyticsSessionInput],
        filter: AnalyticsFilterKey,
        interval: DateInterval?
    ) -> [AnalyticsSessionInput] {
        sessions.filter { session in
            let dateMatches = interval.map { $0.contains(session.startedAt) } ?? true
            let modeMatches = filter.mode == nil || session.mode == filter.mode
            let targetMatches = filter.targetedPreset == nil || session.configuration.targetedPreset == filter.targetedPreset
            let benchmarkMatches = filter.benchmarkProfileKey == nil || profileKey(session) == filter.benchmarkProfileKey
            return dateMatches && modeMatches && targetMatches && benchmarkMatches
        }
    }

    private func profileKey(_ session: AnalyticsSessionInput) -> String {
        "\(session.benchmarkID ?? "")-v\(session.benchmarkVersion ?? 0)"
    }

    private func intervals(
        for range: AnalyticsDateRange,
        now: Date
    ) -> (current: DateInterval?, previous: DateInterval?, baseline: DateInterval?) {
        guard let days = range.days,
              let start = Calendar.current.date(byAdding: .day, value: -days, to: now),
              let previousStart = Calendar.current.date(byAdding: .day, value: -days, to: start) else {
            return (nil, nil, nil)
        }
        return (
            DateInterval(start: start, end: now),
            DateInterval(start: previousStart, end: start),
            DateInterval(start: .distantPast, end: start)
        )
    }

    private func cachedSnapshot(for key: AnalyticsSnapshotCacheKey) -> DashboardSnapshot? {
        guard let value = snapshots[key] else { return nil }
        snapshotRecency.removeAll { $0 == key }
        snapshotRecency.append(key)
        return value
    }

    private func storeSnapshot(_ snapshot: DashboardSnapshot, for key: AnalyticsSnapshotCacheKey) {
        snapshots[key] = snapshot
        snapshotRecency.removeAll { $0 == key }
        snapshotRecency.append(key)
        while snapshotRecency.count > Self.snapshotCacheLimit {
            let evicted = snapshotRecency.removeFirst()
            snapshots[evicted] = nil
        }
    }

    private func finishSnapshotWaiter(_ waiterID: UUID, for key: AnalyticsSnapshotCacheKey) {
        guard var inFlight = inFlightSnapshots[key] else { return }
        inFlight.waiterIDs.remove(waiterID)
        inFlightSnapshots[key] = inFlight
    }

    private func cancelSnapshotWaiter(_ waiterID: UUID, for key: AnalyticsSnapshotCacheKey) {
        guard var inFlight = inFlightSnapshots[key] else { return }
        inFlight.waiterIDs.remove(waiterID)
        if inFlight.waiterIDs.isEmpty {
            inFlight.task.cancel()
            inFlightSnapshots[key] = nil
        } else {
            inFlightSnapshots[key] = inFlight
        }
    }

    private func milliseconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) * 1_000 + Double(components.attoseconds) / 1_000_000_000_000_000
    }
}

@MainActor
@Observable
final class AnalyticsStore {
    private let service: AnalyticsService
    private let revision: RepositoryRevision
    private let logger = Logger(subsystem: "com.ayush.ZetaMax", category: "Navigation")
    private var snapshotTask: Task<Void, Never>?
    private var recommendationTask: Task<Void, Never>?
    private var historyTask: Task<Void, Never>?
    private var prewarmTask: Task<Void, Never>?
    private var repositoryChangeTask: Task<Void, Never>?
    private var snapshotRequestID: UUID?
    private var recommendationRequestID: UUID?
    private var historyRequestID: UUID?
    private var currentSnapshotFilter: AnalyticsFilterKey?
    private var recommendationsWereRequested = false
    private var historyWasRequested = false

    private(set) var snapshot = DashboardSnapshot()
    private(set) var recommendations: [Recommendation] = []
    private(set) var historyBaseline = TimingBaselineResult.empty
    private(set) var isRefreshingSnapshot = false
    private(set) var isRefreshingRecommendations = false
    private(set) var isRefreshingHistory = false
    private(set) var lastSnapshotWasCacheHit = false
    private(set) var lastPresentationMilliseconds = 0.0
    private(set) var errorMessage: String?

    init(container: ModelContainer, revision: RepositoryRevision) {
        service = AnalyticsService(container: container)
        self.revision = revision
    }

    func prewarmDefaultSnapshot() {
        prewarmTask?.cancel()
        let revisionValue = revision.value
        prewarmTask = Task {
            _ = try? await service.snapshot(for: .default30Days, revision: revisionValue)
        }
    }

    func requestSnapshot(for filter: AnalyticsFilterKey, debounce: Bool = true) {
        snapshotTask?.cancel()
        currentSnapshotFilter = filter
        let requestID = UUID()
        snapshotRequestID = requestID
        let revisionValue = revision.value
        isRefreshingSnapshot = true
        errorMessage = nil
        let start = ContinuousClock.now
        snapshotTask = Task {
            defer {
                if snapshotRequestID == requestID { isRefreshingSnapshot = false }
            }
            do {
                if debounce { try await Task.sleep(for: .milliseconds(150)) }
                let result = try await service.snapshot(for: filter, revision: revisionValue)
                try Task.checkCancellation()
                guard revision.value == revisionValue else { return }
                snapshot = result.value
                lastSnapshotWasCacheHit = result.wasCacheHit
                lastPresentationMilliseconds = Self.milliseconds(start.duration(to: .now))
                logger.notice("Analytics presented cacheHit=\(result.wasCacheHit) milliseconds=\(self.lastPresentationMilliseconds, privacy: .public)")
            } catch is CancellationError {
                return
            } catch is AnalyticsStaleRevisionError {
                if snapshotRequestID == requestID {
                    requestSnapshot(for: filter, debounce: false)
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func requestRecommendations() {
        recommendationTask?.cancel()
        recommendationsWereRequested = true
        let requestID = UUID()
        recommendationRequestID = requestID
        let revisionValue = revision.value
        let start = ContinuousClock.now
        isRefreshingRecommendations = true
        recommendationTask = Task {
            defer {
                if recommendationRequestID == requestID { isRefreshingRecommendations = false }
            }
            do {
                let result = try await service.recommendations(revision: revisionValue)
                try Task.checkCancellation()
                guard revision.value == revisionValue else { return }
                recommendations = result.value
                let elapsed = Self.milliseconds(start.duration(to: .now))
                logger.notice("Recommendations presented cacheHit=\(result.wasCacheHit) milliseconds=\(elapsed, privacy: .public)")
            } catch is CancellationError {
                return
            } catch is AnalyticsStaleRevisionError {
                if recommendationRequestID == requestID {
                    requestRecommendations()
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func requestHistoryBaseline() {
        historyTask?.cancel()
        historyWasRequested = true
        let requestID = UUID()
        historyRequestID = requestID
        let revisionValue = revision.value
        let start = ContinuousClock.now
        isRefreshingHistory = true
        historyTask = Task {
            defer {
                if historyRequestID == requestID { isRefreshingHistory = false }
            }
            do {
                let result = try await service.historyBaseline(revision: revisionValue)
                try Task.checkCancellation()
                guard revision.value == revisionValue else { return }
                historyBaseline = result.value
                let elapsed = Self.milliseconds(start.duration(to: .now))
                logger.notice("History presented cacheHit=\(result.wasCacheHit) milliseconds=\(elapsed, privacy: .public)")
            } catch is CancellationError {
                return
            } catch is AnalyticsStaleRevisionError {
                if historyRequestID == requestID {
                    requestHistoryBaseline()
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func repositoryDidChange() {
        repositoryChangeTask?.cancel()
        snapshotTask?.cancel()
        recommendationTask?.cancel()
        historyTask?.cancel()
        prewarmTask?.cancel()
        snapshotRequestID = nil
        recommendationRequestID = nil
        historyRequestID = nil
        isRefreshingSnapshot = false
        isRefreshingRecommendations = false
        isRefreshingHistory = false
        let revisionValue = revision.value
        repositoryChangeTask = Task {
            await service.invalidate(for: revisionValue)
            guard !Task.isCancelled else { return }
            if let currentSnapshotFilter {
                requestSnapshot(for: currentSnapshotFilter, debounce: false)
            } else {
                prewarmDefaultSnapshot()
            }
            if recommendationsWereRequested { requestRecommendations() }
            if historyWasRequested { requestHistoryBaseline() }
        }
    }

    private static func milliseconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) * 1_000 + Double(components.attoseconds) / 1_000_000_000_000_000
    }
}
