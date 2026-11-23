#if os(iOS)
//
//  DonationViewController.swift
//  openSSS
//
//  Support openSSS: shows the developer's WeChat donation QR code with a
//  hint to screenshot it and scan it in WeChat. Reached from the Support
//  row on the Me tab.
//
//  Copyright © 2026 openSSS Contributors. All rights reserved.
//

import UIKit

final class DonationViewController: UIViewController
{
    override func viewDidLoad()
    {
        super.viewDidLoad()
        view.backgroundColor = ShellTheme.background
        title = NSLocalizedString("Support openSSS", comment: "")

        // White card so the QR code stays scannable on the dark shell
        // background.
        let cardView = UIView()
        cardView.backgroundColor = .white
        cardView.layer.cornerRadius = ShellTheme.cardCornerRadius
        cardView.translatesAutoresizingMaskIntoConstraints = false

        let qrImageView = UIImageView(image: UIImage(named: "DonationQR"))
        qrImageView.contentMode = .scaleAspectFit
        qrImageView.translatesAutoresizingMaskIntoConstraints = false

        let hintLabel = UILabel()
        hintLabel.font = ShellTheme.rowValueFont
        hintLabel.textColor = ShellTheme.secondaryText
        hintLabel.textAlignment = .center
        hintLabel.numberOfLines = 0
        hintLabel.text = NSLocalizedString("Screenshot to save, then scan it in WeChat", comment: "")
        hintLabel.translatesAutoresizingMaskIntoConstraints = false

        cardView.addSubview(qrImageView)
        view.addSubview(cardView)
        view.addSubview(hintLabel)

        NSLayoutConstraint.activate([
            cardView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            cardView.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -24),
            cardView.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 32),
            cardView.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -32),
            cardView.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.8),

            qrImageView.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 16),
            qrImageView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 16),
            qrImageView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -16),
            qrImageView.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -16),
            // The QR image is 1273 x 1210.
            qrImageView.heightAnchor.constraint(equalTo: qrImageView.widthAnchor, multiplier: 1210.0 / 1273.0),

            hintLabel.topAnchor.constraint(equalTo: cardView.bottomAnchor, constant: 24),
            hintLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            hintLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
        ])
    }

    override var preferredStatusBarStyle: UIStatusBarStyle
    {
        return shellPreferredStatusBarStyle
    }
}
#endif
