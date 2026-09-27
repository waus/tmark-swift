import AVFoundation
import Foundation

/// Uses only the system decoder. Older systems may reject Ogg/Opus at runtime.
enum NativeAudioDecoder {
    static func decodeOpus(_ data: Data) async throws -> URL {
        let task = Task.detached(priority: .userInitiated) {
            let source = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).appendingPathExtension("ogg")
            let output = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).appendingPathExtension("wav")
            defer { try? FileManager.default.removeItem(at: source) }
            do {
                try Task.checkCancellation()
                try data.write(to: source)
                let input = try AVAudioFile(forReading: source)
                let format = input.processingFormat
                let destination = try AVAudioFile(
                    forWriting: output,
                    settings: format.settings,
                    commonFormat: format.commonFormat,
                    interleaved: format.isInterleaved
                )
                guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8192) else {
                    throw URLError(.cannotDecodeContentData)
                }
                while input.framePosition < input.length {
                    try Task.checkCancellation()
                    try input.read(into: buffer)
                    guard buffer.frameLength > 0 else { break }
                    try destination.write(from: buffer)
                }
                try Task.checkCancellation()
                return output
            } catch {
                try? FileManager.default.removeItem(at: output)
                throw error
            }
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }
}
