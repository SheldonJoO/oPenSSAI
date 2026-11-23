#if os(iOS)
//
//  SettingRowCell.swift
//  openSSS
//
//  One settings row in the Me tab: a tinted SF Symbol, a bold title, an
//  optional gray value, and either a chevron or a toggle switch.
//
//  Copyright © 2026 openSSS Contributors. All rights reserved.
//

import UIKit

final class SettingRowCell: ShellCardCell
{
    static let reuseIdentifier = "SettingRowCell"

    /// Fired when the toggle switch changes (toggle rows only).
    var onToggleChanged: ((Bool) -> Void)?

    private let iconImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = ShellTheme.rowTitleFont
        label.textColor = ShellTheme.primaryText
        label.numberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let valueLabel: UILabel = {
        let label = UILabel()
        label.font = ShellTheme.rowValueFont
        label.textColor = ShellTheme.secondaryText
        label.textAlignment = .right
        label.numberOfLines = 1
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let chevronImageView: UIImageView = {
        let imageView = UIImageView(image: UIImage(systemName: "chevron.right"))
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = ShellTheme.secondaryText
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private lazy var toggleSwitch: UISwitch = {
        let toggle = UISwitch()
        toggle.onTintColor = ShellTheme.accentColor
        toggle.addTarget(self, action: #selector(toggleChanged(_:)), for: .valueChanged)
        toggle.translatesAutoresizingMaskIntoConstraints = false
        return toggle
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?)
    {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        accessoryType = .none
        separatorInset = UIEdgeInsets(top: 0, left: 16 + ShellTheme.rowIconSize + 12, bottom: 0, right: 16)

        contentView.addSubview(iconImageView)
        contentView.addSubview(titleLabel)
        contentView.addSubview(valueLabel)
        contentView.addSubview(chevronImageView)
        contentView.addSubview(toggleSwitch)

        NSLayoutConstraint.activate([
            iconImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            iconImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: ShellTheme.rowIconSize),
            iconImageView.heightAnchor.constraint(equalToConstant: ShellTheme.rowIconSize),

            titleLabel.leadingAnchor.constraint(equalTo: iconImageView.trailingAnchor, constant: 12),
            titleLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            titleLabel.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor, constant: 14),
            titleLabel.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -14),

            valueLabel.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 12),
            valueLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            chevronImageView.leadingAnchor.constraint(equalTo: valueLabel.trailingAnchor, constant: 8),
            chevronImageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            chevronImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            chevronImageView.widthAnchor.constraint(equalToConstant: 12),
            chevronImageView.heightAnchor.constraint(equalToConstant: 16),

            toggleSwitch.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 12),
            toggleSwitch.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            toggleSwitch.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])
    }

    override func prepareForReuse()
    {
        super.prepareForReuse()
        onToggleChanged = nil
        valueLabel.text = nil
        valueLabel.textColor = ShellTheme.secondaryText
        valueLabel.isHidden = false
        chevronImageView.isHidden = false
        toggleSwitch.isHidden = true
    }

    @objc private func toggleChanged(_ sender: UISwitch)
    {
        onToggleChanged?(sender.isOn)
    }

    /// Disclosure row: icon + title + optional value + chevron.
    func configure(
        iconSystemName: String,
        iconTint: UIColor,
        title: String,
        value: String? = nil
    )
    {
        iconImageView.image = UIImage(systemName: iconSystemName)
        iconImageView.tintColor = iconTint
        titleLabel.text = title
        valueLabel.text = value
        valueLabel.isHidden = value == nil
        chevronImageView.isHidden = false
        toggleSwitch.isHidden = true
        selectionStyle = .default
    }

    /// Toggle row: icon + title + switch (no value, no chevron).
    func configureToggle(
        iconSystemName: String,
        iconTint: UIColor,
        title: String,
        isOn: Bool,
        onToggleChanged: @escaping (Bool) -> Void
    )
    {
        iconImageView.image = UIImage(systemName: iconSystemName)
        iconImageView.tintColor = iconTint
        titleLabel.text = title
        valueLabel.isHidden = true
        chevronImageView.isHidden = true
        toggleSwitch.isHidden = false
        toggleSwitch.isOn = isOn
        toggleSwitch.onTintColor = ShellTheme.accentColor
        self.onToggleChanged = onToggleChanged
        selectionStyle = .none
    }

    /// Info row: icon + title + value, not tappable (no chevron).
    func configureInfo(
        iconSystemName: String,
        iconTint: UIColor,
        title: String,
        value: String?,
        valueColor: UIColor? = nil
    )
    {
        iconImageView.image = UIImage(systemName: iconSystemName)
        iconImageView.tintColor = iconTint
        titleLabel.text = title
        valueLabel.text = value
        valueLabel.textColor = valueColor ?? ShellTheme.secondaryText
        valueLabel.isHidden = value == nil
        chevronImageView.isHidden = true
        toggleSwitch.isHidden = true
        selectionStyle = .none
    }
}
#endif
