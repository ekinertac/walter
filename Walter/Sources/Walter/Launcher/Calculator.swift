// Bounded, error-returning recursive descent. Never evaluates code/NSExpression.
import Foundation

struct CalculatorResult {
    let expression: String
    let answer: String
    let rawValue: Double
}

enum CalculatorError: Error, Equatable {
    case invalidInput, tooComplex, divisionByZero, nonFinite
}

final class Calculator {
    private let locale: Locale
    init(locale: Locale = .current) { self.locale = locale }

    func evaluate(query: String) -> CalculatorResult? {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.utf8.count <= 2048,
              let parsed = try? Self.parse(text), parsed.operated else { return nil }
        return CalculatorResult(expression: text, answer: format(parsed.value), rawValue: parsed.value)
    }

    /// Explicit errors for tests/callers; the UI simply suppresses invalid input.
    func calculate(_ text: String) throws -> Double { try Self.parse(text).value }

    private static func parse(_ text: String) throws -> (value: Double, operated: Bool) {
        guard !text.isEmpty else { throw CalculatorError.invalidInput }
        guard text.utf8.count <= 2048 else { throw CalculatorError.tooComplex }
        var parser = try Parser(text)
        let value = try parser.expression(depth: 0)
        guard parser.current == .end else { throw CalculatorError.invalidInput }
        return (value, parser.operated)
    }

    private func format(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        if value != 0 && (abs(value) < 1e-10 || abs(value) >= 1e15) {
            formatter.numberStyle = .scientific
            formatter.usesSignificantDigits = true
            formatter.maximumSignificantDigits = 12
            formatter.minimumSignificantDigits = 1
            formatter.exponentSymbol = "e"
        } else {
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 10
            formatter.minimumFractionDigits = 0
        }
        return formatter.string(from: NSNumber(value: value == 0 ? 0 : value)) ?? String(value)
    }

    private enum Token: Equatable {
        case number(Double), function(String), plus, minus, multiply, divide, modulo, power, left, right, end
    }

    private struct Parser {
        let tokens: [Token]
        var index = 0
        var operated = false
        var current: Token { tokens[index] }

        init(_ text: String) throws {
            let chars = Array(text)
            var result: [Token] = []
            var i = 0
            func digit(_ c: Character) -> Bool { c >= "0" && c <= "9" }
            while i < chars.count {
                guard result.count < 512 else { throw CalculatorError.tooComplex }
                let c = chars[i]
                if c.isWhitespace { i += 1; continue }
                if digit(c) || c == "." {
                    let start = i
                    while i < chars.count && digit(chars[i]) { i += 1 }
                    if i < chars.count && chars[i] == "." {
                        i += 1
                        while i < chars.count && digit(chars[i]) { i += 1 }
                    }
                    if i < chars.count && (chars[i] == "e" || chars[i] == "E") {
                        i += 1
                        if i < chars.count && (chars[i] == "+" || chars[i] == "-") { i += 1 }
                        let exponentStart = i
                        while i < chars.count && digit(chars[i]) { i += 1 }
                        guard i > exponentStart else { throw CalculatorError.invalidInput }
                    }
                    guard let number = Double(String(chars[start..<i])) else { throw CalculatorError.invalidInput }
                    guard number.isFinite else { throw CalculatorError.nonFinite }
                    result.append(.number(number)); continue
                }
                switch c {
                case "+": result.append(.plus)
                case "-": result.append(.minus)
                case "*":
                    if i + 1 < chars.count && chars[i + 1] == "*" { result.append(.power); i += 1 }
                    else { result.append(.multiply) }
                case "x", "X": result.append(.multiply)
                case "/": result.append(.divide)
                case "%": result.append(.modulo)
                case "^": result.append(.power)
                case "(": result.append(.left)
                case ")": result.append(.right)
                default:
                    guard c.isASCII && c.isLetter else { throw CalculatorError.invalidInput }
                    let start = i
                    while i < chars.count && chars[i].isASCII && chars[i].isLetter { i += 1 }
                    let name = String(chars[start..<i]).lowercased()
                    guard ["sqrt", "log", "abs", "ceil", "floor"].contains(name) else { throw CalculatorError.invalidInput }
                    result.append(.function(name)); continue
                }
                i += 1
            }
            result.append(.end)
            tokens = result
        }

        mutating func advance() { index += 1 }
        func finite(_ value: Double) throws -> Double {
            guard value.isFinite else { throw CalculatorError.nonFinite }
            return value
        }
        func bounded(_ depth: Int) throws {
            guard depth <= 64 else { throw CalculatorError.tooComplex }
        }

        mutating func expression(depth: Int) throws -> Double {
            var value = try term(depth: depth)
            while current == .plus || current == .minus {
                let op = current; advance(); operated = true
                let rhs = try term(depth: depth)
                value = try finite(op == .plus ? value + rhs : value - rhs)
            }
            return value
        }
        mutating func term(depth: Int) throws -> Double {
            var value = try unary(depth: depth)
            while current == .multiply || current == .divide || current == .modulo {
                let op = current; advance(); operated = true
                let rhs = try unary(depth: depth)
                if (op == .divide || op == .modulo) && rhs == 0 { throw CalculatorError.divisionByZero }
                switch op {
                case .multiply: value = try finite(value * rhs)
                case .divide: value = try finite(value / rhs)
                default: value = try finite(value.truncatingRemainder(dividingBy: rhs))
                }
            }
            return value
        }
        mutating func unary(depth: Int) throws -> Double {
            try bounded(depth)
            if current == .plus { advance(); operated = true; return try unary(depth: depth + 1) }
            if current == .minus { advance(); operated = true; return try finite(-unary(depth: depth + 1)) }
            return try power(depth: depth)
        }
        mutating func power(depth: Int) throws -> Double {
            let value = try primary(depth: depth)
            if current == .power {
                advance(); operated = true
                let rhs = try unary(depth: depth + 1)
                return try finite(pow(value, rhs))
            }
            return value
        }
        mutating func primary(depth: Int) throws -> Double {
            try bounded(depth)
            switch current {
            case .number(let value): advance(); return value
            case .left:
                advance()
                let value = try expression(depth: depth + 1)
                guard current == .right else { throw CalculatorError.invalidInput }
                advance(); return value
            case .function(let name):
                advance(); operated = true
                guard current == .left else { throw CalculatorError.invalidInput }
                advance()
                let value = try expression(depth: depth + 1)
                guard current == .right else { throw CalculatorError.invalidInput }
                advance()
                switch name {
                case "sqrt": return try finite(sqrt(value))
                case "log": return try finite(log10(value))
                case "abs": return abs(value)
                case "ceil": return ceil(value)
                default: return floor(value)
                }
            default: throw CalculatorError.invalidInput
            }
        }
    }
}
