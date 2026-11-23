#if os(iOS)
//
//  InstallProgressSteps.swift
//  openSSS
//
//  Maps the engine's pipeline stages onto the five user-facing install
//  phases (Download → Unpack → Sign → Install → Done) shown by
//  InstallProgressPopupViewController, and derives each phase's checklist
//  state (pending / current / completed / skipped) plus the current
//  phase's within-phase percentage from the operation Progress.
//
//  The engine publishes one stage at a time on the operation Progress's
//  localizedDescription (PipelineExecutor sets it to the step's
//  localizedStageDescription as each step starts); this model reverses
//  that mapping by exact string match, so no engine change is needed.
//
//  A phase reads as skipped — never stuck — once the pipeline has moved
//  past it without it ever being observed: either the pipeline has no
//  such step (refresh has no download or unpack steps; resign has no
//  download step) or the step flashed by before KVO delivered it (a
//  local .ipa import's download completes almost instantly). Whether a
//  phase has been "passed" is judged in pipeline order, not checklist
//  order, because refresh runs its Done bookkeeping
//  (cacheResignedMetadata) before its Install step (refreshApp).
//
//  Within-phase percentages come from the pipeline's step weights
//  (PipelineStepDefinition): each step's child Progress is added to the
//  operation Progress with its weight as pending units, so the parent's
//  fractionCompleted is already the weighted cumulative total. The model
//  only slices that same fraction into phase bands, so the total bar
//  never jumps back to 0 at a phase boundary.
//
//  Copyright © 2026 openSSS Contributors. All rights reserved.
//

import Foundation

/// The five user-facing phases of an install/refresh, in checklist order.
enum InstallProgressPhase: Int, CaseIterable
{
    case download
    case unpack
    case sign
    case install
    case done

    var title: String
    {
        switch self
        {
        case .download:
            return NSLocalizedString("Progress Step Download", comment: "")
        case .unpack:
            return NSLocalizedString("Progress Step Unpack", comment: "")
        case .sign:
            return NSLocalizedString("Progress Step Sign", comment: "")
        case .install:
            return NSLocalizedString("Progress Step Install", comment: "")
        case .done:
            return NSLocalizedString("Progress Step Done", comment: "")
        }
    }
}

/// Display state of one phase in the install-progress checklist.
enum InstallProgressPhaseState: Equatable
{
    /// Not reached yet.
    case pending
    /// Running now; the fraction (0...1) is progress within this phase.
    case current(fraction: Double)
    /// Finished.
    case completed
    /// The pipeline has no such step (or it flashed by unobserved).
    case skipped
}

extension PipelineStep
{
    /// All 31 cases, for the stage-description reverse lookup
    /// (PipelineStep is not CaseIterable).
    static let allProgressSteps: [PipelineStep] = [
        .backupAppData,
        .cacheApp,
        .cacheResignedMetadata,
        .cacheSigningCert,
        .changeAppIcon,
        .cleanStagedApp,
        .createIPA,
        .deactivateApp,
        .downloadApp,
        .embedSigningCert,
        .exportResignedIPA,
        .fetchProvisioningProfiles,
        .installApp,
        .markAppInactive,
        .patchInfoPlist,
        .preflightChecks,
        .prepareAppExtensionBundleIDs,
        .refreshApp,
        .removeApp,
        .removeAppExtensions,
        .removeBackupData,
        .resignApp,
        .restoreAppData,
        .sendApp,
        .stageApp,
        .stageBackupApp,
        .uninstallApp,
        .updateAppCertificate,
        .userCustomization,
        .verifyApp,
        .verifyCertificate,
    ]

    /// The step whose published stage label matches a Progress
    /// localizedDescription, or nil when the text is not a published
    /// stage (fallback text, or a step from a future engine version).
    static func step(forStageDescription description: String) -> PipelineStep?
    {
        return stageDescriptionLookup[description]
    }

    private static let stageDescriptionLookup: [String: PipelineStep] = {
        var lookup = [String: PipelineStep]()
        for step in allProgressSteps
        {
            lookup[step.localizedStageDescription] = step
        }
        return lookup
    }()

    /// Which user-facing phase this engine step belongs to. Covers all
    /// 31 PipelineStep cases:
    ///
    /// - Download: fetching the app (preflightChecks is defensive only —
    ///   no pipeline definition includes it; the standalone preflight
    ///   runs before the operation Progress exists).
    /// - Unpack: verifying, caching, and staging the bundle, plus the
    ///   user-customization prompt.
    /// - Sign: certificates, provisioning profiles, icon/extension
    ///   prep, re-signing, and packaging the signed .ipa (createIPA /
    ///   exportResignedIPA finalize the signed bundle; the device
    ///   transfer starts at sendApp).
    /// - Install: sending the app to the device and installing it
    ///   (refreshApp is refresh's device-side reinstall), plus the
    ///   device-side data transfer and removal steps of the
    ///   activate/deactivate/backup/restore/delete pipelines.
    /// - Done: post-install bookkeeping and cleanup.
    var installProgressPhase: InstallProgressPhase
    {
        switch self
        {
        case .downloadApp, .preflightChecks:
            return .download
        case .verifyApp, .cacheApp, .stageApp, .stageBackupApp, .userCustomization:
            return .unpack
        case .updateAppCertificate, .verifyCertificate, .changeAppIcon,
             .removeAppExtensions, .fetchProvisioningProfiles,
             .prepareAppExtensionBundleIDs, .embedSigningCert, .resignApp,
             .patchInfoPlist, .createIPA, .exportResignedIPA:
            return .sign
        case .sendApp, .installApp, .refreshApp, .backupAppData,
             .restoreAppData, .uninstallApp, .deactivateApp:
            return .install
        case .cacheSigningCert, .cacheResignedMetadata, .cleanStagedApp,
             .removeBackupData, .markAppInactive, .removeApp:
            return .done
        }
    }
}

/// Tracks the engine stages observed for one operation and derives the
/// five-phase checklist state. One instance per popup binding; the popup
/// replaces it on retarget so a refresh-all hop starts clean.
final class InstallProgressStepModel
{
    private let kind: InstallProgressPopupViewController.OperationKind
    private var observedSteps: [PipelineStep] = []
    private var observedStepSet: Set<PipelineStep> = []
    private var weightTable: [PipelineExecutionStep]

    init(kind: InstallProgressPopupViewController.OperationKind)
    {
        self.kind = kind
        self.weightTable = Self.defaultWeightTable(for: kind)
    }

    /// Records a stage published on the operation Progress. Unknown or
    /// repeated text is ignored (the fallback Installing…/Refreshing…
    /// text is not a stage).
    func observeStageDescription(_ description: String?)
    {
        guard let description, !description.isEmpty,
              let step = PipelineStep.step(forStageDescription: description),
              !observedStepSet.contains(step) else { return }
        observedSteps.append(step)
        observedStepSet.insert(step)
        reselectWeightTableIfNeeded()
    }

    /// Checklist state for all five phases, in order, derived from the
    /// observed stages and the operation Progress's weighted fraction.
    func states(fractionCompleted: Double, totalUnitCount: Int64) -> [InstallProgressPhaseState]
    {
        let finished = fractionCompleted >= 1.0
        let observedPhases = Set(observedSteps.map(\.installProgressPhase))
        let currentPhase = observedSteps.last?.installProgressPhase
        let bands = phaseBands()
        // The parent Progress totals 100 units (PipelineRunner); each
        // step contributes its weight, so fraction * total is the
        // completed weight. (Install weights sum to 108, so the fraction
        // reaches 1.0 partway through installApp — the same threshold
        // the popup already uses for completion.)
        let completedUnits = fractionCompleted * Double(max(totalUnitCount, 1))
        // Pipeline position of the latest observed step within the
        // selected weight table, for the passed/pending judgment. -1
        // when nothing is observed yet or the step is not in the table
        // (unknown future step).
        let currentIndex = observedSteps.last.flatMap { step in
            weightTable.lastIndex(where: { $0.step == step })
        } ?? -1

        return InstallProgressPhase.allCases.map { phase in
            if finished
            {
                // Completion itself fulfills the Done phase: its steps
                // are weight-1 bookkeeping that runs last, and the
                // 108/100 weight overflow can finish the fraction
                // before they are observed.
                if phase == .done || observedPhases.contains(phase)
                {
                    return .completed
                }
                return .skipped
            }
            if phase == currentPhase
            {
                return .current(fraction: phaseFraction(for: phase, bands: bands, completedUnits: completedUnits))
            }
            if observedPhases.contains(phase)
            {
                return .completed
            }
            // Never observed: skipped only if the pipeline has already
            // moved past every step of this phase — judged in pipeline
            // order, not checklist order, because refresh runs its Done
            // bookkeeping before its Install step.
            if let lastIndex = lastTableIndex(for: phase), lastIndex < currentIndex
            {
                return .skipped
            }
            if bands[phase] == nil, currentIndex >= 0
            {
                // No step of this phase exists in the selected pipeline
                // (refresh has no download/unpack; resign has no
                // download), and the operation has started.
                return .skipped
            }
            return .pending
        }
    }

    // MARK: - Weight tables

    private static func defaultWeightTable(for kind: InstallProgressPopupViewController.OperationKind) -> [PipelineExecutionStep]
    {
        switch kind
        {
        case .install:
            // Install, update, and reinstall all run the install pipeline.
            return PipelineStepDefinition.install
        case .refresh:
            // Refresh is the common refresh-family pipeline; resign and
            // friends are picked up by reselectWeightTableIfNeeded once
            // one of their steps is observed.
            return PipelineStepDefinition.refresh
        }
    }

    private static func candidateWeightTables(for kind: InstallProgressPopupViewController.OperationKind) -> [[PipelineExecutionStep]]
    {
        switch kind
        {
        case .install:
            return [PipelineStepDefinition.install]
        case .refresh:
            // In the order the shell most often shows them. (The legacy
            // activate/restore tables equal the refresh table.)
            return [
                PipelineStepDefinition.refresh,
                PipelineStepDefinition.resign,
                PipelineStepDefinition.activate,
                PipelineStepDefinition.restore,
                PipelineStepDefinition.backup,
                PipelineStepDefinition.deactivate,
                PipelineStepDefinition.removeApp,
                PipelineStepDefinition.deleteApp,
            ]
        }
    }

    /// The popup only knows install- vs refresh-family, but the refresh
    /// family runs several pipelines (refresh, resign, activate, …) with
    /// different weights. Once an observed step falls outside the current
    /// table, switch to the first candidate table containing every
    /// observed step, so the within-phase percentage stays accurate.
    private func reselectWeightTableIfNeeded()
    {
        let tableSteps = Set(weightTable.map(\.step))
        guard !observedStepSet.isSubset(of: tableSteps) else { return }
        for candidate in Self.candidateWeightTables(for: kind)
        {
            if observedStepSet.isSubset(of: Set(candidate.map(\.step)))
            {
                weightTable = candidate
                return
            }
        }
        // No known pipeline contains every observed step (e.g. a future
        // engine step): keep the current table. Phase classification
        // still holds; only the within-phase percentage is approximate.
    }

    private func phaseBands() -> [InstallProgressPhase: (start: Int64, end: Int64)]
    {
        var bands = [InstallProgressPhase: (start: Int64, end: Int64)]()
        var cursor: Int64 = 0
        for entry in weightTable
        {
            let phase = entry.step.installProgressPhase
            if let existing = bands[phase]
            {
                // A phase recurring later in the pipeline (activate and
                // backup sign twice): span first start to last end so
                // the percentage stays monotonic across both passes.
                bands[phase] = (existing.start, cursor + entry.weight)
            }
            else
            {
                bands[phase] = (cursor, cursor + entry.weight)
            }
            cursor += entry.weight
        }
        return bands
    }

    private func lastTableIndex(for phase: InstallProgressPhase) -> Int?
    {
        return weightTable.lastIndex(where: { $0.step.installProgressPhase == phase })
    }

    private func phaseFraction(for phase: InstallProgressPhase, bands: [InstallProgressPhase: (start: Int64, end: Int64)], completedUnits: Double) -> Double
    {
        guard let band = bands[phase], band.end > band.start else
        {
            // The current phase has no weight in the selected table
            // (defensive: table selection keeps every observed step in
            // the table, so this only fires for unknown future steps).
            return 0
        }
        let fraction = (completedUnits - Double(band.start)) / Double(band.end - band.start)
        return min(max(fraction, 0), 1)
    }
}
#endif
