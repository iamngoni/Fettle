import SwiftUI

@MainActor
@Observable
final class CalculatorTool: FettleTool {
    let kind: ToolID = .calculator
    let title = "Calculator"
    let symbol = "function"
    let tint = Color(hex: 0xFF9F0A)
    let section: ToolSection = .tools

    var lines: [String] {
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
            lines = saved
        } else {
            lines = [""]
        }
        if let data = UserDefaults.standard.data(forKey: "calc.rates"),
           let cached = try? JSONDecoder().decode([String: Double].self, from: data) {
            rates = cached
        }
        fetchRates()
    }

    func result(for line: String) -> String? {
        CalcEngine.evaluate(line, rates: rates)
    }

    func ensureTrailingBlank() {
        if lines.last?.trimmingCharacters(in: .whitespaces).isEmpty == false {
            lines.append("")
        }
    }

    private func saveLines() {
        if let data = try? JSONEncoder().encode(lines) {
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
