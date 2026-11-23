//
//  ShellSwiftUI.swift
//  openSSS
//
//  SwiftUI-side shell tokens for the upstream SwiftUI screens reachable
//  from the Me tab (pairing, certificates, anisette): the same colors the
//  UIKit shell uses, plus a pre-styled hosting controller and a List/Form
//  background modifier. tvOS falls back to the legacy dark palette:
//  ShellTheme is iOS-only. (Promotes the private tokens that used to live
//  in OnboardingView.swift so every SwiftUI screen shares one definition.)
//
//  Copyright © 2026 openSSS Contributors. All rights reserved.
//

import SwiftUI
import UIKit

/// Shell-theme colors for SwiftUI. On iOS these mirror ShellTheme
/// (near-black background, dark gray cards, user-chosen accent); on tvOS
/// they keep the legacy dark settings palette.
extension Color
{
    static var shellBackground: Color
    {
        #if os(iOS)
        Color(uiColor: ShellTheme.background)
        #else
        Color.black
        #endif
    }

    static var shellCard: Color
    {
        #if os(iOS)
        Color(uiColor: ShellTheme.card)
        #else
        Color(.secondarySystemBackground)
        #endif
    }

    static var shellCardHighlighted: Color
    {
        #if os(iOS)
        Color(uiColor: ShellTheme.cardHighlighted)
        #else
        Color.white.opacity(0.2)
        #endif
    }

    static var shellPrimaryText: Color
    {
        #if os(iOS)
        Color(uiColor: ShellTheme.primaryText)
        #else
        Color.white
        #endif
    }

    static var shellSecondaryText: Color
    {
        #if os(iOS)
        Color(uiColor: ShellTheme.secondaryText)
        #else
        Color.white.opacity(0.6)
        #endif
    }

    static var shellSeparator: Color
    {
        #if os(iOS)
        Color(uiColor: ShellTheme.separator)
        #else
        Color.white.opacity(0.15)
        #endif
    }

    static var shellAccent: Color
    {
        #if os(iOS)
        Color(uiColor: ShellTheme.accentColor)
        #else
        Color.accentColor
        #endif
    }

    /// Translucent accent, used for selected-row and secondary-action fills.
    static var shellAccentBackground: Color
    {
        #if os(iOS)
        Color(uiColor: ShellTheme.accentBackground)
        #else
        Color.accentColor.opacity(0.16)
        #endif
    }
}

/// Shell-theme fonts for SwiftUI.
extension Font
{
    /// In-content section headings ("Signing", "Manage", ...).
    static var shellSectionTitle: Font
    {
        #if os(iOS)
        Font.system(size: 15, weight: .bold)
        #else
        Font.system(size: 13, weight: .semibold)
        #endif
    }
}

enum ShellSwiftUI
{
    /// Card corner radius (ShellTheme.cardCornerRadius on iOS).
    static var cardCornerRadius: CGFloat
    {
        #if os(iOS)
        ShellTheme.cardCornerRadius
        #else
        14
        #endif
    }
}

extension View
{
    /// Shell background for a List or Form: hides the system scroll-content
    /// background (iOS 16+) and paints the shell background behind the
    /// rows. Pair with `.listRowBackground(Color.shellCard)`.
    /// On iOS 15 the system scroll background cannot be hidden, so the
    /// List keeps its default backdrop (rows still get shell cards).
    @ViewBuilder
    func shellListBackground() -> some View
    {
        if #available(iOS 16.0, tvOS 16.0, *)
        {
            self.scrollContentBackground(.hidden)
                .background(Color.shellBackground)
        }
        else
        {
            self.background(Color.shellBackground)
        }
    }
}

#if os(iOS)
/// UIHostingController pre-styled for the shell: shell background, shell
/// accent as the SwiftUI accent color (via the view's tint color), and
/// live accent updates when the user picks a new accent color.
final class ShellHostingController<Content: View>: UIHostingController<Content>
{
    private var accentObserver: NSObjectProtocol?

    override func viewDidLoad()
    {
        super.viewDidLoad()
        view.backgroundColor = ShellTheme.background
        view.tintColor = ShellTheme.accentColor
        accentObserver = NotificationCenter.default.addObserver(
            forName: ShellTheme.accentDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.view.tintColor = ShellTheme.accentColor
        }
    }

    deinit
    {
        if let accentObserver
        {
            NotificationCenter.default.removeObserver(accentObserver)
        }
    }
}
#endif
