import Foundation
import Testing
@testable import Walter

@Suite("Bounded calculator")
struct CalculatorTests {
    @Test(arguments: [
        ("128*3+15", 399.0), ("(10+5)*3", 45.0), ("100/7", 100.0/7),
        ("1920x1080", 2073600.0), ("2^10", 1024.0), ("2**3", 8.0), ("0^0", 1.0),
        ("2^3^2", 512.0), ("-2^2", -4.0), ("(-2)^2", 4.0), ("2^-2", 0.25),
        ("10-3-2", 5.0), ("20/2/2", 5.0), ("1+-2", -1.0), ("--2", 2.0),
        ("sqrt(144)", 12.0), ("log(100)", 2.0), ("abs(-4)", 4.0),
        ("ceil(1.2)", 2.0), ("floor(-1.2)", -2.0), ("sqrt(abs(-9))", 3.0),
        ("7%2", 1.0), ("-7%2", -1.0), ("5.5%2", 1.5), ("1e-12*2", 2e-12)
    ])
    func arithmetic(expression: String, expected: Double) throws {
        let calculator = Calculator(locale: Locale(identifier: "en_US"))
        let value = try calculator.calculate(expression)
        #expect(abs(value - expected) <= max(abs(expected) * 1e-12, 1e-25))
        #expect(calculator.evaluate(query: expression) != nil)
    }

    @Test(arguments: ["", "hello", "1+", "(", "(1+2", "1+2)", "1..2+3", "1/0", "1%0",
                      "0/0", "sqrt(-1)", "log(0)", "log(-1)", "1e309", "1e308*10", "10^1000",
                      "2(3)", "sqrt 4", "unknown(1)", "1;2", "2^^3", "1e+", "2***3"])
    func invalidInputDoesNotProduceAnAnswer(expression: String) {
        #expect(Calculator(locale: Locale(identifier: "en_US")).evaluate(query: expression) == nil)
    }

    @Test func errorTypesAndBounds() {
        let calc = Calculator(locale: Locale(identifier: "en_US"))
        #expect(throws: CalculatorError.divisionByZero) { try calc.calculate("1/0") }
        #expect(throws: CalculatorError.nonFinite) { try calc.calculate("sqrt(-1)") }
        #expect(throws: CalculatorError.tooComplex) { try calc.calculate(String(repeating: "(", count: 70) + "1" + String(repeating: ")", count: 70)) }
        #expect(throws: CalculatorError.tooComplex) { try calc.calculate(String(repeating: "1+", count: 600) + "1") }
        #expect(throws: CalculatorError.tooComplex) { try calc.calculate(String(repeating: "1", count: 3000)) }
        #expect(calc.evaluate(query: "42") == nil)
    }

    @Test func malformedInputStressIsBounded() {
        let calc = Calculator(locale: Locale(identifier: "en_US"))
        let alphabet = Array("0123+-*/%^().sqrtlogxyz ")
        var state: UInt64 = 12345
        for _ in 0..<1000 {
            var text = ""
            for _ in 0..<40 {
                state = state &* 6364136223846793005 &+ 1
                text.append(alphabet[Int(state % UInt64(alphabet.count))])
            }
            if let result = calc.evaluate(query: text) { #expect(result.rawValue.isFinite) }
        }
    }

    @Test func localeAndTinyValues() throws {
        let en = Calculator(locale: Locale(identifier: "en_US"))
        let de = Calculator(locale: Locale(identifier: "de_DE"))
        #expect(en.evaluate(query: "100/7")?.answer == "14.2857142857")
        #expect(de.evaluate(query: "100/7")?.answer == "14,2857142857")
        #expect(en.evaluate(query: "1000+2000")?.answer == "3,000")
        for locale in [Locale(identifier: "en_US"), Locale(identifier: "de_DE")] {
            let result = try #require(Calculator(locale: locale).evaluate(query: "1e-12*2"))
            let formatter = NumberFormatter(); formatter.locale = locale; formatter.numberStyle = .scientific
            #expect(formatter.number(from: result.answer)?.doubleValue == 2e-12)
            #expect(result.answer != "0")
        }
    }
}
