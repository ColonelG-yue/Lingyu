/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * Originally from boring.notch project
 * Modified and adapted for Atoll (DynamicIsland)
 * See NOTICE for details.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import AppKit
import SwiftUI

enum PanDirection: Equatable {
    case left, right, up, down

    var isHorizontal: Bool { self == .left || self == .right }

    static func dominant(deltaX: CGFloat, deltaY: CGFloat) -> PanDirection? {
        guard max(abs(deltaX), abs(deltaY)) > 0 else { return nil }
        if abs(deltaX) >= abs(deltaY) {
            return deltaX < 0 ? .left : .right
        }
        return deltaY > 0 ? .down : .up
    }
}

struct PanGestureValue {
    let direction: PanDirection
    let translation: CGFloat
    let velocity: CGFloat
    let phase: NSEvent.Phase
    let isDiscreteSwipe: Bool
}

/// Pure commit rules shared by the notch, tab strip, and media gestures.
/// Keeping these rules free of SwiftUI state makes accidental cross-page
/// changes much easier to test and prevents terminal scrolling from becoming
/// a tab switch merely because a velocity sample was large.
enum PanGesturePolicy {
    static func shouldCommitOpening(
        _ value: PanGestureValue,
        sensitivity: CGFloat,
        velocityThreshold: CGFloat = 650
    ) -> Bool {
        value.isDiscreteSwipe
            || value.translation >= sensitivity
            || value.velocity >= velocityThreshold
    }

    static func tabSwitchDistance(sensitivity: CGFloat) -> CGFloat {
        min(max(sensitivity * 0.42, 72), 120)
    }

    static func shouldCommitTabSwitch(
        _ value: PanGestureValue,
        sensitivity: CGFloat,
        velocityThreshold: CGFloat = 1_150
    ) -> Bool {
        guard value.direction.isHorizontal else { return false }
        return value.isDiscreteSwipe
            || value.translation >= tabSwitchDistance(sensitivity: sensitivity)
            || (value.translation >= 30 && value.velocity >= velocityThreshold)
    }
}

extension View {
    /// Installs one gesture pipeline for every pan direction. Keeping this as
    /// one modifier is important: three separate NSEvent monitors race each
    /// other and can reset the same trackpad gesture before it commits.
    func unifiedPanGesture(
        threshold: CGFloat = 4,
        action: @escaping (PanGestureValue) -> Void
    ) -> some View {
        // Use one AppKit event pipeline. Keeping a second SwiftUI
        // DragGesture here makes terminal scrolling and tab switching race
        // over the same trackpad movement.
        self.background(UnifiedScrollMonitor(threshold: threshold, action: action))
    }
}

private struct UnifiedScrollMonitor: NSViewRepresentable {
    let threshold: CGFloat
    let action: (PanGestureValue) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.installMonitor(on: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.update(action: action)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.removeMonitor()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(threshold: threshold, action: action)
    }

    @MainActor final class Coordinator: NSObject {
        private let threshold: CGFloat
        private var action: (PanGestureValue) -> Void
        private var monitor: Any?
        private weak var observedView: NSView?
        private var lockedDirection: PanDirection?
        private var accumulated: CGFloat = 0
        private var pendingX: CGFloat = 0
        private var pendingY: CGFloat = 0
        private var gestureStartedAt: TimeInterval?
        private let noiseThreshold: CGFloat = 0.2
        private let axisDominanceRatio: CGFloat = 1.25
        private let intentDistance: CGFloat = 10
        private let verticalEdgeInset: CGFloat = 4

        init(threshold: CGFloat, action: @escaping (PanGestureValue) -> Void) {
            self.threshold = threshold
            self.action = action
        }

        func update(action: @escaping (PanGestureValue) -> Void) {
            self.action = action
        }

        func installMonitor(on view: NSView) {
            removeMonitor()
            observedView = view

            // A local monitor is sufficient for scrolls delivered to Atoll's
            // panel. A global monitor required Accessibility permission and
            // also duplicated events whenever Atoll itself was active.
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .swipe]) { [weak self] event in
                self?.handle(event)
                return event
            }
        }

        func removeMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
            reset()
            observedView = nil
        }

        private func handle(_ event: NSEvent) {
            guard isCursorNearObservedView(using: event) else { return }

            if event.type == .swipe {
                handleDiscreteSwipe(event)
            } else {
                handleScroll(event)
            }
        }

        /// Three-finger gestures may arrive as a single `.swipe` event whose
        /// delta is only around 1. Mark it as discrete instead of pretending
        /// that value is a pixel distance; the caller can commit immediately.
        private func handleDiscreteSwipe(_ event: NSEvent) {
            guard let direction = PanDirection.dominant(deltaX: event.deltaX, deltaY: event.deltaY) else { return }
            if AppRuntimeEnvironment.gestureDiagnosticsEnabled {
                Logger.log("Gesture swipe: \(direction)", category: .debug)
            }
            action(.init(
                direction: direction,
                translation: 0,
                velocity: .infinity,
                phase: .began,
                isDiscreteSwipe: true
            ))
            action(.init(
                direction: direction,
                translation: 0,
                velocity: .infinity,
                phase: .ended,
                isDiscreteSwipe: true
            ))
            reset()
        }

        private func handleScroll(_ event: NSEvent) {
            if event.phase == .ended || event.momentumPhase == .ended {
                finish(at: event.timestamp)
                return
            }

            // Momentum belongs to the gesture that has already ended. Ignoring
            // it prevents one flick from advancing through multiple tabs.
            guard event.momentumPhase.isEmpty else { return }

            let deltaX = event.scrollingDeltaX
            let deltaY = event.scrollingDeltaY
            guard max(abs(deltaX), abs(deltaY)) > noiseThreshold else { return }

            if lockedDirection == nil {
                pendingX += deltaX
                pendingY += deltaY

                let horizontalDistance = abs(pendingX)
                let verticalDistance = abs(pendingY)
                guard max(horizontalDistance, verticalDistance) >= max(threshold, intentDistance) else { return }

                let horizontalIntent = horizontalDistance >= verticalDistance * axisDominanceRatio
                let verticalIntent = verticalDistance >= horizontalDistance * axisDominanceRatio
                guard horizontalIntent || verticalIntent else { return }

                guard let candidate = PanDirection.dominant(deltaX: pendingX, deltaY: pendingY) else { return }
                lockedDirection = candidate
                accumulated = candidate.isHorizontal ? horizontalDistance : verticalDistance
                gestureStartedAt = event.timestamp
            } else if let direction = lockedDirection {
                let primaryDelta = direction.isHorizontal ? deltaX : deltaY
                let eventDirection = PanDirection.dominant(
                    deltaX: direction.isHorizontal ? primaryDelta : 0,
                    deltaY: direction.isHorizontal ? 0 : primaryDelta
                )
                // Small reversals should not abruptly change the locked axis.
                if eventDirection == direction {
                    accumulated += abs(primaryDelta)
                } else {
                    accumulated = max(threshold, accumulated - abs(primaryDelta) * 0.35)
                }
            }

            guard let direction = lockedDirection else { return }
            let velocity = currentVelocity(at: event.timestamp)
            action(.init(
                direction: direction,
                translation: accumulated,
                velocity: velocity,
                phase: accumulated <= threshold ? .began : .changed,
                isDiscreteSwipe: false
            ))

            // Mouse wheels often have no phase information. Finish each such
            // event so the interaction never remains permanently locked.
            if event.phase.isEmpty && event.momentumPhase.isEmpty && !event.hasPreciseScrollingDeltas {
                finish(at: event.timestamp)
            }
        }

        private func finish(at timestamp: TimeInterval) {
            guard let direction = lockedDirection else {
                reset()
                return
            }
            if AppRuntimeEnvironment.gestureDiagnosticsEnabled {
                Logger.log(
                    "Gesture scroll: \(direction), translation=\(Int(accumulated)), velocity=\(Int(currentVelocity(at: timestamp)))",
                    category: .debug
                )
            }
            action(.init(
                direction: direction,
                translation: accumulated,
                velocity: currentVelocity(at: timestamp),
                phase: .ended,
                isDiscreteSwipe: false
            ))
            reset()
        }

        private func currentVelocity(at timestamp: TimeInterval) -> CGFloat {
            guard let gestureStartedAt else { return 0 }
            let elapsed = max(timestamp - gestureStartedAt, 1.0 / 120.0)
            return accumulated / elapsed
        }

        private func reset() {
            lockedDirection = nil
            accumulated = 0
            pendingX = 0
            pendingY = 0
            gestureStartedAt = nil
        }

        private func isCursorNearObservedView(using event: NSEvent) -> Bool {
            guard let view = observedView, let window = view.window else { return false }

            let screenPoint: NSPoint
            if let eventWindow = event.window {
                let rect = NSRect(origin: event.locationInWindow, size: .zero)
                screenPoint = eventWindow.convertToScreen(rect).origin
            } else {
                screenPoint = NSEvent.mouseLocation
            }

            let windowPoint = window.convertPoint(fromScreen: screenPoint)
            let localPoint = view.convert(windowPoint, from: nil)
            let hitArea = view.bounds.insetBy(dx: 0, dy: -verticalEdgeInset)
            return hitArea.contains(localPoint)
        }
    }
}
