import Foundation

protocol QuestionGenerating: AnyObject {
    func nextQuestion(configuration: PracticeConfiguration, categoryWeights: [String: Double]) -> GeneratedQuestion
}

final class QuestionGenerator: QuestionGenerating {
    private var random: SplitMix64
    private var lastPrompt: String?

    init(seed: UInt64) {
        random = SplitMix64(seed: seed)
    }

    func nextQuestion(configuration: PracticeConfiguration, categoryWeights: [String: Double] = [:]) -> GeneratedQuestion {
        let configuration = configuration.validated
        var result: GeneratedQuestion
        if configuration.mode == .targeted {
            result = targeted(configuration)
        } else if configuration.mode == .adaptive, !categoryWeights.isEmpty {
            let candidates = (0..<20).map { _ in basic(configuration) }
            result = weightedCandidate(candidates, weights: categoryWeights)
        } else {
            result = basic(configuration)
        }

        for _ in 0..<4 where result.prompt == lastPrompt {
            result = configuration.mode == .targeted ? targeted(configuration) : basic(configuration)
        }
        lastPrompt = result.prompt
        return result
    }

    private func basic(_ configuration: PracticeConfiguration) -> GeneratedQuestion {
        let operation = configuration.operations.randomElement(using: &random) ?? .addition
        switch operation {
        case .addition:
            let left = integer(in: configuration.additionLeft)
            let right = integer(in: configuration.additionRight)
            return make(.addition, .standard, Decimal(left), Decimal(right), Decimal(left + right))
        case .subtraction:
            let answer = integer(in: configuration.additionLeft)
            let subtrahend = integer(in: configuration.additionRight)
            return make(.subtraction, .standard, Decimal(answer + subtrahend), Decimal(subtrahend), Decimal(answer))
        case .multiplication:
            let left = integer(in: configuration.multiplicationLeft)
            let right = integer(in: configuration.multiplicationRight)
            return make(.multiplication, .standard, Decimal(left), Decimal(right), Decimal(left * right))
        case .division:
            let divisor = nonZeroInteger(in: configuration.multiplicationLeft)
            let quotient = integer(in: configuration.multiplicationRight)
            return make(.division, .standard, Decimal(divisor * quotient), Decimal(divisor), Decimal(quotient))
        case .power, .percentage:
            return basic(PracticeConfiguration.classicDefault)
        }
    }

    private func targeted(_ configuration: PracticeConfiguration) -> GeneratedQuestion {
        let range = configuration.targetedRange.normalized
        switch configuration.targetedPreset {
        case .twoDigitMultiplication:
            let left = integer(in: range)
            let right = integer(in: range)
            return make(.multiplication, .standard, Decimal(left), Decimal(right), Decimal(left * right))
        case .exactDivision:
            let quotient = integer(in: range)
            let divisor = Int.random(in: 2...min(25, max(2, range.maximum)), using: &random)
            return make(.division, .standard, Decimal(quotient * divisor), Decimal(divisor), Decimal(quotient))
        case .negativeSubtraction:
            let lower = integer(in: range)
            let gap = Int.random(in: 1...max(1, min(99, range.maximum - range.minimum + 1)), using: &random)
            let upper = lower + gap
            return make(.subtraction, .negativeSubtraction, Decimal(lower), Decimal(upper), Decimal(lower - upper))
        case .squaresAndCubes:
            let base = integer(in: range)
            if Bool.random(using: &random) {
                return make(.power, .square, Decimal(base), Decimal(2), Decimal(base * base))
            }
            return make(.power, .cube, Decimal(base), Decimal(3), Decimal(base * base * base))
        case .percentages:
            return percentageQuestion(range: range)
        case .decimalArithmetic:
            return decimalQuestion()
        case .quantInterview:
            switch Int.random(in: 0..<10, using: &random) {
            case 0, 1: return percentageQuestion(range: range)
            case 2, 3: return decimalQuestion()
            default:
                var standard = configuration
                standard.mode = .classic
                standard.operations = [.addition, .subtraction, .multiplication, .division]
                return basic(standard)
            }
        }
    }

    private func percentageQuestion(range: OperandRange) -> GeneratedQuestion {
        let rates: [Decimal] = [1, 5, 10, 12.5, 15, 20, 25, 30, 40, 50, 75]
        for _ in 0..<50 {
            let rate = rates.randomElement(using: &random) ?? 10
            let base = Decimal(integer(in: range))
            let answer = rate * base / 100
            if decimalPlaces(answer) <= 2 {
                return make(.percentage, .percentage, rate, base, answer)
            }
        }
        let base = Decimal(integer(in: range))
        return make(.percentage, .percentage, 10, base, base / 10)
    }

    private func decimalQuestion() -> GeneratedQuestion {
        let operation = [ArithmeticOperation.addition, .subtraction, .multiplication, .division]
            .randomElement(using: &random) ?? .addition
        for _ in 0..<100 {
            let left = randomDecimal()
            let right = randomDecimal(nonZero: operation == .division)
            let answer: Decimal
            let displayedLeft: Decimal
            switch operation {
            case .addition:
                displayedLeft = left
                answer = left + right
            case .subtraction:
                displayedLeft = left
                answer = left - right
            case .multiplication:
                displayedLeft = left
                answer = left * right
            case .division:
                let quotient = randomDecimal()
                displayedLeft = quotient * right
                answer = quotient
            default:
                continue
            }
            if decimalPlaces(displayedLeft) <= 2 && decimalPlaces(right) <= 2 && decimalPlaces(answer) <= 2 {
                return make(operation, .decimalArithmetic, displayedLeft, right, answer)
            }
        }
        return make(.addition, .decimalArithmetic, 1.5, 2.25, 3.75)
    }

    private func randomDecimal(nonZero: Bool = false) -> Decimal {
        repeat {
            let scale = Int.random(in: 1...2, using: &random)
            let denominator = scale == 1 ? 10 : 100
            let numerator = Int.random(in: 1...9_999, using: &random)
            let value = Decimal(numerator) / Decimal(denominator)
            if !nonZero || value != 0 { return value }
        } while true
    }

    private func make(
        _ operation: ArithmeticOperation,
        _ kind: QuestionKind,
        _ left: Decimal,
        _ right: Decimal?,
        _ answer: Decimal
    ) -> GeneratedQuestion {
        let prompt: String
        switch kind {
        case .square:
            prompt = "\(DecimalText.canonical(left))²"
        case .cube:
            prompt = "\(DecimalText.canonical(left))³"
        case .percentage:
            prompt = "\(DecimalText.canonical(left))% of \(DecimalText.canonical(right ?? 0))"
        default:
            prompt = "\(DecimalText.canonical(left)) \(operation.symbol) \(DecimalText.canonical(right ?? 0))"
        }
        let category = category(for: operation, kind: kind, left: left, right: right, answer: answer)
        return GeneratedQuestion(
            operation: operation,
            kind: kind,
            category: category,
            leftOperand: left,
            rightOperand: right,
            prompt: prompt,
            correctAnswer: answer
        )
    }

    private func category(
        for operation: ArithmeticOperation,
        kind: QuestionKind,
        left: Decimal,
        right: Decimal?,
        answer: Decimal
    ) -> QuestionCategory {
        let detail: String
        if kind == .decimalArithmetic {
            detail = "decimal arithmetic"
        } else if kind == .percentage {
            detail = "common percentages"
        } else if kind == .square || kind == .cube {
            detail = kind == .square ? "squares" : "cubes"
        } else if operation == .subtraction && answer < 0 {
            detail = "negative result"
        } else if operation == .division {
            let divisor = abs((right as NSDecimalNumber?)?.intValue ?? 0)
            detail = divisor <= 9 ? "divisor 2–9" : "divisor 10+"
        } else {
            let leftInt = abs((left as NSDecimalNumber).intValue)
            let rightInt = abs((right.map { $0 as NSDecimalNumber })?.intValue ?? 0)
            let leftDigits = digitBucket(leftInt)
            let rightDigits = digitBucket(rightInt)
            if operation == .addition && leftInt % 10 + rightInt % 10 >= 10 {
                detail = "carrying required"
            } else {
                detail = "\(leftDigits) × \(rightDigits)"
            }
        }
        return QuestionCategory(
            key: "\(operation.rawValue)/\(detail.replacingOccurrences(of: " ", with: "-"))",
            displayName: "\(operation.title) · \(detail)",
            operation: operation
        )
    }

    private func digitBucket(_ value: Int) -> String {
        switch value {
        case 0...9: "1-digit"
        case 10...99: "2-digit"
        default: "3+-digit"
        }
    }

    private func integer(in range: OperandRange) -> Int {
        let range = range.normalized
        return Int.random(in: range.minimum...range.maximum, using: &random)
    }

    private func nonZeroInteger(in range: OperandRange) -> Int {
        let range = range.normalized
        if range.minimum == 0 && range.maximum == 0 { return 1 }
        for _ in 0..<20 {
            let value = integer(in: range)
            if value != 0 { return value }
        }
        return range.maximum == 0 ? range.minimum : range.maximum
    }

    private func decimalPlaces(_ value: Decimal) -> Int {
        let text = DecimalText.canonical(value)
        return text.split(separator: ".", omittingEmptySubsequences: false).dropFirst().first?.count ?? 0
    }

    private func weightedCandidate(_ candidates: [GeneratedQuestion], weights: [String: Double]) -> GeneratedQuestion {
        let candidateWeights = candidates.map { max(0.0001, weights[$0.category.key] ?? 0.25) }
        let total = candidateWeights.reduce(0, +)
        var threshold = Double.random(in: 0..<total, using: &random)
        for (candidate, weight) in zip(candidates, candidateWeights) {
            threshold -= weight
            if threshold <= 0 { return candidate }
        }
        return candidates.last ?? basic(.classicDefault)
    }
}
