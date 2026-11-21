#if os(iOS)
//
//  AnisetteSettingsViewController.swift
//  oPenSSAI
//
//  The Anisette screen, reachable from Me → Signing. It exposes the levers
//  that decide whether Apple ID sign-in works: the on-device anisette
//  (ODA) toggle, the remote server list (AnisetteServersView, previously only
//  reachable from the old Settings screen), the client configuration editor
//  (AnisetteDataView — Client Info / User-Agent overrides), and the adi.pb
//  reset. The ODA toggle and the reset reuse the exact behavior of
//  UserCustomizationsView (sign out + restart for the toggle, sign out +
//  Keychain clear for the reset); this screen only re-homes them in the shell.
//
//  Copyright © 2026 oPenSSAI Contributors. All rights reserved.
//

import UIKit
import SwiftUI

final class AnisetteSettingsViewController: UIViewController
{
    private enum Section: Int, CaseIterable
    {
        case anisette
        case reset

        var title: String
        {
            switch self
            {
            case .anisette: return "Anisette"
            case .reset: return NSLocalizedString("Reset", comment: "")
            }
        }

        var footer: String
        {
            switch self
            {
            case .anisette:
                return NSLocalizedString("On-device Anisette runs ADI emulation directly on this device and does not use remote servers. When it is off, sign-in uses the server selected in the server list below.", comment: "")
            case .reset:
                return NSLocalizedString("Resetting signs you out of Apple ID and clears the provisioned adi.pb data from your Keychain. Your active signing certificate will be preserved.", comment: "")
            }
        }
    }

    private enum AnisetteRow: Int, CaseIterable { case onDevice, servers, clientConfig }
    private enum ResetRow: Int, CaseIterable { case resetAdiPb }

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

        navigationItem.title = NSLocalizedString("Anisette Settings", comment: "")
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.backButtonDisplayMode = .minimal

        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    override func viewWillAppear(_ animated: Bool)
    {
        super.viewWillAppear(animated)
        tableView.reloadData()
    }

    override var preferredStatusBarStyle: UIStatusBarStyle
    {
        return shellPreferredStatusBarStyle
    }

    // MARK: - Values

    private var selectedServerText: String?
    {
        let urlString = UserDefaults.standard.menuAnisetteURL
        guard let host = URL(string: urlString)?.host, !host.isEmpty else
        {
            return NSLocalizedString("Default", comment: "")
        }
        return host
    }

    // MARK: - Actions

    private func onDeviceAnisetteToggled(_ isOn: Bool)
    {
        // Mirrors UserCustomizationsView: changing the Anisette mode
        // invalidates the provisioned data, signs the user out, and needs a
        // restart. Nothing is written until the user confirms.
        let alertController = UIAlertController(
            title: NSLocalizedString("Restart Required", comment: ""),
            message: NSLocalizedString("Changing Anisette config will invalidate your current provisioned Anisette data and you will be signed out.\n\nThis action will require a restart, do you want to proceed?", comment: ""),
            preferredStyle: .alert
        )
        let restartAction = UIAlertAction(title: NSLocalizedString("Restart Now", comment: ""), style: .destructive) { _ in
            Task {
                await AuthManager.shared.signOut(keepCertificate: true, keepAnisetteData: false)
                UserDefaults.standard.useOnDeviceAnisette = isOn
                exit(0)
            }
        }
        let cancelAction = UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel) { [weak self] _ in
            // Revert the switch to the persisted value.
            self?.tableView.reloadData()
        }
        alertController.addAction(restartAction)
        alertController.addAction(cancelAction)
        present(alertController, animated: true)
    }

    private func serversRowTapped()
    {
        let serversView = AnisetteServersView(
            selected: UserDefaults.standard.menuAnisetteURL,
            onResetAdiPb: { [weak self] in
                guard let self = self else { return }
                let toastView = ToastView(
                    text: NSLocalizedString("Cleared adi.pb!", comment: ""),
                    detailText: NSLocalizedString("You will need to log back into Apple ID in oPenSSAI.", comment: ""))
                toastView.show(in: self)
            })
        let hostingController = ShellHostingController(rootView: serversView)
        hostingController.title = NSLocalizedString("Anisette Servers", comment: "")
        navigationController?.pushViewController(hostingController, animated: true)
    }

    private func clientConfigRowTapped()
    {
        // The Client Info / User-Agent override editor (AnisetteDataView).
        // Previously only reachable from the old Settings screen, which the
        // shell does not expose — so a manual client-info override was
        // impossible in 0704. Saving here writes customAnisetteClientInfo
        // to UserDefaults; the next sign-in uses it (still sanitized by
        // edgeSafeClientInfo before it is sent to Apple).
        let configView = AnisetteDataView()
        let hostingController = ShellHostingController(rootView: configView)
        hostingController.title = NSLocalizedString("Anisette Client Configuration", comment: "")
        navigationController?.pushViewController(hostingController, animated: true)
    }

    private func resetAdiPbTapped()
    {
        // Same flow as UserCustomizationsView.presentResetAdiDialog.
        let alertController = UIAlertController(
            title: NSLocalizedString("Reset adi.pb", comment: ""),
            message: NSLocalizedString("This will sign you out of Apple ID in oPenSSAI and clear the provisioned adi.pb data from your Keychain. Your active signing certificate will be preserved.", comment: ""),
            preferredStyle: .alert
        )
        let contentVC = ResetAdiAlertViewController()
        alertController.setValue(contentVC, forKey: "contentViewController")

        let cancelAction = UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel, handler: nil)
        let resetAction = UIAlertAction(title: NSLocalizedString("Reset & Sign Out", comment: ""), style: .destructive) { _ in
            let keepHeaders = contentVC.isKeepHeadersChecked
            Task {
                await AuthManager.shared.signOut(keepCertificate: true, keepAnisetteData: false, keepAnisetteHeaders: keepHeaders)
                debugLog("Reset adi.pb (keepAnisetteHeaders: \(keepHeaders)) and signed out")
                if let topVC = UIApplication.shared.topViewController() {
                    let detail = keepHeaders
                        ? NSLocalizedString("Signed out of Apple ID. You can now sign back in with fresh provisioning.", comment: "")
                        : NSLocalizedString("Signed out of Apple ID. Reset adi.pb and header configs to defaults.", comment: "")
                    ToastView(
                        text: NSLocalizedString("Cleared adi.pb!", comment: ""),
                        detailText: detail
                    ).show(in: topVC)
                }
            }
        }

        alertController.addAction(cancelAction)
        alertController.addAction(resetAction)
        present(alertController, animated: true)
    }
}

// MARK: - UITableViewDataSource / Delegate

extension AnisetteSettingsViewController: UITableViewDataSource, UITableViewDelegate
{
    func numberOfSections(in tableView: UITableView) -> Int
    {
        return Section.allCases.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int
    {
        switch Section(rawValue: section)
        {
        case .anisette: return AnisetteRow.allCases.count
        case .reset: return ResetRow.allCases.count
        case .none: return 0
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell
    {
        let cell = tableView.dequeueReusableCell(withIdentifier: SettingRowCell.reuseIdentifier, for: indexPath) as! SettingRowCell
        let rowCount = self.tableView(tableView, numberOfRowsInSection: indexPath.section)
        let position: ShellCardPosition
        if rowCount == 1 { position = .single }
        else if indexPath.row == 0 { position = .top }
        else if indexPath.row == rowCount - 1 { position = .bottom }
        else { position = .middle }
        cell.configureCardBackground(position: position)

        let accent = ShellTheme.accentColor

        switch Section(rawValue: indexPath.section)
        {
        case .anisette:
            switch AnisetteRow(rawValue: indexPath.row)
            {
            case .onDevice:
                cell.configureToggle(
                    iconSystemName: "cpu", iconTint: accent,
                    title: NSLocalizedString("On-Device Anisette", comment: ""),
                    isOn: UserDefaults.standard.useOnDeviceAnisette,
                    onToggleChanged: { [weak self] isOn in
                        self?.onDeviceAnisetteToggled(isOn)
                    })
            case .servers:
                cell.configure(
                    iconSystemName: "server.rack", iconTint: accent,
                    title: NSLocalizedString("Anisette Servers", comment: ""),
                    value: selectedServerText)
            case .clientConfig:
                cell.configure(
                    iconSystemName: "slider.horizontal.3", iconTint: accent,
                    title: NSLocalizedString("Anisette Client Configuration", comment: ""))
            case .none:
                break
            }

        case .reset:
            cell.configure(
                iconSystemName: "trash", iconTint: ShellTheme.expiredRed,
                title: NSLocalizedString("Reset adi.pb", comment: ""))

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
        case .anisette:
            switch AnisetteRow(rawValue: indexPath.row)
            {
            case .servers:
                serversRowTapped()
            case .clientConfig:
                clientConfigRowTapped()
            case .onDevice, .none:
                break
            }
        case .reset:
            resetAdiPbTapped()
        case .none:
            break
        }
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

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String?
    {
        guard let section = Section(rawValue: section) else { return nil }
        return section.footer
    }
}
#endif
