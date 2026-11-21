#if os(iOS)
//
//  InstallProgressPopupViewController.swift
//  oPenSSAI
//
//  Modal popup for install/refresh progress: app icon + name, progress bar,
//  percentage, and a stage description line. The stage comes from the
//  pipeline, which publishes each step on the operation Progress's
//  localizedDescription (see PipelineExecutor); before the first step
//  starts, a generic Installing…/Refreshing… fallback is shown.
//
//  Presented by AppsViewController while an operation is in flight and
//  dismissed by it when the operation ends. Cancel cancels the underlying
//  Progress (the engine picks cancellation up at the next step boundary).
//
//  Copyright © 2026 oPenSSAI Contributors. All rights reserved.
//

import UIKit

final class InstallProgressPopupViewController: UIViewController
{
    /// Which family the shown operation belongs to; only used for the
    /// fallback stage text while the pipeline has not published a stage yet.
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

    private var fractionObservation: NSKeyValueObservation?
    private var stageObservation: NSKeyValueObservation?
    private var hasCompleted = false

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

        let contentStack = UIStackView(arrangedSubviews: [headerStack, progressStack, stageLabel, cancelButton])
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

        self.progress = progress
        progressView.progress = Float(progress.fractionCompleted)
        progressView.observedProgress = progress
        updatePercentage()
        updateStage()

        fractionObservation = progress.observe(\.fractionCompleted, options: [.new]) { [weak self] progress, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.updatePercentage()
                if progress.fractionCompleted >= 1.0, !self.hasCompleted
                {
                    self.hasCompleted = true
                    self.onCompleted?()
                }
            }
        }
        stageObservation = progress.observe(\.localizedDescription, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.updateStage()
            }
        }
    }

    private func updatePercentage()
    {
        percentageLabel.text = String(format: "%d%%", Int(progress.fractionCompleted * 100))
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
#endif
