#if os(iOS)
//
//  StorageViewController.swift
//  oPenSSAI
//
//  Storage & Cleanup: a breakdown of what the app stores in its private
//  sandbox, with actions to clear caches and delete pending .ipa files.
//  All sizes are computed live from the file system.
//
//  Copyright © 2026 oPenSSAI Contributors. All rights reserved.
//

import UIKit

import Nuke

/// Live file-system size accounting for the app's private sandbox.
enum ShellStorage
{
    static func directorySize(at url: URL) -> Int64
    {
        var total: Int64 = 0
        let resourceKeys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: Array(resourceKeys)) else { return 0 }
        for case let fileURL as URL in enumerator
        {
            guard let values = try? fileURL.resourceValues(forKeys: resourceKeys),
                  values.isRegularFile == true else { continue }
            total += Int64(values.fileSize ?? 0)
        }
        return total
    }

    static func formattedSize(_ bytes: Int64) -> String
    {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private static var documentsURL: URL { FileManager.default.documentsDirectory }
    private static var applicationSupportURL: URL { FileManager.default.applicationSupportDirectory }
    private static var cachesURL: URL
    {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
    }

    static func documentsSize() -> Int64 { directorySize(at: documentsURL) }
    static func applicationSupportSize() -> Int64 { directorySize(at: applicationSupportURL) }
    static func cachesSize() -> Int64 { directorySize(at: cachesURL) }
    static func temporarySize() -> Int64 { directorySize(at: FileManager.default.temporaryDirectory) }

    /// Total bytes the app occupies in its private sandbox.
    static func totalAppSize() -> Int64
    {
        documentsSize() + applicationSupportSize() + cachesSize() + temporarySize()
    }

    /// Clears the image cache (memory + disk) and the tmp directory.
    /// Never touches Documents (pairing files, pending .ipas) or the database.
    static func clearCaches()
    {
        ImagePipeline.shared.cache.removeAll()

        for directory in [cachesURL, FileManager.default.temporaryDirectory]
        {
            guard let contents = try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil) else { continue }
            for url in contents
            {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }
}

final class StorageViewController: UIViewController
{
    private enum Section: Int, CaseIterable
    {
        case breakdown
        case actions

        var title: String
        {
            switch self
            {
            case .breakdown: return NSLocalizedString("Storage Breakdown", comment: "")
            case .actions: return NSLocalizedString("Cleanup", comment: "")
            }
        }
    }

    private enum BreakdownRow: Int, CaseIterable
    {
        case pendingIPAs
        case documents
        case appSupport
        case caches
        case temporary
    }

    private enum ActionRow: Int, CaseIterable
    {
        case clearCaches
        case deletePending
    }

    private var sizes: [BreakdownRow: Int64] = [:]
    private var totalSize: Int64 = 0

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

    private let totalLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 40, weight: .heavy)
        label.textColor = ShellTheme.primaryText
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let totalCaptionLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 15, weight: .regular)
        label.textColor = ShellTheme.secondaryText
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    override func viewDidLoad()
    {
        super.viewDidLoad()
        view.backgroundColor = ShellTheme.background
        title = NSLocalizedString("Storage & Cleanup", comment: "")

        totalCaptionLabel.text = NSLocalizedString("Total Storage Used", comment: "")

        let header = UIView(frame: CGRect(x: 0, y: 0, width: 0, height: 110))
        header.addSubview(totalLabel)
        header.addSubview(totalCaptionLabel)
        NSLayoutConstraint.activate([
            totalLabel.topAnchor.constraint(equalTo: header.topAnchor, constant: 16),
            totalLabel.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            totalLabel.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            totalCaptionLabel.topAnchor.constraint(equalTo: totalLabel.bottomAnchor, constant: 6),
            totalCaptionLabel.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            totalCaptionLabel.trailingAnchor.constraint(equalTo: header.trailingAnchor),
        ])
        tableView.tableHeaderView = header

        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        refreshSizes()
    }

    override var preferredStatusBarStyle: UIStatusBarStyle
    {
        return shellPreferredStatusBarStyle
    }

    private func refreshSizes()
    {
        Task { @MainActor [weak self] in
            guard let self else { return }
            // PendingIPAStore is main-actor isolated; read it here, then
            // enumerate the (potentially large) directories off the main actor.
            let pending = PendingIPAStore.shared.totalSize()
            let (documents, appSupport, caches, temporary) = await Task.detached(priority: .utility) {
                (
                    ShellStorage.documentsSize(),
                    ShellStorage.applicationSupportSize(),
                    ShellStorage.cachesSize(),
                    ShellStorage.temporarySize()
                )
            }.value

            // Pending .ipas live inside Documents, so show Documents net of
            // them — otherwise the breakdown rows would sum past the total.
            self.sizes = [
                .pendingIPAs: pending,
                .documents: max(documents - pending, 0),
                .appSupport: appSupport,
                .caches: caches,
                .temporary: temporary,
            ]
            self.totalSize = documents + appSupport + caches + temporary
            self.totalLabel.text = ShellStorage.formattedSize(self.totalSize)
            self.tableView.reloadData()
        }
    }

    private func clearCaches()
    {
        Task.detached(priority: .utility) {
            ShellStorage.clearCaches()
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.refreshSizes()
                ToastView(
                    text: NSLocalizedString("Cache Cleared", comment: ""),
                    detailText: nil
                ).show(in: self)
            }
        }
    }

    private func deletePendingFiles()
    {
        guard !PendingIPAStore.shared.items.isEmpty else { return }

        let alert = UIAlertController(
            title: NSLocalizedString("Delete Pending Files?", comment: ""),
            message: NSLocalizedString("This deletes all .ipa files waiting to be installed. Installed apps are not affected.", comment: ""),
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel))
        alert.addAction(UIAlertAction(title: NSLocalizedString("Delete", comment: ""), style: .destructive) { [weak self] _ in
            PendingIPAStore.shared.removeAll()
            self?.refreshSizes()
        })
        present(alert, animated: true)
    }
}

extension StorageViewController: UITableViewDataSource, UITableViewDelegate
{
    func numberOfSections(in tableView: UITableView) -> Int
    {
        return Section.allCases.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int
    {
        switch Section(rawValue: section)
        {
        case .breakdown: return BreakdownRow.allCases.count
        case .actions: return ActionRow.allCases.count
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
        case .breakdown:
            let row = BreakdownRow(rawValue: indexPath.row)
            let sizeText = sizes[row ?? .documents].map { ShellStorage.formattedSize($0) }
            switch row
            {
            case .pendingIPAs:
                cell.configureInfo(
                    iconSystemName: "arrow.down.app", iconTint: accent,
                    title: NSLocalizedString("Pending .ipa Files", comment: ""),
                    value: sizeText)
            case .documents:
                cell.configureInfo(
                    iconSystemName: "folder", iconTint: accent,
                    title: NSLocalizedString("Documents", comment: ""),
                    value: sizeText)
            case .appSupport:
                cell.configureInfo(
                    iconSystemName: "cylinder.split.1x2", iconTint: accent,
                    title: NSLocalizedString("Database & Settings", comment: ""),
                    value: sizeText)
            case .caches:
                cell.configureInfo(
                    iconSystemName: "photo", iconTint: accent,
                    title: NSLocalizedString("Image Cache", comment: ""),
                    value: sizeText)
            case .temporary:
                cell.configureInfo(
                    iconSystemName: "trash", iconTint: accent,
                    title: NSLocalizedString("Temporary Files", comment: ""),
                    value: sizeText)
            case .none:
                break
            }

        case .actions:
            switch ActionRow(rawValue: indexPath.row)
            {
            case .clearCaches:
                cell.configure(
                    iconSystemName: "paintbrush", iconTint: accent,
                    title: NSLocalizedString("Clear Cache", comment: ""))
            case .deletePending:
                cell.configure(
                    iconSystemName: "trash", iconTint: ShellTheme.expiredRed,
                    title: NSLocalizedString("Delete Pending Files", comment: ""))
            case .none:
                break
            }

        case .none:
            break
        }

        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath)
    {
        tableView.deselectRow(at: indexPath, animated: true)

        guard Section(rawValue: indexPath.section) == .actions else { return }
        switch ActionRow(rawValue: indexPath.row)
        {
        case .clearCaches:
            clearCaches()
        case .deletePending:
            deletePendingFiles()
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
