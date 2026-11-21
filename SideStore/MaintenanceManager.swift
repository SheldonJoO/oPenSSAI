//
//  MaintenanceManager.swift
//  SideStore
//
//  Created by Magesh K on 22/08/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import Foundation
import CoreData
import SideSign

public final class MaintenanceManager {
    public static let shared = MaintenanceManager()

    // Increment this counter whenever you want to trigger another maintenance pass in future updates
    public static let currentMaintenanceCounter = 7

    public static let maintenanceCounterFileName = ".maintenance_counter"

    /// Candidate base directories for the maintenance counter file, in
    /// priority order — the same fallback chain as
    /// `PersistentContainer.defaultDirectoryURL()`: App Group →
    /// Application Support → tmp. Sideloaded installs usually have no App
    /// Group container; without the fallback the counter could never
    /// persist, so every cold launch re-ran pass 1 (Keychain.clearAll +
    /// signOut) and logged the user out.
    private static var maintenanceCounterBaseDirectories: [URL] {
        var directories: [URL] = []
        if let sharedDirectory = FileManager.default.altstoreSharedDirectory {
            directories.append(sharedDirectory)
        }
        if let appSupportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            directories.append(appSupportDirectory)
        }
        directories.append(FileManager.default.temporaryDirectory)
        return directories
    }

    /// The counter file URL. Prefers the location where a counter file
    /// already exists, so the counter survives an App Group availability
    /// flip (e.g. re-signing with a different method); otherwise uses the
    /// highest-priority available directory.
    private var maintenanceCounterFileURL: URL {
        for baseDirectory in Self.maintenanceCounterBaseDirectories {
            let url = baseDirectory.appendingPathComponent(Self.maintenanceCounterFileName)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        return Self.maintenanceCounterBaseDirectories[0].appendingPathComponent(Self.maintenanceCounterFileName)
    }

    private var completedCounter: Int {
        get {
            let url = maintenanceCounterFileURL
            guard let str = try? String(contentsOf: url, encoding: .utf8),
                  let val = Int(str.trimmingCharacters(in: .whitespacesAndNewlines)) else { return 0 }
            return val
        }
        set {
            let url = maintenanceCounterFileURL
            do {
                try "\(newValue)".write(to: url, atomically: true, encoding: .utf8)
            } catch {
                debugLog("[MaintenanceManager] Failed to write maintenance counter to '\(url.path)': \(error)")
            }
        }
    }

    /// Whether the counter file can actually be persisted. The counter is
    /// the only record of which passes already ran; if it cannot be
    /// written, the destructive passes must not run — otherwise they
    /// would re-run on every launch. Needs proper testing: verify on a
    /// device without an App Group container that the counter lands in
    /// Application Support and survives relaunches.
    private var canPersistCounter: Bool {
        let url = maintenanceCounterFileURL
        let current = completedCounter
        do {
            try "\(current)".write(to: url, atomically: true, encoding: .utf8)
            return (try? String(contentsOf: url, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) == "\(current)"
        } catch {
            debugLog("[MaintenanceManager] Maintenance counter is not writable at '\(url.path)': \(error)")
            return false
        }
    }

    /// Whether the install already holds live sign-in state (Keychain
    /// credentials or an active account/team in the database). When the
    /// counter reads 0 but live state exists, this is an upgraded install
    /// whose counter was lost — not a fresh install — so the destructive
    /// passes must be skipped: re-running them would wipe a working login.
    private func hasLiveSignInState() async -> Bool {
        if AuthManager.shared.isAuthenticated { return true }
        guard DatabaseManager.shared.isStarted else { return false }
        return await DatabaseManager.shared.hasActiveAccountOrTeam()
    }

    private init() {}

    public func performDatabaseMigrationIfNeeded() async {
        // Shares `completedCounter` with performMaintenanceIfNeeded, so
        // the counter fallback above covers this too: once the counter
        // persists, the guard below stops the migration re-running on
        // every launch.
        let current = completedCounter
        guard current < Self.currentMaintenanceCounter else { return }

        for pass in (current + 1)...Self.currentMaintenanceCounter {
            switch pass {
            case 4:
                await migrateDatabaseFiles()
            default:
                break
            }
        }
    }

    public func performMaintenanceIfNeeded() async {
        let current = completedCounter
        guard current < Self.currentMaintenanceCounter else { return }

        // Defense in depth: the destructive passes (1: wipe Keychain +
        // sign out, 2: sign out again, 6: reset anisette/SideSign
        // config to defaults, wiping user-configured client-info
        // overrides that may be load-bearing for sign-in) must never
        // run when we cannot prove they have not run before. That is
        // the case when the counter cannot be persisted, or when the
        // counter reads 0 but the install already holds live sign-in
        // state (an upgrade from a build whose counter never persisted).
        // When in doubt, skip them and log it — never re-run a Keychain
        // wipe or a config reset on a guess.
        let skipDestructivePasses: Bool
        if !canPersistCounter {
            debugLog("[MaintenanceManager] Skipping destructive maintenance passes 1, 2, 6: maintenance counter is not writable.")
            skipDestructivePasses = true
        } else if current == 0 {
            // Note: `await` cannot appear to the right of `&&` (the RHS is
            // an autoclosure), so the async check gets its own branch.
            if await hasLiveSignInState() {
                debugLog("[MaintenanceManager] Skipping destructive maintenance passes 1, 2, 6: counter reads 0 but live sign-in state exists (upgraded install with a lost counter).")
                skipDestructivePasses = true
            } else {
                skipDestructivePasses = false
            }
        } else {
            skipDestructivePasses = false
        }

        for pass in (current + 1)...Self.currentMaintenanceCounter {
            if skipDestructivePasses && (pass == 1 || pass == 2 || pass == 6) {
                debugLog("[MaintenanceManager] Skipping destructive maintenance pass \(pass).")
                continue
            }
            debugLog("[MaintenanceManager] Running maintenance pass \(pass)...")
            switch pass {
            case 1:
                Keychain.shared.clearAll()
                await AuthManager.shared.signOut(keepCertificate: false, keepAnisetteData: false)
            case 2:
                AnisetteDataManager.shared.clearCache()
                await AuthManager.shared.signOut(keepCertificate: true, keepAnisetteData: false)
            case 3:
                UserDefaults.standard.tunnelOverridePeerIp = nil
            case 4:
                await migrateLegacyCachedAppBundles()
            case 5:
                await migrateLegacyCachedSigningCertificates()
            case 6:
                AnisetteConfigManager.shared.resetToDefaults()
                SideSignConfigManager.shared.resetToDefaults()
            case 7:
                await migratePairingFiles()
            default:
                break
            }
        }

        completedCounter = Self.currentMaintenanceCounter
        debugLog("[MaintenanceManager] Maintenance up to counter \(Self.currentMaintenanceCounter) complete.")
    }

}

private extension MaintenanceManager {
    func migrateDatabaseFiles() async {
        let fileManager = FileManager.default
        let dbDir = PersistentContainer.defaultDirectoryURL()

        let extensions = ["", "-wal", "-shm"]
        let legacyName = AppConstants.Database.legacyFileName
        let targetName = AppConstants.Database.fileName

        let legacyTargetURL = dbDir.appendingPathComponent(legacyName)
        let newTargetURL = dbDir.appendingPathComponent(targetName)

        if fileManager.fileExists(atPath: legacyTargetURL.path) && !fileManager.fileExists(atPath: newTargetURL.path) {
            for ext in extensions {
                let src = dbDir.appendingPathComponent("\(legacyName)\(ext)")
                let dst = dbDir.appendingPathComponent("\(targetName)\(ext)")
                if fileManager.fileExists(atPath: src.path) {
                    do {
                        try fileManager.moveItem(at: src, to: dst)
                        debugLog("[MaintenanceManager] Migrated database file '\(src.lastPathComponent)' -> '\(dst.lastPathComponent)'")
                    } catch {
                        debugLog("[MaintenanceManager] Failed to move database file '\(src.lastPathComponent)': \(error)")
                    }
                }
            }
        }
    }

    // added in v0.7.0
    func migrateLegacyCachedAppBundles() async {
        let context = DatabaseManager.shared.viewContext
        await context.perform {
            let fetchRequest: NSFetchRequest<InstalledApp> = InstalledApp.fetchRequest()
            let installedApps = (try? context.fetch(fetchRequest)) ?? []
            let appsByBundleID = Dictionary(installedApps.map { ($0.resignedBundleIdentifier, $0) }, uniquingKeysWith: { first, _ in first })

            var didMutate = false
            let appsDir = InstalledApp.appsDirectoryURL
            guard let subdirectories = try? FileManager.default.contentsOfDirectory(
                at: appsDir,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else {
                return
            }

            for directory in subdirectories {
                guard directory.lastPathComponent != "Payloads" else { continue }
                let legacyAppURL = directory.appendingPathComponent("App.app")
                guard FileManager.default.fileExists(atPath: legacyAppURL.path) else { continue }

                guard let signature = AppBundleFingerprint.compute(for: legacyAppURL) else {
                    debugLog("[MaintenanceManager] Failed to compute fingerprint for legacy app at '\(legacyAppURL.path)'")
                    continue
                }

                let targetFileURL = InstalledApp.payloadURL(forSignature: signature)
                let targetParentDir = targetFileURL.deletingLastPathComponent()

                do {
                    if !FileManager.default.fileExists(atPath: targetFileURL.path) {
                        try FileManager.default.createDirectory(at: targetParentDir, withIntermediateDirectories: true, attributes: nil)
                        try FileManager.default.moveItem(at: legacyAppURL, to: targetFileURL)
                    } else {
                        try FileManager.default.removeItem(at: legacyAppURL)
                    }

                    let bundleID = directory.lastPathComponent
                    if let app = appsByBundleID[bundleID] {
                        app.appBundleFingerprint = signature
                        didMutate = true
                    }
                    debugLog("[MaintenanceManager] Migrated legacy app bundle '\(bundleID)' to payload '\(signature)'.")
                } catch {
                    debugLog("[MaintenanceManager] Failed to move legacy app bundle at '\(legacyAppURL.path)': \(error)")
                }
            }

            if didMutate {
                try? context.save()
            }
        }
    }

    func migrateLegacyCachedSigningCertificates() async {
        let context = DatabaseManager.shared.viewContext
        await context.perform {
            let fetchRequest: NSFetchRequest<InstalledApp> = InstalledApp.fetchRequest()
            guard let installedApps = try? context.fetch(fetchRequest) else { return }
            let fileManager = FileManager.default
            let appsDir = InstalledApp.appsDirectoryURL

            for app in installedApps {
                guard app.bundleIdentifier != app.resignedBundleIdentifier else { continue }

                let legacyCertURL = appsDir.appendingPathComponent(app.bundleIdentifier).appendingPathComponent("signing_certificate.der")
                let targetCertURL = app.signingCertificateURL

                guard fileManager.fileExists(atPath: legacyCertURL.path) else { continue }

                do {
                    if !fileManager.fileExists(atPath: targetCertURL.path) {
                        let targetDir = targetCertURL.deletingLastPathComponent()
                        try fileManager.createDirectory(at: targetDir, withIntermediateDirectories: true, attributes: nil)
                        try fileManager.moveItem(at: legacyCertURL, to: targetCertURL)
                    } else {
                        try fileManager.removeItem(at: legacyCertURL)
                    }
                    debugLog("[MaintenanceManager] Migrated signing cert for '\(app.bundleIdentifier)' -> '\(app.resignedBundleIdentifier)'")
                } catch {
                    debugLog("[MaintenanceManager] Failed to migrate signing cert from '\(legacyCertURL.path)': \(error)")
                }
            }
        }
    }

    func migratePairingFiles() async {
        let fileManager = FileManager.default
        let lockdownURL = fileManager.documentsDirectory.appendingPathComponent(AppConstants.Pairing.lockdownPairingFileName)
        let remoteURL = fileManager.documentsDirectory.appendingPathComponent(AppConstants.Pairing.remotePairingFileName)

        let legacyURL = fileManager.documentsDirectory.appendingPathComponent(AppConstants.Pairing.legacyPairingFileName)
        guard fileManager.fileExists(atPath: legacyURL.path),
              let content = try? String(contentsOf: legacyURL), !content.isEmpty else 
        { 
            return 
        }

        let remoteRP = try? PairingFileManager.shared.parse(content: content, preferred: .rppairing)
        let lockdown = try? PairingFileManager.shared.parse(content: content, preferred: .lockdown)
        if remoteRP != nil && !fileManager.fileExists(atPath: remoteURL.path) {
            try? content.write(to: remoteURL, atomically: true, encoding: .utf8)
            debugLog("[MaintenanceManager] Migrated remote pairing file to '\(remoteURL.path)'.")
        }
        if lockdown != nil && !fileManager.fileExists(atPath: lockdownURL.path) {
            try? content.write(to: lockdownURL, atomically: true, encoding: .utf8)
            debugLog("[MaintenanceManager] Migrated lockdown pairing file to '\(lockdownURL.path)'.")
        }

        try? fileManager.removeItem(at: legacyURL)
        debugLog("[MaintenanceManager] Removed legacy pairing file '\(legacyURL.path)'.")
    }
}
