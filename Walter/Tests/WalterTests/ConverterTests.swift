import Testing
@testable import Walter

@Suite("Converter")
struct ConverterTests {

    let converter = Converter()

    // MARK: - Unit conversion (no network needed)

    @Test func kmToMiles() {
        let r = converter.convert(query: "10 km in miles")
        #expect(!r.isEmpty)
        #expect(r[0].title.contains("mi"))
    }

    @Test func celsiusToFahrenheit() {
        let r = converter.convert(query: "100 c in f")
        #expect(!r.isEmpty)
        #expect(r[0].title.contains("212"))
    }

    @Test func fahrenheitToCelsius() {
        let r = converter.convert(query: "32 f in c")
        #expect(!r.isEmpty)
        #expect(r[0].title.contains("0"))
    }

    @Test func kgToPounds() {
        let r = converter.convert(query: "1 kg in lb")
        #expect(!r.isEmpty)
        #expect(r[0].title.contains("lb"))
    }

    @Test func tbToGb() {
        let r = converter.convert(query: "1 tb in gb")
        #expect(!r.isEmpty)
        // Formatter may use "1,000" or "1.000" depending on locale
        #expect(r[0].title.contains("GB"))
        #expect(r[0].title.contains("1"))
    }

    @Test func noTargetShowsAll() {
        let r = converter.convert(query: "10 km in")
        #expect(r.count > 1) // should show all length units
    }

    @Test func nonsenseReturnsEmpty() {
        let r = converter.convert(query: "hello world")
        #expect(r.isEmpty)
    }
}
