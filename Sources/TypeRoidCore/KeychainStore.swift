import Foundation
import Security

enum KeychainStore {
    private static let service = "com.typeroid.app"

    enum Availability: Equatable {
        case present
        case missing
        case locked
    }

    /// Never prompts. Safe to call while the app is launching.
    static func availability(account: String) -> Availability {
        if let helper = helperURL {
            let result = run(helper, arguments: ["--check", account], timeout: 5)
            return result.status == 0 && result.output.contains("yes") ? .present : .missing
        }
        switch copy(account: account, returnData: false, prompt: false).status {
        case errSecSuccess:
            return .present
        case errSecItemNotFound:
            return .missing
        default:
            return .locked
        }
    }

    /// Silent read. The preview must not call SecItemCopyMatching: a mismatched
    /// signature hangs inside keychain decrypt instead of failing.
    static func read(account: String) -> String? {
        if let helper = helperURL {
            return readFromHelper(account: account)
        }
        let result = copy(account: account, returnData: true, prompt: false)
        guard result.status == errSecSuccess, let data = result.data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Used when a tool actually needs the secret.
    static func readAllowingPrompt(account: String) async -> String? {
        if helperURL != nil {
            return read(account: account)
        }
        if let silent = read(account: account), !silent.isEmpty {
            return silent
        }
        return await withCheckedContinuation { continuation in
            let gate = NSLock()
            var resumed = false
            let finish: (String?) -> Void = { value in
                gate.lock()
                let already = resumed
                resumed = true
                gate.unlock()
                guard !already else { return }
                continuation.resume(returning: value)
            }

            DispatchQueue.global(qos: .userInitiated).async {
                let result = copy(account: account, returnData: true, prompt: true)
                let value = result.status == errSecSuccess
                    ? result.data.flatMap { String(data: $0, encoding: .utf8) }
                    : nil
                finish(value)
            }
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 25) {
                finish(nil)
            }
        }
    }

    static func write(_ value: String?, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        guard let value, !value.isEmpty else {
            SecItemDelete(query as CFDictionary)
            return
        }

        let data = Data(value.utf8)
        let update: [String: Any] = [
            kSecValueData as String: data,
        ]

        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    /// Signed with the real app id so it can read typeROID's own key without hanging.
    /// Absent in the signed app, which reads the keychain itself.
    private static var helperURL: URL? {
        guard Bundle.main.bundleIdentifier == "com.typeroid.preview" else { return nil }
        let url = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/typeroid-key")
        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }

    private static func readFromHelper(account: String) -> String? {
        guard let helper = helperURL else { return nil }
        guard account.allSatisfy({ $0.isLetter || $0 == "_" }), account.hasSuffix("_api_key") else { return nil }
        let result = run(helper, arguments: ["--read", account], timeout: 5)
        guard result.status == 0 else { return nil }
        let key = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return key.isEmpty ? nil : key
    }

    private static func run(_ url: URL, arguments: [String], timeout: TimeInterval) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = url
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        do {
            try process.run()
        } catch {
            return (1, "")
        }
        if finished.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            return (1, "")
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }

    private static func copy(account: String, returnData: Bool, prompt: Bool) -> (status: OSStatus, data: Data?) {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationUI as String: prompt ? kSecUseAuthenticationUIAllow : kSecUseAuthenticationUIFail,
        ]
        if returnData {
            query[kSecReturnData as String] = true
        } else {
            query[kSecReturnAttributes as String] = true
        }

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        let data = returnData ? item as? Data : nil
        return (status, data)
    }
}
