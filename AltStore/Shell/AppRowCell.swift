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

        let textStack = UIStackView(arrangedSubviews: [nameStack, bundleIDLabel])
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
}
#endif
