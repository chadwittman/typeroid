import AppKit
import CoreGraphics
import Foundation

enum FullScreenCaptureError: LocalizedError {
    case captureFailed
    case pngEncodingFailed

    var errorDescription: String? {
        switch self {
        case .captureFailed:
            return "Screen capture failed. Turn on Screen Recording for typeROID."
        case .pngEncodingFailed:
            return "Screen capture could not be encoded."
        }
    }
}

enum FullScreenCapture {
    static func capturePNG() throws -> Data {
        guard let image = CGWindowListCreateImage(.null, .optionOnScreenOnly, kCGNullWindowID, [.bestResolution, .nominalResolution]) else {
            throw FullScreenCaptureError.captureFailed
        }
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw FullScreenCaptureError.pngEncodingFailed
        }
        return data
    }
}
