//
//  AppDelegate.swift
//  AltStore
//
//  Created by Riley Testut on 5/9/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

@preconcurrency import UIKit
import UserNotifications
import AVFoundation
import Intents
import SideSign
import CoreData
import Nuke

extension AppDelegate
{
    nonisolated static let openPatreonSettingsDeepLinkNotification = Notification.Name(Bundle.Info.appbundleIdentifier + ".OpenPatreonSettingsDeepLinkNotification")
    nonisolated static let importAppDeepLinkNotification = Notification.Name(Bundle.Info.appbundleIdentifier + ".ImportAppDeepLinkNotification")
    nonisolated static let addSourceDeepLinkNotification = Notification.Name(Bundle.Info.appbundleIdentifier + ".AddSourceDeepLinkNotification")
    
    nonisolated static let appBackupDidFinish = Notification.Name(Bundle.Info.appbundleIdentifier + ".AppBackupDidFinish")
    
    nonisolated static let importAppDeepLinkURLKey = "fileURL"
    nonisolated static let appBackupResultKey = "result"
    nonisolated static let addSourceDeepLinkURLKey = "sourceURL"
    
    static func dumpSideBackupLogsIfNeeded() async {
        await Task.detached {
            for appGroup in Bundle.main.appGroups {
                guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) else { continue }
                let logFileURL = containerURL.appendingPathComponent("Logs", isDirectory: true).appendingPathComponent("SideBackup.log")
                debugLog("[AppDelegate] Checking for SideBackup log in group '\(appGroup)' at: \(logFileURL.path)")
                if FileManager.default.fileExists(atPath: logFileURL.path) {
                    debugLog("[AppDelegate] Found SideBackup log file in group '\(appGroup)'.")
                    do {
                        let logContents = try String(contentsOf: logFileURL, encoding: .utf8)
                        if logContents.isEmpty {
                            debugLog("[AppDelegate] SideBackup log file in group '\(appGroup)' is empty.")
                        } else {
                            debugLog("""
                            [SideBackup Logs (\(appGroup))]
                            
                            \(logContents.trimmingCharacters(in: .whitespacesAndNewlines))
                            
                            [SideBackup Logs End]
                            """)
                        }
                        try FileManager.default.removeItem(at: logFileURL)
                    } catch {
                        debugLog("[AppDelegate] Failed to read or delete SideBackup log file in group '\(appGroup)': \(error)")
                    }
                }
            }

        }.value
    }
}

@UIApplicationMain
final class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?
    
    #if !os(tvOS)
    private let intentHandler = IntentHandler()
    private let viewAppIntentHandler = ViewAppIntentHandler()
    #endif
    
    public let consoleLog = ConsoleLog()

    // Holds an imported .ipa URL when the app isn't active yet (cold launch),
    // so the import notification can be posted once the app becomes active.
    private var pendingImportIPAURL: URL?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool
    {
        // navigation bar buttons spacing is too much (so hack it to use minimal spacing)
        // this is swift-5 specific behavior and might change
        // https://stackoverflow.com/a/64988363/11971304
        //
        // Warning: this affects all screens through out the app, and basically overrides storyboard
        let stackViewAppearance = UIStackView.appearance(whenContainedInInstancesOf: [UINavigationBar.self])
        stackViewAppearance.spacing = -8        // adjust as needed
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .medium
        let dateString = dateFormatter.string(from: Date())
        let versionString = Bundle.Info.activeBundleVersion

        func centerInBanner(_ text: String, width: Int = 49) -> String {
            let padding = max(0, width - text.count)
            let left = String(repeating: " ", count: padding / 2)
            let right = String(repeating: " ", count: padding - left.count)
            return "|\(left)\(text)\(right)|"
        }

        // register console logging and start capturing
        let suffixFormat: SuffixFormat = UserDefaults.standard.isRotateLogsOnStartupEnabled ? .timestamp : .none
        consoleLog.updateConfiguration(baseName: "console", suffixFormat: suffixFormat, policy: .subsequent)
        consoleLog.startCapturing()

        // register crash handler
        setupCrashHandler()
        
        UNUserNotificationCenter.current().delegate = self
        
        debugLog("===================================================")
        debugLog("|               App is Starting up                |")
        debugLog("===================================================")
        debugLog("| Console Logger started capturing output streams |")
        debugLog("===================================================")
        debugLog(centerInBanner(versionString))
        debugLog("===================================================")
        debugLog(centerInBanner(dateString))
        debugLog("===================================================")
        debugLog("\n")

        
        #if DEBUG
        UserDefaults.enableGlobalLogging()
//        UserDefaults.dumpAllSettingsOnBoot()
        #endif
        
        // Register default settings before doing anything else.
        UserDefaults.registerDefaults()
        BackgroundServiceManager.ensureBackgroundServicesStarted()
        syncMinimuxerBackendFromUserDefaults()

        SideStoreLogging.setLogging(UserDefaults.standard.isSideStoreVerboseLoggingEnabled)
        AltSign.setLogging(UserDefaults.standard.isAltSignVerboseLoggingEnabled)
        minimuxerSetLogging(UserDefaults.standard.isMinimuxerVerboseLoggingEnabled)
        SideSignConfigManager.shared.applyConfigToDeveloperPortal()

        // Override point for customization after application launch.
//        UserDefaults.standard.setValue(true, forKey: "com.apple.CoreData.MigrationDebug")
//        UserDefaults.standard.setValue(true, forKey: "com.apple.CoreData.SQLDebug")
        

        // Trigger daily boot sync for Anisette servers if needed
        if !UserDefaults.standard.useOnDeviceAnisette{
            Task.detached {
                await AnisetteServersManager.shared.performDailySyncIfNeeded()
            }
        }

        // Recreate Database if requested
        // NOTE: Userdefaults are local to the SideStore.app sandbox and are not shared
        if UserDefaults.standard.recreateDatabaseOnNextStart{
            // reset the state
            UserDefaults.standard.recreateDatabaseOnNextStart = false
            
            // re-create database
            DatabaseManager.recreateDatabase()
        }
        
        
        // The boot sequence loads the pairing file and starts minimuxer. It
        // runs detached, but AppBootManager keeps the task so launch and
        // operations can await it before first use instead of racing it.
        AppBootManager.shared.startBootSequence()
        
        
        let isFirstLaunch = (UserDefaults.standard.firstLaunch == nil)
        if isFirstLaunch
        {
            UserDefaults.standard.firstLaunch = Date()
        }
        
        Task.detached(priority: .userInitiated) {
            do
            {
                await MaintenanceManager.shared.performDatabaseMigrationIfNeeded()
                
                debugLog("Starting DatabaseManager...")
                try await DatabaseManager.shared.start()
                debugLog("Started DatabaseManager.")
                
                debugLog("Reconciling any staged drafts started...")
                await Self.reconcileSelfReinstallationIfNeeded()
                debugLog("Reconcile any staged drafts completed.")
                
                await WidgetDataManager.publishCurrentInstalledAppsIfNeeded(in: DatabaseManager.shared.viewContext)
                
                if isFirstLaunch && !AuthManager.shared.isAuthenticated
                {
                    // Truly fresh install: no Keychain credentials
                    // survived, so clearing any stale sign-in state is
                    // harmless. When credentials DID survive a reinstall
                    // (Keychain outlives the app sandbox), keep them —
                    // wiping them here used to log the user out right
                    // after every reinstall.
                    await AuthManager.shared.signOut()
                }
                else if isFirstLaunch
                {
                    debugLog("[AppDelegate] First launch with surviving Keychain credentials; keeping sign-in state.")
                }

                // Perform one-time maintenance tasks after database is started
                await MaintenanceManager.shared.performMaintenanceIfNeeded()
            }
            catch
            {
                debugLog("Failed to start DatabaseManager. Error: \(error)")
            }
        }
        
        self.setTintColor()
        self.prepareImageCache()

        SecureValueTransformer.register()        
        
        #if DEBUG && targetEnvironment(simulator)
        UserDefaults.standard.isDebugModeEnabled = true
        #endif
        
        self.prepareForBackgroundFetch()
        
        return true
    }
    
    func applicationDidEnterBackground(_ application: UIApplication)
    {
        BackgroundServiceManager.ensureBackgroundServicesStarted()
        // Make sure to update SceneDelegate.sceneDidEnterBackground() as well.
        guard let oneMonthAgo = Calendar.current.date(byAdding: .month, value: -1, to: Date()) else { return }
        
        let midnightOneMonthAgo = Calendar.current.startOfDay(for: oneMonthAgo)
        Task.detached(priority: .background) {
            do
            {
                try await DatabaseManager.shared.purgeLoggedErrors(before: midnightOneMonthAgo)
            }
            catch
            {
                debugLog("[oPenSSAI] Failed to purge logged errors before \(midnightOneMonthAgo). \(error)")
            }
        }
             
    }

    func applicationWillEnterForeground(_ application: UIApplication)
    {
        BackgroundServiceManager.ensureBackgroundServicesStarted()
        Task.detached {
            await AppManager.shared.reconcileInstalledApps()
        }

        // P0-3: retry any background refresh that failed earlier, now that
        // the user is back in the app.
        self.retryFailedBackgroundRefreshIfNeeded()
    }

    func applicationDidBecomeActive(_ application: UIApplication)
    {
        // Flush any .ipa import that arrived before the app was active (cold launch).
        guard let url = self.pendingImportIPAURL else { return }
        self.pendingImportIPAURL = nil
        NotificationCenter.default.post(name: AppDelegate.importAppDeepLinkNotification, object: nil, userInfo: [AppDelegate.importAppDeepLinkURLKey: url])
    }

    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any]) -> Bool
    {
        return self.open(url)
    }
    
    #if !os(tvOS)
    func application(_ application: UIApplication, handlerFor intent: INIntent) -> Any?
    {
        switch intent
        {
        case is RefreshAllIntent: return self.intentHandler
        case is ViewAppIntent: return self.viewAppIntentHandler
        default: return nil
        }
    }
    #endif
    
    func applicationWillTerminate(_ application: UIApplication) {
        // Stop console logging and clean up resources
        debugLog("\n ")
        debugLog("===================================================")
        debugLog("| Console Logger stopped capturing output streams |")
        debugLog("===================================================")
        debugLog("|           App is being terminated               |")
        debugLog("===================================================")
        consoleLog.stopCapturing()
    }
}

extension AppDelegate
{
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration
    {
        // Called when a new scene session is being created.
        // Use this method to select a configuration to create the new scene with.
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }
    
    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>)
    {
        // Called when the user discards a scene session.
        // If any sessions were discarded while the application was not running, this will be called shortly after application:didFinishLaunchingWithOptions.
        // Use this method to release any resources that were specific to the discarded scenes, as they will not return.
    }
}

private extension AppDelegate
{
    func setTintColor()
    {
        self.window?.tintColor = .altPrimary
    }
    
    func prepareImageCache()
    {
        // Avoid caching responses twice.
        DataLoader.sharedUrlCache.diskCapacity = 0
        
        let pipeline = ImagePipeline { configuration in
            do
            {
                let dataCache = try DataCache(name: "io.sidestore.Nuke")
                dataCache.sizeLimit = 512 * 1024 * 1024 // 512MB
                
                configuration.dataCache = dataCache
            }
            catch
            {
                debugLog("[AppDelegate] Failed to create image disk cache. Falling back to URL cache. \(error.localizedDescription)")
            }
        }
        
        ImagePipeline.shared = pipeline
        
        if let dataCache = ImagePipeline.shared.configuration.dataCache as? DataCache
        {
            debugLog("[AppDelegate] Current image cache size: \(dataCache.totalSize.formatted(.byteCount(style: .file)))")
        }
    }
    
    func open(_ url: URL) -> Bool
    {
        if url.isFileURL
        {
            guard url.pathExtension.lowercased() == "ipa" else { return false }

            // Copy the shared .ipa out of its security-scoped location into a
            // temporary directory we own, so it stays readable while signing.
            let didStartAccessing = url.startAccessingSecurityScopedResource()
            defer {
                if didStartAccessing { url.stopAccessingSecurityScopedResource() }
            }

            let temporaryDirectory = FileManager.default.uniqueTemporaryURL()
            do {
                try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true, attributes: nil)
            } catch {
                debugLog("[AppDelegate] Failed to create temp directory for imported IPA: \(error)")
                return false
            }

            let ipaURL = temporaryDirectory.appendingPathComponent(url.lastPathComponent)

            do {
                try FileManager.default.copyItem(at: url, to: ipaURL)
            } catch {
                debugLog("[AppDelegate] Failed to copy imported IPA: \(error)")
                return false
            }

            if UIApplication.shared.applicationState == .active {
                NotificationCenter.default.post(name: AppDelegate.importAppDeepLinkNotification, object: nil, userInfo: [AppDelegate.importAppDeepLinkURLKey: ipaURL])
            } else {
                // Defer until the app is active (cold launch) — see applicationDidBecomeActive.
                self.pendingImportIPAURL = ipaURL
            }

            return true
        }
        else
        {
            return URLHandler.shared.handle(url)
        }
    }
}

extension AppDelegate
{
    private func prepareForBackgroundFetch()
    {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { (success, error) in
            // no-op
        }
        
        #if !os(tvOS)
        // P0-2: BGTaskScheduler as a second background-refresh trigger
        // source. Must register before the app finishes launching.
        BackgroundRefreshTaskScheduler.register()
        BackgroundRefreshTaskScheduler.schedule()
        #endif

        #if DEBUG && targetEnvironment(simulator)
        UIApplication.shared.registerForRemoteNotifications()
        #endif
    }
    
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data)
    {
        let tokenParts = deviceToken.map { data -> String in
            return String(format: "%02.2hhx", data)
        }
        
        let token = tokenParts.joined()
        #if DEBUG
        debugLog("[AppDelegate] Apple Push Notification(APN) Token: \(token)")
        #endif
    }
    
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable : Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void)
    {
        self.application(application, performFetchWithCompletionHandler: completionHandler)
    }
    
    func application(_ application: UIApplication, performFetchWithCompletionHandler backgroundFetchCompletionHandler: @escaping (UIBackgroundFetchResult) -> Void)
    {
        #if !os(tvOS)
        if UserDefaults.standard.isBackgroundRefreshEnabled && !UserDefaults.standard.presentedLaunchReminderNotification
        {
            let threeHours: TimeInterval = 3 * 60 * 60
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: threeHours, repeats: false)
            
            let content = UNMutableNotificationContent()
            content.title = NSLocalizedString("App Refresh Tip", comment: "")
            content.body = NSLocalizedString("The more you open SideStore, the more chances it's given to refresh apps in the background.", comment: "")
            
            let request = UNNotificationRequest(identifier: "background-refresh-reminder5", content: content, trigger: trigger)
            UNUserNotificationCenter.current().add(request)
            
            UserDefaults.standard.presentedLaunchReminderNotification = true
        }
        #endif
        
        self.runBackgroundRefresh(completion: backgroundFetchCompletionHandler)
    }

    /// Shared background-refresh core for Background Fetch and
    /// BGTaskScheduler (P0-2): extended background task + database start +
    /// source fetch + app refresh. Calls completion exactly once, with the
    /// combined result from performBackgroundFetch.
    func runBackgroundRefresh(completion: @escaping (UIBackgroundFetchResult) -> Void)
    {
        BackgroundServiceManager.ensureBackgroundServicesStarted()

        BackgroundTaskManager.shared.performExtendedBackgroundTask { (taskResult, taskCompletionHandler) in
            if let error = taskResult.error
            {
                debugLog("Error starting extended background task. Aborting. \(error)")
                completion(.failed)
                taskCompletionHandler()
                return
            }
            
            Task.detached(priority: .userInitiated) {
                do
                {
                    try await DatabaseManager.shared.start()
                    self.performBackgroundFetch { (backgroundFetchResult) in
                        completion(backgroundFetchResult)
                    } refreshAppsCompletionHandler: { (refreshAppsResult) in
                        taskCompletionHandler()
                    }
                }
                catch
                {
                    completion(.failed)
                    taskCompletionHandler()
                }
            }
        }
    }
    
    func performBackgroundFetch(backgroundFetchCompletionHandler: @escaping (UIBackgroundFetchResult) -> Void,
                                refreshAppsCompletionHandler: @escaping (Result<[String: Result<InstalledApp, Error>], Error>) -> Void)
    {
        // Snapshot the apps this run will attempt, so a pipeline-level
        // failure can still remember which apps need a foreground retry (P0-3).
        let installedApps: [InstalledApp]
        let attemptedBundleIDs: [String]
        if UserDefaults.standard.isBackgroundRefreshEnabled
        {
            let context = DatabaseManager.shared.persistentContainer.newBackgroundContext()
            installedApps = InstalledApp.fetchAppsForBackgroundRefresh(in: context)
            var ids: [String] = []
            context.performAndWait { ids = installedApps.map(\.bundleIdentifier) }
            attemptedBundleIDs = ids
        }
        else
        {
            installedApps = []
            attemptedBundleIDs = []
        }

        // P0-2: the fetch result must reflect the refresh outcome. Source
        // fetching and app refreshing run in parallel; the completion is
        // reported once both finish. A source-fetch failure on its own
        // must never report .failed, or iOS throttles future fetches.
        let coordinator = BackgroundFetchCoordinator { sourcesResult, refreshResult in
            // P0-3: remember failed apps so the next foreground launch can
            // retry them, and remind the user on a backoff schedule.
            Self.recordBackgroundRefreshOutcome(refreshResult, attemptedBundleIDs: attemptedBundleIDs)

            let fetchResult = Self.combinedFetchResult(sourcesResult: sourcesResult, refreshResult: refreshResult)
            backgroundFetchCompletionHandler(fetchResult)
            refreshAppsCompletionHandler(refreshResult)
        }

        self.fetchSources { (result) in
            coordinator.finishSources(result)
        }

        guard UserDefaults.standard.isBackgroundRefreshEnabled else
        {
            coordinator.finishRefresh(.success([:]))
            return
        }

        do
        {
            _ = try AppManager.shared.backgroundRefresh(installedApps) { (result) in
                coordinator.finishRefresh(result)
            }
        }
        catch
        {
            // backgroundRefresh can throw synchronously (operation init);
            // previously that swallowed the refresh completion entirely.
            coordinator.finishRefresh(.failure(error))
        }
    }

    /// Combines the source-fetch and app-refresh outcomes into one
    /// UIBackgroundFetchResult. The refresh outcome decides; the source
    /// fetch can only upgrade an otherwise idle run to .newData, never
    /// downgrade it to .failed.
    private static func combinedFetchResult(sourcesResult: Result<Set<Source>, Error>?,
                                            refreshResult: Result<[String: Result<InstalledApp, Error>], Error>) -> UIBackgroundFetchResult
    {
        switch refreshResult
        {
        case .failure:
            // The refresh itself failed: the run was unproductive.
            return .failed

        case .success(let results):
            if results.isEmpty
            {
                // Nothing needed refreshing; sources decide.
                if case .success = sourcesResult
                {
                    return .newData
                }
                return .noData
            }

            let succeededCount = results.values.filter {
                if case .success = $0 { return true }
                return false
            }.count

            if succeededCount == results.count
            {
                return .newData
            }
            else if succeededCount > 0
            {
                // Partial success: work was done, don't punish scheduling.
                return .newData
            }
            else
            {
                // Every app failed.
                return .failed
            }
        }
    }
}

extension AppDelegate
{
    /// Local-notification identifier for the P0-3 retry reminder. Fixed so
    /// a newer failure replaces any pending reminder instead of stacking.
    nonisolated static let refreshRetryReminderNotificationID = "sidestore-refresh-retry-reminder"

    /// Records the outcome of a background refresh run (P0-3). Failed apps
    /// are remembered so the next foreground launch retries them, and a
    /// local notification reminds the user to open the app on a backoff
    /// schedule. A clean run clears any pending retry.
    private static func recordBackgroundRefreshOutcome(_ result: Result<[String: Result<InstalledApp, Error>], Error>,
                                                attemptedBundleIDs: [String])
    {
        switch result
        {
        case .success(let results):
            let failedBundleIDs = results.compactMap { (bundleID, result) -> String? in
                if case .failure = result { return bundleID }
                return nil
            }

            if failedBundleIDs.isEmpty
            {
                Self.clearPendingRefreshRetry()
            }
            else
            {
                Self.noteFailedRefresh(bundleIDs: failedBundleIDs)
            }
            
        case .failure:
            // Whole pipeline failed before per-app results existed: retry
            // everything this run attempted. Nothing attempted means there
            // was nothing to refresh (e.g. .noInstalledApps), not a retry
            // candidate.
            guard !attemptedBundleIDs.isEmpty else
            {
                Self.clearPendingRefreshRetry()
                return
            }
            Self.noteFailedRefresh(bundleIDs: attemptedBundleIDs)
        }
    }

    /// Remembers failed apps and schedules an "open the app to retry"
    /// reminder on exponential backoff: 1h after the 1st failure, 2h after
    /// the 2nd, 4h, 8h, ... capped at 24h.
    private static func noteFailedRefresh(bundleIDs: [String])
    {
        guard !bundleIDs.isEmpty else { return }

        let defaults = UserDefaults.standard
        defaults.pendingFailedRefreshBundleIDs = bundleIDs

        let attemptCount = defaults.failedRefreshAttemptCount + 1
        defaults.failedRefreshAttemptCount = attemptCount
        
        let delayHours = min(pow(2.0, Double(attemptCount - 1)), 24.0)
        let delay = delayHours * 60 * 60

        let content = UNMutableNotificationContent()
        content.title = NSLocalizedString("Failed to Refresh Apps", comment: "")
        content.body = String(format: NSLocalizedString("%lld apps failed to refresh in the background. Open openSSS to retry.", comment: ""), bundleIDs.count)
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
        let request = UNNotificationRequest(identifier: Self.refreshRetryReminderNotificationID, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)

        debugLog("[AppDelegate] Scheduled refresh-retry reminder in \(delayHours)h for \(bundleIDs.count) app(s) (attempt \(attemptCount)).")
    }

    private static func clearPendingRefreshRetry()
    {
        let defaults = UserDefaults.standard
        defaults.pendingFailedRefreshBundleIDs = nil
        defaults.failedRefreshAttemptCount = 0
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.refreshRetryReminderNotificationID])
    }

    /// P0-3: if a background refresh failed earlier, retry the failed apps
    /// as soon as the user returns to the foreground instead of waiting for
    /// the next background window. Runs the same foreground refresh path as
    /// Renew All, so progress shows in the shell UI.
    private func retryFailedBackgroundRefreshIfNeeded()
    {
        guard UserDefaults.standard.isBackgroundRefreshEnabled else { return }
        guard let failedBundleIDs = UserDefaults.standard.pendingFailedRefreshBundleIDs,
              !failedBundleIDs.isEmpty else { return }
        guard !AppManager.shared.isActivelyManagingAnyApp else
        {
            debugLog("[AppDelegate] Skipping foreground refresh retry: another operation is in progress.")
            return
        }

        // The user is here now and the retry is running: cancel the reminder.
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.refreshRetryReminderNotificationID])

        Task { @MainActor in
            do
            {
                try await DatabaseManager.shared.start()
            }
            catch
            {
                debugLog("[AppDelegate] Failed to start DatabaseManager for foreground refresh retry. \(error)")
                return
            }

            let context = DatabaseManager.shared.viewContext
            let predicate = NSPredicate(format: "%K IN %@", #keyPath(InstalledApp.bundleIdentifier), failedBundleIDs)
            let apps = InstalledApp.all(satisfying: predicate, in: context).filter { $0.isActive }

            guard !apps.isEmpty else
            {
                // Apps are gone (uninstalled): nothing left to retry.
                UserDefaults.standard.pendingFailedRefreshBundleIDs = nil
                UserDefaults.standard.failedRefreshAttemptCount = 0
                return
            }

            debugLog("[AppDelegate] Retrying failed background refresh for \(apps.count) app(s) in foreground.")
            let group = AppManager.shared.refresh(apps, presentingViewController: nil)
            group.completionHandler = { results in
                DispatchQueue.main.async {
                    // Re-record: still-failing apps stay pending (backoff
                    // grows); a clean run clears the pending retry.
                    let failed = results.compactMap { (bundleID, result) -> String? in
                        if case .failure = result { return bundleID }
                        return nil
                    }
                    if failed.isEmpty
                    {
                        Self.clearPendingRefreshRetry()
                    }
                    else
                    {
                        Self.noteFailedRefresh(bundleIDs: failed)
                    }
                }
            }
        }
    }
}

/// Coordinates the two parallel branches of a background fetch (source
/// fetching + app refreshing) and reports a single combined result once
/// both finish. Thread-safe: either branch may finish on any queue, and
/// the finish handler fires exactly once.
private final class BackgroundFetchCoordinator: @unchecked Sendable
{
    typealias SourcesResult = Result<Set<Source>, Error>
    typealias RefreshResult = Result<[String: Result<InstalledApp, Error>], Error>

    private let lock = NSLock()
    private var sourcesResult: SourcesResult?
    private var refreshResult: RefreshResult?
    private var didFinish = false
    private let finishHandler: (SourcesResult?, RefreshResult) -> Void

    init(finishHandler: @escaping (SourcesResult?, RefreshResult) -> Void)
    {
        self.finishHandler = finishHandler
    }

    func finishSources(_ result: SourcesResult)
    {
        self.finish(sources: result, refresh: nil)
    }

    func finishRefresh(_ result: RefreshResult)
    {
        self.finish(sources: nil, refresh: result)
    }

    private func finish(sources: SourcesResult?, refresh: RefreshResult?)
    {
        var handlerToCall: ((SourcesResult?, RefreshResult) -> Void)?
        var pendingSources: SourcesResult?
        var pendingRefresh: RefreshResult?
        
        self.lock.lock()
        if let sources
        {
            self.sourcesResult = sources
        }
        if let refresh
        {
            self.refreshResult = refresh
        }
        if !self.didFinish, let refreshResult = self.refreshResult, self.sourcesResult != nil
        {
            self.didFinish = true
            handlerToCall = self.finishHandler
            pendingSources = self.sourcesResult
            pendingRefresh = refreshResult
        }
        self.lock.unlock()

        if let handlerToCall, let pendingRefresh
        {
            handlerToCall(pendingSources, pendingRefresh)
        }
    }
}

private extension AppDelegate
{
    func fetchSources(completionHandler: @escaping (Result<Set<Source>, Error>) -> Void)
    {
        AppManager.shared.fetchSources() { (result) in
            do
            {
                let (sources, context) = try result.get()
                
                let previousUpdatesFetchRequest = InstalledApp.supportedUpdatesFetchRequest() as! NSFetchRequest<NSFetchRequestResult>
                previousUpdatesFetchRequest.includesPendingChanges = false
                previousUpdatesFetchRequest.resultType = .dictionaryResultType
                previousUpdatesFetchRequest.propertiesToFetch = [#keyPath(InstalledApp.bundleIdentifier),
                                                                 #keyPath(InstalledApp.storeApp.latestSupportedVersion.version),
                                                                 #keyPath(InstalledApp.storeApp.latestSupportedVersion._buildVersion)]
                
                let previousNewsItemsFetchRequest = NewsItem.fetchRequest() as NSFetchRequest<NSFetchRequestResult>
                previousNewsItemsFetchRequest.includesPendingChanges = false
                previousNewsItemsFetchRequest.resultType = .dictionaryResultType
                previousNewsItemsFetchRequest.propertiesToFetch = [#keyPath(NewsItem.identifier)]
                
                let previousUpdates = try context.fetch(previousUpdatesFetchRequest) as! [[String: String]]
                let previousNewsItems = try context.fetch(previousNewsItemsFetchRequest) as! [[String: String]]
                
                try context.save()
                
                
                
                let updatesFetchRequest = InstalledApp.supportedUpdatesFetchRequest()
                let newsItemsFetchRequest = NewsItem.fetchRequest() as NSFetchRequest<NewsItem>
                
                let updates = try context.fetch(updatesFetchRequest)
                let newsItems = try context.fetch(newsItemsFetchRequest)
                
                #if !os(tvOS)
                for update in updates
                {
                    guard let storeApp = update.storeApp, let latestSupportedVersion = storeApp.latestSupportedVersion, latestSupportedVersion.isSupported else { continue }
                    
                    if let previousUpdate = previousUpdates.first(where: { $0[#keyPath(InstalledApp.bundleIdentifier)] == update.bundleIdentifier })
                    {
                        // An update for this app was already available, so check whether the version or build version is different.
                        guard let previousVersion = previousUpdate[#keyPath(InstalledApp.storeApp.latestSupportedVersion.version)] else { continue }
                        
                        // previousUpdate might not contain buildVersion, but if it does then map empty string to nil to match AppVersion.
                        let previousBuildVersion = previousUpdate[#keyPath(InstalledApp.storeApp.latestSupportedVersion._buildVersion)].map { $0.isEmpty ? nil : "" }
                        
                        // Only show notification if previous latestSupportedVersion does not _exactly_ match current latestSupportedVersion.
                        guard previousVersion != latestSupportedVersion.version || previousBuildVersion != latestSupportedVersion.buildVersion  else { continue }
                    }
                    
                    let content = UNMutableNotificationContent()
                    content.title = NSLocalizedString("New Update Available", comment: "")
                    content.body = String(format: NSLocalizedString("%@ %@ is now available for download.", comment: ""), update.name, latestSupportedVersion.localizedVersion)
                    content.sound = .default
                    
                    let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
                    UNUserNotificationCenter.current().add(request)
                }
                
                for newsItem in newsItems
                {
                    guard !previousNewsItems.contains(where: { $0[#keyPath(NewsItem.identifier)] == newsItem.identifier }) else { continue }
                    guard !newsItem.isSilent else { continue }
                    
                    let content = UNMutableNotificationContent()
                    
                    if let app = newsItem.storeApp
                    {
                        content.title = String(format: NSLocalizedString("%@ News", comment: ""), app.name)
                    }
                    else
                    {
                        content.title = NSLocalizedString("SideStore News", comment: "")
                    }
                    
                    content.body = newsItem.title
                    content.sound = .default
                    
                    let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
                    UNUserNotificationCenter.current().add(request)
                }
                #else
                DispatchQueue.main.async {
                    if UIApplication.shared.applicationState == .active {
                        if !updates.isEmpty, let window = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.windows.first(where: { $0.isKeyWindow }) }).first {
                            let toastView = ToastView(text: NSLocalizedString("New Update Available", comment: ""), detailText: String(format: NSLocalizedString("%lld update(s) available", comment: ""), updates.count))
                            toastView.show(in: window)
                        }
                    } else {
                        NotificationCenter.default.post(name: NSNotification.Name("TVTopShelfItemsDidChangeNotification"), object: nil)
                    }
                }
                #endif

                DispatchQueue.main.async {
                    UIApplication.shared.applicationIconBadgeNumber = updates.count
                }
                
                completionHandler(.success(sources))
            }
            catch
            {
                debugLog("Error fetching apps: \(error)")
                completionHandler(.failure(error))
            }
        }
    }
}

private extension AppDelegate {
    func setupCrashHandler() {
        NSSetUncaughtExceptionHandler { exception in
            // Clear handler immediately so execution can never recurse under any circumstance
            NSSetUncaughtExceptionHandler(nil)
            
            let stackTrace = exception.callStackSymbols.joined(separator: "\n")
            let message = """
            \n===================================================
            |           UNCAUGHT NSEXCEPTION CRASH            |
            ===================================================
              • Name: \(exception.name.rawValue)
              • Reason: \(exception.reason ?? "Unknown")
            
            Call Stack:
            \(stackTrace)
            ===================================================\n
            """
            
            debugLog(message)
            
            // Write directly to stderr to bypass Swift formatting/logger abstractions
            fputs(message, stderr)
            fflush(stderr)
            
            // Also write to NSLog (Apple System Log)
            NSLog("%@", message)
        }
        
        let fatalSignals = [SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGFPE, SIGTRAP]
        for sig in fatalSignals {
            signal(sig) { signalNumber in
                signal(signalNumber, SIG_DFL)
                
                let signalName: String
                switch signalNumber {
                case SIGABRT: signalName = "SIGABRT (Abort/Assertion Failure)"
                case SIGSEGV: signalName = "SIGSEGV (Segmentation Fault)"
                case SIGBUS: signalName = "SIGBUS (Bus Error)"
                case SIGILL: signalName = "SIGILL (Illegal Instruction)"
                case SIGFPE: signalName = "SIGFPE (Floating Point Exception)"
                case SIGTRAP: signalName = "SIGTRAP (Trace Trap)"
                default: signalName = "Signal \(signalNumber)"
                }
                
                let stackTrace = Thread.callStackSymbols.joined(separator: "\n")
                let message = """
                \n===================================================
                |             UNCAUGHT FATAL SIGNAL               |
                ===================================================
                  • Signal: \(signalName)
                
                Call Stack:
                \(stackTrace)
                ===================================================\n
                """
                
                debugLog(message)
                fputs(message, stderr)
                fflush(stderr)
                NSLog("%@", message)
                
                raise(signalNumber)
            }
        }
    }
    
    static func reconcileSelfReinstallationIfNeeded() {
        guard let appGroup = Bundle.main.altstoreAppGroup,
              let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) else {
            debugLog("[AppDelegate] reconcileSelfReinstallation: Failed to get App Group container.")
            return
        }
        
        let jsonURL = containerURL.appendingPathComponent("StagedSelfReinstall.json")
        guard FileManager.default.fileExists(atPath: jsonURL.path) else {
            debugLog("[AppDelegate] reconcileSelfReinstallation: No staged self-reinstall metadata file found at \(jsonURL.path).")
            return
        }
        
        defer {
            try? FileManager.default.removeItem(at: jsonURL)
        }
        
        guard let jsonData = try? Data(contentsOf: jsonURL),
              let stagedData = (try? JSONSerialization.jsonObject(with: jsonData, options: [])) as? [String: Any] else {
            debugLog("[AppDelegate] reconcileSelfReinstallation: Failed to read StagedSelfReinstall.json.")
            return
        }
        
        let lastBundlePath = stagedData["lastBundlePath"] as? String
        let currBundlePath = Bundle.main.bundlePath
        debugLog("[AppDelegate] reconcileSelfReinstallation: Current BundlePath: '\(currBundlePath)', Last BundlePath: '\(lastBundlePath ?? "nil")'")
        
        if let lastBundlePath, currBundlePath != lastBundlePath {
            debugLog("[AppDelegate] reconcileSelfReinstallation: App reinstallation confirmed (BundlePath changed)! Applying staged updates to SideStore app in database.")
            let context = DatabaseManager.shared.persistentContainer.newBackgroundContext()
            context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
            
            var didSave = false
            context.performAndWait {
                do {
                    if let _ = InstalledApp.deserialize(from: jsonData, format: .json, context: context) {
                        if context.hasChanges {
                            try context.save()
                            didSave = true
                            debugLog("[AppDelegate] reconcileSelfReinstallation: Database successfully updated and saved.")
                        }
                    } else {
                        debugLog("[AppDelegate] reconcileSelfReinstallation: Failed to restore InstalledApp from staged JSON data.")
                    }
                } catch {
                    debugLog("[AppDelegate] reconcileSelfReinstallation: CoreData error during save: \(error)")
                }
            }
            
            if didSave {
                Task {
                    await WidgetDataManager.publishCurrentInstalledApps(in: context)
                }
            }
        } else {
            debugLog("[AppDelegate] reconcileSelfReinstallation: BundlePath matched pre-installation path. Reinstallation was not completed or failed.")
        }
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
