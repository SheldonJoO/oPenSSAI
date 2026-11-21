//
//  PairingCodeLiveActivityManager.swift
//  SideStore
//
//  Copyright © 2026 SideStore. All rights reserved.
//

import ActivityKit
import Foundation
import UserNotifications

/// Starts and ends the pairing-code Live Activity (Dynamic Island) shown
/// while wireless pairing waits for the code to be entered on the other
/// device.
///
/// The PIN callback that feeds this manager is retained by the singleton
/// pairing service (`WirelessPairService.onPinReceived`), so `start` is
/// reached even after the pairing screen's view model is gone — the user
/// is usually in Settings by the time the code arrives. Do not move the
/// `start` call behind a view-model lifetime check.
///
/// A local notification with the code is posted alongside the activity as
/// an auxiliary channel: it only lands when the user granted notification
/// permission, so the Live Activity stays the primary path.
///
/// Live Activities need iOS 16.2+ for the ActivityContent-based APIs used
/// here (deployment target is iOS 15.0), so the whole type is
/// availability-gated and callers check `#available` first.
///
/// Needs proper testing: Live Activities only render on a real device with
/// a Dynamic Island (or on the Lock Screen on other devices) — verify
/// on-device that the activity starts when the PIN sheet appears and ends
/// on success, failure, and cancel.
@available(iOS 16.2, *)
@MainActor
final class PairingCodeLiveActivityManager {
    static let shared = PairingCodeLiveActivityManager()

    private init() {}

    /// The currently running activity, if this launch started one.
    private var activity: Activity<PairingCodeAttributes>?

    /// User-facing reason the last `start` failed (e.g. Live Activities
    /// disabled), so the pairing UI can tell the user how to fix it.
    /// `nil` after a successful start.
    private(set) var lastStartFailure: String?

    /// How long the code stays fresh before the system dims the activity.
    /// Pairing normally completes within seconds; the stale date only bounds
    /// a leaked activity if the app is killed mid-pairing.
    private static let staleInterval: TimeInterval = 10 * 60

    /// Safety net: if the pairing UI is gone (e.g. the user left the
    /// screen for Settings), nobody ends the activity when pairing
    /// finishes — end it after this long so a stale code never lingers
    /// in the island. Prompt ends (success/failure/cancel) cancel this.
    private static let watchdogInterval: TimeInterval = 5 * 60

    /// Notification identifier for the pairing-code fallback banner. A
    /// fixed identifier lets a newer code replace an older one, and lets
    /// `end` clear the banner when pairing finishes.
    private static let notificationIdentifier = "pairing-code"

    private var endTask: Task<Void, Never>?

    /// Start the Live Activity, or update it if one is already running
    /// (e.g. a second device connected and a new code arrived). Also posts
    /// the local-notification fallback when notification permission is
    /// granted.
    func start(pinCode: String) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            lastStartFailure = NSLocalizedString("Live Activities are turned off for openSSS. Turn them on in Settings to see the pairing code in the Dynamic Island.", comment: "")
            debugLog("[PairingCodeLiveActivity] Live Activities are disabled; not starting")
            postPinNotification(pinCode: pinCode)
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
            lastStartFailure = nil
            Task { await existing.update(content) }
            scheduleWatchdog()
            postPinNotification(pinCode: pinCode)
            return
        }

        do {
            activity = try Activity.request(attributes: PairingCodeAttributes(), content: content)
            lastStartFailure = nil
            debugLog("[PairingCodeLiveActivity] Live Activity started")
            scheduleWatchdog()
            postPinNotification(pinCode: pinCode)
        } catch {
            lastStartFailure = NSLocalizedString("Couldn't show the pairing code in the Dynamic Island.", comment: "")
            debugLog("[PairingCodeLiveActivity] Failed to start Live Activity: \(error)")
            postPinNotification(pinCode: pinCode)
        }
    }

    /// End the Live Activity immediately (pairing completed, failed, or
    /// cancelled). Also ends orphaned activities from an earlier launch
    /// and clears the fallback notification.
    func end() {
        endTask?.cancel()
        endTask = nil

        let current = activity
        activity = nil

        if let current {
            Task { await current.end(nil, dismissalPolicy: .immediate) }
        }

        for orphan in Activity<PairingCodeAttributes>.activities where orphan.id != current?.id {
            Task { await orphan.end(nil, dismissalPolicy: .immediate) }
        }

        let center = UNUserNotificationCenter.current()
        center.removeDeliveredNotifications(withIdentifiers: [Self.notificationIdentifier])
        center.removePendingNotificationRequests(withIdentifiers: [Self.notificationIdentifier])
    }

    /// End the activity after `watchdogInterval` unless `end` runs first
    /// (pairing finished promptly) or a newer code restarts the clock.
    private func scheduleWatchdog() {
        endTask?.cancel()
        endTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.watchdogInterval * 1_000_000_000))
            guard !Task.isCancelled else { return }
            debugLog("[PairingCodeLiveActivity] Watchdog ending stale activity")
            self?.end()
        }
    }

    /// Auxiliary channel: a banner with the code, for users who granted
    /// notification permission. No-op when permission is denied (the
    /// Live Activity is the primary path), and never requests permission
    /// here — the PIN prompt is no time to ask.
    private func postPinNotification(pinCode: String) {
        Task {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            guard settings.authorizationStatus == .authorized else { return }
            let content = UNMutableNotificationContent()
            content.title = NSLocalizedString("Pairing Code", comment: "")
            content.body = String(format: NSLocalizedString("Your pairing code is %@.", comment: ""), pinCode)
            content.sound = .default
            // Nil trigger delivers immediately.
            let request = UNNotificationRequest(identifier: Self.notificationIdentifier, content: content, trigger: nil)
            try? await center.add(request)
        }
    }
}
