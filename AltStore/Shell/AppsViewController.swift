#if os(iOS)
//
//  AppsViewController.swift
//  oPenSSAI
//
//  The Apps tab: large "oPenSSAI" title, a + button, segmented
//  Pending / Installed tabs, a heading row with a Renew All pill, and the
//  card list of apps (icon, name + version, bundle ID, days left).
//  Installed apps come from Core Data; pending apps from PendingIPAStore.
//  Install / refresh / re-sign / reinstall / delete all go through the
//  existing AppManager engine, mirroring MyAppsViewController's flows.
//
//  Copyright © 2026 oPenSSAI Contributors. All rights reserved.
//

import UIKit
import CoreData
import UniformTypeIdentifiers

final class AppsViewController: UIViewController
{
    private enum Tab
    {
        case pending
        case installed
    }

    private enum Section
    {
        case apps
    }

    private var selectedTab: Tab = .installed
    private var isRefreshingAll = false

    private let iconCache = NSCache<NSString, UIImage>()

    private lazy var fetchedResultsController: NSFetchedResultsController<InstalledApp> = {
        let request = InstalledApp.fetchRequest()
        request.predicate = NSPredicate(format: "%K == YES", #keyPath(InstalledApp.isActive))
        request.sortDescriptors = [NSSortDescriptor(keyPath: \InstalledApp.name, ascending: true)]
        let controller = NSFetchedResultsController(
            fetchRequest: request,
            managedObjectContext: DatabaseManager.shared.viewContext,
            sectionNameKeyPath: nil,
            cacheName: nil
        )
        controller.delegate = self
        return controller
    }()

    private var installedApps: [InstalledApp]
    {
        fetchedResultsController.fetchedObjects ?? []
    }

    private var pendingApps: [PendingIPA]
    {
        PendingIPAStore.shared.items
    }

    // MARK: - Views

    private lazy var segmentedTabsView = SegmentedTabsView(
        onSelect: { [weak self] tab in
            self?.selectTab(tab == 0 ? .pending : .installed)
        }
    )

    private lazy var tableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .insetGrouped)
        tableView.backgroundColor = ShellTheme.background
        tableView.separatorColor = ShellTheme.separator
        tableView.register(AppRowCell.self, forCellReuseIdentifier: AppRowCell.reuseIdentifier)
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "EmptyCell")
        tableView.dataSource = self
        tableView.delegate = self
        tableView.translatesAutoresizingMaskIntoConstraints = false
        return tableView
    }()

    private lazy var addButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "plus"), for: .normal)
        button.setPreferredSymbolConfiguration(
            UIImage.SymbolConfiguration(pointSize: 20, weight: .bold), forImageIn: .normal)
        button.tintColor = ShellTheme.accentColor
        button.backgroundColor = ShellTheme.card
        button.layer.cornerRadius = 22
        button.frame = CGRect(x: 0, y: 0, width: 44, height: 44)
        button.addTarget(self, action: #selector(addButtonTapped), for: .touchUpInside)
        return button
    }()

    private lazy var renewAllButton: UIButton = {
        var configuration = UIButton.Configuration.filled()
        configuration.image = UIImage(systemName: "arrow.clockwise")
        configuration.imagePadding = 6
        configuration.baseBackgroundColor = ShellTheme.accentBackground
        configuration.baseForegroundColor = ShellTheme.accentColor
        configuration.cornerStyle = .capsule
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 14)
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
            return outgoing
        }

        let button = UIButton(configuration: configuration)
        button.setTitle(NSLocalizedString("Renew All", comment: ""), for: .normal)
        button.addTarget(self, action: #selector(renewAllButtonTapped), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let renewSpinner: UIActivityIndicatorView = {
        let spinner = UIActivityIndicatorView(style: .medium)
        spinner.hidesWhenStopped = true
        spinner.translatesAutoresizingMaskIntoConstraints = false
        return spinner
    }()

    // MARK: - Lifecycle

    override func viewDidLoad()
    {
        super.viewDidLoad()
        view.backgroundColor = ShellTheme.background

        navigationItem.title = "openSSS"
        navigationItem.largeTitleDisplayMode = .always
        navigationItem.backButtonDisplayMode = .minimal
        navigationItem.rightBarButtonItem = UIBarButtonItem(customView: addButton)

        view.addSubview(segmentedTabsView)
        view.addSubview(tableView)

        let bottomInset = ShellTheme.pillHeight + ShellTheme.pillBottomMargin + 24
        tableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: bottomInset, right: 0)
        tableView.verticalScrollIndicatorInsets = UIEdgeInsets(top: 0, left: 0, bottom: bottomInset, right: 0)

        NSLayoutConstraint.activate([
            segmentedTabsView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            segmentedTabsView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            segmentedTabsView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            segmentedTabsView.heightAnchor.constraint(equalToConstant: 52),

            tableView.topAnchor.constraint(equalTo: segmentedTabsView.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        try? fetchedResultsController.performFetch()

        NotificationCenter.default.addObserver(
            self, selector: #selector(pendingStoreDidChange),
            name: PendingIPAStore.didChangeNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(appProgressDidChange(_:)),
            name: AppManager.didChangeAppProgressNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(importAppDeepLink(_:)),
            name: AppDelegate.importAppDeepLinkNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(applyTheme),
            name: ShellTheme.accentDidChangeNotification, object: nil)

        updateCounts()
    }

    override func viewWillAppear(_ animated: Bool)
    {
        super.viewWillAppear(animated)
        // Re-fetch: the first fetch may have run before the database finished
        // starting (first launch straight out of onboarding).
        try? fetchedResultsController.performFetch()
        tableView.reloadData()
        updateCounts()
    }

    override var preferredStatusBarStyle: UIStatusBarStyle
    {
        return .lightContent
    }

    // MARK: - Tabs

    private func selectTab(_ tab: Tab)
    {
        guard tab != selectedTab else { return }
        selectedTab = tab
        segmentedTabsView.select(tab == .pending ? 0 : 1, animated: true)
        tableView.reloadData()
    }

    func showPendingTab()
    {
        selectTab(.pending)
    }

    private func updateCounts()
    {
        segmentedTabsView.setCounts(pending: pendingApps.count, installed: installedApps.count)
        segmentedTabsView.select(selectedTab == .pending ? 0 : 1, animated: false)
    }

    @objc private func pendingStoreDidChange()
    {
        updateCounts()
        if selectedTab == .pending
        {
            tableView.reloadData()
        }
    }

    /// An install/refresh progress was registered or cleared. Progress is
    /// set asynchronously (PipelineRunner runs detached, after a minimuxer
    /// readiness check), so a reload right after starting an operation
    /// would run too early — this notification is what makes the bar
    /// appear as soon as the operation actually starts.
    @objc private func appProgressDidChange(_ notification: Notification)
    {
        // Posted on a background thread; hop to main before touching the table view.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard let bundleID = notification.userInfo?[AppManager.appProgressBundleIdentifierKey] as? String else
            {
                self.tableView.reloadData()
                return
            }
            // Reload just the affected row when it is on screen; off-screen
            // rows pick up the progress when they are configured.
            let row: Int?
            switch self.selectedTab
            {
            case .pending:
                row = self.pendingApps.firstIndex { $0.bundleIdentifier == bundleID }
            case .installed:
                row = self.installedApps.firstIndex { $0.bundleIdentifier == bundleID }
            }
            guard let row else { return }
            let indexPath = IndexPath(row: row, section: 0)
            guard self.tableView.indexPathsForVisibleRows?.contains(indexPath) == true else { return }
            self.tableView.reloadRows(at: [indexPath], with: .none)
        }
    }

    /// In-flight progress for a row, or nil when idle or already complete
    /// (mirrors upstream MyAppsViewController's fractionCompleted < 1.0 check).
    private func activeProgress(_ progress: Progress?) -> Progress?
    {
        guard let progress, progress.fractionCompleted < 1.0 else { return nil }
        return progress
    }

    @objc private func applyTheme()
    {
        addButton.tintColor = ShellTheme.accentColor
        renewAllButton.configuration?.baseBackgroundColor = ShellTheme.accentBackground
        renewAllButton.configuration?.baseForegroundColor = ShellTheme.accentColor
        segmentedTabsView.applyTheme()
        tableView.reloadData()
    }

    // MARK: - Import (.ipa deep links + picker)

    @objc private func importAppDeepLink(_ notification: Notification)
    {
        guard let url = notification.userInfo?[AppDelegate.importAppDeepLinkURLKey] as? URL else { return }
        importIPA(at: url)
    }

    private func importIPA(at url: URL)
    {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do
            {
                _ = try await PendingIPAStore.shared.add(from: url)
                self.selectTab(.pending)
            }
            catch
            {
                ToastView(error: error).show(in: self)
            }
        }
    }

    @objc private func addButtonTapped()
    {
        InstallAppDialog.presentSourceSelection(
            from: self,
            barButtonItem: navigationItem.rightBarButtonItem,
            onChooseFiles: { [weak self] in
                self?.presentDocumentPicker()
            },
            onConfirm: { [weak self] url in
                // Remote URL: download into the pending queue.
                self?.importIPA(at: url)
            }
        )
    }

    private func presentDocumentPicker()
    {
        let supportedTypes = UTType.types(tag: "ipa", tagClass: .filenameExtension, conformingTo: nil)
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: supportedTypes, asCopy: true)
        picker.delegate = self
        present(picker, animated: true)
    }

    // MARK: - Renew all

    @objc private func renewAllButtonTapped()
    {
        guard !isRefreshingAll else { return }

        let installedApps = InstalledApp.fetchAppsForRefreshingAll(in: DatabaseManager.shared.viewContext)
        guard !installedApps.isEmpty else
        {
            let error: Error
            if let altstoreApp = InstalledApp.fetchAltStore(in: DatabaseManager.shared.viewContext),
               let storeApp = altstoreApp.storeApp, storeApp.isPledgeRequired && !storeApp.isPledged
            {
                error = OperationError.pledgeInactive(appName: altstoreApp.name)
            }
            else
            {
                error = OperationError.noInstalledApps
            }
            ToastView(error: error).show(in: self)
            return
        }

        isRefreshingAll = true
        renewAllButton.isEnabled = false
        renewAllButton.setTitle(NSLocalizedString("Renewing…", comment: ""), for: .normal)
        renewSpinner.color = ShellTheme.accentColor
        renewSpinner.startAnimating()
        tableView.reloadData()

        let group = AppManager.shared.refresh(installedApps, presentingViewController: self)
        group.completionHandler = { [weak self] results in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isRefreshingAll = false
                self.renewAllButton.isEnabled = true
                self.renewAllButton.setTitle(NSLocalizedString("Renew All", comment: ""), for: .normal)
                self.renewSpinner.stopAnimating()
                self.tableView.reloadData()

                let failures = results.compactMapValues { (result) -> Error? in
                    switch result
                    {
                    case .failure(let error) where error is CancellationError: return nil
                    case .failure(let error): return error
                    case .success: return nil
                    }
                }

                guard !failures.isEmpty else { return }
                if failures.count == 1, let failure = failures.values.first
                {
                    ToastView(error: failure).show(in: self)
                }
                else
                {
                    let text = String(format: NSLocalizedString("%d apps failed to refresh", comment: ""), failures.count)
                    ToastView(text: text, detailText: nil, opensLog: true).show(in: self)
                }
            }
        }
    }

    // MARK: - Installed app actions

    private func presentActions(for installedApp: InstalledApp)
    {
        let isSelfApp = installedApp.bundleIdentifier == StoreApp.altstoreAppID

        let alert = UIAlertController(title: installedApp.name, message: nil, preferredStyle: .actionSheet)

        if !isSelfApp
        {
            alert.addAction(UIAlertAction(title: NSLocalizedString("Open", comment: ""), style: .default) { [weak self] _ in
                self?.open(installedApp)
            })
        }

        alert.addAction(UIAlertAction(title: NSLocalizedString("Renew", comment: ""), style: .default) { [weak self] _ in
            self?.refresh(installedApp)
        })

        if !isSelfApp
        {
            alert.addAction(UIAlertAction(title: NSLocalizedString("Re-sign", comment: ""), style: .default) { [weak self] _ in
                self?.resign(installedApp)
            })
            alert.addAction(UIAlertAction(title: NSLocalizedString("Reinstall", comment: ""), style: .default) { [weak self] _ in
                self?.reinstallFromCache(installedApp)
            })
            alert.addAction(UIAlertAction(title: NSLocalizedString("Delete", comment: ""), style: .destructive) { [weak self] _ in
                self?.deleteApp(installedApp)
            })
        }

        alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel))
        present(alert, animated: true)
    }

    private func open(_ installedApp: InstalledApp)
    {
        UIApplication.shared.open(installedApp.openAppURL) { [weak self] success in
            guard !success, let self else { return }
            ToastView(error: OperationError.openAppFailed(name: installedApp.name), opensLog: true).show(in: self)
        }
    }

    private func refresh(_ installedApp: InstalledApp)
    {
        guard AppManager.shared.refreshProgress(for: installedApp) == nil else { return }

        tableView.reloadData()
        let group = AppManager.shared.refresh([installedApp], presentingViewController: self)
        group.completionHandler = { [weak self] results in
            DispatchQueue.main.async {
                guard let self else { return }
                self.tableView.reloadData()
                if let failure = results.values.compactMap({ result -> Error? in
                    if case .failure(let error) = result, !(error is CancellationError) { return error }
                    return nil
                }).first
                {
                    ToastView(error: failure, opensLog: true).show(in: self)
                }
            }
        }
    }

    private func resign(_ installedApp: InstalledApp)
    {
        guard AppManager.shared.refreshProgress(for: installedApp) == nil else { return }

        tableView.reloadData()
        AppManager.shared.resign(installedApp, alternateIconMode: .preserve, presentingViewController: self) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.tableView.reloadData()
                switch result
                {
                case .failure(let error) where error is CancellationError:
                    break
                case .failure(let error):
                    ToastView(error: error, opensLog: true).show(in: self)
                case .success:
                    break
                }
            }
        }
    }

    private func reinstallFromCache(_ installedApp: InstalledApp)
    {
        InstallAppDialog.present(installedApp: installedApp, from: self) { [weak self] in
            guard let self else { return }
            guard AppManager.shared.installationProgress(for: installedApp) == nil else { return }

            self.tableView.reloadData()
            AppManager.shared.reinstall(installedApp, presentingViewController: self) { [weak self] result in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.tableView.reloadData()
                    switch result
                    {
                    case .failure(let error) where error is CancellationError:
                        break
                    case .failure(let error):
                        ToastView(error: error, opensLog: true).show(in: self)
                    case .success:
                        break
                    }
                }
            }
        }
    }

    private func deleteApp(_ installedApp: InstalledApp)
    {
        guard installedApp.isActive else { return }

        let appName = installedApp.name
        let title = String(format: NSLocalizedString("Delete “%@”?", comment: ""), appName)
        let message = String(format: NSLocalizedString("This will remove “%@” from oPenSSAI and erase any backup data for this app.", comment: ""), appName)

        let contentVC = DeleteAppAlertViewController()

        let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alertController.setValue(contentVC, forKey: "contentViewController")

        let actionTitleForState: (Bool) -> String = { isChecked in
            isChecked ? NSLocalizedString("Delete", comment: "") : NSLocalizedString("Remove", comment: "")
        }

        let confirmAction = UIAlertAction(title: actionTitleForState(contentVC.isChecked), style: .destructive) { [weak self] _ in
            guard let self else { return }
            let deleteFromDevice = contentVC.isChecked

            Task { @MainActor in
                if deleteFromDevice
                {
                    AppManager.shared.deleteApp(installedApp, presentingViewController: self) { [weak self] result in
                        switch result
                        {
                        case .success(let app):
                            try? app.managedObjectContext?.save()
                        case .failure(let error) where error is CancellationError:
                            break
                        case .failure(let error):
                            DispatchQueue.main.async {
                                guard let self else { return }
                                ToastView(error: error, opensLog: true).show(in: self)
                            }
                        }
                    }
                }
                else
                {
                    AppManager.shared.removeApp(installedApp, presentingViewController: self) { [weak self] result in
                        if case .failure(let error) = result
                        {
                            DispatchQueue.main.async {
                                guard let self else { return }
                                ToastView(error: error, opensLog: true).show(in: self)
                            }
                        }
                    }
                }
            }
        }

        contentVC.onToggle = { [weak confirmAction] isChecked in
            // UIAlertAction.title is get-only; update it via KVC like the
            // original MyAppsViewController does.
            confirmAction?.setValue(actionTitleForState(isChecked), forKey: "title")
        }

        alertController.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel))
        alertController.addAction(confirmAction)
        present(alertController, animated: true)
    }

    // MARK: - Pending app install

    // Needs proper testing: end-to-end install of a queued .ipa on a real
    // device (pairing file + Apple ID sign-in), including the failure paths
    // (invalid .ipa, no pairing file, 3-app free-account limit).
    private func installPending(_ item: PendingIPA)
    {
        let ipaURL = PendingIPAStore.shared.ipaURL(for: item)
        InstallAppDialog.present(ipaURL: ipaURL, from: self) { [weak self] in
            guard let self else { return }
            tableView.reloadData()
            AppManager.shared.install(.url(ipaURL), presentingViewController: self) { [weak self] result in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.tableView.reloadData()
                    switch result
                    {
                    case .success:
                        PendingIPAStore.shared.remove(item)
                        self.selectTab(.installed)
                    case .failure(let error) where error is CancellationError:
                        break
                    case .failure(let error):
                        ToastView(error: error, opensLog: true).show(in: self)
                    }
                }
            }
        }
    }

    // MARK: - Validity

    /// Days remaining until `expirationDate`, as shown on the right of an
    /// installed app row. Dates that cannot be real (no provisioning profile,
    /// e.g. in the Simulator) show an em dash instead of a bogus count.
    static func validity(for expirationDate: Date) -> (text: String, color: UIColor?)
    {
        let now = Date()
        let earliestPlausible = Date(timeIntervalSince1970: 1577836800) // 2020-01-01
        let latestPlausible = now.addingTimeInterval(366 * 24 * 60 * 60)
        guard expirationDate >= earliestPlausible, expirationDate <= latestPlausible else
        {
            return ("—", nil)
        }

        guard expirationDate > now else
        {
            return (NSLocalizedString("Expired", comment: ""), ShellTheme.expiredRed)
        }

        let calendar = Calendar.current
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: now),
            to: calendar.startOfDay(for: expirationDate)
        ).day ?? 0

        if days <= 0
        {
            return (NSLocalizedString("Expires Today", comment: ""), ShellTheme.expiredRed)
        }
        if days == 1
        {
            return (String(format: NSLocalizedString("%d Day", comment: ""), days), ShellTheme.expiredRed)
        }
        return (String(format: NSLocalizedString("%d Days", comment: ""), days), nil)
    }
}

// MARK: - UITableViewDataSource / Delegate

extension AppsViewController: UITableViewDataSource, UITableViewDelegate
{
    func numberOfSections(in tableView: UITableView) -> Int
    {
        return 1
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int
    {
        switch selectedTab
        {
        case .pending: return max(pendingApps.count, 1)
        case .installed: return max(installedApps.count, 1)
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell
    {
        switch selectedTab
        {
        case .pending:
            guard !pendingApps.isEmpty else
            {
                return emptyCell(
                    text: NSLocalizedString("No pending apps — tap + to import an .ipa.", comment: ""),
                    tableView: tableView, indexPath: indexPath)
            }
            let item = pendingApps[indexPath.row]
            let cell = tableView.dequeueReusableCell(withIdentifier: AppRowCell.reuseIdentifier, for: indexPath) as! AppRowCell
            cell.configureCardBackground(position: cardPosition(row: indexPath.row, count: pendingApps.count))
            cell.configure(
                icon: PendingIPAStore.shared.icon(for: item),
                name: item.name,
                version: item.version,
                bundleIdentifier: item.bundleIdentifier,
                status: NSLocalizedString("Pending", comment: "")
            )
            cell.setProgress(activeProgress(AppManager.shared.installationProgress(forBundleID: item.bundleIdentifier)))
            return cell

        case .installed:
            guard !installedApps.isEmpty else
            {
                return emptyCell(
                    text: NSLocalizedString("No installed apps yet.", comment: ""),
                    tableView: tableView, indexPath: indexPath)
            }
            let app = installedApps[indexPath.row]
            let cell = tableView.dequeueReusableCell(withIdentifier: AppRowCell.reuseIdentifier, for: indexPath) as! AppRowCell
            cell.configureCardBackground(position: cardPosition(row: indexPath.row, count: installedApps.count))

            let validity = Self.validity(for: app.expirationDate)
            let isBusy = AppManager.shared.refreshProgress(for: app) != nil
                || AppManager.shared.installationProgress(for: app) != nil
            cell.configure(
                icon: iconCache.object(forKey: app.bundleIdentifier as NSString)
                    ?? PendingIPAStore.placeholderIcon(for: app.name),
                name: app.name,
                version: app.version,
                bundleIdentifier: app.resignedBundleIdentifier,
                status: validity.text,
                statusColor: validity.color,
                isBusy: isBusy
            )
            // refreshProgress falls back to installationProgress, so this
            // covers refresh, re-sign, and reinstall alike.
            cell.setProgress(activeProgress(AppManager.shared.refreshProgress(for: app)))
            loadIconIfNeeded(for: app, at: indexPath)
            return cell
        }
    }

    private func emptyCell(text: String, tableView: UITableView, indexPath: IndexPath) -> UITableViewCell
    {
        let cell = tableView.dequeueReusableCell(withIdentifier: "EmptyCell", for: indexPath)
        cell.backgroundColor = ShellTheme.card
        cell.textLabel?.text = text
        cell.textLabel?.font = UIFont.systemFont(ofSize: 15, weight: .regular)
        cell.textLabel?.textColor = ShellTheme.secondaryText
        cell.textLabel?.textAlignment = .center
        cell.textLabel?.numberOfLines = 0
        cell.selectionStyle = .none
        cell.separatorInset = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: .greatestFiniteMagnitude)
        return cell
    }

    private func cardPosition(row: Int, count: Int) -> ShellCardPosition
    {
        if count == 1 { return .single }
        if row == 0 { return .top }
        if row == count - 1 { return .bottom }
        return .middle
    }

    private func loadIconIfNeeded(for app: InstalledApp, at indexPath: IndexPath)
    {
        let key = app.bundleIdentifier as NSString
        guard iconCache.object(forKey: key) == nil else { return }

        let objectID = app.objectID
        Task { @MainActor [weak self] in
            guard let self else { return }
            let image = try? await app.loadIcon()
            let finalImage = image ?? PendingIPAStore.placeholderIcon(for: app.name)
            self.iconCache.setObject(finalImage, forKey: key)

            // Only update the cell if it still shows the same app.
            guard self.selectedTab == .installed,
                  indexPath.row < self.installedApps.count,
                  self.installedApps[indexPath.row].objectID == objectID,
                  let cell = self.tableView.cellForRow(at: indexPath) as? AppRowCell else { return }

            let validity = Self.validity(for: app.expirationDate)
            let isBusy = AppManager.shared.refreshProgress(for: app) != nil
                || AppManager.shared.installationProgress(for: app) != nil
            cell.configure(
                icon: finalImage,
                name: app.name,
                version: app.version,
                bundleIdentifier: app.resignedBundleIdentifier,
                status: validity.text,
                statusColor: validity.color,
                isBusy: isBusy
            )
            cell.setProgress(activeProgress(AppManager.shared.refreshProgress(for: app)))
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath)
    {
        tableView.deselectRow(at: indexPath, animated: true)

        switch selectedTab
        {
        case .pending:
            guard !pendingApps.isEmpty else { return }
            installPending(pendingApps[indexPath.row])
        case .installed:
            guard !installedApps.isEmpty else { return }
            presentActions(for: installedApps[indexPath.row])
        }
    }

    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool
    {
        // Pending entries can be swiped away; installed apps use Delete.
        return selectedTab == .pending && !pendingApps.isEmpty
    }

    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath)
    {
        guard editingStyle == .delete, selectedTab == .pending else { return }
        PendingIPAStore.shared.remove(pendingApps[indexPath.row])
    }

    func tableView(_ tableView: UITableView, titleForDeleteConfirmationButtonForRowAt indexPath: IndexPath) -> String?
    {
        return NSLocalizedString("Delete", comment: "")
    }

    // Section header: the "Installed Apps" / "Pending Apps" heading row,
    // with the Renew All pill on the installed tab.
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView?
    {
        let container = UIView()

        let titleLabel = UILabel()
        titleLabel.font = ShellTheme.headingFont
        titleLabel.textColor = ShellTheme.primaryText
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = selectedTab == .installed
            ? NSLocalizedString("Installed Apps", comment: "")
            : NSLocalizedString("Pending Apps", comment: "")

        container.addSubview(titleLabel)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            titleLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])

        if selectedTab == .installed
        {
            renewAllButton.removeFromSuperview()
            container.addSubview(renewAllButton)
            container.addSubview(renewSpinner)
            NSLayoutConstraint.activate([
                renewAllButton.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
                renewAllButton.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                renewSpinner.centerXAnchor.constraint(equalTo: renewAllButton.centerXAnchor),
                renewSpinner.centerYAnchor.constraint(equalTo: renewAllButton.centerYAnchor),
                titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: renewAllButton.leadingAnchor, constant: -12),
            ])
        }

        return container
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat
    {
        return 60
    }
}

// MARK: - NSFetchedResultsControllerDelegate

extension AppsViewController: NSFetchedResultsControllerDelegate
{
    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>)
    {
        updateCounts()
        if selectedTab == .installed
        {
            tableView.reloadData()
        }
    }
}

// MARK: - UIDocumentPickerDelegate

extension AppsViewController: UIDocumentPickerDelegate
{
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL])
    {
        guard let url = urls.first else { return }
        importIPA(at: url)
    }
}

// MARK: - Segmented tabs

/// The Pending / Installed segmented tabs: two half-width buttons with a
/// magenta underline under the selected one, counts in smaller gray text.
private final class SegmentedTabsView: UIView
{
    private let onSelect: (Int) -> Void

    private var pendingCount = 0
    private var installedCount = 0
    private var selectedIndex = 1

    private lazy var pendingButton: UIButton = makeButton(index: 0)
    private lazy var installedButton: UIButton = makeButton(index: 1)

    private let underlineView: UIView = {
        let view = UIView()
        view.backgroundColor = ShellTheme.accentColor
        view.layer.cornerRadius = 2
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private var underlineLeadingConstraint: NSLayoutConstraint!
    private var underlineWidthConstraint: NSLayoutConstraint!

    init(onSelect: @escaping (Int) -> Void)
    {
        self.onSelect = onSelect
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView(arrangedSubviews: [pendingButton, installedButton])
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(stack)
        addSubview(underlineView)

        underlineLeadingConstraint = underlineView.leadingAnchor.constraint(equalTo: leadingAnchor)
        underlineWidthConstraint = underlineView.widthAnchor.constraint(equalToConstant: 0)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),

            underlineView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
            underlineView.heightAnchor.constraint(equalToConstant: 4),
            underlineLeadingConstraint,
            underlineWidthConstraint,
        ])

        updateTitles()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder)
    {
        fatalError("init(coder:) has not been implemented")
    }

    private func makeButton(index: Int) -> UIButton
    {
        let button = UIButton(type: .system)
        button.tag = index
        button.addTarget(self, action: #selector(buttonTapped(_:)), for: .touchUpInside)
        return button
    }

    @objc private func buttonTapped(_ sender: UIButton)
    {
        select(sender.tag, animated: true)
        onSelect(sender.tag)
    }

    func setCounts(pending: Int, installed: Int)
    {
        pendingCount = pending
        installedCount = installed
        updateTitles()
    }

    func select(_ index: Int, animated: Bool)
    {
        selectedIndex = index
        updateTitles()

        let updateLayout = {
            let halfWidth = self.bounds.width / 2
            self.underlineLeadingConstraint.constant = CGFloat(index) * halfWidth
            self.underlineWidthConstraint.constant = halfWidth
            self.layoutIfNeeded()
        }

        if animated
        {
            UIView.animate(withDuration: 0.25, animations: updateLayout)
        }
        else
        {
            updateLayout()
        }
    }

    func applyTheme()
    {
        underlineView.backgroundColor = ShellTheme.accentColor
        updateTitles()
    }

    override func layoutSubviews()
    {
        super.layoutSubviews()
        // Keep the underline aligned after rotations / size changes.
        let halfWidth = bounds.width / 2
        underlineLeadingConstraint.constant = CGFloat(selectedIndex) * halfWidth
        underlineWidthConstraint.constant = halfWidth
    }

    private func updateTitles()
    {
        pendingButton.setAttributedTitle(
            tabTitle(text: NSLocalizedString("Pending", comment: ""), count: pendingCount, selected: selectedIndex == 0),
            for: .normal)
        installedButton.setAttributedTitle(
            tabTitle(text: NSLocalizedString("Installed", comment: ""), count: installedCount, selected: selectedIndex == 1),
            for: .normal)
    }

    private func tabTitle(text: String, count: Int, selected: Bool) -> NSAttributedString
    {
        let titleColor = selected ? ShellTheme.accentColor : ShellTheme.secondaryText
        let title = NSMutableAttributedString(
            string: text,
            attributes: [
                .font: ShellTheme.segmentTitleFont,
                .foregroundColor: titleColor,
            ])
        let countText = NSAttributedString(
            string: "  \(count)",
            attributes: [
                .font: ShellTheme.segmentCountFont,
                .foregroundColor: ShellTheme.secondaryText,
            ])
        title.append(countText)
        return title
    }
}
#endif
