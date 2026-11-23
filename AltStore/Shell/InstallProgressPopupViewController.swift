#if os(iOS)
//
//  InstallProgressPopupViewController.swift
//  openSSS
//
//  Modal popup for install/refresh progress: app icon + name, overall
//  progress bar + percentage, a five-phase checklist (Download → Unpack
//  → Sign → Install → Done), and the engine's current stage text.
//  Completed phases show a checkmark, the current phase is highlighted
//  with its within-phase percentage, and phases the pipeline never runs
//  (refresh has no download/unpack; a local .ipa import's download
//  flashes by unobserved) read as skipped instead of stuck. See
//  InstallProgressSteps for the stage-to-phase mapping.
//
//  The stage comes from the pipeline, which publishes each step on the
//  operation Progress's localizedDescription (see PipelineExecutor);
//  before the first step starts, a generic Installing…/Refreshing…
//  fallback is shown. The overall bar and percentage are the operation
//  Progress's fractionCompleted, which is already the weighted
//  cumulative total — it never jumps back to 0 at a phase boundary.
//
//  Presented by AppsViewController while an operation is in flight and
//  dismissed by it when the operation ends. Cancel cancels the underlying
//  Progress (the engine picks cancellation up at the next step boundary).
//  Failures surface as a translated ToastView from AppsViewController's
//  completion handlers (MinimuxerErrorTranslator), not here.
//
//  Copyright © 2026 openSSS Contributors. All rights reserved.
//

import UIKit

final class InstallProgressPopupViewController: UIViewController
{
    /// Which family the shown operation belongs to; only used for the
    /// fallback stage text while the pipeline has not published a stage
    /// yet, and for the checklist's default weight table.
    enum OperationKind
    {
        case install
        case refresh
    }

    /// Bundle ID of the app currently shown. Retargeted in place when a
    /// refresh-all group moves on to the next app.
    private(set) var bundleID: String

    /// Called once when the bound Progress reaches 100% (a multi-app group
    /// keeps a finished operation's Progress registered until the whole
    /// group ends, so the coordinator advances on this instead of waiting
    /// for the progress to be cleared).
    var onCompleted: (() -> Void)?

    private var progress: Progress
    private var operationKind: OperationKind
    private var stepModel: InstallProgressStepModel

    private var fractionObservation: NSKeyValueObservation?
    private var stageObservation: NSKeyValueObservation?
    private var hasCompleted = false
    private var lastStepStates: [InstallProgressPhaseState] = []

    // MARK: - Views

    private let dimView: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let cardView: UIView = {
        let view = UIView()
        view.backgroundColor = ShellTheme.card
        view.layer.cornerRadius = 20
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let iconImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.layer.cornerRadius = ShellTheme.appIconCornerRadius
        imageView.layer.masksToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private let nameLabel: UILabel = {
        let label = UILabel()
        label.font = ShellTheme.appNameFont
        label.textColor = ShellTheme.primaryText
        label.numberOfLines = 2
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let subtitleLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 13, weight: .regular)
        label.textColor = ShellTheme.secondaryText
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let progressView: UIProgressView = {
        let progressView = UIProgressView(progressViewStyle: .default)
        progressView.progressTintColor = ShellTheme.accentColor
        progressView.trackTintColor = ShellTheme.separator
        progressView.layer.cornerRadius = 3
        progressView.clipsToBounds = true
        progressView.translatesAutoresizingMaskIntoConstraints = false
        return progressView
    }()

    private let percentageLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.monospacedDigitSystemFont(ofSize: 15, weight: .semibold)
        label.textColor = ShellTheme.secondaryText
        label.textAlignment = .right
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var stepRows: [InstallProgressStepRowView] = {
        InstallProgressPhase.allCases.map { InstallProgressStepRowView(phase: $0) }
    }()

    private lazy var stepsStackView: UIStackView = {
        let stack = UIStackView(arrangedSubviews: stepRows)
        stack.axis = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private let stageLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 15, weight: .regular)
        label.textColor = ShellTheme.secondaryText
        label.numberOfLines = 2
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var cancelButton: UIButton = {
        var configuration = UIButton.Configuration.filled()
        configuration.baseBackgroundColor = ShellTheme.cardHighlighted
        configuration.baseForegroundColor = ShellTheme.primaryText
        configuration.cornerStyle = .capsule
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16)
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
            return outgoing
        }

        let button = UIButton(configuration: configuration)
        button.setTitle(NSLocalizedString("Cancel", comment: ""), for: .normal)
        button.addTarget(self, action: #selector(cancelButtonTapped), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    // MARK: - Init

    init(bundleID: String, name: String, version: String?, icon: UIImage?, progress: Progress, kind: OperationKind)
    {
        self.bundleID = bundleID
        self.progress = progress
        self.operationKind = kind
        self.stepModel = InstallProgressStepModel(kind: kind)
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
        isModalInPresentation = true

        // Labels are set in viewDidLoad; stash the display values until
        // then (views do not exist yet).
        pendingName = name
        pendingVersion = version
        pendingIcon = icon
    }

    @available(*, unavailable)
    required init?(coder: NSCoder)
    {
        fatalError("init(coder:) has not been implemented")
    }

    // Display values passed before the view loads.
    private var pendingName: String?
    private var pendingVersion: String?
    private var pendingIcon: UIImage?

    override func viewDidLoad()
    {
        super.viewDidLoad()
        view.backgroundColor = .clear

        view.addSubview(dimView)
        view.addSubview(cardView)

        let textStack = UIStackView(arrangedSubviews: [nameLabel, subtitleLabel])
        textStack.axis = .vertical
        textStack.spacing = 4

        let headerStack = UIStackView(arrangedSubviews: [iconImageView, textStack])
        headerStack.axis = .horizontal
        headerStack.spacing = 12
        headerStack.alignment = .center

        let progressStack = UIStackView(arrangedSubviews: [progressView, percentageLabel])
        progressStack.axis = .horizontal
        progressStack.spacing = 8
        progressStack.alignment = .center

        let contentStack = UIStackView(arrangedSubviews: [headerStack, progressStack, stepsStackView, stageLabel, cancelButton])
        contentStack.axis = .vertical
        contentStack.spacing = 16
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            dimView.topAnchor.constraint(equalTo: view.topAnchor),
            dimView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            dimView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            dimView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            cardView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            cardView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            cardView.widthAnchor.constraint(equalTo: view.safeAreaLayoutGuide.widthAnchor, multiplier: 0.86),
            cardView.widthAnchor.constraint(lessThanOrEqualToConstant: 340),

            contentStack.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 20),
            contentStack.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 20),
            contentStack.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -20),
            contentStack.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -20),

            iconImageView.widthAnchor.constraint(equalToConstant: ShellTheme.appIconSize),
            iconImageView.heightAnchor.constraint(equalToConstant: ShellTheme.appIconSize),
            progressView.heightAnchor.constraint(equalToConstant: 6),
            cancelButton.heightAnchor.constraint(equalToConstant: 44),
        ])

        nameLabel.text = pendingName
        subtitleLabel.text = pendingVersion.map { "v\($0)" } ?? bundleID
        iconImageView.image = pendingIcon
        pendingName = nil
        pendingVersion = nil
        pendingIcon = nil

        bind(progress: progress)
    }

    deinit
    {
        fractionObservation?.invalidate()
        stageObservation?.invalidate()
    }

    /// The popup sits over a dark dimming scrim, so the status bar stays
    /// light even in light mode (unlike the other shell screens, 0710).
    override var preferredStatusBarStyle: UIStatusBarStyle
    {
        return .lightContent
    }

    // MARK: - Binding

    /// Switches the popup to another app's operation in place (refresh-all
    /// moving on to the next app), without dismissing and re-presenting.
    func retarget(bundleID: String, name: String, version: String?, icon: UIImage?, progress: Progress, kind: OperationKind)
    {
        self.bundleID = bundleID
        self.operationKind = kind
        nameLabel.text = name
        subtitleLabel.text = version.map { "v\($0)" } ?? bundleID
        iconImageView.image = icon
        resetCancelButton()
        bind(progress: progress)
    }

    /// Updates the icon once the real one finishes loading (installed apps
    /// start with a placeholder when the icon is not cached yet).
    func updateIcon(_ icon: UIImage?)
    {
        iconImageView.image = icon
    }

    private func bind(progress: Progress)
    {
        fractionObservation?.invalidate()
        stageObservation?.invalidate()
        hasCompleted = false
        lastStepStates = []

        // A fresh model per operation: a refresh-all hop must not inherit
        // the previous app's observed stages.
        stepModel = InstallProgressStepModel(kind: operationKind)
        stepModel.observeStageDescription(progress.localizedDescription)

        self.progress = progress
        progressView.progress = Float(progress.fractionCompleted)
        progressView.observedProgress = progress
        updatePercentage()
        updateStage()
        updateSteps()

        fractionObservation = progress.observe(\.fractionCompleted, options: [.new]) { [weak self] progress, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.updatePercentage()
                self.updateSteps()
                if progress.fractionCompleted >= 1.0, !self.hasCompleted
                {
                    self.hasCompleted = true
                    self.onCompleted?()
                }
            }
        }
        stageObservation = progress.observe(\.localizedDescription, options: [.new]) { [weak self] progress, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.stepModel.observeStageDescription(progress.localizedDescription)
                self.updateStage()
                self.updateSteps()
            }
        }
    }

    private func updatePercentage()
    {
        percentageLabel.text = String(format: "%d%%", Int(progress.fractionCompleted * 100))
    }

    /// Refreshes the checklist from the observed stages and the weighted
    /// fraction. Only rows whose state changed are reconfigured, so the
    /// frequent fraction updates during a download do not churn labels.
    ///
    /// Needs proper testing: on-device install/refresh runs to confirm
    /// the checklist tracks the real stages — especially the local-import
    /// download flash-by and the refresh skip states — since this cannot
    /// be verified without a Mac build.
    private func updateSteps()
    {
        let states = stepModel.states(fractionCompleted: progress.fractionCompleted, totalUnitCount: progress.totalUnitCount)
        for (index, state) in states.enumerated()
        {
            guard index < stepRows.count else { continue }
            if index >= lastStepStates.count || lastStepStates[index] != state
            {
                stepRows[index].configure(state: state)
            }
        }
        lastStepStates = states
    }

    /// The pipeline's current stage, or a generic fallback while no step
    /// has started yet (progress registered, first step not reached).
    private func updateStage()
    {
        if let description = progress.localizedDescription, !description.isEmpty
        {
            stageLabel.text = description
            return
        }
        switch operationKind
        {
        case .install:
            stageLabel.text = NSLocalizedString("Installing…", comment: "")
        case .refresh:
            stageLabel.text = NSLocalizedString("Refreshing…", comment: "")
        }
    }

    // MARK: - Cancel

    @objc private func cancelButtonTapped()
    {
        // Cancelling the parent Progress propagates to the step children,
        // whose cancellation handlers mark their operations cancelled; the
        // engine unwinds at the next step boundary and clears the progress,
        // which dismisses this popup via the coordinator.
        progress.cancel()
        cancelButton.isEnabled = false
        cancelButton.setTitle(NSLocalizedString("Cancelling…", comment: ""), for: .normal)
    }

    private func resetCancelButton()
    {
        cancelButton.isEnabled = true
        cancelButton.setTitle(NSLocalizedString("Cancel", comment: ""), for: .normal)
    }
}

/// One row of the install-progress checklist: a status icon, the phase
/// title, and the current phase's within-phase percentage (or "Skipped").
private final class InstallProgressStepRowView: UIView
{
    private let iconImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 15, weight: .regular)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let statusLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.monospacedDigitSystemFont(ofSize: 14, weight: .semibold)
        label.textAlignment = .right
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    init(phase: InstallProgressPhase)
    {
        super.init(frame: .zero)
        titleLabel.text = phase.title

        let stack = UIStackView(arrangedSubviews: [iconImageView, titleLabel, statusLabel])
        stack.axis = .horizontal
        stack.spacing = 10
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 22),
            iconImageView.heightAnchor.constraint(equalToConstant: 22),
        ])

        configure(state: .pending)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder)
    {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(state: InstallProgressPhaseState)
    {
        switch state
        {
        case .pending:
            iconImageView.image = UIImage(systemName: "circle")
            iconImageView.tintColor = ShellTheme.secondaryText
            titleLabel.font = UIFont.systemFont(ofSize: 15, weight: .regular)
            titleLabel.textColor = ShellTheme.secondaryText
            statusLabel.text = nil
        case .current(let fraction):
            iconImageView.image = UIImage(systemName: "largecircle.fill.circle")
            iconImageView.tintColor = ShellTheme.accentColor
            titleLabel.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
            titleLabel.textColor = ShellTheme.primaryText
            statusLabel.text = String(format: "%d%%", Int(fraction * 100))
            statusLabel.textColor = ShellTheme.accentColor
        case .completed:
            iconImageView.image = UIImage(systemName: "checkmark.circle.fill")
            iconImageView.tintColor = ShellTheme.accentColor
            titleLabel.font = UIFont.systemFont(ofSize: 15, weight: .regular)
            titleLabel.textColor = ShellTheme.primaryText
            statusLabel.text = nil
        case .skipped:
            iconImageView.image = UIImage(systemName: "minus.circle")
            iconImageView.tintColor = ShellTheme.secondaryText
            titleLabel.font = UIFont.systemFont(ofSize: 15, weight: .regular)
            titleLabel.textColor = ShellTheme.secondaryText
            statusLabel.text = NSLocalizedString("Progress Step Skipped", comment: "")
            statusLabel.textColor = ShellTheme.secondaryText
        }
    }
}
#endif
