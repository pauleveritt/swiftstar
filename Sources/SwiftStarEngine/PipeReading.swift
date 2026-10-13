import Foundation

/// Stopping a pipe's `readabilityHandler` reads safely.
enum PipeReading {
    /// Stops reading `handle` early (a drain limit or a timeout) and ends its
    /// stream, without closing it. Closing from outside the handler is unsafe:
    /// setting `readabilityHandler = nil` doesn't wait for a handler already
    /// running, and `availableData` (like `fileDescriptor`) raises an
    /// Objective-C exception on a closed handle, which ends the app. The
    /// handle closes itself at EOF in its handler, or when it is released.
    static func stop(_ handle: FileHandle, _ continuation: AsyncStream<Data>.Continuation) {
        handle.readabilityHandler = nil
        continuation.finish()
    }
}
