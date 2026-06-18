import Foundation

final class OutputVolumeDucker {
    private let originalVolume: Int?

    init(reduction: Double = 0.70) {
        let current = Self.currentOutputVolume()
        originalVolume = current

        guard let current, current > 0 else { return }
        let target = max(0, min(100, Int((Double(current) * (1.0 - reduction)).rounded())))
        Self.setOutputVolume(target)
    }

    func restore() {
        guard let originalVolume else { return }
        Self.setOutputVolume(originalVolume)
    }

    private static func currentOutputVolume() -> Int? {
        runAppleScript("output volume of (get volume settings)")
            .flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    private static func setOutputVolume(_ volume: Int) {
        _ = runAppleScript("set volume output volume \(volume)")
    }

    private static func runAppleScript(_ script: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]

        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = output.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }
}
