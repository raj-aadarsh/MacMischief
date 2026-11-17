import AppKit
import CoreGraphics

struct TrackedWindow: Equatable {
    let id: CGWindowID
    /// Cocoa global coordinates (origin = bottom-left of the primary display).
    let frame: CGRect
}

struct WindowSnapshot: Equatable {
    /// Ordered front-to-back.
    var windows: [TrackedWindow]
    static let empty = WindowSnapshot(windows: [])
}

/// Polls the *positions* of on-screen windows (read-only; no permissions needed —
/// window titles/contents are never read) on a background queue.
final class WindowTracker: @unchecked Sendable {
    static let shared = WindowTracker()

    @MainActor var onChange: ((WindowSnapshot) -> Void)?

    private let queue = DispatchQueue(label: "macmischief.window-tracker", qos: .userInitiated)
    private var timer: DispatchSourceTimer?
    private var last: WindowSnapshot?
    private let ownPID = ProcessInfo.processInfo.processIdentifier
    /// Poll quickly until this time (after a change, a click, or an app switch).
    private var fastUntil: TimeInterval = 0
    private var lastPoll: TimeInterval = 0
    private static let fastInterval: TimeInterval = 0.1
    private static let slowInterval: TimeInterval = 0.5

    @MainActor func start() {
        queue.async { [self] in
            guard timer == nil else { return }
            last = nil
            lastPoll = 0
            fastUntil = Self.now + 1
            let t = DispatchSource.makeTimerSource(queue: queue)
            t.schedule(deadline: .now(), repeating: .milliseconds(100), leeway: .milliseconds(20))
            t.setEventHandler { [weak self] in self?.tick() }
            t.resume()
            timer = t
        }
    }

    @MainActor func stop() {
        queue.async { [self] in
            timer?.cancel()
            timer = nil
        }
    }

    /// Something probably changed (e.g. another app came forward): check right away.
    @MainActor func nudge() {
        queue.async { [self] in
            fastUntil = Self.now + 1
            if timer != nil { poll() }
        }
    }

    private static var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    /// Asking the window server for the window list is the most expensive thing we
    /// do, so poll fast only while something is happening (mouse held down = a
    /// window may be dragging), and slowly otherwise.
    private func tick() {
        let now = Self.now
        let mouseDown = CGEventSource.buttonState(.combinedSessionState, button: .left)
        if mouseDown { fastUntil = max(fastUntil, now + 0.6) }
        let interval = now < fastUntil ? Self.fastInterval : Self.slowInterval
        guard now - lastPoll >= interval - 0.01 else { return }
        poll()
    }

    private func poll() {
        lastPoll = Self.now
        let snap = Self.capture(excludingPID: ownPID)
        guard snap != last else { return }
        last = snap
        fastUntil = Self.now + 1
        DispatchQueue.main.async {
            MainActor.assumeIsolated { WindowTracker.shared.onChange?(snap) }
        }
    }

    static func capture(excludingPID pid: pid_t) -> WindowSnapshot {
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return .empty }
        let primaryHeight = CGDisplayBounds(CGMainDisplayID()).height
        var out: [TrackedWindow] = []
        out.reserveCapacity(info.count)
        for w in info {
            guard (w[kCGWindowLayer as String] as? Int) == 0,
                  let owner = w[kCGWindowOwnerPID as String] as? pid_t, owner != pid,
                  let number = w[kCGWindowNumber as String] as? CGWindowID,
                  let boundsDict = w[kCGWindowBounds as String] as? NSDictionary,
                  let b = CGRect(dictionaryRepresentation: boundsDict as CFDictionary)
            else { continue }
            let alpha = (w[kCGWindowAlpha as String] as? Double) ?? 1
            guard alpha > 0.05, b.width >= 80, b.height >= 50 else { continue }
            // CG uses a top-left origin; convert to Cocoa's bottom-left origin.
            let frame = CGRect(x: b.minX, y: primaryHeight - b.maxY, width: b.width, height: b.height)
            out.append(TrackedWindow(id: number, frame: frame))
        }
        return WindowSnapshot(windows: out)
    }
}
