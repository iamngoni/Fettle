import Foundation
import SwiftUI
import CryptoKit
import IOKit
import Security

@MainActor
@Observable
final class LicenseManager {
    private static let apiBase = URL(string: "https://api.lemonsqueezy.com/v1/licenses")!
    private static let keychainAccount = "license-key"
    private static let instanceIDKey = "license.instanceID"
    private static let keyTailKey = "license.keyTail"
    private static let lastValidatedKey = "license.lastValidatedAt"

    var licenseKeyInput = ""
    private(set) var isWorking = false
    private(set) var isActivated = false
    private(set) var statusMessage = "Lifetime unlock: $3 once, one active Mac at a time."
    private(set) var statusColor = Theme.textMuted
    private(set) var keyTail: String?
    private(set) var activationUsage: String?

    private var instanceID: String?

    init() {
        instanceID = UserDefaults.standard.string(forKey: Self.instanceIDKey)
        keyTail = UserDefaults.standard.string(forKey: Self.keyTailKey)
        isActivated = instanceID != nil && LicenseKeychain.read(account: Self.keychainAccount) != nil
        if isActivated {
            statusMessage = "Activated on this Mac."
            statusColor = Theme.greenLight
            validate()
        }
    }

    var displayKeyTail: String {
        guard let keyTail, !keyTail.isEmpty else { return "" }
        return "•••• \(keyTail)"
    }

    func activate() {
        let key = licenseKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            statusMessage = "Enter a license key first."
            statusColor = Theme.red
            return
        }

        isWorking = true
        statusMessage = "Activating license..."
        statusColor = Theme.textMuted

        Task {
            do {
                let response = try await Self.post("activate", fields: [
                    "license_key": key,
                    "instance_name": Self.instanceName()
                ])

                guard response.activated == true, let instanceID = response.instance?.id else {
                    throw LicenseError.server(response.error ?? "License could not be activated.")
                }

                LicenseKeychain.write(key, account: Self.keychainAccount)
                self.instanceID = instanceID
                self.keyTail = Self.tail(for: key)
                self.licenseKeyInput = ""
                self.isActivated = true
                self.activationUsage = Self.usageText(from: response.license_key)
                UserDefaults.standard.set(instanceID, forKey: Self.instanceIDKey)
                UserDefaults.standard.set(self.keyTail, forKey: Self.keyTailKey)
                Self.markValidated()
                self.statusMessage = "Activated on this Mac."
                self.statusColor = Theme.greenLight
            } catch {
                self.statusMessage = Self.message(for: error)
                self.statusColor = Theme.red
            }
            self.isWorking = false
        }
    }

    func validate() {
        guard let key = LicenseKeychain.read(account: Self.keychainAccount),
              let instanceID
        else { return }

        isWorking = true
        Task {
            do {
                let response = try await Self.post("validate", fields: [
                    "license_key": key,
                    "instance_id": instanceID
                ])

                guard response.valid == true else {
                    self.clearActivation()
                    throw LicenseError.server(response.error ?? "License is no longer valid.")
                }

                Self.markValidated()
                self.activationUsage = Self.usageText(from: response.license_key)
                self.statusMessage = "Activated on this Mac."
                self.statusColor = Theme.greenLight
            } catch {
                if Self.hasOfflineGrace {
                    self.statusMessage = "Activated. Online check will retry later."
                    self.statusColor = Theme.greenLight
                } else {
                    self.statusMessage = Self.message(for: error)
                    self.statusColor = Theme.red
                }
            }
            self.isWorking = false
        }
    }

    func deactivate() {
        guard let key = LicenseKeychain.read(account: Self.keychainAccount),
              let instanceID
        else {
            clearActivation()
            return
        }

        isWorking = true
        statusMessage = "Releasing this seat..."
        statusColor = Theme.textMuted

        Task {
            do {
                let response = try await Self.post("deactivate", fields: [
                    "license_key": key,
                    "instance_id": instanceID
                ])

                guard response.deactivated == true else {
                    throw LicenseError.server(response.error ?? "License could not be deactivated.")
                }

                self.clearActivation()
                self.statusMessage = "Seat released."
                self.statusColor = Theme.textMuted
            } catch {
                self.statusMessage = Self.message(for: error)
                self.statusColor = Theme.red
            }
            self.isWorking = false
        }
    }

    private func clearActivation() {
        LicenseKeychain.delete(account: Self.keychainAccount)
        instanceID = nil
        keyTail = nil
        activationUsage = nil
        isActivated = false
        UserDefaults.standard.removeObject(forKey: Self.instanceIDKey)
        UserDefaults.standard.removeObject(forKey: Self.keyTailKey)
        UserDefaults.standard.removeObject(forKey: Self.lastValidatedKey)
    }

    private static func post(_ action: String, fields: [String: String]) async throws -> LicenseAPIResponse {
        let url = apiBase.appendingPathComponent(action)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formBody(fields)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<500).contains(http.statusCode) else {
            throw LicenseError.server("License server did not respond.")
        }
        return try JSONDecoder().decode(LicenseAPIResponse.self, from: data)
    }

    private static func formBody(_ fields: [String: String]) -> Data {
        let body = fields
            .map { key, value in
                "\(escape(key))=\(escape(value))"
            }
            .joined(separator: "&")
        return Data(body.utf8)
    }

    private static func escape(_ value: String) -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private static func instanceName() -> String {
        let host = Host.current().localizedName ?? "Mac"
        return "\(host) · \(machineFingerprint.prefix(8))"
    }

    private static var machineFingerprint: String {
        let fallback = Host.current().localizedName ?? UUID().uuidString
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        defer {
            if service != 0 { IOObjectRelease(service) }
        }

        let uuid = (service == 0 ? nil : IORegistryEntryCreateCFProperty(service, "IOPlatformUUID" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String) ?? fallback
        let digest = SHA256.hash(data: Data(uuid.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func tail(for key: String) -> String {
        String(key.suffix(6))
    }

    private static func markValidated() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastValidatedKey)
    }

    private static var hasOfflineGrace: Bool {
        let last = UserDefaults.standard.double(forKey: lastValidatedKey)
        guard last > 0 else { return false }
        return Date().timeIntervalSince1970 - last < 14 * 24 * 60 * 60
    }

    private static func usageText(from license: LicenseKeyPayload?) -> String? {
        guard let usage = license?.activation_usage,
              let limit = license?.activation_limit
        else { return nil }
        return "\(usage)/\(limit) seats active"
    }

    private static func message(for error: Error) -> String {
        if let error = error as? LicenseError { return error.localizedDescription }
        return "License check failed. Try again."
    }
}

private enum LicenseError: LocalizedError {
    case server(String)

    var errorDescription: String? {
        switch self {
        case .server(let message): return message
        }
    }
}

private struct LicenseAPIResponse: Decodable {
    let activated: Bool?
    let valid: Bool?
    let deactivated: Bool?
    let error: String?
    let license_key: LicenseKeyPayload?
    let instance: LicenseInstancePayload?
}

private struct LicenseKeyPayload: Decodable {
    let status: String?
    let activation_limit: Int?
    let activation_usage: Int?
}

private struct LicenseInstancePayload: Decodable {
    let id: String
}

private enum LicenseKeychain {
    private static let service = "za.co.codecraftsolutions.Fettle.license"

    static func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func write(_ value: String, account: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let update: [String: Any] = [kSecValueData as String: data]
        if SecItemUpdate(query as CFDictionary, update as CFDictionary) == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
