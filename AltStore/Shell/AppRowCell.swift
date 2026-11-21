#if os(iOS)
//
//  AppRowCell.swift
//  oPenSSAI
//
//  One app row in the Apps tab: 60pt rounded icon, bold name + gray version,
//  monospaced bundle ID, and a right-side status (days left / "Pending").
//  Matches the reference layout pixel for pixel.
//
//  Copyright © 2026 oPenSSAI Contributors. All rights reserved.
//

import UIKit

final class AppRowCell: ShellCardCell
{
    static let reuseIdentifier = "AppRowCell"

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
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let versionLabel: UILabel = {
        let label = UILabel()
        label.font = ShellTheme.appVersionFont
        label.textColor = ShellTheme.secondaryText
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let bundleIDLabel: UILabel = {
        let label = UILabel()
        label.font = ShellTheme.bundleIDFont
        label.textColor = ShellTheme.secondaryText
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let statusLabel: UILabel = {
        let label = UILabel()
        label.font = ShellTheme.statusFont
        label.textColor = ShellTheme.secondaryText
        label.textAlignment = .right
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let activityIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.color = ShellTheme.secondaryText
        indicator.hidesWhenStopped = true
        indicator.translatesAutoresizingMaskIntoConstraints = false
        return indicator
    }()

    private let progressView: UIProgressView = {
        let progressView = UIProgressView(progressViewStyle: .default)
        progressView.progressTintColor = ShellTheme.accentColor
        progressView.trackTintColor = ShellTheme.separator
        progressView.translatesAutoresizingMaskIntoConstraints = false
        return progressView
    }()

    private let progressLabel: UILabel = {
        let label = UILabel()
        label.font = ShellTheme.bundleIDFont
        label.textColor = ShellTheme.secondaryText
        label.textAlignment = .right
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    /// Bar + percentage, shown under the bundle ID while an install/refresh
    /// is in flight. A hidden arranged subview collapses in the stack, so
    /// the row is its normal height when idle.
    private lazy var progressStack: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [progressView, progressLabel])
        stack.axis = .horizontal
        stack.spacing = 8
        stack.alignment = .center
        stack.isHidden = true
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    /// KVO on the in-flight Progress's fractionCompleted, driving the %
    /// label. (The bar itself tracks the Progress via observedProgress.)
    private var progressObservation: NSKeyValueObservation?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?)
    {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        accessoryType = .none
        separatorInset = UIEdgeInsets(
            top: 0,
            left: 16 + ShellTheme.appIconSize + 12,
            bottom: 0,
            right: 16
        )

        let nameStack = UIStackView(arrangedSubviews: [nameLabel, versionLabel])
        nameStack.axis = .horizontal
        nameStack.spacing = 8
        nameStack.alignment = .firstBaseline
        nameStack.translatesAutoresizingMaskIntoConstraints = false

        let textStack = UIStackView(arrangedSubviews: [nameStack, bundleIDLabel, progressStack])
        textStack.axis = .vertical
        textStack.spacing = 4
        textStack.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(iconImageView)
        contentView.addSubview(textStack)
        contentView.addSubview(statusLabel)
        contentView.addSubview(activityIndicator)

        NSLayoutConstraint.activate([
            iconImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            iconImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: ShellTheme.appIconSize),
            iconImageView.heightAnchor.constraint(equalToConstant: ShellTheme.appIconSize),
            iconImageView.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor, constant: 12),
            iconImageView.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -12),

            textStack.leadingAnchor.constraint(equalTo: iconImageView.trailingAnchor, constant: 12),
            textStack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            textStack.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor, constant: 12),
            textStack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -12),

            statusLabel.leadingAnchor.constraint(greaterThanOrEqualTo: textStack.trailingAnchor, constant: 12),
            statusLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            statusLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            activityIndicator.centerXAnchor.constraint(equalTo: statusLabel.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: statusLabel.centerYAnchor),
        ])
    }

    override func prepareForReuse()
    {
        super.prepareForReuse()
        iconImageView.image = nil
        statusLabel.isHidden = false
        activityIndicator.stopAnimating()
        setProgress(nil)
    }

    /// Configures the row. `statusColor` overrides the default gray (e.g.
    /// red for expired apps). Pass `isBusy: true` to show a spinner instead
    /// of the status text while the app is refreshing/installing.
    func configure(
        icon: UIImage?,
        name: String,
        version: String?,
        bundleIdentifier: String,
        status: String,
        statusColor: UIColor? = nil,
        isBusy: Bool = false
    )
    {
        iconImageView.image = icon
        nameLabel.text = name
        if let version, !version.isEmpty
        {
            versionLabel.text = "v\(version)"
            versionLabel.isHidden = false
        }
        else
        {
            versionLabel.isHidden = true
        }
        bundleIDLabel.text = bundleIdentifier
        statusLabel.text = status
        statusLabel.textColor = statusColor ?? ShellTheme.secondaryText
        statusLabel.isHidden = isBusy
        if isBusy
        {
            activityIndicator.startAnimating()
        }
        else
        {
            activityIndicator.stopAnimating()
        }
    }

    /// Shows the install/refresh progress bar + percentage for an in-flight
    /// operation, or hides them when `progress` is nil (idle). The bar
    /// tracks the Progress via UIProgressView.observedProgress (as upstream
    /// PillButton does); the % label is driven by KVO on fractionCompleted.
    func setProgress(_ progress: Progress?)
    {
        progressObservation?.invalidate()
        progressObservation = nil
        progressView.progress = Float(progress?.fractionCompleted ?? 0)
        progressView.observedProgress = progress

        guard let progress else
        {
            progressStack.isHidden = true
            return
        }

        progressStack.isHidden = false
        progressLabel.text = Self.percentageText(for: progress.fractionCompleted)
        progressObservation = progress.observe(\.fractionCompleted, options: [.new]) { [weak self] progress, _ in
            // Progress updates arrive on background threads; update UI on main.
            DispatchQueue.main.async {
                self?.progressLabel.text = Self.percentageText(for: progress.fractionCompleted)
            }
        }
    }

    private static func percentageText(for fractionCompleted: Double) -> String
    {
        return String(format: "%d%%", Int(fractionCompleted * 100))
    }
}
#endif
