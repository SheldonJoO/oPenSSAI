#if os(iOS)
//
//  AppleIDsViewController.swift
//  oPenSSAI
//
//  Manage the stored Apple IDs (teams): list every signed-in Apple ID with
//  its team and certificate status, switch the active team used for signing
//  and refreshing, add a new Apple ID through the normal sign-in flow, or
//  remove an Apple ID from this device. Removing an ID only deletes local
//  records; it never revokes the signing certificate on Apple's servers.
//
//  Note: the Keychain holds credentials for a single Apple ID, so switching
//  to a team whose Apple ID has no stored credentials asks the user to sign
//  in again with that ID (the sign-in flow re-activates the existing team
//  and provisions its certificate). Per-app team assignment is not
//  supported by the engine — refresh always signs with the active team —
//  so active-team switching is the whole feature.
//
//  Copyright © 2026 oPenSSAI Contributors. All rights reserved.
//

import UIKit
import CoreData

import SideSign

final class AppleIDsViewController: UIViewController
{
    /// Snapshot of one stored team, captured on the view context.
    private struct TeamRow
    {
        let accountObjectID: NSManagedObjectID
        let appleID: String
        let teamName: String
        let teamIdentifier: String
        let teamType: ALTTeamType
        let isActive: Bool
        let installedAppCount: Int
        let certificateStatus: CertificateStatus
    }

    private enum CertificateStatus
    {
        case valid(until: Date)
        case expired
        case none

        var text: String
        {
            switch self
            {
            case .valid(let until):
                return String(
                    format: NSLocalizedString("Certificate Expires %@", comment: ""),
                    AppleIDsViewController.dateFormatter.string(from: until))
            case .expired:
                return NSLocalizedString("Certificate Expired", comment: "")
            case .none:
                return NSLocalizedString("No Certificate", comment: "")
            }
        }
    }

    private enum Section: Int, CaseIterable
    {
        case teams
        case add
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private var teams: [TeamRow] = []

    private lazy var tableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .insetGrouped)
        tableView.backgroundColor = ShellTheme.background
        tableView.separatorColor = ShellTheme.separator
        tableView.register(AppleIDCell.self, forCellReuseIdentifier: AppleIDCell.reuseIdentifier)
        tableView.register(SettingRowCell.self, forCellReuseIdentifier: SettingRowCell.reuseIdentifier)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 76
        tableView.sectionHeaderTopPadding = 0
        tableView.translatesAutoresizingMaskIntoConstraints = false
        return tableView
    }()

    override func viewDidLoad()
    {
        super.viewDidLoad()
        view.backgroundColor = ShellTheme.background

        navigationItem.title = NSLocalizedString("Apple IDs", comment: "")

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
        reload()
    }

    // MARK: - Data

    private func reload()
    {
        // Make sure the in-memory active certificate is loaded so it can be
        // matched against its team below.
        if CertificateManager.shared.activeCertificate == nil
        {
            _ = try? CertificateManager.shared.loadActiveCertificate()
        }

        let context = DatabaseManager.shared.viewContext
        let request = Team.fetchRequest()
        request.sortDescriptors = [
            NSSortDescriptor(key: "account.appleID", ascending: true),
            NSSortDescriptor(key: "name", ascending: true),
        ]
        let storedTeams = (try? context.fetch(request)) ?? []

        let identifiers = Set(storedTeams.map(\.identifier))
        let latestExpiry = Self.latestCertificateExpiryByTeamIdentifier(identifiers)
        let now = Date()

        self.teams = storedTeams.map { team in
            let status: CertificateStatus
            if let expiry = latestExpiry[team.identifier]
            {
                status = expiry > now ? .valid(until: expiry) : .expired
            }
            else
            {
                status = .none
            }
            return TeamRow(
                accountObjectID: team.account.objectID,
                appleID: team.account.appleID,
                teamName: team.name,
                teamIdentifier: team.identifier,
                teamType: team.type,
                isActive: team.isActiveTeam,
                installedAppCount: team.installedApps.count,
                certificateStatus: status
            )
        }

        tableView.reloadData()
    }

    /// Newest expiry date of the locally cached certificates belonging to
    /// each given team, keyed by team identifier. A certificate belongs to
    /// a team when its subject or issuer contains the team identifier (same
    /// match CertificatesViewModel uses to spot third-party certificates).
    private static func latestCertificateExpiryByTeamIdentifier(_ identifiers: Set<String>) -> [String: Date]
    {
        guard !identifiers.isEmpty else { return [:] }

        var certificates = CertificateManager.shared.getAllLocalCertificates()
        if let active = CertificateManager.shared.activeCertificate?.certificate
        {
            certificates.append(active)
        }

        var seenSerials = Set<String>()
        var latest: [String: Date] = [:]
        for certificate in certificates
        {
            guard seenSerials.insert(certificate.serialNumber).inserted else { continue }
            guard let data = certificate.data else { continue }
            let details = parseCertificate(derData: data)
            guard let validUntil = details.validUntil else { continue }
            for identifier in identifiers
                where details.subject.contains(identifier) || details.issuer.contains(identifier)
            {
                if latest[identifier] == nil || validUntil > latest[identifier]!
                {
                    latest[identifier] = validUntil
                }
            }
        }
        return latest
    }

    /// Activates the newest still-valid locally cached certificate belonging
    /// to the given team, if one exists. Returns false when no matching
    /// valid certificate is cached (the user then has to sign in again to
    /// provision one). Never touches certificates of other teams.
    @discardableResult
    private static func activateMatchingCertificate(forTeamIdentifier identifier: String) -> Bool
    {
        var certificates = CertificateManager.shared.getAllLocalCertificates()
        if let active = CertificateManager.shared.activeCertificate?.certificate
        {
            certificates.append(active)
        }

        var seenSerials = Set<String>()
        var best: (certificate: ALTCertificate, validUntil: Date)?
        let now = Date()
        for certificate in certificates
        {
            guard seenSerials.insert(certificate.serialNumber).inserted else { continue }
            guard let data = certificate.data else { continue }
            let details = parseCertificate(derData: data)
            guard let validUntil = details.validUntil, validUntil > now else { continue }
            guard details.subject.contains(identifier) || details.issuer.contains(identifier) else { continue }
            if best == nil || validUntil > best!.validUntil
            {
                best = (certificate, validUntil)
            }
        }

        guard let best else { return false }
        do
        {
            try CertificateManager.shared.setActiveCertificate(best.certificate)
            return true
        }
        catch
        {
            debugLog("[AppleIDsVC] Failed to activate certificate for team \(identifier): \(error)")
            return false
        }
    }

    // MARK: - Actions

    private func showActions(for row: TeamRow, sourceView: UIView)
    {
        let alert = UIAlertController(
            title: row.appleID,
            message: "\(row.teamName) · \(row.teamType.localizedDescription)",
            preferredStyle: .actionSheet
        )
        if !row.isActive
        {
            alert.addAction(UIAlertAction(
                title: NSLocalizedString("Switch to This Apple ID", comment: ""), style: .default
            ) { [weak self] _ in
                self?.switchTo(row: row)
            })
        }
        alert.addAction(UIAlertAction(
            title: NSLocalizedString("Remove Apple ID", comment: ""), style: .destructive
        ) { [weak self] _ in
            self?.confirmRemove(row: row)
        })
        alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel))
        alert.popoverPresentationController?.sourceView = sourceView
        alert.popoverPresentationController?.sourceRect = sourceView.bounds
        present(alert, animated: true)
    }

    private func switchTo(row: TeamRow)
    {
        // The Keychain holds credentials for a single Apple ID. When they
        // already belong to this team, switching is just a flag flip;
        // otherwise the user has to sign in with that Apple ID — the
        // sign-in flow re-activates the existing team and provisions its
        // certificate.
        if AuthManager.shared.currentAppleID?.lowercased() == row.appleID.lowercased()
        {
            Task { @MainActor [weak self] in
                guard let self else { return }
                do
                {
                    try await AuthManager.shared.switchActiveTeam(to: row.teamIdentifier)
                    let foundCertificate = Self.activateMatchingCertificate(forTeamIdentifier: row.teamIdentifier)
                    self.reload()
                    ToastView(
                        text: String(format: NSLocalizedString("Switched to %@", comment: ""), row.appleID),
                        detailText: foundCertificate ? nil : NSLocalizedString(
                            "No local certificate was found for this team. Sign in again to provision one.", comment: "")
                    ).show(in: self)
                }
                catch
                {
                    ToastView(error: error).show(in: self.view)
                }
            }
        }
        else
        {
            let alert = UIAlertController(
                title: row.appleID,
                message: NSLocalizedString(
                    "Sign in again with this Apple ID to switch to it. Your other Apple IDs stay saved on this device.", comment: ""),
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(
                title: NSLocalizedString("Sign In & Switch", comment: ""), style: .default
            ) { [weak self] _ in
                self?.signIn()
            })
            alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel))
            present(alert, animated: true)
        }
    }

    private func confirmRemove(row: TeamRow)
    {
        let alert = UIAlertController(
            title: String(format: NSLocalizedString("Remove %@", comment: ""), row.appleID),
            message: NSLocalizedString(
                "This removes the Apple ID and its team records from this device. Installed apps are not affected, and the signing certificate is not revoked.", comment: ""),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(
            title: NSLocalizedString("Remove Apple ID", comment: ""), style: .destructive
        ) { [weak self] _ in
            self?.performRemove(row: row)
        })
        alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel))
        present(alert, animated: true)
    }

    private func performRemove(row: TeamRow)
    {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do
            {
                if row.isActive
                {
                    // Clear the stored sign-in (tokens + cached team/session)
                    // but keep the local certificate: removal never revokes
                    // anything, on this device or on Apple's servers.
                    await AuthManager.shared.signOut(keepCertificate: true)
                }
                try await Self.deleteAccount(objectID: row.accountObjectID)
                self.reload()
                ToastView(
                    text: String(format: NSLocalizedString("Removed %@", comment: ""), row.appleID),
                    detailText: nil
                ).show(in: self)
            }
            catch
            {
                ToastView(error: error).show(in: self.view)
            }
        }
    }

    /// Deletes an account and its teams from the local database. The model
    /// cascades the delete to the account's teams (and their App IDs) and
    /// nulls the team reference of installed apps, so installed apps keep
    /// working. This is purely local: nothing is revoked on Apple's servers.
    private static func deleteAccount(objectID: NSManagedObjectID) async throws
    {
        let context = DatabaseManager.shared.persistentContainer.newBackgroundContext()
        try await context.perform {
            guard let account = try? context.existingObject(with: objectID) as? Account else { return }
            context.delete(account)
            try context.save()
        }
        await DatabaseManager.shared.viewContext.perform {
            DatabaseManager.shared.viewContext.processPendingChanges()
            DatabaseManager.shared.viewContext.refreshAllObjects()
        }
    }

    /// Runs the normal sign-in flow. Signing in with a new Apple ID adds it
    /// (and makes it active); signing in with an already stored ID
    /// re-activates that team and provisions its certificate.
    private func signIn()
    {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do
            {
                let result = try await AuthManager.shared.signIn(presentingViewController: self)
                debugLog("[AppleIDsVC] Signed in for team: \(result.team.name) (\(result.team.identifier))")
            }
            catch is CancellationError
            {
                debugLog("[AppleIDsVC] Sign-in cancelled by user")
            }
            catch
            {
                debugLog("[AppleIDsVC] Sign-in failed: \(error)")
                ToastView(error: error).show(in: self.view)
            }
            self.reload()
        }
    }

    // MARK: - Cell

    private final class AppleIDCell: ShellCardCell
    {
        static let reuseIdentifier = "AppleIDCell"

        private let iconImageView: UIImageView = {
            let imageView = UIImageView()
            imageView.contentMode = .scaleAspectFit
            imageView.translatesAutoresizingMaskIntoConstraints = false
            return imageView
        }()

        private let titleLabel: UILabel = {
            let label = UILabel()
            label.font = ShellTheme.rowTitleFont
            label.textColor = ShellTheme.primaryText
            label.numberOfLines = 1
            label.translatesAutoresizingMaskIntoConstraints = false
            return label
        }()

        private let detailLabel: UILabel = {
            let label = UILabel()
            label.font = ShellTheme.rowValueFont
            label.textColor = ShellTheme.secondaryText
            label.numberOfLines = 2
            label.translatesAutoresizingMaskIntoConstraints = false
            return label
        }()

        override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?)
        {
            super.init(style: style, reuseIdentifier: reuseIdentifier)

            contentView.addSubview(iconImageView)
            contentView.addSubview(titleLabel)
            contentView.addSubview(detailLabel)

            NSLayoutConstraint.activate([
                iconImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
                iconImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
                iconImageView.widthAnchor.constraint(equalToConstant: ShellTheme.rowIconSize),
                iconImageView.heightAnchor.constraint(equalToConstant: ShellTheme.rowIconSize),

                titleLabel.leadingAnchor.constraint(equalTo: iconImageView.trailingAnchor, constant: 12),
                titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
                titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),

                detailLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
                detailLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
                detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
                detailLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
            ])
        }

        override func prepareForReuse()
        {
            super.prepareForReuse()
            accessoryType = .none
            tintColor = nil
        }

        func configure(row: TeamRow)
        {
            iconImageView.image = UIImage(systemName: "person.crop.circle")
            iconImageView.tintColor = ShellTheme.accentColor
            titleLabel.text = row.appleID

            var firstLine = "\(row.teamName) · \(row.teamType.localizedDescription)"
            if row.installedAppCount > 0
            {
                firstLine += " · " + String(
                    format: NSLocalizedString("%d Apps", comment: ""), row.installedAppCount)
            }
            detailLabel.text = firstLine + "\n" + row.certificateStatus.text

            if row.isActive
            {
                accessoryType = .checkmark
                tintColor = ShellTheme.accentColor
            }
            else
            {
                accessoryType = .none
            }
        }
    }
}

// MARK: - UITableViewDataSource / Delegate

extension AppleIDsViewController: UITableViewDataSource, UITableViewDelegate
{
    func numberOfSections(in tableView: UITableView) -> Int
    {
        return Section.allCases.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int
    {
        switch Section(rawValue: section)
        {
        case .teams: return teams.isEmpty ? 1 : teams.count
        case .add: return 1
        case .none: return 0
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell
    {
        switch Section(rawValue: indexPath.section)
        {
        case .teams:
            if teams.isEmpty
            {
                let cell = tableView.dequeueReusableCell(withIdentifier: SettingRowCell.reuseIdentifier, for: indexPath) as! SettingRowCell
                cell.configureCardBackground(position: .single)
                cell.configureInfo(
                    iconSystemName: "person.crop.circle", iconTint: ShellTheme.accentColor,
                    title: NSLocalizedString("No Apple IDs Yet", comment: ""),
                    value: nil)
                return cell
            }
            let cell = tableView.dequeueReusableCell(withIdentifier: AppleIDCell.reuseIdentifier, for: indexPath) as! AppleIDCell
            let position: ShellCardPosition
            if teams.count == 1 { position = .single }
            else if indexPath.row == 0 { position = .top }
            else if indexPath.row == teams.count - 1 { position = .bottom }
            else { position = .middle }
            cell.configureCardBackground(position: position)
            cell.configure(row: teams[indexPath.row])
            return cell

        case .add:
            let cell = tableView.dequeueReusableCell(withIdentifier: SettingRowCell.reuseIdentifier, for: indexPath) as! SettingRowCell
            cell.configureCardBackground(position: .single)
            cell.configure(
                iconSystemName: "plus.circle", iconTint: ShellTheme.accentColor,
                title: NSLocalizedString("Add Apple ID", comment: ""))
            return cell

        case .none:
            return UITableViewCell()
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath)
    {
        tableView.deselectRow(at: indexPath, animated: true)

        switch Section(rawValue: indexPath.section)
        {
        case .teams:
            guard !teams.isEmpty,
                  let cell = tableView.cellForRow(at: indexPath) else { return }
            showActions(for: teams[indexPath.row], sourceView: cell)
        case .add:
            signIn()
        case .none:
            break
        }
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String?
    {
        guard Section(rawValue: section) == .teams else { return nil }
        return NSLocalizedString(
            "Signing and refreshing use the active Apple ID. Switching to another Apple ID signs you in again with that account when needed.", comment: "")
    }
}
#endif
