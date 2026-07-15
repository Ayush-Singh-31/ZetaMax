import SwiftData
import SwiftUI

@main
@MainActor
struct ZetaMaxApp: App {
    private let container: ModelContainer
    private let repository: SwiftDataRepository
    private let analyticsStore: AnalyticsStore
    @State private var engine: SessionEngine
    @State private var navigation = NavigationModel()
    @State private var appearance: AppAppearance

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
            self.analyticsStore = AnalyticsStore(container: container, revision: repository.revision)
            _appearance = State(initialValue: AppAppearance.persisted())
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
                    if arguments.contains("-ui-testing-one-digit") {
                        configuration.additionLeft = OperandRange(2, 3)
                        configuration.additionRight = OperandRange(2, 3)
                    } else {
                        configuration.additionLeft = OperandRange(2, 9)
                        configuration.additionRight = OperandRange(2, 9)
                    }
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
            AppRootView(
                engine: engine,
                navigation: navigation,
                repository: repository,
                analyticsStore: analyticsStore,
                appearance: $appearance
            )
                .modelContainer(container)
                .onChange(of: engine.configuration) { _, configuration in
                    if let data = try? JSONEncoder().encode(configuration) {
                        UserDefaults.standard.set(data, forKey: "lastPracticeConfiguration")
                    }
                }
                .onChange(of: appearance) { _, appearance in
                    appearance.persist()
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
        for sessionIndex in 0..<6 {
            var configuration = PracticeConfiguration.classicDefault
            configuration.durationSeconds = 120
            switch sessionIndex % 4 {
            case 1:
                configuration.mode = .adaptive
                configuration.adaptiveFocus = 0.65
            case 2:
                configuration.mode = .targeted
                configuration.targetedPreset = .quantInterview
            case 3:
                configuration = BenchmarkProfile.builtIns.first { $0.durationSeconds == 120 }!.configuration
            default:
                break
            }
            let startedAt = now.addingTimeInterval(Double(sessionIndex - 5) * 4.5 * 86_400)
            let session = PracticeSession(configuration: configuration, seed: UInt64(8_000 + sessionIndex), startedAt: startedAt)
            repository.context.insert(session)
            let questionCount = 16 + sessionIndex % 3
            for position in 0..<questionCount {
                let question = fixtureQuestion(index: position, sessionIndex: sessionIndex)
                let presentedAt = startedAt.addingTimeInterval(Double(position) * (120 / Double(questionCount)))
                let attempt = QuestionAttempt(question: question, position: position, presentedAt: presentedAt)
                repository.context.insert(attempt)
                attempt.session = session
                session.attempts.append(attempt)
                let base = fixtureBaseMilliseconds(for: question)
                let historicalShift = (5 - sessionIndex) * 70
                let lateSessionAdjustment = position >= (questionCount * 4 / 5) ? 430 : (position >= questionCount * 3 / 5 ? 160 : 0)
                let deterministicNoise = ((position * 137 + sessionIndex * 83) % 620) - 220
                let response = max(420, base + historicalShift + lateSessionAdjustment + deterministicNoise)
                attempt.wasEventuallyCorrect = true
                attempt.responseTimeMilliseconds = response
                attempt.answeredAt = presentedAt.addingTimeInterval(Double(response) / 1_000)
                let submission = AnswerSubmission(
                    rawInput: question.answerCanonical,
                    normalizedAnswer: question.correctAnswer,
                    submittedAt: attempt.answeredAt!,
                    elapsedMilliseconds: response,
                    isCorrect: true
                )
                repository.context.insert(submission)
                submission.attempt = attempt
                attempt.submissions.append(submission)
                session.correctCount += 1
            }
            session.status = sessionIndex == 0 ? .interrupted : .completed
            session.endReason = sessionIndex == 0 ? .systemSleep : .timerExpired
            session.endedAt = startedAt.addingTimeInterval(120)
            session.activeElapsedMilliseconds = 120_000
        }
        try repository.context.save()
        try repository.replaceSkillEstimates(with: AdaptiveModel.estimates(from: repository.fetchSessions()))
    }

    private static func fixtureQuestion(index: Int, sessionIndex: Int) -> GeneratedQuestion {
        switch index % 8 {
        case 0:
            return GeneratedQuestion(operation: .addition, kind: .standard, category: QuestionCategory(key: "addition/two-digit-carry", displayName: "Addition · two-digit with carrying", operation: .addition), leftOperand: 47, rightOperand: 38, prompt: "47 + 38", correctAnswer: 85)
        case 1:
            return GeneratedQuestion(operation: .subtraction, kind: .standard, category: QuestionCategory(key: "subtraction/two-digit-borrow", displayName: "Subtraction · two-digit with borrowing", operation: .subtraction), leftOperand: 83, rightOperand: 47, prompt: "83 − 47", correctAnswer: 36)
        case 2, 6:
            let left = 2 + (index + sessionIndex) % 11
            let right = 3 + (index * 2 + sessionIndex) % 10
            return GeneratedQuestion(operation: .multiplication, kind: .standard, category: QuestionCategory(key: "multiplication/core-facts", displayName: "Multiplication · core facts", operation: .multiplication), leftOperand: Decimal(left), rightOperand: Decimal(right), prompt: "\(left) × \(right)", correctAnswer: Decimal(left * right))
        case 3:
            return GeneratedQuestion(operation: .multiplication, kind: .standard, category: QuestionCategory(key: "multiplication/two-digit", displayName: "Multiplication · two-digit pair", operation: .multiplication), leftOperand: 12, rightOperand: 17, prompt: "12 × 17", correctAnswer: 204)
        case 4:
            return GeneratedQuestion(operation: .division, kind: .standard, category: QuestionCategory(key: "division/two-digit-divisor", displayName: "Division · exact two-digit divisor", operation: .division), leftOperand: 144, rightOperand: 12, prompt: "144 ÷ 12", correctAnswer: 12)
        case 5:
            return GeneratedQuestion(operation: .power, kind: .square, category: QuestionCategory(key: "power/squares-11-20", displayName: "Powers · squares 11–20", operation: .power), leftOperand: 13, rightOperand: nil, prompt: "13²", correctAnswer: 169)
        default:
            return GeneratedQuestion(operation: .percentage, kind: .percentage, category: QuestionCategory(key: "percentage/common", displayName: "Percentages · common fractions", operation: .percentage), leftOperand: 15, rightOperand: 240, prompt: "15% of 240", correctAnswer: 36)
        }
    }

    private static func fixtureBaseMilliseconds(for question: GeneratedQuestion) -> Int {
        switch question.category.key {
        case "addition/two-digit-carry": 1_050
        case "subtraction/two-digit-borrow": 1_480
        case "multiplication/core-facts": 1_180
        case "multiplication/two-digit": 2_650
        case "division/two-digit-divisor": 1_850
        case "power/squares-11-20": 2_050
        case "percentage/common": 2_350
        default: 1_500
        }
    }
}
