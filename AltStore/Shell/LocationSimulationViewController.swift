#if os(iOS)
//
//  LocationSimulationViewController.swift
//  oPenSSAI
//
//  The Virtual Location screen, reachable from Me → Virtual Location.
//  Coordinates are sent to the Mac helper (tools/location-helper), which
//  drives the device's DVT location simulation service; the simulated
//  position is system-wide (Maps and every app read it from locationd).
//  Needs proper testing on a real device with the helper running.
//
//  Copyright © 2026 oPenSSAI Contributors. All rights reserved.
//

import UIKit

final class LocationSimulationViewController: UIViewController
{
    private enum Section: Int, CaseIterable
    {
        case status
        case coordinates
        case presets
        case control
        case helper

        var title: String
        {
            switch self
            {
            case .status: return NSLocalizedString("Current Status", comment: "")
            case .coordinates: return NSLocalizedString("Coordinates", comment: "")
            case .presets: return NSLocalizedString("Preset Locations", comment: "")
            case .control: return NSLocalizedString("Virtual Location", comment: "")
            case .helper: return NSLocalizedString("Location Helper", comment: "")
            }
        }

        var footer: String?
        {
            switch self
            {
            case .status:
                return NSLocalizedString("The simulated location is delivered to this device by the location-helper on your Mac (Apple's DVT developer service) and applies system-wide. Stop and restore the real location when you are done.", comment: "")
            case .coordinates:
                return NSLocalizedString("Coordinates are WGS-84. Places inside China may appear offset by a few hundred meters in Apple Maps (GCJ-02 coordinate difference); this is normal.", comment: "")
            case .presets:
                return nil
            case .control:
                return nil
            case .helper:
                return NSLocalizedString("Run tools/location-helper on your Mac (see the repository README), keep the phone and the Mac on the same local network, and enter the Mac's local IP address and port here.", comment: "")
            }
        }
    }

    private enum StatusRow: Int, CaseIterable { case simulation, helper }
    private enum CoordinateRow: Int, CaseIterable { case latitude, longitude }
    private enum ControlRow: Int, CaseIterable { case start, stop }
    private enum HelperRow: Int, CaseIterable { case address, test }

    private var latitudeText: String
    private var longitudeText: String
    private var status: LocationSimulationStatus?
    private var helperReachable: Bool?
    private var isWorking = false

    private lazy var tableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .insetGrouped)
        tableView.backgroundColor = ShellTheme.background
        tableView.separatorColor = ShellTheme.separator
        tableView.register(SettingRowCell.self, forCellReuseIdentifier: SettingRowCell.reuseIdentifier)
        tableView.register(CoordinateInputCell.self, forCellReuseIdentifier: CoordinateInputCell.reuseIdentifier)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.sectionHeaderTopPadding = 0
        tableView.keyboardDismissMode = .onDrag
        tableView.translatesAutoresizingMaskIntoConstraints = false
        return tableView
    }()

    private lazy var spinnerItem: UIBarButtonItem = {
        let spinner = UIActivityIndicatorView(style: .medium)
        spinner.startAnimating()
        return UIBarButtonItem(customView: spinner)
    }()

    init()
    {
        let lastLocation = LocationSimulationManager.shared.lastLocation
        self.latitudeText = lastLocation.map { String($0.latitude) } ?? ""
        self.longitudeText = lastLocation.map { String($0.longitude) } ?? ""
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

        navigationItem.title = NSLocalizedString("Virtual Location", comment: "")
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
        refreshStatus()
    }

    override var preferredStatusBarStyle: UIStatusBarStyle
    {
        return .lightContent
    }

    // MARK: - Values

    private var statusText: String
    {
        guard let status else
        {
            return NSLocalizedString("Not Tested", comment: "")
        }
        if status.active, let location = status.location
        {
            return "\(NSLocalizedString("Simulating", comment: "")) · \(location.coordinateText)"
        }
        if !status.connected
        {
            return NSLocalizedString("Connection Failed", comment: "")
        }
        return NSLocalizedString("Not Started", comment: "")
    }

    private var helperText: String
    {
        guard let helperReachable else
        {
            return NSLocalizedString("Not Tested", comment: "")
        }
        return helperReachable
            ? NSLocalizedString("Connected", comment: "")
            : NSLocalizedString("Connection Failed", comment: "")
    }

    private var enteredLocation: SimulatedLocation?
    {
        guard let latitude = Double(latitudeText.trimmingCharacters(in: .whitespaces)),
              let longitude = Double(longitudeText.trimmingCharacters(in: .whitespaces)) else
        {
            return nil
        }
        let location = SimulatedLocation(latitude: latitude, longitude: longitude, name: nil)
        return location.isValid ? location : nil
    }

    private func setWorking(_ working: Bool)
    {
        isWorking = working
        navigationItem.rightBarButtonItem = working ? spinnerItem : nil
    }

    // MARK: - Actions

    private func refreshStatus()
    {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let fetched = await LocationSimulationManager.shared.refreshStatus()
            self.status = fetched ?? LocationSimulationManager.shared.lastStatus
            self.helperReachable = fetched != nil
            self.tableView.reloadData()
        }
    }

    private func startTapped()
    {
        guard !isWorking else { return }
        guard let location = enteredLocation else
        {
            ToastView(text: NSLocalizedString("Invalid coordinates", comment: "")).show(in: self)
            return
        }
        view.endEditing(true)
        setWorking(true)
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.setWorking(false) }
            do
            {
                let service = try LocationSimulationManager.shared.makeService()
                try await service.setLocation(location)
                LocationSimulationManager.shared.lastLocation = location
                ToastView(text: NSLocalizedString("Location simulation started", comment: ""),
                          detailText: location.coordinateText).show(in: self)
            }
            catch
            {
                ToastView(error: error).show(in: self.view)
            }
            self.refreshStatus()
        }
    }

    private func stopTapped()
    {
        guard !isWorking else { return }
        view.endEditing(true)
        setWorking(true)
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.setWorking(false) }
            do
            {
                let service = try LocationSimulationManager.shared.makeService()
                try await service.clearLocation()
                ToastView(text: NSLocalizedString("Location simulation stopped", comment: "")).show(in: self)
            }
            catch
            {
                ToastView(error: error).show(in: self.view)
            }
            self.refreshStatus()
        }
    }

    private func presetTapped(_ preset: SimulatedLocation)
    {
        view.endEditing(true)
        latitudeText = String(preset.latitude)
        longitudeText = String(preset.longitude)
        tableView.reloadSections(IndexSet(integer: Section.coordinates.rawValue), with: .none)
        ToastView(text: NSLocalizedString("Coordinates filled", comment: ""),
                  detailText: preset.name.map { "\($0) · \(preset.coordinateText)" } ?? preset.coordinateText).show(in: self)
    }

    private func addressTapped()
    {
        let manager = LocationSimulationManager.shared
        let alert = UIAlertController(
            title: NSLocalizedString("Helper Address", comment: ""),
            message: NSLocalizedString("Enter Helper Address", comment: ""),
            preferredStyle: .alert
        )
        alert.addTextField { textField in
            textField.text = manager.helperAddress
            textField.placeholder = "192.168.1.5:\(LocationSimulationManager.defaultHelperPort)"
            textField.keyboardType = .numbersAndPunctuation
            textField.autocapitalizationType = .none
            textField.autocorrectionType = .no
        }
        alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel))
        alert.addAction(UIAlertAction(title: NSLocalizedString("Save", comment: ""), style: .default) { [weak self] _ in
            let text = alert.textFields?.first?.text ?? ""
            manager.helperAddress = text.trimmingCharacters(in: .whitespacesAndNewlines)
            self?.refreshStatus()
        })
        present(alert, animated: true)
    }

    private func testConnectionTapped()
    {
        guard !isWorking else { return }
        setWorking(true)
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.setWorking(false) }
            do
            {
                let service = try LocationSimulationManager.shared.makeService()
                let fetched = try await service.fetchStatus()
                self.status = fetched
                self.helperReachable = true
                ToastView(text: NSLocalizedString("Connected", comment: ""),
                          detailText: fetched.active
                            ? "\(NSLocalizedString("Simulating", comment: "")) · \(fetched.location?.coordinateText ?? "")"
                            : NSLocalizedString("Not Started", comment: "")).show(in: self)
            }
            catch
            {
                self.helperReachable = false
                ToastView(error: error).show(in: self.view)
            }
            self.tableView.reloadData()
        }
    }
}

// MARK: - UITableViewDataSource / Delegate

extension LocationSimulationViewController: UITableViewDataSource, UITableViewDelegate
{
    func numberOfSections(in tableView: UITableView) -> Int
    {
        return Section.allCases.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int
    {
        switch Section(rawValue: section)
        {
        case .status: return StatusRow.allCases.count
        case .coordinates: return CoordinateRow.allCases.count
        case .presets: return LocationPresets.all.count
        case .control: return ControlRow.allCases.count
        case .helper: return HelperRow.allCases.count
        case .none: return 0
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell
    {
        let rowCount = self.tableView(tableView, numberOfRowsInSection: indexPath.section)
        let position: ShellCardPosition
        if rowCount == 1 { position = .single }
        else if indexPath.row == 0 { position = .top }
        else if indexPath.row == rowCount - 1 { position = .bottom }
        else { position = .middle }

        if Section(rawValue: indexPath.section) == .coordinates
        {
            let cell = tableView.dequeueReusableCell(withIdentifier: CoordinateInputCell.reuseIdentifier, for: indexPath) as! CoordinateInputCell
            cell.configureCardBackground(position: position)
            switch CoordinateRow(rawValue: indexPath.row)
            {
            case .latitude:
                cell.configure(
                    title: NSLocalizedString("Latitude", comment: ""),
                    text: latitudeText, placeholder: "37.54469",
                    onTextChanged: { [weak self] text in self?.latitudeText = text })
            case .longitude:
                cell.configure(
                    title: NSLocalizedString("Longitude", comment: ""),
                    text: longitudeText, placeholder: "121.36857",
                    onTextChanged: { [weak self] text in self?.longitudeText = text })
            case .none:
                break
            }
            return cell
        }

        let cell = tableView.dequeueReusableCell(withIdentifier: SettingRowCell.reuseIdentifier, for: indexPath) as! SettingRowCell
        cell.configureCardBackground(position: position)

        let accent = ShellTheme.accentColor

        switch Section(rawValue: indexPath.section)
        {
        case .status:
            switch StatusRow(rawValue: indexPath.row)
            {
            case .simulation:
                cell.configureInfo(
                    iconSystemName: "location.fill", iconTint: accent,
                    title: NSLocalizedString("Current Status", comment: ""),
                    value: statusText)
            case .helper:
                cell.configureInfo(
                    iconSystemName: "server.rack", iconTint: accent,
                    title: NSLocalizedString("Location Helper", comment: ""),
                    value: helperText)
            case .none:
                break
            }

        case .presets:
            let preset = LocationPresets.all[indexPath.row]
            cell.configureInfo(
                iconSystemName: "mappin", iconTint: accent,
                title: preset.name ?? preset.coordinateText,
                value: preset.coordinateText)

        case .control:
            switch ControlRow(rawValue: indexPath.row)
            {
            case .start:
                cell.configure(
                    iconSystemName: "play.fill", iconTint: accent,
                    title: NSLocalizedString("Start Simulation", comment: ""))
            case .stop:
                cell.configure(
                    iconSystemName: "stop.fill", iconTint: ShellTheme.expiredRed,
                    title: NSLocalizedString("Stop & Restore Real Location", comment: ""))
            case .none:
                break
            }

        case .helper:
            switch HelperRow(rawValue: indexPath.row)
            {
            case .address:
                let address = LocationSimulationManager.shared.helperAddress
                cell.configure(
                    iconSystemName: "desktopcomputer", iconTint: accent,
                    title: NSLocalizedString("Helper Address", comment: ""),
                    value: address.isEmpty ? NSLocalizedString("Not Set", comment: "") : address)
            case .test:
                cell.configure(
                    iconSystemName: "bolt", iconTint: accent,
                    title: NSLocalizedString("Test Connection", comment: ""))
            case .none:
                break
            }

        case .coordinates, .none:
            break
        }

        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath)
    {
        tableView.deselectRow(at: indexPath, animated: true)

        switch Section(rawValue: indexPath.section)
        {
        case .presets:
            presetTapped(LocationPresets.all[indexPath.row])
        case .control:
            switch ControlRow(rawValue: indexPath.row)
            {
            case .start: startTapped()
            case .stop: stopTapped()
            case .none: break
            }
        case .helper:
            switch HelperRow(rawValue: indexPath.row)
            {
            case .address: addressTapped()
            case .test: testConnectionTapped()
            case .none: break
            }
        case .status, .coordinates, .none:
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

// MARK: - Coordinate input cell

/// One coordinate row: a title on the left, a decimal-pad text field on the
/// right, with a Done button above the keyboard.
private final class CoordinateInputCell: ShellCardCell
{
    static let reuseIdentifier = "CoordinateInputCell"

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
        textField.keyboardType = .decimalPad
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
        onTextChanged?(textField.text ?? "")
    }

    @objc private func doneTapped()
    {
        textField.resignFirstResponder()
    }
}
#endif
