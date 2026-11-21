//
//  BackgroundRefreshTaskScheduler.swift
//  AltStore
//
//  Created by oPenSSAI Contributors on 11/21/26.
//  Copyright © 2026 AltStore. All rights reserved.
//

#if !os(tvOS)

import BackgroundTasks
import UIKit

/// Second background-refresh trigger source alongside Background Fetch
/// (P0-2). Registers a BGAppRefreshTask and a BGProcessingTask and reuses
/// the existing AppDelegate background-refresh pipeline when iOS launches
/// them. BG tasks are one-shot, so every launch re-submits the next cycle.
enum BackgroundRefreshTaskScheduler
{
    /// Identifiers are derived from the runtime bundle ID so they always
    /// match the BGTaskSchedulerPermittedIdentifiers entries in Info.plist
    /// (which use $(PRODUCT_BUNDLE_IDENTIFIER)).
    static var appRefreshTaskIdentifier: String
    {
        (Bundle.main.bundleIdentifier ?? Bundle.Info.appbundleIdentifier) + ".refresh"
    }

    static var processingTaskIdentifier: String
    {
        (Bundle.main.bundleIdentifier ?? Bundle.Info.appbundleIdentifier) + ".refresh-processing"
    }

    /// Must be called during launch, before the app finishes launching.
    static func register()
    {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: self.appRefreshTaskIdentifier, using: nil) { task in
            guard let task = task as? BGAppRefreshTask else { return }
            self.handleAppRefreshTask(task)
        }

        BGTaskScheduler.shared.register(forTaskWithIdentifier: self.processingTaskIdentifier, using: nil) { task in
            guard let task = task as? BGProcessingTask else { return }
            self.handleProcessingTask(task)
        }

        debugLog("[BackgroundRefreshTaskScheduler] Registered BG tasks.")
    }

    /// Submit both tasks for the next cycle. Called at launch and every
    /// time a task fires, so a missed cycle is re-armed.
    static func schedule()
    {
        guard UserDefaults.standard.isBackgroundRefreshEnabled else { return }

        // App refresh: lightweight, opportunistic.
        let refreshRequest = BGAppRefreshTaskRequest(identifier: self.appRefreshTaskIdentifier)
        refreshRequest.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60) // 1 hour
        do
        {
            try BGTaskScheduler.shared.submit(refreshRequest)
        }
        catch
        {
            debugLog("[BackgroundRefreshTaskScheduler] Failed to submit app refresh task: \(error)")
        }

        // Processing: longer runtime for the actual re-signing work.
        let processingRequest = BGProcessingTaskRequest(identifier: self.processingTaskIdentifier)
        processingRequest.requiresNetworkConnectivity = true
        processingRequest.requiresExternalPower = false
        processingRequest.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60) // 1 hour
        do
        {
            try BGTaskScheduler.shared.submit(processingRequest)
        }
        catch
        {
            debugLog("[BackgroundRefreshTaskScheduler] Failed to submit processing task: \(error)")
        }
    }

    private static func handleAppRefreshTask(_ task: BGAppRefreshTask)
    {
        // Re-arm immediately: a submitted task fires at most once.
        self.schedule()
        self.runRefresh(for: task)
    }

    private static func handleProcessingTask(_ task: BGProcessingTask)
    {
        self.schedule()
        self.runRefresh(for: task)
    }

    private static func runRefresh(for task: BGTask)
    {
        let completion = BGTaskCompletion(task: task)

        task.expirationHandler = {
            debugLog("[BackgroundRefreshTaskScheduler] BG task expired before refresh finished.")
            completion.complete(success: false)
        }

        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else
        {
            completion.complete(success: false)
            return
        }

        // Reuse the Background Fetch pipeline end to end (extended
        // background task + source fetch + app refresh).
        appDelegate.runBackgroundRefresh { result in
            // .failed tells iOS the run was unproductive; anything else
            // counts as a completed run.
            completion.complete(success: result != .failed)
        }
    }
}

/// Exactly-once completion for a BGTask: the refresh callback and the
/// expiration handler can race, and setTaskCompleted must be called once.
private final class BGTaskCompletion: @unchecked Sendable
{
    private let lock = NSLock()
    private let task: BGTask
    private var didComplete = false

    init(task: BGTask)
    {
        self.task = task
    }

    func complete(success: Bool)
    {
        self.lock.lock()
        defer { self.lock.unlock() }

        guard !self.didComplete else { return }
        self.didComplete = true
        self.task.setTaskCompleted(success: success)
    }
}

#endif
