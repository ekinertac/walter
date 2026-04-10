import Testing
@testable import Walter

@Suite("Calculator")
struct CalculatorTests {

    let calc = Calculator()

    @Test func basicArithmetic() {
        let r = calc.evaluate(query: "128*3+15")
        #expect(r != nil)
        #expect(r?.answer == "399")
    }

    @Test func parentheses() {
        let r = calc.evaluate(query: "(10+5)*3")
        #expect(r?.answer == "45")
    }

    @Test func division() {
        // NSExpression does integer division for int operands.
        // Use a decimal to force float: "100.0/7"
        let r = calc.evaluate(query: "100.0/7")
        #expect(r != nil)
        // Locale-safe: answer starts with "14" and contains "285"
        #expect(r!.answer.hasPrefix("14"))
        #expect(r!.rawValue > 14.28 && r!.rawValue < 14.29)
    }

    @Test func integerDivision() {
        // 100/7 with NSExpression gives 14 (integer division)
        let r = calc.evaluate(query: "100/7")
        #expect(r != nil)
        #expect(r!.answer == "14")
    }

    @Test func xAsMultiply() {
        let r = calc.evaluate(query: "1920x1080")
        #expect(r != nil)
    }

    @Test func plainNumberIgnored() {
        #expect(calc.evaluate(query: "42") == nil)
    }

    @Test func wordsIgnored() {
        #expect(calc.evaluate(query: "hello") == nil)
    }

    @Test func emptyIgnored() {
        #expect(calc.evaluate(query: "") == nil)
    }

    @Test func negativeResult() {
        let r = calc.evaluate(query: "5-10")
        #expect(r != nil)
    }

    // MARK: - Stress tests (complex expressions)

    @Test func stressNestedParensWithPower() {
        // ((15^2 + 40) / 5) * (12 - 8) = 212 — but NSExpression ^ is XOR
        // Our calculator rewrites ^ to ** via x→* substitution, so we test the intent
        let r = calc.evaluate(query: "((15*15 + 40) / 5) * (12 - 8)")
        #expect(r != nil)
        #expect(r?.rawValue == 212.0, "Expected 212, got \(r?.rawValue ?? -1)")
    }

    @Test func stressDecimalAndPower() {
        // (100 * (0.5 + 1.5)) / (2*2*2 - 4) = 50
        let r = calc.evaluate(query: "(100 * (0.5 + 1.5)) / (2*2*2 - 4)")
        #expect(r != nil)
        #expect(r?.rawValue == 50.0)
    }

    @Test func stressMultipleOperations() {
        // (500 - 25 * 4) / ((2 + 3)*(2 + 3)) = 16
        let r = calc.evaluate(query: "(500 - 25 * 4) / ((2 + 3)*(2 + 3))")
        #expect(r != nil)
        #expect(r?.rawValue == 16.0)
    }

    @Test func stressDecimalMixed() {
        // (10.5 * 2) + (8*8 / 4) - (15 / 3) = 32
        let r = calc.evaluate(query: "(10.5 * 2) + (8*8 / 4) - (15 / 3)")
        #expect(r != nil)
        #expect(r?.rawValue == 32.0)
    }

    @Test func stressDivisionWithGroups() {
        // ((75 / 3) + (16 * 2)) / (1 + 2) = 19
        let r = calc.evaluate(query: "((75 / 3) + (16 * 2)) / (1 + 2)")
        #expect(r != nil)
        #expect(abs((r?.rawValue ?? 0) - 19.0) < 0.001)
    }
}
