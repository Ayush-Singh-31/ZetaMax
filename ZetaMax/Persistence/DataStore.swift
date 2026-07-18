import Foundation
import SwiftData

@MainActor
protocol AttemptRepository: AnyObject {
    func createSession(configuration: PracticeConfiguration, seed: UInt64, startedAt: Date) throws -> PracticeSession
    func addAttempt(_ attempt: QuestionAttempt, to session: PracticeSession) throws
    func addSubmission(_ submission: AnswerSubmission, to attempt: QuestionAttempt, session: PracticeSession) throws
    func finish(_ session: PracticeSession, status: SessionStatus, reason: SessionEndReason, at date: Date, elapsedMilliseconds: Int) throws
    func fetchSessions() throws -> [PracticeSession]
    func fetchSkillEstimates() throws -> [SkillEstimate]
    func replaceSkillEstimates(with estimates: [SkillEstimate]) throws
}

enum DataStore {
    static let schema = Schema([
        PracticeSession.self,
        QuestionAttempt.self,
        AnswerSubmission.self,
        SkillEstimate.self
    ])

    static func makeContainer(inMemory: Bool = false, storeURL: URL? = nil) throws -> ModelContainer {
        let configuration: ModelConfiguration
        if let storeURL {
            configuration = ModelConfiguration("ZetaMax", schema: schema, url: storeURL, allowsSave: true)
        } else {
            configuration = ModelConfiguration(
                "ZetaMax",
                schema: schema,
                isStoredInMemoryOnly: inMemory,
                allowsSave: true
            )
        }
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}

@MainActor
final class SwiftDataRepository: AttemptRepository {
    let context: ModelContext
    let revision: RepositoryRevision

    init(context: ModelContext, revision: RepositoryRevision? = nil) {
        self.context = context
        self.revision = revision ?? RepositoryRevision()
        context.autosaveEnabled = true
    }

    func createSession(configuration: PracticeConfiguration, seed: UInt64, startedAt: Date) throws -> PracticeSession {
        let session = PracticeSession(configuration: configuration, seed: seed, startedAt: startedAt)
        context.insert(session)
        try context.save()
        return session
    }

    func addAttempt(_ attempt: QuestionAttempt, to session: PracticeSession) throws {
        context.insert(attempt)
        attempt.session = session
        session.attempts.append(attempt)
        session.appendToSearchableText(for: attempt)
        try context.save()
    }

    func addSubmission(_ submission: AnswerSubmission, to attempt: QuestionAttempt, session: PracticeSession) throws {
        context.insert(submission)
        submission.attempt = attempt
        attempt.submissions.append(submission)
        if submission.isCorrect {
            session.correctCount += 1
        } else {
            session.incorrectSubmissionCount += 1
            attempt.incorrectAttempts += 1
        }
        try context.save()
    }

    func finish(
        _ session: PracticeSession,
        status: SessionStatus,
        reason: SessionEndReason,
        at date: Date,
        elapsedMilliseconds: Int
    ) throws {
        session.status = status
        session.endReason = reason
        session.endedAt = date
        session.activeElapsedMilliseconds = elapsedMilliseconds
        try context.save()
        revision.advance()
    }

    func fetchSessions() throws -> [PracticeSession] {
        var descriptor = FetchDescriptor<PracticeSession>()
        descriptor.sortBy = [SortDescriptor(\PracticeSession.startedAt, order: .reverse)]
        return try context.fetch(descriptor)
    }

    func fetchSkillEstimates() throws -> [SkillEstimate] {
        try context.fetch(FetchDescriptor<SkillEstimate>())
    }

    func replaceSkillEstimates(with estimates: [SkillEstimate]) throws {
        for old in try fetchSkillEstimates() { context.delete(old) }
        estimates.forEach(context.insert)
        try context.save()
        revision.advance()
    }

    func rebuildSkillEstimatesIfNeeded() throws {
        let sessions = try fetchSessions()
        let sessionsMissingSearchIndex = sessions.filter(\.searchableText.isEmpty)
        sessionsMissingSearchIndex.forEach { $0.rebuildSearchableText() }
        if !sessionsMissingSearchIndex.isEmpty {
            try context.save()
        }
        let estimates = try fetchSkillEstimates()
        guard (!sessions.isEmpty && estimates.isEmpty)
                || estimates.contains(where: { $0.algorithmVersion != AdaptiveModel.algorithmVersion }) else { return }
        try replaceSkillEstimates(with: AdaptiveModel.estimates(from: sessions))
    }

    func recoverInterruptedSessions(at date: Date = .now) throws {
        let inProgress = SessionStatus.inProgress.rawValue
        let descriptor = FetchDescriptor<PracticeSession>(predicate: #Predicate { $0.statusRaw == inProgress })
        let sessions = try context.fetch(descriptor)
        for session in sessions {
            session.status = .interrupted
            session.endReason = .recoveredAfterLaunch
            session.endedAt = date
        }
        try context.save()
        if !sessions.isEmpty { revision.advance() }
    }

    func delete(_ session: PracticeSession) throws {
        let remainingSessions = try fetchSessions().filter { $0.id != session.id }
        let rebuiltEstimates = AdaptiveModel.estimates(from: remainingSessions)
        do {
            context.delete(session)
            for estimate in try fetchSkillEstimates() { context.delete(estimate) }
            rebuiltEstimates.forEach(context.insert)
            try context.save()
            revision.advance()
        } catch {
            context.rollback()
            throw error
        }
    }

    func resetAllData() throws {
        do {
            // Deleting the roots lets SwiftData honor both cascade relationships.
            // Batch-deleting children first violates the mandatory inverse triggers
            // in an on-disk store before the graph can be cascaded.
            for session in try fetchSessions() { context.delete(session) }
            for estimate in try fetchSkillEstimates() { context.delete(estimate) }
            try context.save()
            revision.advance()
        } catch {
            context.rollback()
            throw error
        }
    }
}
