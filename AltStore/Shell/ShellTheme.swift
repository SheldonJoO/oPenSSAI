#if os(iOS)
//
//  ShellTheme.swift
//  oPenSSAI
//
//  Design system for the oPenSSAI shell: the two-tab (Apps / Me) interface
//  rebuilt in the style of Seal's reference screenshots (pure black
//  background, dark navy cards, magenta/violet accent). Fresh implementation;
//  no Seal assets, strings, or branding are used anywhere.
//
//  Copyright © 2026 oPenSSAI Contributors. All rights reserved.
//

import UIKit

/// Accent color choices offered by the Appearance & Theme screen.
/// Violet (magenta) is the default and matches the reference design.
enum ShellAccent: String, CaseIterable, Sendable
{
    case violet
    case orange
    case blue
    case green
    case pink

    var color: UIColor
    {
        switch self
        {
        case .violet: return UIColor(hex: 0xD946EF)
        case .orange: return UIColor(hex: 0xF97316)
        case .blue: return UIColor(hex: 0x3B82F6)
        case .green: return UIColor(hex: 0x22C55E)
        case .pink: return UIColor(hex: 0xEC4899)
        }
    }

    var displayName: String
    {
        switch self
        {
        case .violet: return NSLocalizedString("Violet", comment: "")
        case .orange: return NSLocalizedString("Orange", comment: "")
        case .blue: return NSLocalizedString("Blue", comment: "")
        case .green: return NSLocalizedString("Green", comment: "")
        case .pink: return NSLocalizedString("Pink", comment: "")
        }
    }
}

/// Appearance choices offered by the Appearance & Theme screen.
enum ShellAppearance: String, CaseIterable, Sendable
{
    case system
    case dark

    var displayName: String
    {
        switch self
        {
        case .system: return NSLocalizedString("Follow System", comment: "")
        case .dark: return NSLocalizedString("Dark", comment: "")
        }
    }
}

/// The shell's design tokens. Colors are dynamic: the dark values reproduce
/// the reference palette (pure black, dark navy cards), the light values are
/// adapted equivalents so "Follow System" is honest in light mode.
enum ShellTheme
{
    static let accentDidChangeNotification = Notification.Name("oPenSSAI.ShellTheme.accentDidChange")
    static let appearanceDidChangeNotification = Notification.Name("oPenSSAI.ShellTheme.appearanceDidChange")

    private static let accentDefaultsKey = "shell.accent"
    private static let appearanceDefaultsKey = "shell.appearance"
    static let expiryReminderDefaultsKey = "shell.expiryReminderEnabled"

    static var accent: ShellAccent
    {
        get
        {
            guard let rawValue = UserDefaults.standard.string(forKey: accentDefaultsKey),
                  let accent = ShellAccent(rawValue: rawValue) else { return .violet }
            return accent
        }
        set
        {
            UserDefaults.standard.set(newValue.rawValue, forKey: accentDefaultsKey)
            NotificationCenter.default.post(name: accentDidChangeNotification, object: nil)
        }
    }

    static var appearance: ShellAppearance
    {
        get
        {
            guard let rawValue = UserDefaults.standard.string(forKey: appearanceDefaultsKey),
                  let appearance = ShellAppearance(rawValue: rawValue) else { return .system }
            return appearance
        }
        set
        {
            UserDefaults.standard.set(newValue.rawValue, forKey: appearanceDefaultsKey)
            NotificationCenter.default.post(name: appearanceDidChangeNotification, object: nil)
        }
    }

    /// Whether the 24-hour expiry reminder is enabled. Defaults to true.
    static var isExpiryReminderEnabled: Bool
    {
        get
        {
            guard UserDefaults.standard.object(forKey: expiryReminderDefaultsKey) != nil else { return true }
            return UserDefaults.standard.bool(forKey: expiryReminderDefaultsKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: expiryReminderDefaultsKey) }
    }

    /// Applies the stored appearance to a window (call at launch and whenever
    /// the appearance setting changes).
    static func applyAppearance(to window: UIWindow?)
    {
        switch appearance
        {
        case .system: window?.overrideUserInterfaceStyle = .unspecified
        case .dark: window?.overrideUserInterfaceStyle = .dark
        }
    }

    /// One-line summary shown in the Profile screen, e.g. "Follow System·Violet".
    static var summary: String
    {
        return "\(appearance.displayName)·\(accent.displayName)"
    }

    // MARK: - Colors

    static var accentColor: UIColor { accent.color }

    /// Translucent accent, used for the "Renew All" pill background.
    static var accentBackground: UIColor { accent.color.withAlphaComponent(0.16) }

    static var background: UIColor
    {
        UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .light ? UIColor(hex: 0xF2F2F7) : UIColor(hex: 0x000000)
        }
    }

    static var card: UIColor
    {
        UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .light ? .white : UIColor(hex: 0x1C1E2A)
        }
    }

    static var cardHighlighted: UIColor
    {
        UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .light ? UIColor(hex: 0xE9E9EE) : UIColor(hex: 0x262836)
        }
    }

    /// Floating pill tab bar background.
    static var pillBackground: UIColor
    {
        UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .light ? UIColor(hex: 0xE5E5EA) : UIColor(hex: 0x2A2D3A)
        }
    }

    /// Selected segment inset inside the floating pill tab bar.
    static var pillSelectedBackground: UIColor
    {
        UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .light ? .white : UIColor(hex: 0x14151C)
        }
    }

    static var primaryText: UIColor
    {
        UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .light ? UIColor(hex: 0x111111) : .white
        }
    }

    static var secondaryText: UIColor
    {
        UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .light ? UIColor(hex: 0x6B7280) : UIColor(hex: 0x9CA3AF)
        }
    }

    static var separator: UIColor
    {
        UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .light
                ? UIColor.black.withAlphaComponent(0.08)
                : UIColor.white.withAlphaComponent(0.08)
        }
    }

    /// Orange accent used only for the expiry-reminder rows.
    static let reminderOrange = UIColor(hex: 0xF59E0B)

    /// Pink-red used only for the "Support oPenSSAI" heart.
    static let supportRed = UIColor(hex: 0xF43F5E)

    /// Red used for expired / expiring-soon validity labels.
    static let expiredRed = UIColor(hex: 0xFF453A)

    // MARK: - Fonts

    /// Navigation large title (the "oPenSSAI" / "Me" headings).
    static let largeTitleFont = UIFont.systemFont(ofSize: 40, weight: .heavy)

    /// In-content section headings ("Installed Apps", "Pending Apps").
    static let headingFont = UIFont.systemFont(ofSize: 28, weight: .bold)

    /// Section titles above cards ("Signing", "Manage", ...).
    static let sectionTitleFont = UIFont.systemFont(ofSize: 15, weight: .bold)

    static let rowTitleFont = UIFont.systemFont(ofSize: 17, weight: .semibold)
    static let rowValueFont = UIFont.systemFont(ofSize: 16, weight: .regular)
    static let appNameFont = UIFont.systemFont(ofSize: 17, weight: .bold)
    static let appVersionFont = UIFont.systemFont(ofSize: 15, weight: .regular)
    static let bundleIDFont = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    static let statusFont = UIFont.systemFont(ofSize: 15, weight: .semibold)
    static let tabLabelFont = UIFont.systemFont(ofSize: 13, weight: .semibold)
    static let segmentTitleFont = UIFont.systemFont(ofSize: 17, weight: .semibold)
    static let segmentCountFont = UIFont.systemFont(ofSize: 14, weight: .regular)

    // MARK: - Metrics

    static let cardCornerRadius: CGFloat = 20
    static let horizontalMargin: CGFloat = 16
    static let appIconSize: CGFloat = 60
    static let appIconCornerRadius: CGFloat = 14
    static let rowIconSize: CGFloat = 28
    static let pillHeight: CGFloat = 76
    static let pillBottomMargin: CGFloat = 20
}

extension UIColor
{
    convenience init(hex: UInt32, alpha: CGFloat = 1)
    {
        let red = CGFloat((hex >> 16) & 0xFF) / 255
        let green = CGFloat((hex >> 8) & 0xFF) / 255
        let blue = CGFloat(hex & 0xFF) / 255
        self.init(red: red, green: green, blue: blue, alpha: alpha)
    }
}
#endif
