#if os(iOS)
//
//  AboutViewController.swift
//  oPenSSAI
//
//  About oPenSSAI: icon, name, version, and links to the components &
//  licenses screen and the GitHub repository, with fork attribution.
//
//  Copyright © 2026 oPenSSAI Contributors. All rights reserved.
//

import UIKit

final class AboutViewController: UIViewController
{
    private enum Row: Int, CaseIterable
    {
        case licenses
        case repository
    }

    private lazy var tableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .insetGrouped)
        tableView.backgroundColor = ShellTheme.background
        tableView.separatorColor = ShellTheme.separator
        tableView.register(SettingRowCell.self, forCellReuseIdentifier: SettingRowCell.reuseIdentifier)
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
        title = NSLocalizedString("About oPenSSAI", comment: "")

        tableView.tableHeaderView = makeHeaderView()
        tableView.tableFooterView = makeFooterView()

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
        return .lightContent
    }

    private var versionText: String
    {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        if build.isEmpty { return version }
        return "\(version) (\(build))"
    }

    private func makeHeaderView() -> UIView
    {
        let header = UIView(frame: CGRect(x: 0, y: 0, width: 0, height: 190))

        let iconImageView = UIImageView(image: UIImage(named: "SideStore"))
        iconImageView.contentMode = .scaleAspectFill
        iconImageView.layer.cornerRadius = 18
        iconImageView.layer.masksToBounds = true
        iconImageView.translatesAutoresizingMaskIntoConstraints = false

        let nameLabel = UILabel()
        nameLabel.font = ShellTheme.headingFont
        nameLabel.textColor = ShellTheme.primaryText
        nameLabel.textAlignment = .center
        nameLabel.text = "oPenSSAI"
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        let versionLabel = UILabel()
        versionLabel.font = UIFont.systemFont(ofSize: 15, weight: .regular)
        versionLabel.textColor = ShellTheme.secondaryText
        versionLabel.textAlignment = .center
        versionLabel.text = String(format: NSLocalizedString("Version %@", comment: ""), versionText)
        versionLabel.translatesAutoresizingMaskIntoConstraints = false

        header.addSubview(iconImageView)
        header.addSubview(nameLabel)
        header.addSubview(versionLabel)

        NSLayoutConstraint.activate([
            iconImageView.topAnchor.constraint(equalTo: header.topAnchor, constant: 24),
            iconImageView.centerXAnchor.constraint(equalTo: header.centerXAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 76),
            iconImageView.heightAnchor.constraint(equalToConstant: 76),

            nameLabel.topAnchor.constraint(equalTo: iconImageView.bottomAnchor, constant: 12),
            nameLabel.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            nameLabel.trailingAnchor.constraint(equalTo: header.trailingAnchor),

            versionLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4),
            versionLabel.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            versionLabel.trailingAnchor.constraint(equalTo: header.trailingAnchor),
        ])

        return header
    }

    private func makeFooterView() -> UIView
    {
        let footer = UIView(frame: CGRect(x: 0, y: 0, width: 0, height: 120))

        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 14, weight: .regular)
        label.textColor = ShellTheme.secondaryText
        label.textAlignment = .center
        label.numberOfLines = 0
        label.text = NSLocalizedString("oPenSSAI is free and open-source software (AGPLv3). It is a fork of SideStore, built on AltStore by Riley Testut and the SideStore contributors.", comment: "")
        label.translatesAutoresizingMaskIntoConstraints = false

        footer.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: footer.topAnchor, constant: 16),
            label.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: 32),
            label.trailingAnchor.constraint(equalTo: footer.trailingAnchor, constant: -32),
        ])

        return footer
    }
}

extension AboutViewController: UITableViewDataSource, UITableViewDelegate
{
    func numberOfSections(in tableView: UITableView) -> Int
    {
        return 1
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int
    {
        return Row.allCases.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell
    {
        let cell = tableView.dequeueReusableCell(withIdentifier: SettingRowCell.reuseIdentifier, for: indexPath) as! SettingRowCell
        let position: ShellCardPosition = indexPath.row == 0 ? .top : .bottom
        cell.configureCardBackground(position: position)

        switch Row(rawValue: indexPath.row)
        {
        case .licenses:
            cell.configure(
                iconSystemName: "doc.text", iconTint: ShellTheme.accentColor,
                title: NSLocalizedString("Components & Licenses", comment: ""))
        case .repository:
            cell.configure(
                iconSystemName: "link", iconTint: ShellTheme.accentColor,
                title: NSLocalizedString("GitHub Repository", comment: ""))
        case .none:
            break
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath)
    {
        tableView.deselectRow(at: indexPath, animated: true)

        switch Row(rawValue: indexPath.row)
        {
        case .licenses:
            navigationController?.pushViewController(ComponentLicensesViewController(), animated: true)
        case .repository:
            openWebURL(AppConstants.URLs.sideStoreGitHub, preferredTintColor: ShellTheme.accentColor)
        case .none:
            break
        }
    }
}
#endif
