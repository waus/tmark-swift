import AVFoundation
import Foundation

/// Explicit activation avoids AVAudioPlayer activating the session on the UI thread.
enum NativeAudioSession {
    #if os(iOS)
    private static let queue = DispatchQueue(label: "app.tmark.audio-session", qos: .userInitiated)
    #endif

    static func activate() async throws {
        try Task.checkCancellation()
        #if os(iOS)
        // setActive is available on our minimum iOS version. The asynchronous
        // AVAudioSession activation API requires iOS 27.
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    try AVAudioSession.sharedInstance().setActive(true)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
        #endif
        try Task.checkCancellation()
    }
}
