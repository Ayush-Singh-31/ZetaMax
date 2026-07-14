import SwiftData
import SwiftUI

@main
@MainActor
struct ZetaMaxApp: App {
    private let container: ModelContainer
    private let repository: SwiftDataRepository
    @State private var engine: SessionEngine
    @State private var navigation = NavigationModel()

    init() {
        do {
            let arguments = ProcessInfo.processInfo.arguments
            let isUITesting = arguments.contains("-ui-testing")
            let container = try DataStore.makeContainer(inMemory: isUITesting)
            let repository = SwiftDataRepository(context: container.mainContext)
            try repository.recoverInterruptedSessions()
            try repository.rebuildSkillEstimatesIfNeeded()
            if isUITesting && arguments.contains("-ui-testing-analytics") {
                try Self.seedUITestTimingData(repository: repository)
            }
            self.container = container
            self.repository = repository
            let engine = SessionEngine(repository: repository)
            if isUITesting {
                var configuration = PracticeConfiguration.classicDefault
                configuration.durationSeconds = 15
                if arguments.contains("-ui-testing-negative") {
                    configuration.mode = .targeted
                    configuration.targetedPreset = .negativeSubtraction
                    configuration.targetedRange = OperandRange(2, 20)
                } else if arguments.contains("-ui-testing-decimal") {
                    configuration.mode = .targeted
                    configuration.targetedPreset = .decimalArithmetic
                    configuration.targetedRange = OperandRange(2, 20)
                } else {
                    configuration.operations = [.addition]
                    configuration.additionLeft = OperandRange(2, 9)
                    configuration.additionRight = OperandRange(2, 9)
                }
                engine.configuration = configuration
            } else if let data = UserDefaults.standard.data(forKey: "lastPracticeConfiguration"),
               let saved = try? JSONDecoder().decode(PracticeConfiguration.self, from: data) {
                engine.configuration = saved.validated
            }
            _engine = State(initialValue: engine)
        } catch {
            fatalError("Unable to create ZetaMax data store: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            AppRootView(engine: engine, navigation: navigation, repository: repository)
                .modelContainer(container)
                .onChange(of: engine.configuration) { _, configuration in
                    if let data = try? JSONEncoder().encode(configuration) {
                        UserDefaults.standard.set(data, forKey: "lastPracticeConfiguration")
                    }
                }
        }
        .defaultSize(width: 1_100, height: 760)
        .commands {
            CommandMenu("Practice") {
                Button("Start Session") {
                    navigation.selection = .practice
                    engine.start()
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(engine.phase == .running)

                Button("End Session") { engine.endEarly() }
                    .keyboardShortcut(.escape, modifiers: [])
                    .disabled(engine.phase != .running)
            }
            CommandMenu("Navigate") {
                ForEach(Array(AppSection.allCases.enumerated()), id: \.element.id) { index, section in
                    Button(section.title) { navigation.selection = section }
                        .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: [.command])
                }
            }
        }
    }

    private static func seedUITestTimingData(repository: SwiftDataRepository) throws {
        let now = Date.now
        for sessionIndex in 0..<2 {
            var configuration = PracticeConfiguration.classicDefault
            configuration.durationSeconds = 120
            let startedAt = now.addingTimeInterval(Double(sessionIndex - 2) * 86_400)
            let session = try repository.createSession(
                configuration: configuration,
                seed: UInt64(8_000 + sessionIndex),
                startedAt: startedAt
            )
            for position in 0..<20 {
                let isHard = position.isMultiple(of: 2)
                let question = GeneratedQuestion(
                    operation: .multiplication,
                    kind: .standard,
                    category: QuestionCategory(
                        key: isHard ? "multiplication/ui-hard" : "multiplication/ui-core",
                        displayName: isHard ? "Multiplication · two-digit pair" : "Multiplication · core pair",
                        operation: .multiplication
                    ),
                    leftOperand: isHard ? 12 : 7,
                    rightOperand: isHard ? 99 : 8,
                    prompt: isHard ? "12 × 99" : "7 × 8",
                    correctAnswer: isHard ? 1_188 : 56
                )
                let presentedAt = startedAt.addingTimeInterval(Double(position) * 5)
                let attempt = QuestionAttempt(question: question, position: position, presentedAt: presentedAt)
                try repository.addAttempt(attempt, to: session)
                let response = (isHard ? 2_500 : 900) + sessionIndex * 350 + position * 25
                attempt.wasEventuallyCorrect = true
                attempt.responseTimeMilliseconds = response
                attempt.answeredAt = presentedAt.addingTimeInterval(Double(response) / 1_000)
                try repository.addSubmission(
                    AnswerSubmission(
                        rawInput: question.answerCanonical,
                        normalizedAnswer: question.correctAnswer,
                        submittedAt: attempt.answeredAt!,
                        elapsedMilliseconds: response,
                        isCorrect: true
                    ),
                    to: attempt,
                    session: session
                )
            }
            try repository.finish(
                session,
                status: .completed,
                reason: .timerExpired,
                at: startedAt.addingTimeInterval(120),
                elapsedMilliseconds: 120_000
            )
        }
        try repository.replaceSkillEstimates(with: AdaptiveModel.estimates(from: repository.fetchSessions()))
    }
}
