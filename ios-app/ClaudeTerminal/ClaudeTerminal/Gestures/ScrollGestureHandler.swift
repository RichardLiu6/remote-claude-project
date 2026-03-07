import UIKit

/// Handles touch-based scrolling on the terminal view.
/// Mirrors the Web App's scroll physics:
///   - Non-linear acceleration (small swipe = precise, fast swipe = many lines)
///   - Momentum / inertia after finger lift
///   - Throttled command sending (~25fps)
///   - Gesture disambiguation: short tap = keyboard focus, drag = scroll
///
/// Sends tmux scroll protocol:
///   \x01scroll:up:N / \x01scroll:down:N / \x01scroll:exit
final class ScrollGestureHandler {

    // MARK: - Callbacks

    /// Send a scroll command (direction: "up"/"down"/"exit", lines: count).
    var onScroll: ((_ direction: String, _ lines: Int) -> Void)?

    /// Called on a single tap (not a scroll) — used to focus keyboard.
    var onTap: (() -> Void)?

    /// Called when entering/exiting scroll mode.
    var onScrollModeChanged: ((_ inScrollMode: Bool) -> Void)?

    /// Called when a long press is detected (500ms hold without movement).
    var onLongPress: (() -> Void)?

    // MARK: - State

    private(set) var inScrollMode = false

    // Touch tracking
    private var touchStartY: CGFloat = 0
    private var touchStartX: CGFloat = 0
    private var touchMoved = false
    private var lastMoveTime: TimeInterval = 0
    private var velocity: CGFloat = 0

    // Scroll accumulation & throttle
    private var pendingScroll: CGFloat = 0
    private var scrollThrottleTimer: Timer?

    // Momentum
    private var momentumTimer: CADisplayLink?

    // Long-press
    private var longPressTimer: Timer?
    private var longPressTriggered = false
    private let longPressDelay: TimeInterval = 0.5
    private let longPressMoveThreshold: CGFloat = 5.0

    // MARK: - Non-linear acceleration

    /// Converts pixel displacement to line count.
    /// Apple-inspired pow curve matching the Web App's `accelLines`.
    private func accelLines(_ px: CGFloat) -> CGFloat {
        let absPx = abs(px)
        if absPx < 3 { return 0 }
        // pow(x/6, 1.6): slightly more aggressive than 1.5 for bigger swipes
        let scaled = pow(absPx / 6.0, 1.6)
        let lines = max(1.0, scaled.rounded())
        return lines * (px > 0 ? 1 : -1)
    }

    // MARK: - Flush pending scroll

    private func flushScroll() {
        guard pendingScroll != 0 else { return }
        let direction = pendingScroll > 0 ? "up" : "down"
        let n = min(Int(abs(pendingScroll)), 50)
        onScroll?(direction, n)

        if !inScrollMode {
            inScrollMode = true
            onScrollModeChanged?(true)
        }
        pendingScroll = 0
    }

    // MARK: - Momentum

    private func startMomentum() {
        stopMomentum()

        var v = velocity
        var lastSend = CACurrentMediaTime()
        let decay: CGFloat = 0.95 // Apple native feel: 0.95/frame ~800ms coast

        let link = CADisplayLink(target: MomentumTarget(handler: { [weak self] in
            guard let self = self else { return }
            v *= decay
            if abs(v) < 2 {
                self.stopMomentum()
                return
            }
            let now = CACurrentMediaTime()
            if now - lastSend > 0.05 { // 50ms throttle
                let lines = Int(abs(self.accelLines(v)))
                if lines < 1 {
                    self.stopMomentum()
                    return
                }
                let dir = v > 0 ? "up" : "down"
                self.onScroll?(dir, lines)
                lastSend = now
            }
        }), selector: #selector(MomentumTarget.tick))

        link.add(to: .main, forMode: .common)
        momentumTimer = link
    }

    private func stopMomentum() {
        momentumTimer?.invalidate()
        momentumTimer = nil
    }

    // MARK: - Long press

    private func cancelLongPress() {
        longPressTimer?.invalidate()
        longPressTimer = nil
    }

    // MARK: - Touch handling (call from UIView)

    func touchesBegan(at point: CGPoint) {
        touchStartY = point.y
        touchStartX = point.x
        touchMoved = false
        longPressTriggered = false
        lastMoveTime = CACurrentMediaTime()
        velocity = 0
        stopMomentum()
        cancelLongPress()

        // Start long-press timer
        longPressTimer = Timer.scheduledTimer(withTimeInterval: longPressDelay, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            self.longPressTriggered = true
            self.onLongPress?()
        }
    }

    func touchesMoved(to point: CGPoint) {
        let deltaY = touchStartY - point.y
        let deltaX = touchStartX - point.x

        // Cancel long-press if finger moved beyond threshold
        if abs(deltaY) > longPressMoveThreshold || abs(deltaX) > longPressMoveThreshold {
            cancelLongPress()
        }

        guard abs(deltaY) > 5 else { return }

        touchMoved = true
        cancelLongPress()

        let now = CACurrentMediaTime()
        let dt = now - lastMoveTime
        let dtNorm = max(dt, 0.001) // avoid division by zero

        // iOS natural scroll: finger up -> content up -> see newer -> scroll down
        // Negate deltaY like the Web App does
        pendingScroll += accelLines(-deltaY)

        // Track velocity in pixels per 16ms frame
        velocity = (-deltaY) / CGFloat(dtNorm / 0.016)
        velocity = max(-80, min(80, velocity)) // clamp

        touchStartY = point.y
        lastMoveTime = now

        // Throttle: flush at most every 40ms (~25fps)
        if scrollThrottleTimer == nil {
            scrollThrottleTimer = Timer.scheduledTimer(withTimeInterval: 0.04, repeats: false) { [weak self] _ in
                self?.flushScroll()
                self?.scrollThrottleTimer = nil
            }
        }
    }

    func touchesEnded() {
        cancelLongPress()

        // Flush remaining scroll
        scrollThrottleTimer?.invalidate()
        scrollThrottleTimer = nil
        flushScroll()

        // Start momentum if velocity is significant
        if touchMoved && abs(velocity) > 5 {
            startMomentum()
        }

        if longPressTriggered {
            longPressTriggered = false
            return
        }

        if !touchMoved {
            stopMomentum()
            // Tap: exit copy-mode and focus keyboard
            if inScrollMode {
                onScroll?("exit", 0)
                inScrollMode = false
                onScrollModeChanged?(false)
            }
            onTap?()
        }
    }

    func touchesCancelled() {
        cancelLongPress()
        scrollThrottleTimer?.invalidate()
        scrollThrottleTimer = nil
        stopMomentum()
    }
}

// MARK: - Momentum CADisplayLink target

/// A helper class to use as CADisplayLink target (avoids retain cycle with closures).
private class MomentumTarget {
    let handler: () -> Void

    init(handler: @escaping () -> Void) {
        self.handler = handler
    }

    @objc func tick() {
        handler()
    }
}
