//
//  OperationStep.swift
//  SideStore
//
//  Created by Magesh K on 30/07/26.
//  Copyright © 2026 AltStore. All rights reserved.
//

import Foundation

protocol OperationStep: Equatable, Hashable {}

enum PipelineStep: OperationStep {
    case backupAppData
    case cacheApp
    case cleanStagedApp
    case deactivateApp
    case downloadApp
    case exportResignedIPA
    case fetchProvisioningProfiles
    case installApp
    case markAppInactive
    case stageBackupApp
    case changeAppIcon
    case prepareAppExtensionBundleIDs
    case preflightChecks
    case refreshApp
    case removeApp
    case removeBackupData
    case removeAppExtensions
    case resignApp
    case restoreAppData
    case sendApp
    case stageApp
    case uninstallApp
    case userCustomization
    case verifyApp
    case verifyCertificate
    case updateAppCertificate
    case embedSigningCert
    case cacheSigningCert
    case cacheResignedMetadata
    case patchInfoPlist
    case createIPA

    fileprivate static let stepMap: [ObjectIdentifier: PipelineStep] = [
        ObjectIdentifier(PerformBackupRestoreOperation.self):             .backupAppData,
        ObjectIdentifier(CacheAppOperation.self):                         .cacheApp,
        ObjectIdentifier(CacheSigningCertOperation.self):                 .cacheSigningCert,
        ObjectIdentifier(CacheResignedMetadataOperation.self):            .cacheResignedMetadata,
        ObjectIdentifier(PatchInfoPlistOperation.self):                   .patchInfoPlist,
        ObjectIdentifier(CleanStagedAppOperation.self):                   .cleanStagedApp,
        ObjectIdentifier(DeactivateAppOperation.self):                    .deactivateApp,
        ObjectIdentifier(DownloadAppOperation.self):                      .downloadApp,
        ObjectIdentifier(ExportResignedIpaOperation.self):                .exportResignedIPA,
        ObjectIdentifier(FetchProvisioningProfilesOperation.self):        .fetchProvisioningProfiles,
        ObjectIdentifier(InstallAppOperation.self):                       .installApp,
        ObjectIdentifier(MarkAppInactiveOperation.self):                  .markAppInactive,
        ObjectIdentifier(StageBackupAppOperation.self):                   .stageBackupApp,
        ObjectIdentifier(ChangeAppIconOperation.self):                    .changeAppIcon,
        ObjectIdentifier(PrepareAppExtensionBundleIDsOperation.self):     .prepareAppExtensionBundleIDs,
        ObjectIdentifier(PreflightChecksOperation.self):                  .preflightChecks,
        ObjectIdentifier(RefreshAppOperation.self):                       .refreshApp,
        ObjectIdentifier(RemoveBackupDataOperation.self):                 .removeBackupData,
        ObjectIdentifier(RemoveAppExtensionsOperation.self):              .removeAppExtensions,
        ObjectIdentifier(RemoveAppOperation.self):                        .removeApp,
        ObjectIdentifier(ResignAppOperation.self):                        .resignApp,
        ObjectIdentifier(CreateIpaOperation.self):                        .createIPA,
        ObjectIdentifier(SendAppOperation.self):                          .sendApp,
        ObjectIdentifier(StageAppOperation.self):                         .stageApp,
        ObjectIdentifier(UninstallAppOperation.self):                     .uninstallApp,
        ObjectIdentifier(UserCustomizationOperation.self):                .userCustomization,
        ObjectIdentifier(VerifyAppOperation.self):                        .verifyApp,
        ObjectIdentifier(VerifyCertificateOperation.self):                .verifyCertificate,
        ObjectIdentifier(UpdateAppCertificateOperation.self):             .updateAppCertificate,
        ObjectIdentifier(EmbedSigningCertOperation.self):                 .embedSigningCert,
    ]

    static func step(for type: Any.Type) -> PipelineStep? {
        stepMap[ObjectIdentifier(type)]
    }

    static func step(for operation: Any) -> PipelineStep? {
        if let backupOp = operation as? PerformBackupRestoreOperation {
            return backupOp.action == .backup ? .backupAppData : .restoreAppData
        }
        return step(for: type(of: operation))
    }

    /// User-visible stage label for the install-progress popup, published on
    /// the operation Progress's `localizedDescription` by PipelineExecutor
    /// as each step starts.
    var localizedStageDescription: String {
        switch self {
        case .preflightChecks:
            return NSLocalizedString("Checking requirements…", comment: "")
        case .userCustomization:
            return NSLocalizedString("Customizing app…", comment: "")
        case .downloadApp:
            return NSLocalizedString("Downloading app…", comment: "")
        case .verifyApp:
            return NSLocalizedString("Verifying app…", comment: "")
        case .cacheApp:
            return NSLocalizedString("Caching app…", comment: "")
        case .stageApp:
            return NSLocalizedString("Preparing app…", comment: "")
        case .stageBackupApp:
            return NSLocalizedString("Preparing backup helper…", comment: "")
        case .updateAppCertificate:
            return NSLocalizedString("Updating signing certificate…", comment: "")
        case .verifyCertificate:
            return NSLocalizedString("Verifying certificate…", comment: "")
        case .changeAppIcon:
            return NSLocalizedString("Updating app icon…", comment: "")
        case .removeAppExtensions:
            return NSLocalizedString("Removing app extensions…", comment: "")
        case .fetchProvisioningProfiles:
            return NSLocalizedString("Fetching provisioning profiles…", comment: "")
        case .prepareAppExtensionBundleIDs:
            return NSLocalizedString("Preparing extension IDs…", comment: "")
        case .embedSigningCert:
            return NSLocalizedString("Embedding signing certificate…", comment: "")
        case .resignApp:
            return NSLocalizedString("Re-signing app…", comment: "")
        case .createIPA:
            return NSLocalizedString("Packaging app…", comment: "")
        case .exportResignedIPA:
            return NSLocalizedString("Exporting signed app…", comment: "")
        case .sendApp:
            return NSLocalizedString("Sending app to device…", comment: "")
        case .installApp:
            return NSLocalizedString("Installing on device…", comment: "")
        case .refreshApp:
            return NSLocalizedString("Refreshing app…", comment: "")
        case .patchInfoPlist:
            return NSLocalizedString("Updating app info…", comment: "")
        case .cacheSigningCert:
            return NSLocalizedString("Saving signing certificate…", comment: "")
        case .cacheResignedMetadata:
            return NSLocalizedString("Saving app info…", comment: "")
        case .cleanStagedApp:
            return NSLocalizedString("Cleaning up…", comment: "")
        case .backupAppData:
            return NSLocalizedString("Backing up app data…", comment: "")
        case .restoreAppData:
            return NSLocalizedString("Restoring app data…", comment: "")
        case .removeBackupData:
            return NSLocalizedString("Removing backup data…", comment: "")
        case .uninstallApp:
            return NSLocalizedString("Uninstalling app…", comment: "")
        case .markAppInactive:
            return NSLocalizedString("Marking app inactive…", comment: "")
        case .removeApp:
            return NSLocalizedString("Removing app…", comment: "")
        case .deactivateApp:
            return NSLocalizedString("Deactivating app…", comment: "")
        }
    }
}

enum StandaloneStep: OperationStep {
    case signIn
    case preflightChecks
    case backgroundRefreshApps
    case clearAppCache
    case enableJIT
    case syncAppIDs
    case fetchSource
    case scheduleExpirationWarningNotification
    case injectBatchProfiles
    case unknown

    fileprivate static let stepMap: [ObjectIdentifier: StandaloneStep] = [
        ObjectIdentifier(SignInOperation.self):                                  .signIn,
        ObjectIdentifier(PreflightChecksOperation.self):                         .preflightChecks,
        ObjectIdentifier(BackgroundRefreshAppsOperation.self):                   .backgroundRefreshApps,
        ObjectIdentifier(ClearAppCacheOperation.self):                           .clearAppCache,
        ObjectIdentifier(EnableJITOperation.self):                               .enableJIT,
        ObjectIdentifier(SyncAppIDsOperation.self):                              .syncAppIDs,
        ObjectIdentifier(FetchSourceOperation.self):                             .fetchSource,
        ObjectIdentifier(ScheduleExpirationWarningNotificationOperation.self):   .scheduleExpirationWarningNotification,
        ObjectIdentifier(InjectBatchProfilesOperation.self):                     .injectBatchProfiles,
    ]

    static func step(for type: Any.Type) -> StandaloneStep? {
        stepMap[ObjectIdentifier(type)] ?? .unknown
    }
}
