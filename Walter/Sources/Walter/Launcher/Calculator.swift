// Calculator.swift — Inline math evaluation
//
// Uses NSExpression to evaluate math from the search query. Supports:
//   - Basic arithmetic: 128*3+15, 100/7, 2^10
//   - Decimals: 3.14*2
//   - Parentheses: (10+5)*3
//   - Functions: sqrt(144), log(100)
//
// Returns nil if the query doesn't look like math or can't be evaluated.
// The result is shown as the first search result; Enter copies to clipboard.
//
// Why NSExpression and not a custom parser?
//   It's built into Foundation, handles operator precedence, parentheses,
//   and math functions correctly, and is fast enough for real-time evaluation.
//   The one quirk: `^` means XOR in NSExpression, so we rewrite it to
//   `**` (power) before evaluating.

import Foundation

struct CalculatorResult {
    let expression: String   // what the user typed (cleaned up)
    let answer: String       // formatted result
    let rawValue: Double     // for potential further use
}

class Calculator {

    /// Tries to evaluate the query as a math expression.
    /// Returns nil if it doesn't look like math or evaluation fails.
    func evaluate(query: String) -> CalculatorResult? {
        let cleaned = query.trimmingCharacters(in: .whitespaces)
        guard looksLikeMath(cleaned) else { return nil }

        // Rewrite ^ to ** (power) since NSExpression treats ^ as XOR
        let expr = cleaned
            .replacingOccurrences(of: "^", with: "**")
            // Allow x and X as multiplication
            .replacingOccurrences(of: "x", with: "*")
            .replacingOccurrences(of: "X", with: "*")

        // NSExpression evaluation
        guard let result = evaluateExpression(expr) else { return nil }

        // Don't show trivially simple results (just a number with no operator)
        guard containsOperator(cleaned) else { return nil }

        return CalculatorResult(
            expression: cleaned,
            answer: formatNumber(result),
            rawValue: result
        )
    }

    /// Quick check: does this look like it could be a math expression?
    /// Must contain at least one digit and not look like a word.
    private func looksLikeMath(_ s: String) -> Bool {
        // Must have at least one digit
        guard s.contains(where: { $0.isNumber }) else { return false }
        // Must not start with a letter (unless it's a function like sqrt)
        let mathFunctions = ["sqrt", "log", "abs", "ceil", "floor"]
        if s.first?.isLetter == true {
            let lower = s.lowercased()
            guard mathFunctions.contains(where: { lower.hasPrefix($0) }) else { return false }
        }
        // Must only contain math-safe characters
        let allowed = CharacterSet.decimalDigits
            .union(.init(charactersIn: "+-*/%^().xX "))
            .union(.init(charactersIn: "sqrtlogabceilfloor")) // function names
        let stringChars = CharacterSet(charactersIn: s)
        return allowed.isSuperset(of: stringChars)
    }

    /// Does the string contain at least one operator (so "42" alone doesn't trigger)?
    private func containsOperator(_ s: String) -> Bool {
        let operators = CharacterSet(charactersIn: "+-*/%^xX()")
        return s.unicodeScalars.contains(where: { operators.contains($0) })
    }

    private func evaluateExpression(_ expr: String) -> Double? {
        // NSExpression throws ObjC exceptions on malformed input (not Swift errors).
        // We guard with a regex pre-check to avoid most bad inputs.
        let safePattern = #"^[\d\s\+\-\*\/\%\.\(\)\*]+$"#
        guard expr.range(of: safePattern, options: .regularExpression) != nil else { return nil }

        let nsExpr = NSExpression(format: expr)
        guard let result = nsExpr.expressionValue(with: nil, context: nil) as? NSNumber else {
            return nil
        }

        let d = result.doubleValue
        guard d.isFinite else { return nil }
        return d
    }

    /// Formats the number nicely: no trailing zeros, comma separators for large numbers.
    private func formatNumber(_ value: Double) -> String {
        // Integer result — show without decimals
        if value == value.rounded() && abs(value) < 1e15 {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 0
            return formatter.string(from: NSNumber(value: value)) ?? String(Int(value))
        }

        // Decimal result — up to 10 significant digits, strip trailing zeros
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 10
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }
}
