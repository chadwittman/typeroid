import Foundation

/// Detects sensitive patterns (SSNs, credit cards, passwords, etc.) before API calls.
public enum SensitiveFilter {

    public struct Detection: Sendable {
        public let type: String      // "ssn", "credit_card", "password", etc.
        public let description: String
    }

    /// Check text for sensitive patterns. Returns detections if found.
    public static func scan(_ text: String) -> [Detection] {
        var detections: [Detection] = []

        // SSN: XXX-XX-XXXX or XXXXXXXXX
        let ssnPattern = #"\b\d{3}-\d{2}-\d{4}\b|\b\d{9}\b"#
        if text.range(of: ssnPattern, options: .regularExpression) != nil {
            detections.append(Detection(type: "ssn", description: "Social Security Number detected"))
        }

        // Credit card: 13-19 digits with optional spaces/dashes
        let ccPattern = #"\b(?:\d[ -]*?){13,19}\b"#
        if let range = text.range(of: ccPattern, options: .regularExpression) {
            let match = String(text[range]).replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "-", with: "")
            if match.count >= 13 && match.count <= 19 && luhnCheck(match) {
                detections.append(Detection(type: "credit_card", description: "Credit card number detected"))
            }
        }

        // Password patterns: "password: xxx" or "pwd: xxx" or "pass: xxx"
        let pwdPattern = #"(?i)(password|passwd|pwd|pass)\s*[:=]\s*\S+"#
        if text.range(of: pwdPattern, options: .regularExpression) != nil {
            detections.append(Detection(type: "password", description: "Password detected"))
        }

        // API keys: common patterns
        let keyPatterns = [
            (#"(?i)(api[_-]?key|secret[_-]?key|access[_-]?token)\s*[:=]\s*\S+"#, "API key/secret"),
            (#"\bsk-[a-zA-Z0-9]{20,}\b"#, "OpenAI API key"),
            (#"\bsk-ant-[a-zA-Z0-9]{20,}\b"#, "Anthropic API key"),
            (#"\bgsk_[a-zA-Z0-9]{20,}\b"#, "Groq API key"),
            (#"\bAIza[a-zA-Z0-9_-]{30,}\b"#, "Google API key"),
        ]
        for (pattern, desc) in keyPatterns {
            if text.range(of: pattern, options: .regularExpression) != nil {
                detections.append(Detection(type: "api_key", description: desc + " detected"))
                break  // one is enough
            }
        }

        // Bank account / routing numbers
        let bankPattern = #"(?i)(routing|account)\s*(number|#|no)?\s*[:=]?\s*\d{6,}"#
        if text.range(of: bankPattern, options: .regularExpression) != nil {
            detections.append(Detection(type: "bank", description: "Bank account/routing number detected"))
        }

        return detections
    }

    /// Returns true if text contains sensitive data that should NOT be sent to an API.
    public static func containsSensitiveData(_ text: String) -> Bool {
        !scan(text).isEmpty
    }

    /// Luhn algorithm for credit card validation
    private static func luhnCheck(_ number: String) -> Bool {
        let digits = number.compactMap { $0.wholeNumberValue }
        guard digits.count >= 13 else { return false }
        var sum = 0
        for (i, digit) in digits.reversed().enumerated() {
            if i % 2 == 1 {
                let doubled = digit * 2
                sum += doubled > 9 ? doubled - 9 : doubled
            } else {
                sum += digit
            }
        }
        return sum % 10 == 0
    }
}
