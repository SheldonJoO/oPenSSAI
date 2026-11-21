#if os(iOS)
//
//  ThemePickerViewController.swift
//  oPenSSAI
//
//  Appearance & Theme: three appearance modes (follow system / light /
//  dark) and the accent color (Violet is the default, matching the
//  reference design).
//
//  Copyright © 2026 oPenSSAI Contributors. All rights reserved.
//

import UIKit

final class ThemePickerViewController: UIViewController
{
    private enum Section: Int, CaseIterable
    {
        case appearance
        case accent

        var title: String
        {
            switch self
            {
            case .appearance: return NSLocalizedString("Appearance", comment: "")
            case .accent: return NSLocalizedString("Theme Color", comment: "")
            }
        }
    }

    private lazy var tableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .insetGrouped)
        tableView.backgroundColor = ShellTheme.background
        tableView.separatorColor = ShellTheme.separator
        tableView.register(CheckmarkRowCell.self, forCellReuseIdentifier: CheckmarkRowCell.reuseIdentifier)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.sectionHeaderTopPadding = 0
        tableView.translatesAutoresizingMaskIntoConstraints = false
        return tableView
    }()

    override func viewDidLoad()
    {
        super.viewDidLoad()
        view.backgroundColor = ShellTheme.background
        title = NSLocalizedString("Appearance & Theme", comment: "")

        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    override var preferredStatusBarStyle: UIStatusBarStyle
    {
        return shellPreferredStatusBarStyle
    }
}

extension ThemePickerViewController: UITableViewDataSource, UITableViewDelegate
{
    func numberOfSections(in tableView: UITableView) -> Int
    {
        return Section.allCases.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int
    {
        switch Section(rawValue: section)
        {
        case .appearance: return ShellAppearance.allCases.count
        case .accent: return ShellAccent.allCases.count
        case .none: return 0
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell
    {
        let cell = tableView.dequeueReusableCell(withIdentifier: CheckmarkRowCell.reuseIdentifier, for: indexPath) as! CheckmarkRowCell
        let rowCount = self.tableView(tableView, numberOfRowsInSection: indexPath.section)
        let position: ShellCardPosition
        if rowCount == 1 { position = .single }
        else if indexPath.row == 0 { position = .top }
        else if indexPath.row == rowCount - 1 { position = .bottom }
        else { position = .middle }
        cell.configureCardBackground(position: position)

        switch Section(rawValue: indexPath.section)
        {
        case .appearance:
            let appearance = ShellAppearance.allCases[indexPath.row]
            cell.configure(title: appearance.displayName, colorDot: nil, isChecked: ShellTheme.appearance == appearance)
        case .accent:
            let accent = ShellAccent.allCases[indexPath.row]
            cell.configure(title: accent.displayName, colorDot: accent.color, isChecked: ShellTheme.accent == accent)
        case .none:
            break
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath)
    {
        tableView.deselectRow(at: indexPath, animated: true)

        switch Section(rawValue: indexPath.section)
        {
        case .appearance:
            ShellTheme.appearance = ShellAppearance.allCases[indexPath.row]
            ShellTheme.applyAppearance()
        case .accent:
            ShellTheme.accent = ShellAccent.allCases[indexPath.row]
        case .none:
            break
        }
        tableView.reloadData()
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView?
    {
        guard let section = Section(rawValue: section) else { return nil }
        let container = UIView()
        let label = UILabel()
        label.font = ShellTheme.sectionTitleFont
        label.textColor = ShellTheme.secondaryText
        label.text = section.title
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -6),
        ])
        return container
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat
    {
        return 40
    }
}

// MARK: - Checkmark row

private final class CheckmarkRowCell: ShellCardCell
{
    static let reuseIdentifier = "CheckmarkRowCell"

    private let colorDotView: UIView = {
        let view = UIView()
        view.layer.cornerRadius = 10
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private var colorDotWidthConstraint: NSLayoutConstraint!

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = ShellTheme.rowTitleFont
        label.textColor = ShellTheme.primaryText
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let checkmarkImageView: UIImageView = {
        let imageView = UIImageView(image: UIImage(systemName: "checkmark"))
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?)
    {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        separatorInset = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)

        contentView.addSubview(colorDotView)
        contentView.addSubview(titleLabel)
        contentView.addSubview(checkmarkImageView)

        colorDotWidthConstraint = colorDotView.widthAnchor.constraint(equalToConstant: 20)

        NSLayoutConstraint.activate([
            colorDotView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            colorDotView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            colorDotWidthConstraint,
            colorDotView.heightAnchor.constraint(equalToConstant: 20),

            titleLabel.leadingAnchor.constraint(equalTo: colorDotView.trailingAnchor, constant: 12),
            titleLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            titleLabel.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor, constant: 14),
            titleLabel.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -14),

            checkmarkImageView.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 12),
            checkmarkImageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            checkmarkImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            checkmarkImageView.widthAnchor.constraint(equalToConstant: 16),
            checkmarkImageView.heightAnchor.constraint(equalToConstant: 16),
        ])
    }

    override func prepareForReuse()
    {
        super.prepareForReuse()
        checkmarkImageView.isHidden = true
    }

    func configure(title: String, colorDot: UIColor?, isChecked: Bool)
    {
        titleLabel.text = title
        if let colorDot
        {
            colorDotView.isHidden = false
            colorDotView.backgroundColor = colorDot
            colorDotWidthConstraint.constant = 20
        }
        else
        {
            // No dot: collapse its width so the title starts at the margin.
            colorDotView.isHidden = true
            colorDotWidthConstraint.constant = 0
        }
        checkmarkImageView.isHidden = !isChecked
        checkmarkImageView.tintColor = ShellTheme.accentColor
    }
}
#endif
