//
//  ErrorDetailsViewController.swift
//  AltStore
//
//  Created by Riley Testut on 10/5/22.
//  Copyright © 2022 Riley Testut. All rights reserved.
//

@preconcurrency import UIKit

class ErrorDetailsViewController: UIViewController
{
    var loggedError: LoggedError?

    @IBOutlet private var textView: UITextView!

    override func viewDidLoad()
    {
        super.viewDidLoad()

        if let error = self.loggedError?.error
        {
            self.title = error.localizedErrorCode

            let font = self.textView.font ?? UIFont.preferredFont(forTextStyle: .body)
            let detailedDescription = error.formattedDetailedDescription(with: font)
            self.textView.attributedText = detailedDescription
        }
        else
        {
            self.title = NSLocalizedString("Error Details", comment: "")
        }

        #if os(iOS)
        // Shell styling: the modal sheet's nav controller comes from the
        // storyboard segue with the system-default bar, and the old
        // .altPrimary tint used to leak onto the whole Me stack (it was
        // never restored after popping back).
        self.view.backgroundColor = ShellTheme.background
        self.textView.backgroundColor = ShellTheme.background
        let appearance = ShellTabBarController.makeNavigationBarAppearance()
        self.navigationController?.navigationBar.standardAppearance = appearance
        self.navigationController?.navigationBar.scrollEdgeAppearance = appearance
        self.navigationController?.navigationBar.compactAppearance = appearance
        self.navigationController?.navigationBar.tintColor = ShellTheme.accentColor
        #else
        self.navigationController?.navigationBar.tintColor = .altPrimary
        #endif

        self.textView.isScrollEnabled = true
        self.textView.alwaysBounceVertical = true
        self.textView.showsVerticalScrollIndicator = true

        #if !os(tvOS)
        if let sheetController = self.navigationController?.sheetPresentationController
        {
            sheetController.detents = [.medium(), .large()]
            sheetController.selectedDetentIdentifier = .medium
            sheetController.prefersGrabberVisible = true
        }
        #endif
    }

    override func viewDidLayoutSubviews()
    {
        super.viewDidLayoutSubviews()

        self.textView.textContainerInset.left = self.view.layoutMargins.left
        self.textView.textContainerInset.right = self.view.layoutMargins.right
    }
}
