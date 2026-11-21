//
//  ScheduleExpirationWarningNotificationOperation.swift
//  SideStore
//
//  Created by Magesh K on 30/07/26.
//  Copyright © 2026 AltStore. All rights reserved.
//

import UserNotifications
import Foundation

final class ScheduleExpirationWarningNotificationOperation: BaseStandaloneOperation<StandaloneOperationContext, Bool>, @unchecked Sendable {
    let installedApp: InstalledApp

    init(installedApp: InstalledApp, context: StandaloneOperationContext) throws {
        self.installedApp = installedApp
        try super.init(context: context)
    }

    override func execute(parentProgress: Progress?) async throws -> Bool {
        let startTime = CFAbsoluteTimeGetCurrent()
        debugLog("[ScheduleExpirationWarningNotificationOperation] execute() started")
        defer {
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            debugLog("[ScheduleExpirationWarningNotificationOperation] execute() took: \(String(format: "%.3fs", elapsed))")
        }
        try await super.executePreconditionCheck(parentProgress: parentProgress)
        self.setProgress(10)

        let center = UNUserNotificationCenter.current()
        let now = Date()
        var expirationDate = Date()
        var bundleIdentifier = ""
        var appName = ""
        self.setProgress(30)
        installedApp.managedObjectContext?.performAndWait {
            expirationDate = installedApp.expirationDate
            bundleIdentifier = installedApp.bundleIdentifier
            appName = installedApp.name
        }

        // P0-4: warnings are per-app, with the app name in the copy. For
        // openSSS itself keep the localized display name ("openSSS") so
        // the copy reads exactly as before.
        if bundleIdentifier == StoreApp.altstoreAppID
        {
            appName = NSLocalizedString("oPenSSAI", comment: "")
        }

        let milestones: [(id: String, timeBeforeExp: TimeInterval, titleFormat: String, bodyFormat: String)] = [
            ("24h", 24 * 60 * 60, "%@ Expiring Soon", "%@ will expire in 24 hours. Open the app and refresh it to prevent it from expiring."),
            ("6h",   6 * 60 * 60, "%@ Expiring Extremely Soon", "%@ will expire in 6 hours! Refresh now to prevent expiration."),
            ("0h",   0,           "%@ Expired", "%@ has expired. Please refresh or reinstall the app.")
        ]

        // Identifiers are per-bundleID so every installed app gets its own
        // warnings (P0-4). Also drop the legacy pre-0714 identifiers, which
        // covered only openSSS and would otherwise double-fire for it.
        let allIdentifiers = milestones.map { "\(AppManager.expirationWarningNotificationID).\(bundleIdentifier).\($0.id)" }
            + milestones.map { "\(AppManager.expirationWarningNotificationID).\($0.id)" }
        self.setProgress(50)
        center.removePendingNotificationRequests(withIdentifiers: allIdentifiers)

        let startProgress = self.progress.completedUnitCount
        let endProgress: Int64 = 95
        #if !os(tvOS)
        let range = endProgress - startProgress
        let count = milestones.count
        
        for (index, milestone) in milestones.enumerated() {
            if range > 0 {
                let percent = startProgress + Int64(Double(index + 1) / Double(count) * Double(range))
                self.setProgress(percent)
            }
            
            let identifier = "\(AppManager.expirationWarningNotificationID).\(bundleIdentifier).\(milestone.id)"
            let targetDate = expirationDate.addingTimeInterval(-milestone.timeBeforeExp)
            let triggerInterval = targetDate.timeIntervalSince(now)

            // Skip milestones that are already in the past
            guard triggerInterval > 0 else { continue }

            let content = UNMutableNotificationContent()
            content.title = String(format: NSLocalizedString(milestone.titleFormat, comment: ""), appName)
            content.body = String(format: NSLocalizedString(milestone.bodyFormat, comment: ""), appName)
            content.sound = .default

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: triggerInterval, repeats: false)
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

            do {
                try await center.add(request)
            } catch {
                debugLog("[ScheduleExpirationWarningNotificationOperation] Failed to schedule notification '\(identifier)': \(error)")
            }
        }
        #else
        NotificationCenter.default.post(name: NSNotification.Name("TVTopShelfItemsDidChangeNotification"), object: nil)
        #endif
        self.setProgress(100)
        return true
    }

    /// Removes all pending expiration warnings for one app (e.g. when the
    /// app is uninstalled), so a removed app never warns about expiring.
    static func removePendingWarnings(forBundleIdentifier bundleIdentifier: String)
    {
        let identifiers = ["24h", "6h", "0h"].map { "\(AppManager.expirationWarningNotificationID).\(bundleIdentifier).\($0)" }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
    }
}
