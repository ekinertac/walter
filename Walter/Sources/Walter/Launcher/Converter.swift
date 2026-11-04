// Converter.swift — Offline unit conversion using local factors.
//
// Detects patterns like "100 km in miles" and "100 c to f".
// A missing or partial target shows compatible units as completions.

import Foundation

// MARK: - Public result type

struct ConversionResult {
    let title: String       // e.g. "212 °F"
    let subtitle: String    // e.g. "100 °C → °F"
    let copyValue: String   // e.g. "212"
}

// MARK: - Converter

class Converter {
    private let locale: Locale

    init(locale: Locale = .current) { self.locale = locale }

    /// Attempts to parse the query as a conversion. Returns multiple results
    /// (completion list) when the target is partial or missing.
    func convert(query: String) -> [ConversionResult] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()

        if let results = parseUnit(q), !results.isEmpty {
            return results
        }
        return []
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
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = value == value.rounded() ? 0 : 4
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }
}
