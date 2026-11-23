#if os(iOS)
//
//  PendingIPAStore.swift
//  openSSS
//
//  The "Pending" queue behind the Apps tab's 待安装 list: .ipa files the user
//  imports (from Files, a URL, or another app's "Open in") wait here until
//  they are installed. Each entry keeps the .ipa file, a parsed icon, and the
//  metadata read from the bundle, so the list renders without re-parsing.
//
//  Files live in the app's private Documents/PendingIPAs directory (not the
//  App Group container), so the queue works even when the App Group container
//  is unavailable.
//
//  Copyright © 2026 openSSS Contributors. All rights reserved.
//

import UIKit

import SideSign

/// A single .ipa waiting to be installed.
struct PendingIPA: Codable, Identifiable, Hashable, Sendable
{
    /// Stable identifier; also the file stem of the stored .ipa/.png.
    let id: String
    let name: String
    let version: String
    let bundleIdentifier: String
    let addedDate: Date
    let hasIcon: Bool

    var fileName: String { "\(id).ipa" }
    var iconFileName: String { "\(id).png" }
}

enum PendingIPAError: LocalizedError
{
    case invalidIPA
    case copyFailed

    var errorDescription: String?
    {
        switch self
        {
        case .invalidIPA:
            return NSLocalizedString("This file is not a valid .ipa package.", comment: "")
        case .copyFailed:
            return NSLocalizedString("Could not copy the .ipa file into openSSS.", comment: "")
        }
    }
}

/// Owns the pending-install queue. Main-actor isolated; heavy work (copying
/// and unzipping) runs in detached tasks.
@MainActor
final class PendingIPAStore
{
    static let shared = PendingIPAStore()

    static let didChangeNotification = Notification.Name("openSSS.PendingIPAStore.didChange")

    private(set) var items: [PendingIPA] = []

    var directoryURL: URL
    {
        FileManager.default.documentsDirectory.appendingPathComponent("PendingIPAs", isDirectory: true)
    }

    private var indexURL: URL
    {
        directoryURL.appendingPathComponent("index.json")
    }

    private init()
    {
        self.loadIndex()
    }

    // MARK: - Access

    func ipaURL(for item: PendingIPA) -> URL
    {
        directoryURL.appendingPathComponent(item.fileName)
    }

    func icon(for item: PendingIPA) -> UIImage?
    {
        guard item.hasIcon else { return Self.placeholderIcon(for: item.name) }

        let iconURL = directoryURL.appendingPathComponent(item.iconFileName)
        guard let data = try? Data(contentsOf: iconURL),
              let image = UIImage(data: data) else {
            return Self.placeholderIcon(for: item.name)
        }
        return image
    }

    /// Total bytes used by the pending queue (ipa + icon files).
    func totalSize() -> Int64
    {
        var total: Int64 = 0
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directoryURL, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        for url in urls
        {
            total += (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { Int64($0) } ?? 0
        }
        return total
    }

    // MARK: - Mutation

    /// Imports an .ipa into the queue, parsing its metadata. The source may
    /// be a local file URL (Files picker, "Open in") or a remote URL (which
    /// is downloaded first). Importing an .ipa whose bundle identifier is
    /// already pending replaces the existing entry in place instead of
    /// adding a duplicate.
    func add(from sourceURL: URL) async throws -> PendingIPA
    {
        let id = UUID().uuidString
        let destinationURL = directoryURL.appendingPathComponent("\(id).ipa")

        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        // Copy (or download) + parse off the main actor. A failed import
        // (bad .ipa, failed download) removes the copied file again: an
        // orphaned .ipa would otherwise linger in Documents/PendingIPAs
        // forever, inflating the storage breakdown with no queue entry
        // that could ever delete it.
        let parsed: ParsedIPA
        do
        {
            parsed = try await Task.detached(priority: .userInitiated) {
                if sourceURL.isFileURL
                {
                    let isScoped = sourceURL.startAccessingSecurityScopedResource()
                    defer { if isScoped { sourceURL.stopAccessingSecurityScopedResource() } }
                    do
                    {
                        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
                    }
                    catch
                    {
                        throw PendingIPAError.copyFailed
                    }
                }
                else
                {
                    let (tempURL, _) = try await URLSession.shared.download(from: sourceURL)
                    do
                    {
                        try FileManager.default.copyItem(at: tempURL, to: destinationURL)
                    }
                    catch
                    {
                        throw PendingIPAError.copyFailed
                    }
                }

                return try Self.parseIPA(at: destinationURL)
            }.value
        }
        catch
        {
            try? FileManager.default.removeItem(at: destinationURL)
            throw error
        }

        // Persist the icon, if any.
        var hasIcon = false
        if let icon = parsed.icon, let pngData = icon.pngData()
        {
            let iconURL = directoryURL.appendingPathComponent("\(id).png")
            if (try? pngData.write(to: iconURL)) != nil
            {
                hasIcon = true
            }
        }

        let item = PendingIPA(
            id: id,
            name: parsed.name,
            version: parsed.version,
            bundleIdentifier: parsed.bundleIdentifier,
            addedDate: Date(),
            hasIcon: hasIcon
        )

        // Re-importing an .ipa for an app that is already pending replaces
        // the existing entry in place (preserving list order) instead of
        // adding a duplicate; the replaced entry's files are removed.
        if let index = items.firstIndex(where: { $0.bundleIdentifier == item.bundleIdentifier })
        {
            let oldItem = items[index]
            items[index] = item
            try? FileManager.default.removeItem(at: ipaURL(for: oldItem))
            try? FileManager.default.removeItem(at: directoryURL.appendingPathComponent(oldItem.iconFileName))
        }
        else
        {
            items.insert(item, at: 0)
        }
        saveIndex()
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
        return item
    }

    func remove(_ item: PendingIPA)
    {
        items.removeAll { $0.id == item.id }
        try? FileManager.default.removeItem(at: ipaURL(for: item))
        try? FileManager.default.removeItem(at: directoryURL.appendingPathComponent(item.iconFileName))
        saveIndex()
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
    }

    func removeAll()
    {
        for item in items
        {
            try? FileManager.default.removeItem(at: ipaURL(for: item))
            try? FileManager.default.removeItem(at: directoryURL.appendingPathComponent(item.iconFileName))
        }
        items.removeAll()
        saveIndex()
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
    }

    // MARK: - Parsing

    private struct ParsedIPA
    {
        let name: String
        let version: String
        let bundleIdentifier: String
        let icon: UIImage?
    }

    /// Unzips an .ipa to a temporary directory and reads the .app metadata
    /// with SideSign's bundle parser. Runs off the main actor.
    private nonisolated static func parseIPA(at ipaURL: URL) throws -> ParsedIPA
    {
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory
            .appendingPathComponent("PendingIPA-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: tempDir) }

        do
        {
            try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
            try fileManager.unzipArchive(at: ipaURL, to: tempDir)
        }
        catch
        {
            throw PendingIPAError.invalidIPA
        }

        let payloadURL = tempDir.appendingPathComponent("Payload", isDirectory: true)
        guard let appURLs = try? fileManager.contentsOfDirectory(
                at: payloadURL, includingPropertiesForKeys: nil),
              let appURL = appURLs.first(where: { $0.pathExtension == "app" }),
              let appBundle = ALTApplication(fileURL: appURL) else {
            throw PendingIPAError.invalidIPA
        }

        return ParsedIPA(
            name: appBundle.name,
            version: appBundle.version,
            bundleIdentifier: appBundle.bundleIdentifier,
            icon: appBundle.icon
        )
    }

    // MARK: - Index persistence

    private func loadIndex()
    {
        guard let data = try? Data(contentsOf: indexURL),
              let decoded = try? JSONDecoder().decode([PendingIPA].self, from: data) else {
            items = []
            return
        }
        // Drop entries whose .ipa file is gone (e.g. removed from Files).
        let existing = decoded.filter { FileManager.default.fileExists(atPath: ipaURL(for: $0).path) }
        // Drop duplicates by bundle identifier (imports from before dedupe
        // could leave identical entries pending); keep the first occurrence
        // and remove the duplicate entries' files so no orphans linger.
        var seen = Set<String>()
        var deduped = [PendingIPA]()
        var changed = false
        for item in existing
        {
            if seen.contains(item.bundleIdentifier)
            {
                changed = true
                try? FileManager.default.removeItem(at: ipaURL(for: item))
                try? FileManager.default.removeItem(at: directoryURL.appendingPathComponent(item.iconFileName))
            }
            else
            {
                seen.insert(item.bundleIdentifier)
                deduped.append(item)
            }
        }
        items = deduped
        if changed
        {
            saveIndex()
        }
    }

    private func saveIndex()
    {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: indexURL)
    }

    // MARK: - Placeholder icon

    /// Gray rounded-square placeholder with the app's first letter.
    static func placeholderIcon(for name: String) -> UIImage
    {
        let size = CGSize(width: 120, height: 120)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            let rect = CGRect(origin: .zero, size: size)
            let path = UIBezierPath(roundedRect: rect, cornerRadius: 27)
            UIColor(hex: 0x3A3D4D).setFill()
            path.fill()

            let letter = name.first.map { String($0).uppercased() } ?? "?"
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 56, weight: .bold),
                .foregroundColor: UIColor.white.withAlphaComponent(0.85),
            ]
            let textSize = letter.size(withAttributes: attributes)
            let textRect = CGRect(
                x: (size.width - textSize.width) / 2,
                y: (size.height - textSize.height) / 2,
                width: textSize.width,
                height: textSize.height
            )
            letter.draw(in: textRect, withAttributes: attributes)
        }
    }
}
#endif
