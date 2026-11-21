#if os(iOS)
//
//  LocationSimulationViewController.swift
//  oPenSSAI
//
//  The Virtual Location tab. Coordinates are sent to the Mac helper
//  (tools/location-helper), which drives the device's DVT location
//  simulation service; the simulated position is system-wide (Maps and
//  every app read it from locationd).
//  Coordinates can be typed in, picked from presets, dropped as a pin on
//  the embedded map, or found through address search; every path fills
//  the same coordinate fields and starts through the same helper flow.
//  Needs proper testing on a real device with the helper running.
//
//  Copyright © 2026 oPenSSAI Contributors. All rights reserved.
//

import MapKit
import UIKit

final class LocationSimulationViewController: UIViewController
{
    private enum Section: Int, CaseIterable
    {
        case status
        case coordinates
        case map
        case presets
        case control
        case helper

        var title: String
        {
            switch self
            {
            case .status: return NSLocalizedString("Current Status", comment: "")
            case .coordinates: return NSLocalizedString("Coordinates", comment: "")
            case .map: return NSLocalizedString("Map", comment: "")
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
            case .map:
                return NSLocalizedString("Tap the map to drop a pin, then start the simulation.", comment: "")
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
    private enum MapRow: Int, CaseIterable { case search, map }
    private enum ControlRow: Int, CaseIterable { case start, stop }
    private enum HelperRow: Int, CaseIterable { case address, test }

    private var latitudeText: String
    private var longitudeText: String
    private var status: LocationSimulationStatus?
    private var helperReachable: Bool?
    private var isWorking = false
    /// Display name of the place last picked from the map or search, if any.
    private var pickedPlaceName: String?
    /// The visible map cell, so coordinate edits elsewhere can move the pin.
    private weak var mapCell: MapPickerCell?

    private lazy var tableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .insetGrouped)
        tableView.backgroundColor = ShellTheme.background
        tableView.separatorColor = ShellTheme.separator
        tableView.register(SettingRowCell.self, forCellReuseIdentifier: SettingRowCell.reuseIdentifier)
        tableView.register(CoordinateInputCell.self, forCellReuseIdentifier: CoordinateInputCell.reuseIdentifier)
        tableView.register(MapPickerCell.self, forCellReuseIdentifier: MapPickerCell.reuseIdentifier)
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
        navigationItem.largeTitleDisplayMode = .always
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
        return shellPreferredStatusBarStyle
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

    /// Where the map centers when the screen opens: the coordinates already
    /// in the fields, else the last simulated location, else Yantai.
    private var initialCoordinate: CLLocationCoordinate2D
    {
        if let location = enteredLocation
        {
            return CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude)
        }
        if let lastLocation = LocationSimulationManager.shared.lastLocation
        {
            return CLLocationCoordinate2D(latitude: lastLocation.latitude, longitude: lastLocation.longitude)
        }
        let fallback = LocationPresets.all.first ?? SimulatedLocation(latitude: 37.54469, longitude: 121.36857, name: nil)
        return CLLocationCoordinate2D(latitude: fallback.latitude, longitude: fallback.longitude)
    }

    /// Biases address-search results toward the area the map is showing.
    private var searchRegion: MKCoordinateRegion
    {
        MKCoordinateRegion(center: initialCoordinate,
                           latitudinalMeters: 50_000, longitudinalMeters: 50_000)
    }

    /// Fills the coordinate fields from a picked place (preset, map pin, or
    /// search result) and moves the map pin to it. Starting the simulation
    /// still goes through the same Start button as typed coordinates.
    private func locationPicked(_ location: SimulatedLocation)
    {
        latitudeText = String(location.latitude)
        longitudeText = String(location.longitude)
        pickedPlaceName = location.name
        tableView.reloadSections(IndexSet(integer: Section.coordinates.rawValue), with: .none)
        tableView.reloadRows(at: [IndexPath(row: MapRow.search.rawValue, section: Section.map.rawValue)], with: .none)
        mapCell?.showPin(at: CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude),
                         title: location.name, centerMap: true, animated: true)
        ToastView(text: NSLocalizedString("Coordinates filled", comment: ""),
                  detailText: location.name.map { "\($0) · \(location.coordinateText)" } ?? location.coordinateText).show(in: self)
    }

    /// Moves the map pin to match the typed coordinates, without re-centering
    /// the map (re-centering on every keystroke would fight the user).
    private func syncMapPinToEnteredCoordinates()
    {
        guard let location = enteredLocation else { return }
        mapCell?.showPin(at: CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude),
                         title: nil, centerMap: false, animated: false)
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
            ToastView(text: NSLocalizedString("Invalid coordinates", comment: ""), detailText: nil).show(in: self)
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
                ToastView(text: NSLocalizedString("Location simulation stopped", comment: ""), detailText: nil).show(in: self)
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
        locationPicked(preset)
    }

    private func searchTapped()
    {
        view.endEditing(true)
        let searchViewController = LocationSearchViewController(region: searchRegion) { [weak self] location in
            self?.locationPicked(location)
        }
        navigationController?.pushViewController(searchViewController, animated: true)
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
        case .map: return MapRow.allCases.count
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
                    onTextChanged: { [weak self] text in
                        self?.latitudeText = text
                        self?.syncMapPinToEnteredCoordinates()
                    })
            case .longitude:
                cell.configure(
                    title: NSLocalizedString("Longitude", comment: ""),
                    text: longitudeText, placeholder: "121.36857",
                    onTextChanged: { [weak self] text in
                        self?.longitudeText = text
                        self?.syncMapPinToEnteredCoordinates()
                    })
            case .none:
                break
            }
            return cell
        }

        if Section(rawValue: indexPath.section) == .map, MapRow(rawValue: indexPath.row) == .map
        {
            let cell = tableView.dequeueReusableCell(withIdentifier: MapPickerCell.reuseIdentifier, for: indexPath) as! MapPickerCell
            cell.configureCardBackground(position: position)
            cell.configure(centerCoordinate: initialCoordinate,
                           pinCoordinate: enteredLocation.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) },
                           pinTitle: pickedPlaceName,
                           position: position) { [weak self] coordinate in
                // The pin's coordinate is used as-is (WGS-84). Inside China,
                // MapKit displays GCJ-02, so a dropped pin can be off by a
                // few hundred meters from the true WGS-84 spot — the same
                // offset the Coordinates footnote already warns about.
                self?.locationPicked(SimulatedLocation(latitude: coordinate.latitude,
                                                       longitude: coordinate.longitude, name: nil))
            }
            mapCell = cell
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

        case .map:
            cell.configure(
                iconSystemName: "magnifyingglass", iconTint: accent,
                title: NSLocalizedString("Search Address", comment: ""),
                value: pickedPlaceName)

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
        case .map:
            if MapRow(rawValue: indexPath.row) == .search
            {
                searchTapped()
            }
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

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat
    {
        if Section(rawValue: indexPath.section) == .map, MapRow(rawValue: indexPath.row) == .map
        {
            return 280
        }
        return tableView.rowHeight
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

// MARK: - Map picker cell

/// One tall row holding an MKMapView: tap to drop a pin, which fills the
/// coordinate fields through the same path as a preset. The map centers on
/// the current/last-used coordinate the first time it appears, and is left
/// alone afterwards so table reloads never yank the user's view.
/// User location is deliberately not shown: it would need a location
/// permission prompt and an Info.plist usage string for no benefit here.
/// Needs proper testing on a real device: tap-to-pin, pan/zoom inside the
/// table row, and the pin surviving cell reuse while scrolling.
private final class MapPickerCell: ShellCardCell
{
    static let reuseIdentifier = "MapPickerCell"

    private var onPinDropped: ((CLLocationCoordinate2D) -> Void)?
    private var hasSetInitialRegion = false
    private var pin: MKPointAnnotation?

    private lazy var mapView: MKMapView = {
        let mapView = MKMapView()
        mapView.mapType = .standard
        mapView.isRotateEnabled = false
        mapView.showsUserLocation = false
        mapView.layer.masksToBounds = true
        mapView.translatesAutoresizingMaskIntoConstraints = false

        let tap = UITapGestureRecognizer(target: self, action: #selector(mapTapped(_:)))
        mapView.addGestureRecognizer(tap)
        return mapView
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?)
    {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none

        contentView.addSubview(mapView)

        NSLayoutConstraint.activate([
            mapView.topAnchor.constraint(equalTo: contentView.topAnchor),
            mapView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            mapView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            mapView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
    }

    override func prepareForReuse()
    {
        super.prepareForReuse()
        onPinDropped = nil
    }

    func configure(centerCoordinate: CLLocationCoordinate2D,
                   pinCoordinate: CLLocationCoordinate2D?,
                   pinTitle: String?,
                   position: ShellCardPosition,
                   onPinDropped: @escaping (CLLocationCoordinate2D) -> Void)
    {
        self.onPinDropped = onPinDropped

        let radius = ShellTheme.cardCornerRadius
        let corners: CACornerMask
        switch position
        {
        case .top:
            corners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        case .middle:
            corners = []
        case .bottom:
            corners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        case .single:
            corners = [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        }
        mapView.layer.cornerRadius = corners.isEmpty ? 0 : radius
        mapView.layer.maskedCorners = corners

        if !hasSetInitialRegion
        {
            hasSetInitialRegion = true
            mapView.setRegion(MKCoordinateRegion(center: centerCoordinate,
                                                 latitudinalMeters: 50_000,
                                                 longitudinalMeters: 50_000),
                              animated: false)
        }
        if let pinCoordinate
        {
            showPin(at: pinCoordinate, title: pinTitle, centerMap: false, animated: false)
        }
    }

    /// Moves the (single) pin; optionally re-centers the map on it.
    func showPin(at coordinate: CLLocationCoordinate2D, title: String?, centerMap: Bool, animated: Bool)
    {
        if let pin
        {
            pin.coordinate = coordinate
            pin.title = title
        }
        else
        {
            let pin = MKPointAnnotation()
            pin.coordinate = coordinate
            pin.title = title
            mapView.addAnnotation(pin)
            self.pin = pin
        }
        if centerMap
        {
            mapView.setRegion(MKCoordinateRegion(center: coordinate,
                                                 latitudinalMeters: 50_000,
                                                 longitudinalMeters: 50_000),
                              animated: animated)
        }
    }

    @objc private func mapTapped(_ gesture: UITapGestureRecognizer)
    {
        let point = gesture.location(in: mapView)
        let coordinate = mapView.convert(point, toCoordinateFrom: mapView)
        guard CLLocationCoordinate2DIsValid(coordinate) else { return }
        showPin(at: coordinate, title: nil, centerMap: false, animated: true)
        onPinDropped?(coordinate)
    }
}

// MARK: - Address search

/// Address search for the virtual-location screen: type to get
/// MKLocalSearchCompleter suggestions, tap one to resolve it to coordinates
/// via MKLocalSearch and hand it back to the main screen, which fills the
/// coordinate fields and the map pin. Needs proper testing on a real device:
/// the completer needs network, and suggestion quality varies by region
/// (in mainland China, results come from AutoNavi through Apple's service).
private final class LocationSearchViewController: UIViewController
{
    private let region: MKCoordinateRegion
    private let onSelect: (SimulatedLocation) -> Void

    private var completions: [MKLocalSearchCompletion] = []
    private var isSearching = false

    private lazy var searchBar: UISearchBar = {
        let searchBar = UISearchBar()
        searchBar.placeholder = NSLocalizedString("Search for a place or address", comment: "")
        searchBar.searchBarStyle = .minimal
        searchBar.delegate = self
        searchBar.translatesAutoresizingMaskIntoConstraints = false
        return searchBar
    }()

    private lazy var tableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .plain)
        tableView.backgroundColor = ShellTheme.background
        tableView.separatorColor = ShellTheme.separator
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "CompletionCell")
        tableView.dataSource = self
        tableView.delegate = self
        tableView.keyboardDismissMode = .onDrag
        tableView.translatesAutoresizingMaskIntoConstraints = false
        return tableView
    }()

    private lazy var emptyLabel: UILabel = {
        let label = UILabel()
        label.font = ShellTheme.rowValueFont
        label.textColor = ShellTheme.secondaryText
        label.textAlignment = .center
        label.text = NSLocalizedString("No Results", comment: "")
        label.isHidden = true
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var completer: MKLocalSearchCompleter = {
        let completer = MKLocalSearchCompleter()
        completer.delegate = self
        completer.region = region
        return completer
    }()

    init(region: MKCoordinateRegion, onSelect: @escaping (SimulatedLocation) -> Void)
    {
        self.region = region
        self.onSelect = onSelect
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

        navigationItem.title = NSLocalizedString("Search Address", comment: "")
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.backButtonDisplayMode = .minimal

        view.addSubview(searchBar)
        view.addSubview(tableView)
        view.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            searchBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            searchBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            searchBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            tableView.topAnchor.constraint(equalTo: searchBar.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    override func viewDidAppear(_ animated: Bool)
    {
        super.viewDidAppear(animated)
        searchBar.becomeFirstResponder()
    }

    override var preferredStatusBarStyle: UIStatusBarStyle
    {
        return shellPreferredStatusBarStyle
    }

    private func updateEmptyState()
    {
        let hasQuery = !(searchBar.text ?? "").trimmingCharacters(in: .whitespaces).isEmpty
        emptyLabel.isHidden = !(hasQuery && completions.isEmpty)
    }

    private func resolve(_ completion: MKLocalSearchCompletion)
    {
        guard !isSearching else { return }
        isSearching = true
        view.endEditing(true)

        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isSearching = false }
            do
            {
                let request = MKLocalSearch.Request()
                request.naturalLanguageQuery = [completion.title, completion.subtitle]
                    .filter { !$0.isEmpty }.joined(separator: " ")
                request.region = self.region
                let response = try await MKLocalSearch(request: request).start()
                guard let mapItem = response.mapItems.first else
                {
                    throw LocationSimulationError.invalidResponse
                }
                let coordinate = mapItem.placemark.coordinate
                let location = SimulatedLocation(latitude: coordinate.latitude,
                                                 longitude: coordinate.longitude,
                                                 name: mapItem.name ?? completion.title)
                guard location.isValid else
                {
                    throw LocationSimulationError.invalidCoordinates
                }
                self.onSelect(location)
                self.navigationController?.popViewController(animated: true)
            }
            catch
            {
                ToastView(text: NSLocalizedString("Place lookup failed", comment: ""),
                          detailText: error.localizedDescription).show(in: self)
            }
        }
    }
}

extension LocationSearchViewController: UISearchBarDelegate
{
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String)
    {
        completer.queryFragment = searchText
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar)
    {
        searchBar.resignFirstResponder()
    }
}

extension LocationSearchViewController: MKLocalSearchCompleterDelegate
{
    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter)
    {
        completions = completer.results
        tableView.reloadData()
        updateEmptyState()
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error)
    {
        completions = []
        tableView.reloadData()
        updateEmptyState()
    }
}

extension LocationSearchViewController: UITableViewDataSource, UITableViewDelegate
{
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int
    {
        return completions.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell
    {
        let cell = tableView.dequeueReusableCell(withIdentifier: "CompletionCell", for: indexPath)
        let completion = completions[indexPath.row]

        var content = cell.defaultContentConfiguration()
        content.text = completion.title
        content.secondaryText = completion.subtitle
        content.textProperties.font = ShellTheme.rowTitleFont
        content.textProperties.color = ShellTheme.primaryText
        content.secondaryTextProperties.font = ShellTheme.rowValueFont
        content.secondaryTextProperties.color = ShellTheme.secondaryText
        cell.contentConfiguration = content
        cell.backgroundColor = .clear
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath)
    {
        tableView.deselectRow(at: indexPath, animated: true)
        resolve(completions[indexPath.row])
    }
}
#endif
