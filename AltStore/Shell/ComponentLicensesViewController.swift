#if os(iOS)
//
//  ComponentLicensesViewController.swift
//  oPenSSAI
//
//  Components & Licenses: the open-source projects oPenSSAI is built from,
//  grouped by license type (as in the reference screen), listing oPenSSAI's
//  OWN components and their real licenses — verified against this repo's
//  Package.resolved, vendored LICENSE files, and the upstream repos.
//
//  Copyright © 2026 oPenSSAI Contributors. All rights reserved.
//

import UIKit

// MARK: - Catalog

/// One open-source component used by oPenSSAI.
struct LicenseComponent
{
    let name: String
    /// Released version, or a short commit hash for commit-pinned packages.
    let version: String?
    let license: LicenseType
    let url: URL
    /// One line describing what the component does.
    let summary: String
}

enum LicenseType: String, CaseIterable
{
    case agpl3 = "AGPL-3.0"
    case apache2 = "Apache-2.0"
    case gpl3 = "GPL-3.0"
    case mit = "MIT"

    /// A short plain-language summary of the license terms.
    var summary: String
    {
        switch self
        {
        case .agpl3:
            return NSLocalizedString("A copyleft license like GPL-3.0, extended to network use: users interacting with the software over a network are entitled to its source code.", comment: "")
        case .apache2:
            return NSLocalizedString("A permissive license with an express patent grant. Modified files must carry prominent notices of the changes.", comment: "")
        case .gpl3:
            return NSLocalizedString("A copyleft license: distributed modifications must also be released under GPL-3.0.", comment: "")
        case .mit:
            return NSLocalizedString("A permissive license: use, copy, modify, and distribute freely, keeping the copyright notice.", comment: "")
        }
    }
}

enum LicenseCatalog
{
    static let components: [LicenseComponent] = [
        // AGPL-3.0
        LicenseComponent(
            name: "SideStore", version: "0.7.0", license: .agpl3,
            url: URL(string: "https://github.com/SideStore/SideStore")!,
            summary: NSLocalizedString("The sideloading app oPenSSAI is forked from.", comment: "")),
        LicenseComponent(
            name: "AltStore", version: "2.3.3", license: .agpl3,
            url: URL(string: "https://github.com/rileytestut/AltStore")!,
            summary: NSLocalizedString("The original alternative app store by Riley Testut.", comment: "")),
        LicenseComponent(
            name: "minimuxer", version: nil, license: .agpl3,
            url: URL(string: "https://github.com/SideStore/minimuxer")!,
            summary: NSLocalizedString("Pure-Swift usbmuxd replacement for on-device installs.", comment: "")),
        LicenseComponent(
            name: "em_proxy", version: nil, license: .agpl3,
            url: URL(string: "https://github.com/SideStore/em_proxy")!,
            summary: NSLocalizedString("Local VPN loopback that carries install traffic on-device.", comment: "")),
        LicenseComponent(
            name: "AnisetteKit", version: "db8b410", license: .agpl3,
            url: URL(string: "https://github.com/mahee96/AnisetteKit")!,
            summary: NSLocalizedString("Anisette provisioning data for Apple ID sign-in.", comment: "")),
        LicenseComponent(
            name: "CodeSignKit", version: "d0c6771", license: .agpl3,
            url: URL(string: "https://github.com/mahee96/CodeSignKit")!,
            summary: NSLocalizedString("Code signing primitives.", comment: "")),
        LicenseComponent(
            name: "GSACryptoKit", version: "eae2590", license: .agpl3,
            url: URL(string: "https://github.com/mahee96/GSACryptoKit")!,
            summary: NSLocalizedString("Cryptography for Apple's Grand Slam authentication.", comment: "")),
        LicenseComponent(
            name: "RemotePairingKit", version: "e3f70d1", license: .agpl3,
            url: URL(string: "https://github.com/mahee96/RemotePairingKit")!,
            summary: NSLocalizedString("Remote pairing protocol for device connections.", comment: "")),
        // GPL-3.0
        LicenseComponent(
            name: "SideSign", version: nil, license: .gpl3,
            url: URL(string: "https://github.com/SideStore/SideSign")!,
            summary: NSLocalizedString("App signing library (baseline: AltSign by Riley Testut).", comment: "")),
        // MIT
        LicenseComponent(
            name: "KeychainAccess", version: "e0c7eeb", license: .mit,
            url: URL(string: "https://github.com/kishikawakatsumi/KeychainAccess")!,
            summary: NSLocalizedString("Keychain wrapper for storing credentials.", comment: "")),
        LicenseComponent(
            name: "libdeflate", version: "da6c7da", license: .mit,
            url: URL(string: "https://github.com/SideStore/libdeflate")!,
            summary: NSLocalizedString("Fast DEFLATE compression.", comment: "")),
        LicenseComponent(
            name: "MarkdownKit", version: "1.7.3", license: .mit,
            url: URL(string: "https://github.com/bmoliveira/MarkdownKit")!,
            summary: NSLocalizedString("Markdown parsing and rendering.", comment: "")),
        LicenseComponent(
            name: "Nuke", version: "12.9.0", license: .mit,
            url: URL(string: "https://github.com/kean/Nuke")!,
            summary: NSLocalizedString("Image loading and caching.", comment: "")),
        LicenseComponent(
            name: "ZIPFoundation", version: "0.9.20", license: .mit,
            url: URL(string: "https://github.com/weichsel/ZIPFoundation")!,
            summary: NSLocalizedString("ZIP archive handling.", comment: "")),
        // Apache-2.0
        LicenseComponent(
            name: "SemanticVersion", version: "0.4.0", license: .apache2,
            url: URL(string: "https://github.com/SwiftPackageIndex/SemanticVersion")!,
            summary: NSLocalizedString("Semantic version parsing.", comment: "")),
        LicenseComponent(
            name: "Starscream", version: "4.0.8", license: .apache2,
            url: URL(string: "https://github.com/daltoniam/Starscream")!,
            summary: NSLocalizedString("WebSocket client.", comment: "")),
        LicenseComponent(
            name: "swift-asn1", version: "1.6.0", license: .apache2,
            url: URL(string: "https://github.com/apple/swift-asn1")!,
            summary: NSLocalizedString("ASN.1 parsing.", comment: "")),
        LicenseComponent(
            name: "swift-crypto", version: "4.3.1", license: .apache2,
            url: URL(string: "https://github.com/apple/swift-crypto")!,
            summary: NSLocalizedString("Cryptographic primitives.", comment: "")),
    ]

    static func components(for license: LicenseType) -> [LicenseComponent]
    {
        components.filter { $0.license == license }.sorted { $0.name < $1.name }
    }
}

// MARK: - License groups

/// Top level: one row per license type, with the component count.
final class ComponentLicensesViewController: UIViewController
{
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
        title = NSLocalizedString("Components & Licenses", comment: "")

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
}

extension ComponentLicensesViewController: UITableViewDataSource, UITableViewDelegate
{
    func numberOfSections(in tableView: UITableView) -> Int
    {
        return 1
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int
    {
        return LicenseType.allCases.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell
    {
        let cell = tableView.dequeueReusableCell(withIdentifier: SettingRowCell.reuseIdentifier, for: indexPath) as! SettingRowCell
        let rowCount = LicenseType.allCases.count
        let position: ShellCardPosition
        if indexPath.row == 0 { position = .top }
        else if indexPath.row == rowCount - 1 { position = .bottom }
        else { position = .middle }
        cell.configureCardBackground(position: position)

        let license = LicenseType.allCases[indexPath.row]
        let count = LicenseCatalog.components(for: license).count
        cell.configure(
            iconSystemName: "doc.text", iconTint: ShellTheme.accentColor,
            title: license.rawValue,
            value: String(format: NSLocalizedString("%d Components", comment: ""), count))
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath)
    {
        tableView.deselectRow(at: indexPath, animated: true)
        let license = LicenseType.allCases[indexPath.row]
        navigationController?.pushViewController(LicenseComponentsViewController(license: license), animated: true)
    }
}

// MARK: - Components in one license group

final class LicenseComponentsViewController: UIViewController
{
    private let license: LicenseType
    private var components: [LicenseComponent] { LicenseCatalog.components(for: license) }

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

    init(license: LicenseType)
    {
        self.license = license
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder)
    {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad()
    {
        super.viewDidLoad()
        view.backgroundColor = ShellTheme.background
        title = license.rawValue

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
}

extension LicenseComponentsViewController: UITableViewDataSource, UITableViewDelegate
{
    func numberOfSections(in tableView: UITableView) -> Int
    {
        return 1
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int
    {
        return components.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell
    {
        let cell = tableView.dequeueReusableCell(withIdentifier: SettingRowCell.reuseIdentifier, for: indexPath) as! SettingRowCell
        let position: ShellCardPosition
        if components.count == 1 { position = .single }
        else if indexPath.row == 0 { position = .top }
        else if indexPath.row == components.count - 1 { position = .bottom }
        else { position = .middle }
        cell.configureCardBackground(position: position)

        let component = components[indexPath.row]
        cell.configure(
            iconSystemName: "shippingbox", iconTint: ShellTheme.accentColor,
            title: component.name,
            value: component.version)
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath)
    {
        tableView.deselectRow(at: indexPath, animated: true)
        navigationController?.pushViewController(LicenseDetailViewController(component: components[indexPath.row]), animated: true)
    }
}

// MARK: - Component detail

final class LicenseDetailViewController: UIViewController
{
    private let component: LicenseComponent

    init(component: LicenseComponent)
    {
        self.component = component
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder)
    {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad()
    {
        super.viewDidLoad()
        view.backgroundColor = ShellTheme.background
        title = component.name

        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.spacing = 20
        stackView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stackView)

        let nameLabel = UILabel()
        nameLabel.font = ShellTheme.headingFont
        nameLabel.textColor = ShellTheme.primaryText
        nameLabel.numberOfLines = 0
        nameLabel.text = component.name

        let versionLabel = UILabel()
        versionLabel.font = ShellTheme.rowValueFont
        versionLabel.textColor = ShellTheme.secondaryText
        versionLabel.numberOfLines = 0
        if let version = component.version
        {
            versionLabel.text = String(format: NSLocalizedString("Version %@", comment: ""), version)
        }
        else
        {
            versionLabel.text = NSLocalizedString("Bundled with oPenSSAI", comment: "")
        }

        let licenseTitleLabel = UILabel()
        licenseTitleLabel.font = UIFont.systemFont(ofSize: 19, weight: .bold)
        licenseTitleLabel.textColor = ShellTheme.primaryText
        licenseTitleLabel.text = component.license.rawValue

        let licenseBodyLabel = UILabel()
        licenseBodyLabel.font = ShellTheme.rowValueFont
        licenseBodyLabel.textColor = ShellTheme.secondaryText
        licenseBodyLabel.numberOfLines = 0
        licenseBodyLabel.text = component.license.summary

        let summaryLabel = UILabel()
        summaryLabel.font = ShellTheme.rowValueFont
        summaryLabel.textColor = ShellTheme.secondaryText
        summaryLabel.numberOfLines = 0
        summaryLabel.text = component.summary

        var configuration = UIButton.Configuration.filled()
        configuration.baseBackgroundColor = ShellTheme.accentBackground
        configuration.baseForegroundColor = ShellTheme.accentColor
        configuration.cornerStyle = .medium
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16)
        let linkButton = UIButton(configuration: configuration)
        linkButton.setTitle(NSLocalizedString("View on GitHub", comment: ""), for: .normal)
        linkButton.addTarget(self, action: #selector(linkButtonTapped), for: .touchUpInside)

        for arrangedView in [nameLabel, versionLabel, licenseTitleLabel, licenseBodyLabel, summaryLabel, linkButton]
        {
            stackView.addArrangedSubview(arrangedView)
        }

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            stackView.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 20),
            stackView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 20),
            stackView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -20),
            stackView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -32),
            stackView.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -40),
        ])
    }

    override var preferredStatusBarStyle: UIStatusBarStyle
    {
        return .lightContent
    }

    @objc private func linkButtonTapped()
    {
        openWebURL(component.url, preferredTintColor: ShellTheme.accentColor)
    }
}
#endif
