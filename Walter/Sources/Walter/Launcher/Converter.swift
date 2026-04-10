// Converter.swift — Currency and unit conversion
//
// Detects patterns like:
//   "$100 in euro"     → currency conversion
//   "100 usd in try"   → currency conversion
//   "100 km in miles"  → unit conversion
//   "$50 in"           → shows popular currency targets as completion list
//
// Currency rates are fetched from open.er-api.com (free, no API key) on
// startup and cached for the session. Falls back gracefully if offline.
//
// Unit conversions are fully offline (hardcoded factors).

import Foundation

// MARK: - Public result type

struct ConversionResult {
    let title: String       // e.g. "€92.15"
    let subtitle: String    // e.g. "$100 USD → EUR"
    let copyValue: String   // e.g. "92.15"
}

// MARK: - Converter

class Converter {

    // Exchange rates relative to USD (fetched once, cached in memory)
    private var rates: [String: Double] = [:]
    private var ratesLoaded = false

    init() {
        fetchRates()
    }

    /// Attempts to parse the query as a conversion. Returns multiple results
    /// (completion list) when the target is partial or missing.
    func convert(query: String) -> [ConversionResult] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()

        // Try currency first, then units
        if let results = parseCurrency(q), !results.isEmpty {
            return results
        }
        if let results = parseUnit(q), !results.isEmpty {
            return results
        }
        return []
    }

    // =========================================================================
    // MARK: - Currency
    // =========================================================================

    // Common symbols → ISO code
    private static let symbolMap: [String: String] = [
        "$": "usd", "€": "eur", "£": "gbp", "¥": "jpy", "₺": "try",
        "₹": "inr", "₩": "krw", "₽": "rub", "₿": "btc", "zł": "pln",
        "kr": "sek", "r$": "brl", "฿": "thb",
    ]

    // Name/alias → ISO code
    private static let nameMap: [String: String] = [
        "dollar": "usd", "dollars": "usd", "usd": "usd", "us": "usd",
        "euro": "eur", "euros": "eur", "eur": "eur",
        "pound": "gbp", "pounds": "gbp", "gbp": "gbp", "sterling": "gbp",
        "yen": "jpy", "jpy": "jpy",
        "lira": "try", "try": "try", "tl": "try", "turkish": "try",
        "yuan": "cny", "cny": "cny", "rmb": "cny",
        "rupee": "inr", "rupees": "inr", "inr": "inr",
        "won": "krw", "krw": "krw",
        "ruble": "rub", "rubles": "rub", "rub": "rub",
        "bitcoin": "btc", "btc": "btc",
        "franc": "chf", "chf": "chf", "swiss": "chf",
        "real": "brl", "brl": "brl",
        "peso": "mxn", "mxn": "mxn",
        "cad": "cad", "canadian": "cad",
        "aud": "aud", "australian": "aud",
        "nzd": "nzd",
        "sek": "sek", "krona": "sek", "swedish": "sek",
        "nok": "nok", "norwegian": "nok",
        "dkk": "dkk", "danish": "dkk",
        "pln": "pln", "zloty": "pln", "polish": "pln",
        "thb": "thb", "baht": "thb",
        "sgd": "sgd", "singapore": "sgd",
        "hkd": "hkd",
        "korean": "krw",
        "zar": "zar", "rand": "zar",
        "aed": "aed", "dirham": "aed",
    ]

    // Popular currencies for the completion list when target is empty
    private static let popularTargets = ["eur", "gbp", "try", "jpy", "cny", "cad", "aud", "chf", "inr", "brl"]

    private func parseCurrency(_ q: String) -> [ConversionResult]? {
        guard ratesLoaded else { return nil }

        // Pattern: [symbol]<amount> [currency] [in|to] [target]
        var remaining = q
        var fromCurrency: String?
        var amount: Double?

        // Check for leading symbol: $100, €50, £20, ₺500
        for (symbol, code) in Self.symbolMap {
            if remaining.hasPrefix(symbol) {
                fromCurrency = code
                remaining = String(remaining.dropFirst(symbol.count)).trimmingCharacters(in: .whitespaces)
                break
            }
        }

        // Extract the number
        let numPattern = #"^[\d,]+\.?\d*"#
        guard let numRange = remaining.range(of: numPattern, options: .regularExpression) else {
            return nil
        }
        let numStr = remaining[numRange].replacingOccurrences(of: ",", with: "")
        guard let parsedAmount = Double(numStr) else { return nil }
        amount = parsedAmount
        remaining = String(remaining[numRange.upperBound...]).trimmingCharacters(in: .whitespaces)

        // Extract source currency name if we didn't get it from a symbol
        if fromCurrency == nil {
            let word = remaining.split(separator: " ").first.map(String.init) ?? remaining
            if let code = Self.nameMap[word] {
                fromCurrency = code
                remaining = String(remaining.dropFirst(word.count)).trimmingCharacters(in: .whitespaces)
            }
        }

        guard let from = fromCurrency, let amt = amount else { return nil }

        // Check for "in" or "to" separator
        for sep in ["in", "to"] {
            if remaining.hasPrefix(sep) {
                remaining = String(remaining.dropFirst(sep.count)).trimmingCharacters(in: .whitespaces)
                break
            }
        }

        // If there's a target specified, fuzzy match it
        if !remaining.isEmpty {
            let matchingCodes = Self.nameMap
                .filter { $0.key.hasPrefix(remaining) || $0.value.hasPrefix(remaining) }
                .map { $0.value }
            let uniqueCodes = Array(Set(matchingCodes))

            if uniqueCodes.isEmpty {
                return nil
            }

            return uniqueCodes.prefix(8).compactMap { to -> ConversionResult? in
                convertCurrency(amount: amt, from: from, to: to)
            }
        }

        // No target — show popular currencies as completion list
        let targets = Self.popularTargets.filter { $0 != from }
        return targets.compactMap { to in
            convertCurrency(amount: amt, from: from, to: to)
        }
    }

    private func convertCurrency(amount: Double, from: String, to: String) -> ConversionResult? {
        // Convert via USD as the base
        guard let fromRate = rate(for: from), let toRate = rate(for: to) else { return nil }
        let inUSD = amount / fromRate
        let result = inUSD * toRate

        let formatted = formatCurrency(result, code: to)
        let fromUpper = from.uppercased()
        let toUpper = to.uppercased()

        return ConversionResult(
            title: "\(formatted) \(toUpper)",
            subtitle: "\(formatNumber(amount)) \(fromUpper) → \(toUpper)",
            copyValue: formatNumber(result)
        )
    }

    private func rate(for code: String) -> Double? {
        if code == "usd" { return 1.0 }
        return rates[code]
    }

    // =========================================================================
    // MARK: - Units
    // =========================================================================

    private struct UnitDef {
        let names: [String]         // all accepted names (lowercase)
        let category: String        // e.g. "length", "weight"
        let toBase: (Double) -> Double   // convert to base unit
        let fromBase: (Double) -> Double // convert from base unit
        let symbol: String          // display symbol
    }

    private static let units: [UnitDef] = [
        // Length (base: meters)
        UnitDef(names: ["km", "kilometer", "kilometers", "kilometre"], category: "length",
                toBase: { $0 * 1000 }, fromBase: { $0 / 1000 }, symbol: "km"),
        UnitDef(names: ["m", "meter", "meters", "metre"], category: "length",
                toBase: { $0 }, fromBase: { $0 }, symbol: "m"),
        UnitDef(names: ["cm", "centimeter", "centimeters"], category: "length",
                toBase: { $0 / 100 }, fromBase: { $0 * 100 }, symbol: "cm"),
        UnitDef(names: ["mm", "millimeter", "millimeters"], category: "length",
                toBase: { $0 / 1000 }, fromBase: { $0 * 1000 }, symbol: "mm"),
        UnitDef(names: ["mi", "mile", "miles"], category: "length",
                toBase: { $0 * 1609.344 }, fromBase: { $0 / 1609.344 }, symbol: "mi"),
        UnitDef(names: ["ft", "foot", "feet"], category: "length",
                toBase: { $0 * 0.3048 }, fromBase: { $0 / 0.3048 }, symbol: "ft"),
        UnitDef(names: ["in", "inch", "inches"], category: "length",
                toBase: { $0 * 0.0254 }, fromBase: { $0 / 0.0254 }, symbol: "in"),
        UnitDef(names: ["yd", "yard", "yards"], category: "length",
                toBase: { $0 * 0.9144 }, fromBase: { $0 / 0.9144 }, symbol: "yd"),

        // Weight (base: kg)
        UnitDef(names: ["kg", "kilogram", "kilograms", "kilo", "kilos"], category: "weight",
                toBase: { $0 }, fromBase: { $0 }, symbol: "kg"),
        UnitDef(names: ["g", "gram", "grams"], category: "weight",
                toBase: { $0 / 1000 }, fromBase: { $0 * 1000 }, symbol: "g"),
        UnitDef(names: ["lb", "lbs", "pound", "pounds"], category: "weight",
                toBase: { $0 * 0.453592 }, fromBase: { $0 / 0.453592 }, symbol: "lb"),
        UnitDef(names: ["oz", "ounce", "ounces"], category: "weight",
                toBase: { $0 * 0.0283495 }, fromBase: { $0 / 0.0283495 }, symbol: "oz"),

        // Temperature (base: celsius)
        UnitDef(names: ["c", "celsius", "°c"], category: "temp",
                toBase: { $0 }, fromBase: { $0 }, symbol: "°C"),
        UnitDef(names: ["f", "fahrenheit", "°f"], category: "temp",
                toBase: { ($0 - 32) * 5/9 }, fromBase: { $0 * 9/5 + 32 }, symbol: "°F"),
        UnitDef(names: ["k", "kelvin"], category: "temp",
                toBase: { $0 - 273.15 }, fromBase: { $0 + 273.15 }, symbol: "K"),

        // Data (base: bytes)
        UnitDef(names: ["tb", "terabyte", "terabytes"], category: "data",
                toBase: { $0 * 1e12 }, fromBase: { $0 / 1e12 }, symbol: "TB"),
        UnitDef(names: ["gb", "gigabyte", "gigabytes"], category: "data",
                toBase: { $0 * 1e9 }, fromBase: { $0 / 1e9 }, symbol: "GB"),
        UnitDef(names: ["mb", "megabyte", "megabytes"], category: "data",
                toBase: { $0 * 1e6 }, fromBase: { $0 / 1e6 }, symbol: "MB"),
        UnitDef(names: ["kb", "kilobyte", "kilobytes"], category: "data",
                toBase: { $0 * 1e3 }, fromBase: { $0 / 1e3 }, symbol: "KB"),
    ]

    private func parseUnit(_ q: String) -> [ConversionResult]? {
        // Pattern: <amount> <unit> [in|to] <target_unit>
        let numPattern = #"^[\d,]+\.?\d*"#
        guard let numRange = q.range(of: numPattern, options: .regularExpression) else { return nil }
        let numStr = q[numRange].replacingOccurrences(of: ",", with: "")
        guard let amount = Double(numStr) else { return nil }

        var remaining = String(q[numRange.upperBound...]).trimmingCharacters(in: .whitespaces)

        // Find source unit
        guard let fromUnit = findUnit(in: &remaining) else { return nil }

        // Strip "in" or "to"
        for sep in ["in", "to"] {
            if remaining.hasPrefix(sep) {
                remaining = String(remaining.dropFirst(sep.count)).trimmingCharacters(in: .whitespaces)
                break
            }
        }

        // Find target unit or show all compatible units
        if !remaining.isEmpty {
            if let toUnit = findUnit(in: &remaining) {
                guard fromUnit.category == toUnit.category else { return nil }
                return [convertUnit(amount: amount, from: fromUnit, to: toUnit)]
            }
            // Partial match — filter compatible units
            let compatible = Self.units.filter {
                $0.category == fromUnit.category &&
                $0.symbol != fromUnit.symbol &&
                $0.names.contains(where: { $0.hasPrefix(remaining) })
            }
            return compatible.map { convertUnit(amount: amount, from: fromUnit, to: $0) }
        }

        // No target — show all units in the same category
        let compatible = Self.units.filter {
            $0.category == fromUnit.category && $0.symbol != fromUnit.symbol
        }
        return compatible.map { convertUnit(amount: amount, from: fromUnit, to: $0) }
    }

    private func findUnit(in text: inout String) -> UnitDef? {
        let lower = text.lowercased()
        // Try longest match first (e.g. "kilometers" before "km")
        let sorted = Self.units.flatMap { unit in unit.names.map { ($0, unit) } }
            .sorted { $0.0.count > $1.0.count }

        for (name, unit) in sorted {
            if lower.hasPrefix(name) {
                let after = lower.index(lower.startIndex, offsetBy: name.count)
                // Ensure it's a word boundary (space, end of string, or "in"/"to")
                if after == lower.endIndex || lower[after] == " " {
                    text = String(text[after...]).trimmingCharacters(in: .whitespaces)
                    return unit
                }
            }
        }
        return nil
    }

    private func convertUnit(amount: Double, from: UnitDef, to: UnitDef) -> ConversionResult {
        let baseValue = from.toBase(amount)
        let result = to.fromBase(baseValue)

        return ConversionResult(
            title: "\(formatNumber(result)) \(to.symbol)",
            subtitle: "\(formatNumber(amount)) \(from.symbol) → \(to.symbol)",
            copyValue: formatNumber(result)
        )
    }

    // =========================================================================
    // MARK: - Formatting
    // =========================================================================

    private func formatNumber(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = value == value.rounded() ? 0 : 4
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    private func formatCurrency(_ value: Double, code: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    // =========================================================================
    // MARK: - API fetch
    // =========================================================================

    private func fetchRates() {
        guard let url = URL(string: "https://open.er-api.com/v6/latest/USD") else { return }

        URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            guard let data = data, error == nil else {
                print("Converter: failed to fetch rates — \(error?.localizedDescription ?? "unknown")")
                return
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let ratesDict = json["rates"] as? [String: Double] else {
                print("Converter: invalid rate response")
                return
            }

            DispatchQueue.main.async {
                self?.rates = Dictionary(uniqueKeysWithValues: ratesDict.map { ($0.key.lowercased(), $0.value) })
                self?.ratesLoaded = true
                print("Converter: \(ratesDict.count) exchange rates loaded")
            }
        }.resume()
    }
}
