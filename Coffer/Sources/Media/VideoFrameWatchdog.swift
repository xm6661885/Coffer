import Foundation

struct VideoFrameWatchdog {
    enum Status { case advancing, waiting, stalled }
    var frameInterval = 1.0 / 30
    var minimumFrameWait = 2.0
    private(set) var lastVideoTime = 0.0
    private var lastFrameTimestamp: Double?
    private var lastFrameHostTime = 0.0
    private var lastClock = 0.0
    private var lastClockHostTime = 0.0

    mutating func reset(at time: Double, now: Double = ProcessInfo.processInfo.systemUptime) {
        lastVideoTime = time; lastClock = time; lastFrameTimestamp = nil
        lastFrameHostTime = now; lastClockHostTime = now
    }

    mutating func observe(clock: Double, frameTime: Double?, rate: Float, now: Double = ProcessInfo.processInfo.systemUptime) -> Status {
        let clockMoved = clock > lastClock + 0.001
        if clockMoved { lastClockHostTime = now }
        lastClock = clock
        if let frameTime, frameTime.isFinite, lastFrameTimestamp == nil || frameTime > lastFrameTimestamp! + 0.001 {
            lastFrameTimestamp = frameTime; lastVideoTime = min(clock, max(0, frameTime)); lastFrameHostTime = now
            if clockMoved { return .advancing }
        }
        // Compare presentation timestamps, so a static picture with encoded frames remains healthy.
        let frameWait = max(minimumFrameWait, frameInterval * 3)
        if clock - lastVideoTime > frameWait, now - lastFrameHostTime > max(1, frameWait / Double(max(0.25, rate))) { return .stalled }
        return now - lastClockHostTime > 0.8 ? .waiting : .advancing
    }
}
