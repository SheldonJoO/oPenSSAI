#if os(iOS)
//
//  GuideViewController.swift
//  openSSS
//
//  User Guide: short how-to sections for importing, renewing, pairing,
//  and signing in. Static text, written for openSSS.
//
//  Copyright © 2026 openSSS Contributors. All rights reserved.
//

import UIKit

final class GuideViewController: UIViewController
{
    private struct GuideSection
    {
        let title: String
        let body: String
    }

    private static var sections: [GuideSection]
    {
        [
            GuideSection(
                title: NSLocalizedString("Import & Install", comment: ""),
                body: NSLocalizedString("Tap + on the Apps tab to import an .ipa from Files, or open an .ipa in another app and choose openSSS. Imported apps wait under Pending — tap one to sign and install it.", comment: "")),
            GuideSection(
                title: NSLocalizedString("Renew Apps", comment: ""),
                body: NSLocalizedString("Apps signed with a free Apple ID expire after 7 days. Tap Renew All to re-sign every installed app at once, or tap a single app to renew just that one. openSSS also refreshes apps in the background when possible.", comment: "")),
            GuideSection(
                title: NSLocalizedString("Pair Your Device", comment: ""),
                body: NSLocalizedString("On-device signing needs a pairing file from your computer. Generate one with iloader on your computer, then import it from Device on the Me tab. Without a pairing file, installs and refreshes cannot reach the device.", comment: "")),
            GuideSection(
                title: NSLocalizedString("Apple ID & Certificates", comment: ""),
                body: NSLocalizedString("Sign in with your Apple ID on the Me tab. A free account can keep up to 3 apps active at a time. Manage your signing certificates under Signing Certificate.", comment: "")),
            GuideSection(
                title: NSLocalizedString("Expiry Reminders", comment: ""),
                body: NSLocalizedString("Turn on the 24-hour reminder on the Me tab and openSSS will notify you a day before an app expires, so you can renew it in time.", comment: "")),
        ]
    }

    override func viewDidLoad()
    {
        super.viewDidLoad()
        view.backgroundColor = ShellTheme.background
        title = NSLocalizedString("User Guide", comment: "")

        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.spacing = 28
        stackView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stackView)

        for section in Self.sections
        {
            let titleLabel = UILabel()
            titleLabel.font = UIFont.systemFont(ofSize: 19, weight: .bold)
            titleLabel.textColor = ShellTheme.primaryText
            titleLabel.text = section.title
            titleLabel.numberOfLines = 0

            let bodyLabel = UILabel()
            bodyLabel.font = ShellTheme.rowValueFont
            bodyLabel.textColor = ShellTheme.secondaryText
            bodyLabel.text = section.body
            bodyLabel.numberOfLines = 0

            let sectionStack = UIStackView(arrangedSubviews: [titleLabel, bodyLabel])
            sectionStack.axis = .vertical
            sectionStack.spacing = 8
            stackView.addArrangedSubview(sectionStack)
        }

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            stackView.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 20),
            stackView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 20),
            stackView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -20),
            stackView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -32),
            stackView.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -40),
        ])
    }

    override var preferredStatusBarStyle: UIStatusBarStyle
    {
        return shellPreferredStatusBarStyle
    }
}
#endif
