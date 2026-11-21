//
//  ChangeAppIconOperation.swift
//  SideStore
//
//  Created by Magesh K on 23/7/26.
//  Copyright © 2026 AltStore. All rights reserved.
//

@preconcurrency import UIKit
import SideSign

final class ChangeAppIconOperation: BasePipelineOperation<InstallAppOperationContext, URL>, @unchecked Sendable {
    
    override func execute(parentProgress: Progress?) async throws -> URL {
        let startTime = CFAbsoluteTimeGetCurrent()
        debugLog("[ChangeAppIconOperation] execute() started")
        defer {
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            debugLog("[ChangeAppIconOperation] execute() took: \(String(format: "%.3fs", elapsed))")
        }
        try await super.executePreconditionCheck(parentProgress: parentProgress)
        self.setProgress(10)

        guard let appBundle = self.context.targetAppBundle else {
            throw OperationError.invalidParameters("ChangeAppIconOperation.execute: self.context.appBundle is nil")
        }

        // This step also applies the custom display name chosen in the
        // .userCustomization step: it runs after staging and before resigning,
        // so the name is baked into the resigned bundle and InstalledApp.name.
        // Note: a localized CFBundleDisplayName in InfoPlist.strings would still
        // win over the plist value on the home screen (needs proper testing).
        let customDisplayName = self.context.customDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasCustomName = !(customDisplayName?.isEmpty ?? true)
        let alternateIconURL = self.context.alternateIconURL
        let hasCustomIcon = alternateIconURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false

        guard hasCustomIcon || hasCustomName else {
            self.setProgress(100)
            return appBundle.fileURL
        }

        let appBundleURL = appBundle.fileURL
        self.setProgress(20)

        if hasCustomIcon, let alternateIconURL = alternateIconURL {
            let data = try Data(contentsOf: alternateIconURL)
            guard let image = UIImage(data: data) else {
                throw OperationError.invalidParameters("Invalid icon image data")
            }

            self.setProgress(40)
            let iconScale = await MainActor.run { Int(UIScreen.main.scale) }
            guard let icon = image.resizing(toFill: CGSize(width: 60 * iconScale, height: 60 * iconScale)),
                  let iconData = icon.pngData()
            else {
                throw OperationError.invalidParameters("Failed to resize icon image")
            }

            self.setProgress(65)
            let iconName = "AltIcon"
            let iconURL = appBundleURL.appendingPathComponent(iconName + "@\(iconScale)x.png")
            try iconData.write(to: iconURL, options: .atomic)
        }

        self.setProgress(80)
        let plistURL = InfoPlistParser.resolveInfoPlistURL(for: appBundleURL)
        var parser = try InfoPlistParser(plistURL: plistURL)

        if hasCustomIcon {
            // Backup original CFBundleIcons if not already backed up
            if parser.rawDictionary["CFBundleIcons~original"] == nil {
                parser.set(value: parser.rawDictionary["CFBundleIcons"], for: "CFBundleIcons~original")
            }
            if parser.rawDictionary["CFBundleIcons~ipad~original"] == nil {
                parser.set(value: parser.rawDictionary["CFBundleIcons~ipad"], for: "CFBundleIcons~ipad~original")
            }

            let iconDictionary: [String: any Sendable] = ["CFBundlePrimaryIcon": ["CFBundleIconFiles": ["AltIcon"]]]
            parser.set(value: iconDictionary, for: "CFBundleIcons")
        }

        if hasCustomName, let customDisplayName = customDisplayName {
            debugLog("[ChangeAppIconOperation] Setting CFBundleDisplayName='\(customDisplayName)'")
            parser.set(value: customDisplayName, for: "CFBundleDisplayName")
        }

        self.setProgress(90)
        try parser.write(to: plistURL)

        self.setProgress(100)
        return appBundle.fileURL
    }
}
