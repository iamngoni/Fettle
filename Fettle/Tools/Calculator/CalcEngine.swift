import Foundation

/// A small natural-language calculator: arithmetic, percentages, unit
/// conversion, and currency conversion (using fetched rates). Evaluates one
/// line at a time and returns a formatted result string, or nil for blank /
/// comment / unparseable lines.
enum CalcEngine {

    static func evaluate(_ raw: String, rates: [String: Double]) -> String? {
        let line = raw.trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty, !line.hasPrefix("//"), !line.hasPrefix("#") else { return nil }

        // 1. "X% of Y"
        if let m = capture(line, #"(?i)^([0-9.,]+)\s*%\s+of\s+([0-9.,]+)$"#) {
            return format(number(m[0]) / 100 * number(m[1]))
        }

        // 2. Conversion: "<num> <unit> in|to <unit>"
        if let m = capture(line, #"(?i)^([0-9.,]+)\s*([a-zA-Z$€£]+)\s+(?:in|to)\s+([a-zA-Z$€£]+)$"#),
           let converted = convert(value: number(m[0]), from: m[1], to: m[2], rates: rates) {
            return converted
        }

        // 3. Trailing percent: "X - 9%" / "X + 9%"
        if let m = capture(line, #"^(.+?)\s*([-+])\s*([0-9.,]+)\s*%$"#),
           let base = arithmetic(m[0]) {
            let p = number(m[2])
            return format(m[1] == "-" ? base * (1 - p / 100) : base * (1 + p / 100))
        }

        // 4. Plain arithmetic
        if let v = arithmetic(line) { return format(v) }
        return nil
    }

    // MARK: Conversion

    private static func convert(value: Double, from: String, to: String, rates: [String: Double]) -> String? {
        // Currency first (3-letter codes / symbols).
        if let f = currencyCode(from), let t = currencyCode(to) {
            guard let rf = rates[f], let rt = rates[t], rf > 0 else { return nil }
            let usd = value / rf                // rates are per-USD
            let out = usd * rt
            return symbol(t) + format(out)
        }
        // Physical units.
        if let (mFrom, dim) = unit(from), let (mTo, dim2) = unit(to), dim == dim2 {
            let measurement = Measurement(value: value, unit: mFrom)
            let converted = measurement.converted(to: mTo)
            return "\(format(converted.value)) \(to)"
        }
        return nil
    }

    private static func currencyCode(_ s: String) -> String? {
        let map: [String: String] = ["$": "USD", "€": "EUR", "£": "GBP", "¥": "JPY"]
        if let mapped = map[s] { return mapped }
        let up = s.uppercased()
        let known: Set<String> = ["USD","EUR","GBP","CHF","JPY","CAD","AUD","CNY","INR","ZAR","SEK","NOK","NZD","BRL","MXN","SGD","HKD","KRW","PLN","DKK","TRY"]
        return known.contains(up) ? up : nil
    }

    private static func symbol(_ code: String) -> String {
        ["USD": "$", "EUR": "€", "GBP": "£", "JPY": "¥"][code] ?? "\(code) "
    }

    private static func unit(_ s: String) -> (Dimension, String)? {
        let u = s.lowercased()
        let length: [String: UnitLength] = ["mm": .millimeters, "cm": .centimeters, "m": .meters, "meter": .meters, "meters": .meters, "km": .kilometers, "in": .inches, "inch": .inches, "inches": .inches, "ft": .feet, "foot": .feet, "feet": .feet, "yd": .yards, "yard": .yards, "mi": .miles, "mile": .miles, "miles": .miles]
        let mass: [String: UnitMass] = ["mg": .milligrams, "g": .grams, "gram": .grams, "grams": .grams, "kg": .kilograms, "lb": .pounds, "lbs": .pounds, "pound": .pounds, "pounds": .pounds, "oz": .ounces, "ounce": .ounces, "ounces": .ounces, "ton": .metricTons]
        let volume: [String: UnitVolume] = ["ml": .milliliters, "l": .liters, "liter": .liters, "liters": .liters, "litre": .liters, "litres": .liters, "tsp": .teaspoons, "tbsp": .tablespoons, "cup": .cups, "cups": .cups, "floz": .fluidOunces, "gal": .gallons, "gallon": .gallons, "pint": .pints, "cbm": .cubicMeters]
        let duration: [String: UnitDuration] = ["s": .seconds, "sec": .seconds, "secs": .seconds, "second": .seconds, "seconds": .seconds, "min": .minutes, "mins": .minutes, "minute": .minutes, "minutes": .minutes, "h": .hours, "hr": .hours, "hour": .hours, "hours": .hours]
        let storage: [String: UnitInformationStorage] = ["b": .bytes, "byte": .bytes, "bytes": .bytes, "kb": .kilobytes, "mb": .megabytes, "gb": .gigabytes, "tb": .terabytes, "bit": .bits]

        if let x = length[u] { return (x, "length") }
        if let x = mass[u] { return (x, "mass") }
        if let x = volume[u] { return (x, "volume") }
        if let x = duration[u] { return (x, "duration") }
        if let x = storage[u] { return (x, "storage") }
        return nil
    }

    // MARK: Arithmetic

    private static func arithmetic(_ s: String) -> Double? {
        let clean = s.replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: "£", with: "")
            .replacingOccurrences(of: "€", with: "")
            .replacingOccurrences(of: "×", with: "*")
            .replacingOccurrences(of: "÷", with: "/")
            .replacingOccurrences(of: "−", with: "-")
            .trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty, clean.rangeOfCharacter(from: .decimalDigits) != nil else { return nil }

        // Safe recursive-descent parser: returns nil for partial/invalid input
        // (e.g. "(12 +") instead of crashing the way NSExpression does.
        var parser = ExprParser(clean)
        guard let value = parser.parseExpression(), parser.isAtEnd, value.isFinite else { return nil }
        return value
    }

    // MARK: Helpers

    private static func number(_ s: String) -> Double {
        Double(s.replacingOccurrences(of: ",", with: "")) ?? 0
    }

    private static func format(_ v: Double) -> String {
        // Fixed en_US formatting so results match the period-decimal input
        // (avoids "$22,91"-style locale comma decimals while typing periods).
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "en_US")
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = (v == v.rounded() && abs(v) < 1e15) ? 0 : 2
        return f.string(from: NSNumber(value: v)) ?? String(format: "%.2f", v)
    }

    /// Recursive-descent arithmetic parser. Every method returns nil on malformed
    /// input, so partial expressions typed live never crash.
    private struct ExprParser {
        private let chars: [Character]
        private var pos = 0
        init(_ s: String) { chars = Array(s) }

        private mutating func skipSpaces() { while pos < chars.count, chars[pos] == " " { pos += 1 } }
        private mutating func peek() -> Character? { skipSpaces(); return pos < chars.count ? chars[pos] : nil }
        var isAtEnd: Bool { var p = self; return p.peek() == nil }

        mutating func parseExpression() -> Double? {
            guard var value = parseTerm() else { return nil }
            while let op = peek(), op == "+" || op == "-" {
                pos += 1
                guard let rhs = parseTerm() else { return nil }
                value = (op == "+") ? value + rhs : value - rhs
            }
            return value
        }

        private mutating func parseTerm() -> Double? {
            guard var value = parseFactor() else { return nil }
            while let op = peek(), op == "*" || op == "/" {
                pos += 1
                guard let rhs = parseFactor() else { return nil }
                if op == "/" { guard rhs != 0 else { return nil }; value /= rhs }
                else { value *= rhs }
            }
            return value
        }

        private mutating func parseFactor() -> Double? {
            guard let c = peek() else { return nil }
            if c == "+" { pos += 1; return parseFactor() }
            if c == "-" { pos += 1; guard let v = parseFactor() else { return nil }; return -v }
            if c == "(" {
                pos += 1
                guard let v = parseExpression(), peek() == ")" else { return nil }
                pos += 1
                return v
            }
            return parseNumber()
        }

        private mutating func parseNumber() -> Double? {
            skipSpaces()
            let start = pos
            while pos < chars.count, chars[pos].isNumber || chars[pos] == "." { pos += 1 }
            guard pos > start else { return nil }
            return Double(String(chars[start..<pos]))
        }
    }

    /// Returns capture groups (excluding the full match) for the first match.
    private static func capture(_ s: String, _ pattern: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(s.startIndex..., in: s)
        guard let m = re.firstMatch(in: s, range: range), m.numberOfRanges > 1 else { return nil }
        var groups: [String] = []
        for i in 1..<m.numberOfRanges {
            guard let r = Range(m.range(at: i), in: s) else { return nil }
            groups.append(String(s[r]))
        }
        return groups
    }
}
