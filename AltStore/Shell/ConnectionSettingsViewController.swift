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
//  Changes apply IMMEDIATELY: flipping the mode writes
//  ConnectionConfig.shared.useLocalVPN at once and re-binds the config so
//  minimuxer re-probes reachability for the new mode. (0707 used
//  draft+Save semantics; the engine stayed in localVPN mode when the user
//  never tapped Save, so Shadowrocket sideloading kept failing with the
//  localVPN "tunnel peer IP is not yet reachable" error.) The remote IP
//  commits when its field ends editing. The status section shows the
//  current effective mode + endpoint IP and its reachability, pushed live
//  by minimuxer via the binding callbacks.
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
                return NSLocalizedString("Changes apply immediately; the status updates automatically.", comment: "")
            }
        }
    }

    private let config = ConnectionConfig.shared
    private var cancellables = Set<AnyCancellable>()

    /// Sections currently visible: the Remote Endpoint section only shows
    /// while the effective mode is Remote Direct.
    private var visibleSections: [Section]
    {
        config.useLocalVPN ? [.mode, .status] : [.mode, .remote, .status]
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
        // No Save button: the mode applies on toggle and the IP commits on
        // end-editing (see the header comment).

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
                // the reload so the status rows read the updated values.
                // Only the status rows reload, so an in-progress IP edit
                // is never disturbed.
                DispatchQueue.main.async { [weak self] in
                    self?.reloadStatusRows()
                }
            }
            .store(in: &cancellables)
    }

    private func reloadStatusRows()
    {
        guard let sectionIndex = visibleSections.firstIndex(of: .status) else { return }
        tableView.reloadRows(
            at: [IndexPath(row: 0, section: sectionIndex),
                 IndexPath(row: 1, section: sectionIndex)],
            with: .none)
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

    /// The current effective mode + endpoint IP, e.g. "远程直连 · 10.7.0.1".
    /// This is the mode the engine is actually using — not a draft.
    private var currentModeText: String
    {
        let modeName = config.useLocalVPN
            ? NSLocalizedString("Local VPN", comment: "")
            : NSLocalizedString("Remote Direct", comment: "")
        if let endpointIp = config.effectiveEndpointIp, !endpointIp.isEmpty
        {
            return "\(modeName) · \(endpointIp)"
        }
        return modeName
    }

    /// The reachability row's text and color for the effective mode.
    /// Reachability is live engine state; in local mode with no discovered
    /// peer yet, the status is N/A.
    private var reachableStatus: (text: String, color: UIColor)
    {
        guard let reachable = config.effectiveEndpointReachable else
        {
            return ("N/A", ShellTheme.secondaryText)
        }
        return reachable
            ? (NSLocalizedString("Yes", comment: ""), .systemGreen)
            : (NSLocalizedString("No", comment: ""), ShellTheme.expiredRed)
    }

    // MARK: - Actions

    /// Re-binds the live config so minimuxer picks up the new mode/IP and
    /// re-probes reachability. bindConnectionConfig already triggers a
    /// refreshEndpoint inside the engine; the explicit second refresh is a
    /// no-op once the state settles, and guarantees the status rows are
    /// re-probed even if the bind path changes.
    private func applyConnectionSettings()
    {
        Task {
            await bindConnectionConfig()
            await minimuxer.network.refreshEndpoint()
        }
    }

    private func modeChanged(_ useLocalVPN: Bool)
    {
        guard useLocalVPN != config.useLocalVPN else { return }
        view.endEditing(true)

        // Apply immediately: writing the shared config persists the mode
        // (didSet -> UserDefaults) and the engine binding reads it live,
        // so the next bind + probe runs in the new mode.
        config.useLocalVPN = useLocalVPN
        tableView.reloadData()
        applyConnectionSettings()

        if !useLocalVPN && config.remoteServerIp.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            // Remote mode needs an IP; the switch still takes effect and
            // the IP field is now visible — prompt for the address instead
            // of silently reverting the tap.
            showEmptyRemoteIPAlert()
        }
        else
        {
            let modeName = useLocalVPN
                ? NSLocalizedString("Local VPN", comment: "")
                : NSLocalizedString("Remote Direct", comment: "")
            ToastView(text: String(format: NSLocalizedString("Switched to %@", comment: ""), modeName), detailText: nil).show(in: self)
        }
    }

    /// Commits the remote IP when its field ends editing. An empty value is
    /// refused in remote mode (the field restores the previous value); the
    /// mode switch stays available, so the user is never stuck.
    private func remoteIPCommitted(_ text: String)
    {
        let trimmedIp = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedIp != config.remoteServerIp else { return }

        if !config.useLocalVPN && trimmedIp.isEmpty
        {
            showEmptyRemoteIPAlert()
            tableView.reloadData()
            return
        }

        config.remoteServerIp = trimmedIp
        tableView.reloadData()
        applyConnectionSettings()
    }

    private func showEmptyRemoteIPAlert()
    {
        // Mirrors the upstream validation: the remote IP is mandatory in
        // remote mode.
        let alertController = UIAlertController(
            title: NSLocalizedString("Invalid Configuration", comment: ""),
            message: NSLocalizedString("Remote server IP is required in Remote Direct mode.", comment: ""),
            preferredStyle: .alert)
        alertController.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default))
        present(alertController, animated: true)
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
        // The status section shows the current mode and its reachability.
        return visibleSections[section] == .status ? 2 : 1
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell
    {
        switch visibleSections[indexPath.section]
        {
        case .mode:
            let cell = tableView.dequeueReusableCell(withIdentifier: ConnectionModeCell.reuseIdentifier, for: indexPath) as! ConnectionModeCell
            cell.configureCardBackground(position: .single)
            cell.configure(
                useLocalVPN: config.useLocalVPN,
                onModeChanged: { [weak self] useLocalVPN in
                    self?.modeChanged(useLocalVPN)
                })
            return cell

        case .remote:
            let cell = tableView.dequeueReusableCell(withIdentifier: ConnectionTextFieldCell.reuseIdentifier, for: indexPath) as! ConnectionTextFieldCell
            cell.configureCardBackground(position: .single)
            cell.configure(
                title: NSLocalizedString("Remote Server IP", comment: ""),
                text: config.remoteServerIp,
                placeholder: AppConstants.Connection.defaultRemoteServerIP,
                onEditingEnded: { [weak self] text in
                    self?.remoteIPCommitted(text)
                })
            return cell

        case .status:
            let cell = tableView.dequeueReusableCell(withIdentifier: SettingRowCell.reuseIdentifier, for: indexPath) as! SettingRowCell
            cell.configureCardBackground(position: indexPath.row == 0 ? .top : .bottom)
            if indexPath.row == 0
            {
                cell.configureInfo(
                    iconSystemName: "arrow.left.arrow.right", iconTint: ShellTheme.accentColor,
                    title: NSLocalizedString("Current Mode", comment: ""),
                    value: currentModeText)
            }
            else
            {
                let status = reachableStatus
                cell.configureInfo(
                    iconSystemName: "network", iconTint: ShellTheme.accentColor,
                    title: NSLocalizedString("Reachable", comment: ""),
                    value: status.text,
                    valueColor: status.color)
            }
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
/// Remote Direct. The switch applies immediately (see the header comment).
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
/// upstream ConnectionConfigView (digits, letters, . : % _). The value
/// commits when editing ends (Done, Return, or tapping elsewhere) — not on
/// every keystroke, so a half-typed address never reaches the engine.
private final class ConnectionTextFieldCell: ShellCardCell
{
    static let reuseIdentifier = "ConnectionTextFieldCell"

    private var onEditingEnded: ((String) -> Void)?

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
        textField.addTarget(self, action: #selector(editingEnded), for: .editingDidEnd)
        textField.addTarget(self, action: #selector(editingEnded), for: .editingDidEndOnExit)

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
        onEditingEnded = nil
    }

    func configure(title: String, text: String?, placeholder: String, onEditingEnded: @escaping (String) -> Void)
    {
        titleLabel.text = title
        textField.text = text
        textField.placeholder = placeholder
        self.onEditingEnded = onEditingEnded
    }

    @objc private func textChanged()
    {
        // Input filter only; the value commits on editing end.
        let raw = textField.text ?? ""
        let filtered = raw.filter { "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ.:%_".contains($0) }
        if filtered != raw
        {
            textField.text = filtered
        }
    }

    @objc private func editingEnded()
    {
        onEditingEnded?(textField.text ?? "")
    }

    @objc private func doneTapped()
    {
        textField.resignFirstResponder()
    }
}
#endif
