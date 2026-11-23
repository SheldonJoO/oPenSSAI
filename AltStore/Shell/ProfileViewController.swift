#if os(iOS)
//
//  ProfileViewController.swift
//  openSSS
//
//  The Me tab: Signing (device pairing, Apple ID, certificates), Expiry
//  Reminder (24-hour toggle + next reminder), Manage (appearance & theme,
//  storage & cleanup), Help & Support (guide, community, support),
//  Diagnostics (diagnostic log), About (about openSSS + version).
//  Engine-backed rows push the existing SideStore screens (re-skinned by the
//  shell's navigation appearance); Seal-only rows open new shell screens.
//
//  Copyright © 2026 openSSS Contributors. All rights reserved.
//

import UIKit
import SwiftUI
import Combine
import UserNotifications

final class ProfileViewController: UIViewController
{
    private enum Section: Int, CaseIterable
    {
        case signing
        case reminder
        case manage
        case help
        case diagnostics
        case about

        var title: String
        {
            switch self
            {
            case .signing: return NSLocalizedString("Signing", comment: "")
            case .reminder: return NSLocalizedString("Expiry Reminder", comment: "")
            case .manage: return NSLocalizedString("Manage", comment: "")
            case .help: return NSLocalizedString("Help & Support", comment: "")
            case .diagnostics: return NSLocalizedString("Diagnostics", comment: "")
            case .about: return NSLocalizedString("About", comment: "")
            }
        }
    }

    private enum SigningRow: Int, CaseIterable { case device, appleIDs, certificate, anisette, connection }
    private enum ReminderRow: Int, CaseIterable { case toggle, nextReminder }
    private enum ManageRow: Int, CaseIterable { case appearance, storage }
    private enum HelpRow: Int, CaseIterable { case guide, community, support }
    private enum DiagnosticsRow: Int, CaseIterable { case log }
    private enum AboutRow: Int, CaseIterable { case about }

    private var storageSizeText: String?
    private var cancellables = Set<AnyCancellable>()

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

        navigationItem.title = NSLocalizedString("Me", comment: "")
        navigationItem.largeTitleDisplayMode = .always
        navigationItem.backButtonDisplayMode = .minimal

        view.addSubview(tableView)

        // The standard tab bar is accounted for by the safe area; only a
        // small breathing room below the last row is needed.
        let bottomInset: CGFloat = 24
        tableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: bottomInset, right: 0)
        tableView.verticalScrollIndicatorInsets = UIEdgeInsets(top: 0, left: 0, bottom: bottomInset, right: 0)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        NotificationCenter.default.addObserver(
            self, selector: #selector(applyTheme),
            name: ShellTheme.accentDidChangeNotification, object: nil)

        // Keep the Connection row value (mode + reachability) live while
        // this screen is visible: minimuxer pushes reachability into
        // ConnectionConfig.shared as the network changes.
        ConnectionConfig.shared.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.tableView.reloadRows(
                        at: [IndexPath(row: SigningRow.connection.rawValue, section: Section.signing.rawValue)],
                        with: .none)
                }
            }
            .store(in: &cancellables)
    }

    override func viewWillAppear(_ animated: Bool)
    {
        super.viewWillAppear(animated)
        refreshStorageSize()
        tableView.reloadData()
        Self.rescheduleExpiryReminderIfNeeded()
    }

    override var preferredStatusBarStyle: UIStatusBarStyle
    {
        return shellPreferredStatusBarStyle
    }

    @objc private func applyTheme()
    {
        tableView.reloadData()
    }

    // MARK: - Values

    private var isPaired: Bool
    {
        PairingFileManager.shared.hasPairingFile()
    }

    private var activeAccount: Account?
    {
        DatabaseManager.shared.activeAccount(in: DatabaseManager.shared.viewContext)
    }

    private var appVersionText: String
    {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        return String(format: NSLocalizedString("Version %@", comment: ""), version)
    }

    /// Me → Signing connection row value: the current effective mode plus
    /// endpoint reachability, e.g. "远程直连 · 可达". Reachability is
    /// omitted while no endpoint is known yet (local mode before the
    /// tunnel peer is discovered).
    private var connectionRowValue: String
    {
        let config = ConnectionConfig.shared
        let modeName = config.useLocalVPN
            ? NSLocalizedString("Local VPN", comment: "")
            : NSLocalizedString("Remote Direct", comment: "")
        guard let reachable = config.effectiveEndpointReachable else
        {
            return modeName
        }
        let reachabilityText = reachable
            ? NSLocalizedString("Connection Reachable", comment: "")
            : NSLocalizedString("Connection Unreachable", comment: "")
        return "\(modeName) · \(reachabilityText)"
    }

    /// The next expiry reminder fire date (earliest installed-app expiry
    /// minus 24 hours), or nil when there is nothing to remind about.
    private static func nextReminderDate() -> Date?
    {
        let context = DatabaseManager.shared.viewContext
        let request = InstalledApp.fetchRequest()
        request.predicate = NSPredicate(format: "%K == YES", #keyPath(InstalledApp.isActive))
        guard let apps = try? context.fetch(request), !apps.isEmpty else { return nil }

        let now = Date()
        let earliestExpiry = apps.map(\.expirationDate).min()
        guard let earliestExpiry, earliestExpiry > now else { return nil }

        let reminderDate = earliestExpiry.addingTimeInterval(-24 * 60 * 60)
        return reminderDate > now ? reminderDate : now
    }

    private var nextReminderText: String
    {
        guard ShellTheme.isExpiryReminderEnabled,
              let date = Self.nextReminderDate() else {
            return NSLocalizedString("None", comment: "")
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }

    private func refreshStorageSize()
    {
        Task.detached(priority: .utility) { [weak self] in
            let total = ShellStorage.totalAppSize()
            let text = ShellStorage.formattedSize(total)
            await MainActor.run {
                guard let self else { return }
                self.storageSizeText = text
                self.tableView.reloadRows(
                    at: [IndexPath(row: ManageRow.storage.rawValue, section: Section.manage.rawValue)],
                    with: .none)
            }
        }
    }

    // MARK: - Expiry reminder notification

    /// (Re)schedules the single local notification for the next expiry
    /// reminder, if the toggle is on and a reminder date exists.
    static func rescheduleExpiryReminderIfNeeded()
    {
        let center = UNUserNotificationCenter.current()
        let identifier = "openSSS.expiryReminder"

        guard ShellTheme.isExpiryReminderEnabled,
              let date = nextReminderDate() else {
            center.removePendingNotificationRequests(withIdentifiers: [identifier])
            return
        }

        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional else { return }

            let content = UNMutableNotificationContent()
            content.title = "openSSS"
            content.body = NSLocalizedString("An app expires in 24 hours. Open openSSS to renew it.", comment: "")
            content.sound = .default

            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .second], from: date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
            center.add(request)
        }
    }

    private func setExpiryReminderEnabled(_ isOn: Bool)
    {
        ShellTheme.isExpiryReminderEnabled = isOn

        if isOn
        {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if !granted
                    {
                        ToastView(
                            text: NSLocalizedString("Notifications are disabled", comment: ""),
                            detailText: NSLocalizedString("Enable notifications in Settings to receive the expiry reminder.", comment: "")
                        ).show(in: self)
                    }
                    Self.rescheduleExpiryReminderIfNeeded()
                    self.tableView.reloadData()
                }
            }
        }
        else
        {
            Self.rescheduleExpiryReminderIfNeeded()
        }

        tableView.reloadData()
    }

    // MARK: - Navigation

    private func pushSwiftUIView<Content: View>(_ view: Content, title: String? = nil)
    {
        let hostingController = ShellHostingController(rootView: view)
        hostingController.title = title
        navigationController?.pushViewController(hostingController, animated: true)
    }

    /// Opens the diagnostic (error) log. Called by the shell tab bar for
    /// the error-log deep link, and by the Diagnostics row.
    func openDiagnosticLog()
    {
        let storyboard = UIStoryboard(name: "Settings", bundle: nil)
        let viewController = storyboard.instantiateViewController(withIdentifier: "ErrorLogViewController")
        navigationController?.pushViewController(viewController, animated: true)
    }
}

// MARK: - UITableViewDataSource / Delegate

extension ProfileViewController: UITableViewDataSource, UITableViewDelegate
{
    func numberOfSections(in tableView: UITableView) -> Int
    {
        return Section.allCases.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int
    {
        switch Section(rawValue: section)
        {
        case .signing: return SigningRow.allCases.count
        case .reminder: return ReminderRow.allCases.count
        case .manage: return ManageRow.allCases.count
        case .help: return HelpRow.allCases.count
        case .diagnostics: return DiagnosticsRow.allCases.count
        case .about: return AboutRow.allCases.count
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
        case .signing:
            switch SigningRow(rawValue: indexPath.row)
            {
            case .device:
                cell.configure(
                    iconSystemName: "iphone", iconTint: accent,
                    title: NSLocalizedString("Device", comment: ""),
                    value: isPaired
                        ? NSLocalizedString("Paired", comment: "")
                        : NSLocalizedString("Not Paired", comment: ""))
            case .appleIDs:
                // Single Apple ID entry: the account list handles sign-in,
                // switching, sign-out, and removal. The value shows the
                // currently active account (nil while signed out) and
                // refreshes on every appearance via viewWillAppear.
                cell.configure(
                    iconSystemName: "person.2.circle", iconTint: accent,
                    title: "Apple ID",
                    value: activeAccount?.appleID)
            case .certificate:
                cell.configure(
                    iconSystemName: "person.badge.key", iconTint: accent,
                    title: NSLocalizedString("Signing Certificate", comment: ""))
            case .anisette:
                cell.configure(
                    iconSystemName: "server.rack", iconTint: accent,
                    title: NSLocalizedString("Anisette Settings", comment: ""))
            case .connection:
                cell.configure(
                    iconSystemName: "network", iconTint: accent,
                    title: NSLocalizedString("Connection Settings", comment: ""),
                    value: connectionRowValue)
            case .none:
                break
            }

        case .reminder:
            switch ReminderRow(rawValue: indexPath.row)
            {
            case .toggle:
                cell.configureToggle(
                    iconSystemName: "bell.badge", iconTint: ShellTheme.reminderOrange,
                    title: NSLocalizedString("Remind 24 Hours Before", comment: ""),
                    isOn: ShellTheme.isExpiryReminderEnabled,
                    onToggleChanged: { [weak self] isOn in
                        self?.setExpiryReminderEnabled(isOn)
                    })
            case .nextReminder:
                cell.configureInfo(
                    iconSystemName: "clock", iconTint: ShellTheme.reminderOrange,
                    title: NSLocalizedString("Next Reminder", comment: ""),
                    value: nextReminderText)
            case .none:
                break
            }

        case .manage:
            switch ManageRow(rawValue: indexPath.row)
            {
            case .appearance:
                cell.configure(
                    iconSystemName: "circle.lefthalf.filled", iconTint: accent,
                    title: NSLocalizedString("Appearance & Theme", comment: ""),
                    value: ShellTheme.summary)
            case .storage:
                cell.configure(
                    iconSystemName: "externaldrive", iconTint: accent,
                    title: NSLocalizedString("Storage & Cleanup", comment: ""),
                    value: storageSizeText)
            case .none:
                break
            }

        case .help:
            switch HelpRow(rawValue: indexPath.row)
            {
            case .guide:
                cell.configure(
                    iconSystemName: "book", iconTint: accent,
                    title: NSLocalizedString("User Guide", comment: ""))
            case .community:
                cell.configure(
                    iconSystemName: "person.2", iconTint: accent,
                    title: NSLocalizedString("Join Community", comment: ""))
            case .support:
                cell.configure(
                    iconSystemName: "heart", iconTint: ShellTheme.supportRed,
                    title: NSLocalizedString("Support openSSS", comment: ""))
            case .none:
                break
            }

        case .diagnostics:
            cell.configure(
                iconSystemName: "doc.text", iconTint: accent,
                title: NSLocalizedString("Diagnostic Log", comment: ""))

        case .about:
            cell.configure(
                iconSystemName: "info.circle", iconTint: accent,
                title: NSLocalizedString("About openSSS", comment: ""),
                value: appVersionText)

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
        case .signing:
            switch SigningRow(rawValue: indexPath.row)
            {
            case .device:
                pushSwiftUIView(
                    PairingFileManagementView(),
                    title: NSLocalizedString("Device", comment: ""))
            case .appleIDs:
                navigationController?.pushViewController(AppleIDsViewController(), animated: true)
            case .certificate:
                pushSwiftUIView(
                    CertificatesView(presentingViewController: self),
                    title: NSLocalizedString("Signing Certificate", comment: ""))
            case .anisette:
                navigationController?.pushViewController(AnisetteSettingsViewController(), animated: true)
            case .connection:
                navigationController?.pushViewController(ConnectionSettingsViewController(), animated: true)
            case .none:
                break
            }

        case .reminder:
            break // Toggle row handles itself; Next Reminder is info-only.

        case .manage:
            switch ManageRow(rawValue: indexPath.row)
            {
            case .appearance:
                navigationController?.pushViewController(ThemePickerViewController(), animated: true)
            case .storage:
                navigationController?.pushViewController(StorageViewController(), animated: true)
            case .none:
                break
            }

        case .help:
            switch HelpRow(rawValue: indexPath.row)
            {
            case .guide:
                navigationController?.pushViewController(GuideViewController(), animated: true)
            case .community:
                openWebURL(AppConstants.URLs.sideStoreGitHub, preferredTintColor: ShellTheme.accentColor)
            case .support:
                navigationController?.pushViewController(DonationViewController(), animated: true)
            case .none:
                break
            }

        case .diagnostics:
            openDiagnosticLog()

        case .about:
            navigationController?.pushViewController(AboutViewController(), animated: true)

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
}
#endif
