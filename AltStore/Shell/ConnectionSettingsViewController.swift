#if os(iOS)
//
//  ConnectionSettingsViewController.swift
//  oPenSSAI
//
//  The Connection screen, reachable from Me → Signing. It exposes the
//  connection mode the engine already supports: the LocalDev VPN loopback
//  or a direct connection to a remote server IP (for example through a
//  Shadowrocket 10.7.0.1/32 route), so sideloading works without LocalDev.
//
//  Mirrors ConnectionConfigView (SideStore/Views/Settings/Advanced/
//  Connection): edits are drafts until Save, saving writes them to
//  ConnectionConfig.shared and re-binds the config so minimuxer re-probes
//  reachability. Reachability itself is live engine state, pushed by
//  minimuxer via the binding callbacks — this screen only displays it.
//
//  Copyright © 2026 oPenSSAI Contributors. All rights reserved.
//

import UIKit
import Combine

final class ConnectionSettingsViewController: UIViewController
{
    private enum Section: Int, CaseIterable
    {
        case mode
        case remote
        case status

        var title: String
        {
            switch self
            {
            case .mode: return NSLocalizedString("Connection Mode", comment: "")
            case .remote: return NSLocalizedString("Remote Endpoint", comment: "")
            case .status: return NSLocalizedString("Connection Status", comment: "")
            }
        }

        var footer: String?
        {
            switch self
            {
            case .mode:
                return nil
            case .remote:
                return NSLocalizedString("Add a 10.7.0.1/32 route in Shadowrocket (via the WireGuard configuration) to sideload without turning on LocalDev.", comment: "")
            case .status:
                return NSLocalizedString("The status reflects the saved connection settings and updates automatically.", comment: "")
            }
        }
    }

    private let config = ConnectionConfig.shared
    private var cancellables = Set<AnyCancellable>()

    // Drafts, seeded from the shared config — mirroring the upstream
    // ConnectionConfigView, nothing is written until Save is tapped.
    private var draftUseLocalVPN: Bool = ConnectionConfig.shared.useLocalVPN
    private var draftRemoteServerIp: String = ConnectionConfig.shared.remoteServerIp

    /// Sections currently visible: the Remote Endpoint section only shows
    /// while the draft mode is Remote Direct.
    private var visibleSections: [Section]
    {
        draftUseLocalVPN ? [.mode, .status] : [.mode, .remote, .status]
    }

    private lazy var tableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .insetGrouped)
        tableView.backgroundColor = ShellTheme.background
        tableView.separatorColor = ShellTheme.separator
        tableView.register(SettingRowCell.self, forCellReuseIdentifier: SettingRowCell.reuseIdentifier)
        tableView.register(ConnectionModeCell.self, forCellReuseIdentifier: ConnectionModeCell.reuseIdentifier)
        tableView.register(ConnectionTextFieldCell.self, forCellReuseIdentifier: ConnectionTextFieldCell.reuseIdentifier)
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

        navigationItem.title = NSLocalizedString("Connection Settings", comment: "")
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.backButtonDisplayMode = .minimal
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: NSLocalizedString("Save", comment: ""),
            style: .done, target: self, action: #selector(saveTapped))

        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        observeConfigChanges()
    }

    override func viewWillAppear(_ animated: Bool)
    {
        super.viewWillAppear(animated)
        tableView.reloadData()
        refreshReachability()
    }

    override var preferredStatusBarStyle: UIStatusBarStyle
    {
        return .lightContent
    }

    // MARK: - Reachability

    private func observeConfigChanges()
    {
        config.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                // objectWillChange fires before the new value lands; defer
                // the reload so the status row reads the updated value.
                // Only the status row reloads, so an in-progress IP edit
                // is never disturbed.
                DispatchQueue.main.async { [weak self] in
                    self?.reloadStatusRow()
                }
            }
            .store(in: &cancellables)
    }

    private func reloadStatusRow()
    {
        guard let sectionIndex = visibleSections.firstIndex(of: .status) else { return }
        tableView.reloadRows(at: [IndexPath(row: 0, section: sectionIndex)], with: .none)
    }

    private func refreshReachability()
    {
        // Re-probe the current endpoint: minimuxer re-scans the interfaces
        // (local mode) or TCP-probes the remote server (remote mode) and
        // pushes fresh reachability into ConnectionConfig.shared, which the
        // objectWillChange subscription turns into a status-row reload.
        Task {
            await minimuxer.network.refreshEndpoint()
        }
    }

    /// The reachability row's text and color for the *saved* connection
    /// mode — reachability is live engine state, so it follows the
    /// committed settings, not the draft. Mirrors the upstream view: in
    /// local mode with no discovered peer, the status is N/A.
    private var reachableStatus: (text: String, color: UIColor)
    {
        if config.useLocalVPN
        {
            guard let peerIp = config.tunnelPeerIp, !peerIp.isEmpty else
            {
                return ("N/A", .systemGray)
            }
            return config.tunnelPeerReachable
                ? (NSLocalizedString("Yes", comment: ""), .systemGreen)
                : (NSLocalizedString("No", comment: ""), .systemRed)
        }
        return config.remoteReachable
            ? (NSLocalizedString("Yes", comment: ""), .systemGreen)
            : (NSLocalizedString("No", comment: ""), .systemRed)
    }

    // MARK: - Actions

    private func modeChanged(_ useLocalVPN: Bool)
    {
        guard useLocalVPN != draftUseLocalVPN else { return }
        draftUseLocalVPN = useLocalVPN
        view.endEditing(true)
        tableView.reloadData()
    }

    @objc private func saveTapped()
    {
        view.endEditing(true)

        let trimmedIp = draftRemoteServerIp.trimmingCharacters(in: .whitespacesAndNewlines)
        if !draftUseLocalVPN && trimmedIp.isEmpty
        {
            // Mirrors the upstream validation: the remote IP is mandatory
            // in remote mode.
            let alertController = UIAlertController(
                title: NSLocalizedString("Invalid Configuration", comment: ""),
                message: NSLocalizedString("Remote server IP is required in Remote Direct mode.", comment: ""),
                preferredStyle: .alert)
            alertController.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default))
            present(alertController, animated: true)
            return
        }

        config.useLocalVPN = draftUseLocalVPN
        config.remoteServerIp = trimmedIp

        // Mirror the upstream Confirm: re-bind so minimuxer picks up the
        // new mode/IP and re-probes reachability.
        Task { @MainActor [weak self] in
            await bindConnectionConfig()
            guard let self else { return }
            ToastView(text: NSLocalizedString("Changes saved", comment: ""), detailText: nil).show(in: self)
            self.tableView.reloadData()
        }
    }
}

// MARK: - UITableViewDataSource / Delegate

extension ConnectionSettingsViewController: UITableViewDataSource, UITableViewDelegate
{
    func numberOfSections(in tableView: UITableView) -> Int
    {
        return visibleSections.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int
    {
        return 1
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell
    {
        switch visibleSections[indexPath.section]
        {
        case .mode:
            let cell = tableView.dequeueReusableCell(withIdentifier: ConnectionModeCell.reuseIdentifier, for: indexPath) as! ConnectionModeCell
            cell.configureCardBackground(position: .single)
            cell.configure(
                useLocalVPN: draftUseLocalVPN,
                onModeChanged: { [weak self] useLocalVPN in
                    self?.modeChanged(useLocalVPN)
                })
            return cell

        case .remote:
            let cell = tableView.dequeueReusableCell(withIdentifier: ConnectionTextFieldCell.reuseIdentifier, for: indexPath) as! ConnectionTextFieldCell
            cell.configureCardBackground(position: .single)
            cell.configure(
                title: NSLocalizedString("Remote Server IP", comment: ""),
                text: draftRemoteServerIp,
                placeholder: AppConstants.Connection.defaultRemoteServerIP,
                onTextChanged: { [weak self] text in
                    self?.draftRemoteServerIp = text
                })
            return cell

        case .status:
            let cell = tableView.dequeueReusableCell(withIdentifier: SettingRowCell.reuseIdentifier, for: indexPath) as! SettingRowCell
            cell.configureCardBackground(position: .single)
            let status = reachableStatus
            cell.configureInfo(
                iconSystemName: "network", iconTint: ShellTheme.accentColor,
                title: NSLocalizedString("Reachable", comment: ""),
                value: status.text,
                valueColor: status.color)
            return cell
        }
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView?
    {
        let section = visibleSections[section]

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
        return visibleSections[section].footer
    }
}

// MARK: - Mode switch cell

/// One mode row: a segmented control switching between Local VPN and
/// Remote Direct.
private final class ConnectionModeCell: ShellCardCell
{
    static let reuseIdentifier = "ConnectionModeCell"

    private var onModeChanged: ((Bool) -> Void)?

    private lazy var segmentedControl: UISegmentedControl = {
        let control = UISegmentedControl(items: [
            NSLocalizedString("Local VPN", comment: ""),
            NSLocalizedString("Remote Direct", comment: ""),
        ])
        control.addTarget(self, action: #selector(modeChanged(_:)), for: .valueChanged)
        control.translatesAutoresizingMaskIntoConstraints = false
        return control
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?)
    {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none

        contentView.addSubview(segmentedControl)

        NSLayoutConstraint.activate([
            segmentedControl.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            segmentedControl.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            segmentedControl.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            segmentedControl.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),
        ])
    }

    override func prepareForReuse()
    {
        super.prepareForReuse()
        onModeChanged = nil
    }

    func configure(useLocalVPN: Bool, onModeChanged: @escaping (Bool) -> Void)
    {
        segmentedControl.selectedSegmentIndex = useLocalVPN ? 0 : 1
        self.onModeChanged = onModeChanged
    }

    @objc private func modeChanged(_ sender: UISegmentedControl)
    {
        onModeChanged?(sender.selectedSegmentIndex == 0)
    }
}

// MARK: - Remote server IP input cell

/// One IP row: a title on the left, an IP text field on the right, with a
/// Done button above the keyboard. Mirrors CoordinateInputCell in
/// LocationSimulationViewController; the character filter matches the
/// upstream ConnectionConfigView (digits, letters, . : % _).
private final class ConnectionTextFieldCell: ShellCardCell
{
    static let reuseIdentifier = "ConnectionTextFieldCell"

    private var onTextChanged: ((String) -> Void)?

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = ShellTheme.rowTitleFont
        label.textColor = ShellTheme.primaryText
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var textField: UITextField = {
        let textField = UITextField()
        textField.font = ShellTheme.rowValueFont
        textField.textColor = ShellTheme.primaryText
        textField.textAlignment = .right
        textField.keyboardType = .numbersAndPunctuation
        textField.autocapitalizationType = .none
        textField.autocorrectionType = .no
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.addTarget(self, action: #selector(textChanged), for: .editingChanged)

        let toolbar = UIToolbar()
        toolbar.sizeToFit()
        let done = UIBarButtonItem(
            title: NSLocalizedString("Done", comment: ""),
            style: .done, target: self, action: #selector(doneTapped))
        toolbar.items = [
            UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil),
            done,
        ]
        textField.inputAccessoryView = toolbar
        return textField
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?)
    {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none

        contentView.addSubview(titleLabel)
        contentView.addSubview(textField)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            titleLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            titleLabel.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor, constant: 14),
            titleLabel.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -14),

            textField.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 12),
            textField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            textField.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            textField.widthAnchor.constraint(greaterThanOrEqualToConstant: 140),
        ])
    }

    override func prepareForReuse()
    {
        super.prepareForReuse()
        onTextChanged = nil
    }

    func configure(title: String, text: String?, placeholder: String, onTextChanged: @escaping (String) -> Void)
    {
        titleLabel.text = title
        textField.text = text
        textField.placeholder = placeholder
        self.onTextChanged = onTextChanged
    }

    @objc private func textChanged()
    {
        let raw = textField.text ?? ""
        let filtered = raw.filter { "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ.:%_".contains($0) }
        if filtered != raw
        {
            textField.text = filtered
        }
        onTextChanged?(filtered)
    }

    @objc private func doneTapped()
    {
        textField.resignFirstResponder()
    }
}
#endif
