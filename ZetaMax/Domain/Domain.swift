import Foundation

enum PracticeMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case classic, adaptive, targeted, benchmark

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var systemImage: String {
        switch self {
        case .classic: "timer"
        case .adaptive: "scope"
        case .targeted: "target"
        case .benchmark: "trophy"
        }
    }
}

enum ArithmeticOperation: String, Codable, CaseIterable, Identifiable, Sendable {
    case addition, subtraction, multiplication, division, power, percentage

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .addition: "+"
        case .subtraction: "−"
        case .multiplication: "×"
        case .division: "÷"
        case .power: "^"
        case .percentage: "%"
        }
    }
}

enum QuestionKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case standard, negativeSubtraction, square, cube, percentage, decimalArithmetic

    var id: String { rawValue }
}

enum TargetedPreset: String, Codable, CaseIterable, Identifiable, Sendable {
    case twoDigitMultiplication
    case exactDivision
    case negativeSubtraction
    case squaresAndCubes
    case percentages
    case decimalArithmetic
    case quantInterview

    var id: String { rawValue }
    var title: String {
        switch self {
        case .twoDigitMultiplication: "Two-digit multiplication"
        case .exactDivision: "Exact division"
        case .negativeSubtraction: "Negative subtraction"
        case .squaresAndCubes: "Squares and cubes"
        case .percentages: "Percentages"
        case .decimalArithmetic: "Decimal arithmetic"
        case .quantInterview: "Quant interview mix"
        }
    }

    var detail: String {
        switch self {
        case .twoDigitMultiplication: "Products of two configurable two-digit ranges."
        case .exactDivision: "Integer quotients with no remainder."
        case .negativeSubtraction: "Subtractions whose answers are below zero."
        case .squaresAndCubes: "Rapid recall of powers in a chosen base range."
        case .percentages: "Common percentages with exact finite answers."
        case .decimalArithmetic: "Addition, subtraction, multiplication, and exact division."
        case .quantInterview: "A balanced mix of integer, decimal, and percentage arithmetic."
        }
    }
}

struct OperandRange: Codable, Hashable, Sendable {
    var minimum: Int
    var maximum: Int

    init(_ minimum: Int, _ maximum: Int) {
        self.minimum = minimum
        self.maximum = maximum
    }

    var normalized: OperandRange {
        minimum <= maximum ? self : OperandRange(maximum, minimum)
    }

    func clamped(to limits: ClosedRange<Int>) -> OperandRange {
        OperandRange(
            Swift.max(limits.lowerBound, Swift.min(minimum, limits.upperBound)),
            Swift.max(limits.lowerBound, Swift.min(maximum, limits.upperBound))
        ).normalized
    }
}

struct QuestionCategory: Codable, Hashable, Identifiable, Sendable {
    var key: String
    var displayName: String
    var operation: ArithmeticOperation

    var id: String { key }
}

struct PracticeConfiguration: Codable, Hashable, Sendable {
    static let schemaVersion = 1

    var version = schemaVersion
    var mode: PracticeMode = .classic
    var durationSeconds = 120
    var operations: [ArithmeticOperation] = [.addition, .subtraction, .multiplication, .division]
    var additionLeft = OperandRange(2, 100)
    var additionRight = OperandRange(2, 100)
    var multiplicationLeft = OperandRange(2, 12)
    var multiplicationRight = OperandRange(2, 100)
    var targetedPreset: TargetedPreset = .twoDigitMultiplication
    var targetedRange = OperandRange(10, 99)
    var adaptiveFocus = 0.5
    var benchmarkID: String? = nil
    var benchmarkVersion: Int? = nil

    static let classicDefault = PracticeConfiguration()

    var validated: PracticeConfiguration {
        var copy = self
        copy.durationSeconds = min(max(durationSeconds, 15), 3_600)
        copy.operations = operations.filter { [.addition, .subtraction, .multiplication, .division].contains($0) }
        if copy.operations.isEmpty { copy.operations = [.addition] }
        copy.additionLeft = additionLeft.clamped(to: -9_999...9_999)
        copy.additionRight = additionRight.clamped(to: -9_999...9_999)
        copy.multiplicationLeft = multiplicationLeft.clamped(to: -999...999)
        copy.multiplicationRight = multiplicationRight.clamped(to: -999...999)
        copy.targetedRange = targetedRange.clamped(to: 1...999)
        copy.adaptiveFocus = min(max(adaptiveFocus, 0), 1)
        return copy
    }
}

struct BenchmarkProfile: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let version: Int
    let name: String
    let durationSeconds: Int

    var configuration: PracticeConfiguration {
        var configuration = PracticeConfiguration.classicDefault
        configuration.mode = .benchmark
        configuration.durationSeconds = durationSeconds
        configuration.benchmarkID = id
        configuration.benchmarkVersion = version
        return configuration
    }

    static let builtIns: [BenchmarkProfile] = [30, 60, 120, 300, 600].map { seconds in
        BenchmarkProfile(
            id: "zetamac-standard-\(seconds)",
            version: 1,
            name: seconds == 120 ? "Standard · 2 minutes" : "Standard · \(DurationText.compact(seconds))",
            durationSeconds: seconds
        )
    }
}

struct GeneratedQuestion: Codable, Hashable, Sendable {
    let operation: ArithmeticOperation
    let kind: QuestionKind
    let category: QuestionCategory
    let leftOperand: Decimal
    let rightOperand: Decimal?
    let prompt: String
    let correctAnswer: Decimal

    var leftCanonical: String { DecimalText.canonical(leftOperand) }
    var rightCanonical: String? { rightOperand.map(DecimalText.canonical) }
    var answerCanonical: String { DecimalText.canonical(correctAnswer) }
}

enum DecimalText {
    static func canonical(_ value: Decimal) -> String {
        var value = value
        return NSDecimalString(&value, Locale(identifier: "en_US_POSIX"))
    }

    static func parse(_ input: String, locale: Locale = .current) -> Decimal? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let separator = locale.decimalSeparator ?? "."
        let normalized = separator == "." ? trimmed : trimmed.replacingOccurrences(of: separator, with: ".")
        guard normalized.range(of: #"^[+-]?(?:\d+(?:\.\d*)?|\.\d+)$"#, options: .regularExpression) != nil else {
            return nil
        }
        return Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX"))
    }
}

enum DurationText {
    static func compact(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        let remainder = seconds % 60
        return remainder == 0 ? "\(minutes)m" : "\(minutes)m \(remainder)s"
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(ceil(seconds)))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

struct SplitMix64: RandomNumberGenerator, Sendable {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        return value ^ (value >> 31)
    }
}
