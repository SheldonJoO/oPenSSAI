//
//  PairingCodeLiveActivityManager.swift
//  SideStore
//
//  Copyright © 2026 SideStore. All rights reserved.
//

import ActivityKit
import Foundation

/// Starts and ends the pairing-code Live Activity (Dynamic Island) shown
/// while wireless pairing waits for the code to be entered on the other
/// device. Owned by `WirelessPairViewModel`: start when `pinCode` is set,
/// end when pairing completes, fails, or is cancelled.
///
/// Live Activities need iOS 16.1+ (deployment target is iOS 15.0), so the
/// whole type is availability-gated and callers check `#available` first.
///
/// Needs proper testing: Live Activities only render on a real device with
/// a Dynamic Island (or on the Lock Screen on other devices) — verify
/// on-device that the activity starts when the PIN sheet appears and ends
/// on success, failure, and cancel.
@available(iOS 16.1, *)
@MainActor
final class PairingCodeLiveActivityManager {
    static let shared = PairingCodeLiveActivityManager()

    private init() {}

    /// The currently running activity, if this launch started one.
    private var activity: Activity<PairingCodeAttributes>?

    /// How long the code stays fresh before the system dims the activity.
    /// Pairing normally completes within seconds; the stale date only bounds
    /// a leaked activity if the app is killed mid-pairing.
    private static let staleInterval: TimeInterval = 10 * 60

    /// Start the Live Activity, or update it if one is already running
    /// (e.g. a second device connected and a new code arrived).
    func start(pinCode: String) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            debugLog("[PairingCodeLiveActivity] Live Activities are disabled; not starting")
            return
        }

        let content = ActivityContent(
            state: PairingCodeAttributes.ContentState(pinCode: pinCode),
            staleDate: Date().addingTimeInterval(Self.staleInterval)
        )

        // Adopt an activity from an earlier launch (or a previous start) so
        // we never stack two activities for the same pairing session.
        if let existing = activity ?? Activity<PairingCodeAttributes>.activities.first {
            activity = existing
            Task { await existing.update(content) }
            return
        }

        do {
            activity = try Activity.request(attributes: PairingCodeAttributes(), content: content)
            debugLog("[PairingCodeLiveActivity] Live Activity started")
        } catch {
            debugLog("[PairingCodeLiveActivity] Failed to start Live Activity: \(error)")
        }
    }

    /// End the Live Activity immediately (pairing completed, failed, or
    /// cancelled). Also ends orphaned activities from an earlier launch.
    func end() {
        let current = activity
        activity = nil

        if let current {
            Task { await current.end(nil, dismissalPolicy: .immediate) }
        }

        for orphan in Activity<PairingCodeAttributes>.activities where orphan.id != current?.id {
            Task { await orphan.end(nil, dismissalPolicy: .immediate) }
        }
    }
}
