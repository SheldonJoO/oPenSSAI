//
//  PairingFileManager.swift
//  SideStore
//
//  Created by Magesh K on 17/06/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import Foundation
import UniformTypeIdentifiers
import MinimuxerCommon

public struct PairingFileMetadata: Sendable {
    public let exists: Bool
    public let size: Int64
    public let creationDate: Date?
    public let modificationDate: Date?
}

final class PairingFileManager: NSObject {
    static let shared = PairingFileManager()

    static var supportedContentTypes: [UTType] {
        var types = AppConstants.Pairing.supportedExtensions.compactMap { UTType(filenameExtension: $0) }
        types.append(contentsOf: [.propertyList, .xml])
        return types
    }

    var activeProtocol: PairingProtocol {
        minimuxerPairingProtocol()
    }

    var persistedActiveProtocol: PairingProtocol? {
        get { UserDefaults.standard.activePairingProtocol }
        set { UserDefaults.standard.activePairingProtocol = newValue }
    }

    var preferredProtocol: PairingProtocol? {
        get { UserDefaults.standard.preferredPairingProtocol }
        set { UserDefaults.standard.preferredPairingProtocol = newValue }
    }

    nonisolated func pairingFileURL(for mode: PairingProtocol) -> URL {
        let fileName = mode == .rppairing ? AppConstants.Pairing.remotePairingFileName : AppConstants.Pairing.lockdownPairingFileName
        return FileManager.default.documentsDirectory.appendingPathComponent(fileName)
    }

    /// Pairing files written under a legacy (non-canonical) name.
    ///
    /// Wireless pairing writes the file under a device-derived name
    /// (`<name>_<model>_rp.plist`, or `rp_pairing_file.plist` when the
    /// device has no name), while everything else reads the fixed
    /// `PairingFile_RemoteRP.plist` name — so a wirelessly-paired file was
    /// invisible to the management view and to boot. The legacy Lockdown
    /// name is `ALTPairingFile.mobiledevicepairing`. Needs proper testing
    /// on device.
    nonisolated func legacyPairingFileURLs(for mode: PairingProtocol) -> [URL] {
        let fm = FileManager.default
        let docs = fm.documentsDirectory
        switch mode {
        case .rppairing:
            let canonical = pairingFileURL(for: mode).lastPathComponent
            let names = (try? fm.contentsOfDirectory(atPath: docs.path)) ?? []
            return names
                .filter { $0 != canonical && ($0.hasSuffix(MinimuxerConstants.rpPairingFileSuffix) || $0 == MinimuxerConstants.defaultRPPairingFileName) }
                .map { docs.appendingPathComponent($0) }
        case .lockdown:
            let legacy = docs.appendingPathComponent(AppConstants.Pairing.legacyPairingFileName)
            return fm.fileExists(atPath: legacy.path) ? [legacy] : []
        case .unknown:
            return []
        }
    }

    /// The most recently modified legacy pairing file for `mode`, if any.
    nonisolated func legacyPairingFileURL(for mode: PairingProtocol) -> URL? {
        let fm = FileManager.default
        return legacyPairingFileURLs(for: mode).max { lhs, rhs in
            let lhsDate = (try? fm.attributesOfItem(atPath: lhs.path)[.modificationDate] as? Date) ?? .distantPast
            let rhsDate = (try? fm.attributesOfItem(atPath: rhs.path)[.modificationDate] as? Date) ?? .distantPast
            return lhsDate < rhsDate
        }
    }

    /// The canonical URL for `mode`, migrating a legacy-named file into
    /// place first. If the copy fails, the legacy URL itself is returned so
    /// the file stays usable.
    nonisolated func effectivePairingFileURL(for mode: PairingProtocol) -> URL {
        let canonical = pairingFileURL(for: mode)
        let fm = FileManager.default
        if fm.fileExists(atPath: canonical.path) { return canonical }
        guard let legacy = legacyPairingFileURL(for: mode) else { return canonical }
        do {
            try fm.copyItem(at: legacy, to: canonical)
            debugLog("[PairingFile] Migrated legacy \(mode.rawValue) pairing file to canonical name: \(legacy.lastPathComponent)")
        } catch {
            debugLog("[PairingFile] Failed to migrate legacy pairing file \(legacy.path): \(error)")
            return legacy
        }
        return canonical
    }

    nonisolated func hasPairingFile(for mode: PairingProtocol) -> Bool {
        return FileManager.default.fileExists(atPath: effectivePairingFileURL(for: mode).path)
    }

    nonisolated func hasPairingFile() -> Bool {
        guard !UserDefaults.standard.isPairingReset else { return false }
        if let target = preferredProtocol, hasPairingFile(for: target) {
            return true
        }
        if let mode = persistedActiveProtocol, hasPairingFile(for: mode) {
            return true
        }
        // Fallback: a pairing file exists on disk but no protocol preference
        // was ever recorded (e.g. written by wireless pairing before the
        // import step existed). Report it instead of "not paired".
        return hasPairingFile(for: .rppairing) || hasPairingFile(for: .lockdown)
    }

    nonisolated func metadata(for mode: PairingProtocol) -> PairingFileMetadata {
        let fileURL = effectivePairingFileURL(for: mode)
        let path = fileURL.path
        let fm = FileManager.default
        guard fm.fileExists(atPath: path) else {
            return PairingFileMetadata(exists: false, size: 0, creationDate: nil, modificationDate: nil)
        }
        let attrs = (try? fm.attributesOfItem(atPath: path)) ?? [:]
        let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        let creation = (attrs[.creationDate] as? Date) ?? (attrs[.modificationDate] as? Date)
        let mod = attrs[.modificationDate] as? Date
        return PairingFileMetadata(exists: true, size: size, creationDate: creation, modificationDate: mod)
    }

    nonisolated func fetchPairingFile(for mode: PairingProtocol) -> String? {
        let fileURL = effectivePairingFileURL(for: mode)
        let fm = FileManager.default
        if fm.fileExists(atPath: fileURL.path),
           let contents = try? String(contentsOf: fileURL), !contents.isEmpty 
        {
            return contents
        }
        return nil
    }

    nonisolated func fetchPairingFile(preferred: PairingProtocol? = nil) -> String? {
        guard !UserDefaults.standard.isPairingReset else { return nil }
        let targetPreferred = preferred ?? preferredProtocol
        if let targetPreferred, let contents = fetchPairingFile(for: targetPreferred) {
            return contents
        }
        if let persisted = persistedActiveProtocol, let contents = fetchPairingFile(for: persisted) {
            return contents
        }
        // Fallback: return any on-disk pairing file so boot can start
        // minimuxer even when no protocol preference was recorded.
        return fetchPairingFile(for: .rppairing) ?? fetchPairingFile(for: .lockdown)
    }
    
    @discardableResult
    nonisolated func parse(content: String, preferred: PairingProtocol? = nil) throws -> any PairingFile {
        try PairingFileParser.parse(content: content, preferred: preferred)
    }

    @discardableResult
    func savePairingFile(contents: String, preferred: PairingProtocol? = nil) throws -> any PairingFile {
        let parsed = try parse(content: contents, preferred: preferred)
        let destinationURL = pairingFileURL(for: parsed.mode)
        let fm = FileManager.default
        if fm.fileExists(atPath: destinationURL.path) {
            try? fm.removeItem(at: destinationURL)
        }
        try contents.write(to: destinationURL, atomically: true, encoding: .utf8)
        debugLog("[PairingFile] Saved \(parsed.mode.rawValue) pairing file to: \(destinationURL.path)")
        UserDefaults.standard.isPairingReset = false
        return parsed
    }

    func inspectPairingFile(from url: URL) throws -> (content: String, file: any PairingFile) {
        let isSecured = url.startAccessingSecurityScopedResource()
        defer {
            if isSecured {
                url.stopAccessingSecurityScopedResource()
            }
        }
        let data = try Data(contentsOf: url)
        guard let content = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        let parsed = try parse(content: content, preferred: nil)
        return (content, parsed)
    }

    func importPairingFile(from url: URL, preferred: PairingProtocol? = nil) throws {
        let (content, _) = try inspectPairingFile(from: url)
        let parsed = try savePairingFile(contents: content, preferred: preferred)
        persistedActiveProtocol = parsed.mode
    }

    func deletePairingFile(for mode: PairingProtocol) {
        let fileURL = pairingFileURL(for: mode)
        let fm = FileManager.default
        if fm.fileExists(atPath: fileURL.path) {
            try? fm.removeItem(at: fileURL)
            debugLog("[PairingFile] Deleted \(mode.rawValue) pairing file: \(fileURL.path)")
        }
        // Remove legacy-named files too, or the next existence check would
        // migrate one back into place and resurrect the deleted state.
        for legacy in legacyPairingFileURLs(for: mode) {
            try? fm.removeItem(at: legacy)
        }
        if mode == persistedActiveProtocol {
            persistedActiveProtocol = nil
        }
    }

    func resetAllPairingFiles() {
        let fm = FileManager.default
        let files = [
            AppConstants.Pairing.lockdownPairingFileName,
            AppConstants.Pairing.remotePairingFileName,
            AppConstants.Pairing.legacyPairingFileName
        ]
        for name in files {
            let path = fm.documentsDirectory.appendingPathComponent(name)
            if fm.fileExists(atPath: path.path) {
                try? fm.removeItem(at: path)
            }
        }
        for legacy in legacyPairingFileURLs(for: .rppairing) + legacyPairingFileURLs(for: .lockdown) {
            try? fm.removeItem(at: legacy)
        }
        UserDefaults.standard.isPairingReset = true
        persistedActiveProtocol = nil
        debugLog("[PairingFile] Reset all pairing files.")
    }
}
