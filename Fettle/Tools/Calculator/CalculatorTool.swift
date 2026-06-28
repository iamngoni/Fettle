import SwiftUI

/// One editable line. A stable id lets the editor delete/reorder lines without
/// the index-based crashes a `[String]` + `ForEach(indices)` would risk.
struct CalcLine: Identifiable, Equatable {
    let id = UUID()
    var text: String
}

@MainActor
@Observable
final class CalculatorTool: FettleTool {
    let kind: ToolID = .calculator
    let title = "Calculator"
    let symbol = "function"
    let tint = Color(hex: 0xFF9F0A)
    let section: ToolSection = .tools

    var lines: [CalcLine] {
        didSet { saveLines() }
    }
    private(set) var rates: [String: Double] = ["USD": 1]

    var isActive: Bool { false }
    var statusText: String { "Calc, units & currency" }
    var statusTint: Color { Theme.textMuted }
    var control: ToolControl { .navigate }
    var hasDetail: Bool { true }

    init() {
        if let data = UserDefaults.standard.data(forKey: "calc.lines"),
           let saved = try? JSONDecoder().decode([String].self, from: data), !saved.isEmpty {
            let nonBlank = saved.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            let legacyExamples = ["18% of 1250", "20 EUR in USD", "2 kg in pounds", "(12 + 8) * 3"]
            if nonBlank == legacyExamples {
                UserDefaults.standard.removeObject(forKey: "calc.lines")
                lines = [CalcLine(text: "")]
            } else {
                lines = saved.map { CalcLine(text: $0) }
            }
        } else {
            lines = [CalcLine(text: "")]
        }
        if let data = UserDefaults.standard.data(forKey: "calc.rates"),
           let cached = try? JSONDecoder().decode([String: Double].self, from: data) {
            rates = cached
        }
        fetchRates()
    }

    func result(for text: String) -> String? {
        CalcEngine.evaluate(text, rates: rates)
    }

    /// Keep exactly one trailing blank line so there's always room to type.
    func ensureTrailingBlank() {
        if lines.last?.text.trimmingCharacters(in: .whitespaces).isEmpty == false {
            lines.append(CalcLine(text: ""))
        }
    }

    func removeLine(_ line: CalcLine) {
        lines.removeAll { $0.id == line.id }
        if lines.isEmpty { lines = [CalcLine(text: "")] }
    }

    func clearAll() {
        lines = [CalcLine(text: "")]
    }

    private func saveLines() {
        if let data = try? JSONEncoder().encode(lines.map(\.text)) {
            UserDefaults.standard.set(data, forKey: "calc.lines")
        }
    }

    /// Fetches USD-based exchange rates (ECB via frankfurter.app). Cached so
    /// currency conversion keeps working offline with the last known rates.
    func fetchRates() {
        Task {
            guard let url = URL(string: "https://api.frankfurter.app/latest?from=USD") else { return }
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                struct Response: Decodable { let rates: [String: Double] }
                let decoded = try JSONDecoder().decode(Response.self, from: data)
                var map = decoded.rates
                map["USD"] = 1
                rates = map
                if let encoded = try? JSONEncoder().encode(map) {
                    UserDefaults.standard.set(encoded, forKey: "calc.rates")
                }
            } catch {
                // Keep cached/seed rates on failure.
            }
        }
    }
}
