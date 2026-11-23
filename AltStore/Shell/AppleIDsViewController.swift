#if os(iOS)
//
//  AppleIDsViewController.swift
//  openSSS
//
//  Manage the stored Apple IDs (teams): list every signed-in Apple ID with
//  its team and certificate status, switch the active team used for signing
//  and refreshing, add a new Apple ID through the normal sign-in flow, sign
//  out of the active Apple ID (the account stays listed so it can be
//  switched back to later), or remove an Apple ID from this device.
//  Removing an ID only deletes local records; it never revokes the signing
//  certificate on Apple's servers. The active team's action sheet also
//  offers Complete Pending Actions, which runs the device-registration /
//  certificate-provisioning steps skipped at sign-in (the sign-in flow's
//  skip alerts point here).
//
//  After switching to another Apple ID, the user is offered to re-sign all
//  installed apps with it. This deliberately goes through the resign
//  pipeline (AppManager.resign, one app at a time), NOT the refresh
//  pipeline: refresh only fetches and installs provisioning profiles for
//  the active team and never touches the app binary, so a refreshed app
//  would stay signed by the old team and stop launching once the old
//  team's profile expires. Re-signing is never automatic: the
//  confirmation alert warns that signing may create a new certificate and
//  revoke the existing one (free accounts are limited to 1 active
//  certificate), and the resign only runs after the user confirms.
//  openSSS itself is excluded — it has its own dedicated resign flow, and
//  the per-app menu excludes it too.
//
//  Note: the Keychain holds credentials for a single Apple ID, so switching
//  to a team whose Apple ID has no stored credentials asks the user to sign
//  in again with that ID (the sign-in flow re-activates the existing team
//  and provisions its certificate). Per-app team assignment is not
//  supported by the engine — refresh always signs with the active team —
//  so active-team switching is the whole feature.
//
//  Copyright © 2026 openSSS Contributors. All rights reserved.
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

    /// Guards against starting a second re-sign-all while one is running.
    private var isResigningAll = false

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
        else
        {
            // The sign-in flow's skip acknowledgments point here: device
            // registration / certificate provisioning skipped at sign-in
            // is completed from this screen (AccountVerificationRow's
            // existing flows — nothing is reimplemented). Only the active
            // team can be completed: the developer-portal session belongs
            // to the signed-in Apple ID.
            alert.addAction(UIAlertAction(
                title: NSLocalizedString("Complete Pending Actions", comment: ""), style: .default
            ) { [weak self] _ in
                self?.completePendingActions(for: row)
            })
            // Only offer re-signing when there is something to re-sign.
            if !Self.appsToResign().isEmpty
            {
                alert.addAction(UIAlertAction(
                    title: NSLocalizedString("Resign All Apps", comment: ""), style: .default
                ) { [weak self] _ in
                    self?.confirmResignAll(for: row, afterSwitch: false)
                })
            }
            // Sign-out lives here now that the Me tab has a single Apple ID
            // entry: it clears the stored sign-in but keeps the account
            // listed, unlike Remove which deletes the local records.
            alert.addAction(UIAlertAction(
                title: NSLocalizedString("Sign Out", comment: ""), style: .destructive
            ) { [weak self] _ in
                self?.confirmSignOut()
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

    /// Completes the account setup skipped at sign-in (device registration
    /// and/or signing-certificate provisioning) for the active team, using
    /// the existing AccountVerificationRow flows — the same code the old
    /// Settings screen used. When nothing is pending, this just confirms
    /// the account is fully set up.
    private func completePendingActions(for row: TeamRow)
    {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do
            {
                let team = try await AuthManager.shared.getAuthenticatedTeam()
                guard team.identifier == row.teamIdentifier else
                {
                    // The active team changed under us; refresh the list
                    // instead of running flows against the wrong team.
                    self.reload()
                    return
                }
                let status = await AccountVerificationRow.verifyStatus(for: team)
                switch status
                {
                case .completed:
                    ToastView(
                        text: NSLocalizedString("Account Setup Complete", comment: ""),
                        detailText: NSLocalizedString("Device registration and signing certificate are ready.", comment: "")
                    ).show(in: self)
                case .checking:
                    break
                case .actionRequired:
                    await AccountVerificationRow.resolvePendingActions(for: status, team: team, presentingViewController: self)
                    self.reload()
                }
            }
            catch
            {
                ToastView(error: error).show(in: self.view)
            }
        }
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
                    if foundCertificate
                    {
                        // A cached certificate for the new team is active,
                        // so the installed apps can be re-signed with it
                        // right away. Offer — never force — the re-sign;
                        // the certificate-revocation warning is part of
                        // the confirmation alert.
                        self.offerResignAfterSwitch(for: row)
                    }
                    else
                    {
                        ToastView(
                            text: String(format: NSLocalizedString("Switched to %@", comment: ""), row.appleID),
                            detailText: NSLocalizedString(
                                "No local certificate was found for this team. Sign in again to provision one.", comment: "")
                        ).show(in: self)
                    }
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
                self?.signIn(offerResignAfterSwitch: true)
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

    /// Signs out of the active Apple ID (moved here from the Me tab when
    /// its two Apple ID rows were merged into one). The account and its
    /// teams stay listed, so the user can switch back to them later;
    /// only the stored sign-in is cleared. The checkboxes decide what
    /// survives the sign-out — by default the certificate is kept, so
    /// sign-out never revokes anything on Apple's servers.
    private func confirmSignOut()
    {
        let contentVC = SignOutAlertViewController()

        let alertController = UIAlertController(
            title: NSLocalizedString("Sign Out", comment: ""),
            message: NSLocalizedString("Are you sure you want to sign out? You will no longer be able to install or refresh apps once you sign out.", comment: ""),
            preferredStyle: .alert
        )
        alertController.setValue(contentVC, forKey: "contentViewController")

        let cancelAction = UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel, handler: nil)
        let signOutAction = UIAlertAction(title: NSLocalizedString("Sign Out", comment: ""), style: .destructive) { [weak self] _ in
            let keepCert = contentVC.isChecked
            let keepAnisette = contentVC.isKeepAnisetteChecked
            let keepAnisetteHeaders = contentVC.isKeepAnisetteHeadersChecked
            let keepSideSignHeaders = contentVC.isKeepSideSignHeadersChecked
            Task.detached { [weak self] in
                await AuthManager.shared.signOut(
                    keepCertificate: keepCert,
                    keepAnisetteData: keepAnisette,
                    keepAnisetteHeaders: keepAnisetteHeaders,
                    keepSideSignHeaders: keepSideSignHeaders
                )
                await MainActor.run {
                    self?.reload()
                }
            }
        }

        alertController.addAction(cancelAction)
        alertController.addAction(signOutAction)
        present(alertController, animated: true)
    }

    /// Runs the normal sign-in flow. Signing in with a new Apple ID adds it
    /// (and makes it active); signing in with an already stored ID
    /// re-activates that team and provisions its certificate.
    ///
    /// When `offerResignAfterSwitch` is set (sign-in-driven switch only),
    /// a successful sign-in offers to re-sign the installed apps with the
    /// newly active team. A failed or cancelled sign-in never offers it:
    /// the previously active team must not be re-signed by mistake.
    private func signIn(offerResignAfterSwitch: Bool = false)
    {
        Task { @MainActor [weak self] in
            guard let self else { return }
            var didSignIn = false
            do
            {
                let result = try await AuthManager.shared.signIn(presentingViewController: self)
                debugLog("[AppleIDsVC] Signed in for team: \(result.team.name) (\(result.team.identifier))")
                didSignIn = true
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
            // Sign-in provisions the new team's certificate, so no local
            // certificate check is needed here (unlike the flag-flip
            // switch path, which only offers re-signing when a cached
            // certificate for the team was found).
            if offerResignAfterSwitch,
               didSignIn,
               let activeRow = self.teams.first(where: \.isActive)
            {
                self.offerResignAfterSwitch(for: activeRow)
            }
        }
    }

    // MARK: - Re-sign after switching

    /// The installed apps re-signing covers: the same set Renew All
    /// refreshes, minus openSSS itself (it has its own dedicated resign
    /// flow, and the per-app menu excludes it too).
    private static func appsToResign() -> [InstalledApp]
    {
        InstalledApp.fetchAppsForRefreshingAll(in: DatabaseManager.shared.viewContext)
            .filter { $0.bundleIdentifier != StoreApp.altstoreAppID }
    }

    /// After a successful switch, offers to re-sign the installed apps
    /// with the new team. With nothing installed there is nothing to
    /// re-sign, so this just confirms the switch with a toast.
    private func offerResignAfterSwitch(for row: TeamRow)
    {
        guard !Self.appsToResign().isEmpty else
        {
            ToastView(
                text: String(format: NSLocalizedString("Switched to %@", comment: ""), row.appleID),
                detailText: nil
            ).show(in: self)
            return
        }
        confirmResignAll(for: row, afterSwitch: true)
    }

    /// The certificate-risk warning, shown before anything that could
    /// revoke a certificate: the re-sign in `resignAllApps` only runs
    /// after the user taps Resign here. The wording mirrors the resign
    /// screen's free-account warning (1 active certificate; creating a
    /// new one automatically revokes the existing one).
    private func confirmResignAll(for row: TeamRow, afterSwitch: Bool)
    {
        let title = afterSwitch
            ? String(format: NSLocalizedString("Switched to %@", comment: ""), row.appleID)
            : NSLocalizedString("Resign All Apps", comment: "")
        let alert = UIAlertController(
            title: title,
            message: String(format: NSLocalizedString("Resign all installed apps with %@? Free developer accounts are limited to 1 active signing certificate, so signing may create a new certificate and automatically revoke the existing one, which may disable installations on other devices or made by Xcode.", comment: ""), row.appleID),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: NSLocalizedString("Resign", comment: ""), style: .default) { [weak self] _ in
            self?.resignAllApps()
        })
        if afterSwitch
        {
            alert.addAction(UIAlertAction(title: NSLocalizedString("Resign Later", comment: ""), style: .cancel))
        }
        else
        {
            alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel))
        }
        present(alert, animated: true)
    }

    /// Re-signs every installed app with the active team by running the
    /// existing per-app resign pipeline (`AppManager.resign`, the same
    /// call the Apps tab's Re-sign action makes) one app at a time, in
    /// expiry order. The resign pipeline resolves the team via
    /// `getAuthenticatedTeam()`, which reads the team just switched to,
    /// so no signing logic is duplicated here.
    ///
    /// This must NOT go through `AppManager.refresh`: the refresh step
    /// list (`PipelineStepDefinition.refresh`) has no `.resignApp` step —
    /// it only fetches and installs provisioning profiles for the active
    /// team. A profile only authorizes binaries signed with a certificate
    /// it contains, so a refreshed app would stay signed by the old team
    /// and stop launching once the old team's profile expires, while
    /// refresh still reported success. Needs proper testing on a real
    /// device: the pipeline presents its own UI through this view
    /// controller, and an app whose cached bundle is gone fails with an
    /// error asking for the original IPA.
    private func resignAllApps()
    {
        guard !isResigningAll else { return }

        let installedApps = Self.appsToResign()
        guard !installedApps.isEmpty else
        {
            ToastView(error: OperationError.noInstalledApps).show(in: self)
            return
        }

        isResigningAll = true
        ToastView(
            text: String(format: NSLocalizedString("Resigning %d apps…", comment: ""), installedApps.count),
            detailText: nil
        ).show(in: self)

        resignNext(remaining: installedApps, failures: [], attempted: 0)
    }

    /// Resigns the remaining apps one at a time (the resign pipeline is
    /// per-app; there is no batch resign). Apps already mid-operation are
    /// skipped, not failed. When the queue drains, reports the outcome:
    /// a success toast (this screen shows no per-app progress, so it is
    /// the only completion signal), the single error, or a count with a
    /// link to the diagnostic log.
    private func resignNext(remaining: [InstalledApp], failures: [Error], attempted: Int)
    {
        guard let next = remaining.first else
        {
            isResigningAll = false
            if failures.isEmpty
            {
                if attempted > 0
                {
                    ToastView(text: NSLocalizedString("All apps have been resigned.", comment: ""), detailText: nil).show(in: self)
                }
            }
            else if failures.count == 1, let failure = failures.first
            {
                ToastView(error: failure).show(in: self)
            }
            else
            {
                let text = String(format: NSLocalizedString("%d apps failed to resign", comment: ""), failures.count)
                ToastView(text: text, detailText: nil, opensLog: true).show(in: self)
            }
            reload()
            return
        }

        let rest = Array(remaining.dropFirst())

        // Already mid-operation (e.g. Renew All is running): leave it to
        // that operation instead of queueing a conflicting resign.
        guard AppManager.shared.refreshProgress(for: next) == nil else
        {
            resignNext(remaining: rest, failures: failures, attempted: attempted)
            return
        }

        AppManager.shared.resign(next, alternateIconMode: .preserve, presentingViewController: self) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                var failures = failures
                if case .failure(let error) = result, !(error is CancellationError)
                {
                    failures.append(error)
                }
                self.resignNext(remaining: rest, failures: failures, attempted: attempted + 1)
            }
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
                // No dead end while signed out: tapping this row signs in,
                // just like the Add Apple ID row below.
                cell.configureInfo(
                    iconSystemName: "person.crop.circle", iconTint: ShellTheme.accentColor,
                    title: NSLocalizedString("No Apple IDs Yet", comment: ""),
                    value: NSLocalizedString("Sign In", comment: ""))
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
            if teams.isEmpty
            {
                signIn()
                return
            }
            guard let cell = tableView.cellForRow(at: indexPath) else { return }
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
