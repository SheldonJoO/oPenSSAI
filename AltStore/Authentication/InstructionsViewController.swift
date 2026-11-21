//
//  InstructionsViewController.swift
//  AltStore
//
//  Created by Riley Testut on 9/6/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

@preconcurrency import UIKit

final class InstructionsViewController: UIViewController
{
    var completionHandler: (() -> Void)?
    
    var showsBottomButton: Bool = false
    
    @IBOutlet private var contentStackView: UIStackView!
    @IBOutlet private var dismissButton: UIButton!
    /// Step titles 2–4 are still English in the storyboard (step 1 was
    /// translated there); there is no Base.lproj, so the storyboard
    /// strings never localize — these are overridden in code instead.
    /// Optional outlets: the tvOS storyboard has no connections for
    /// them, and an unconnected optional outlet is simply nil.
    @IBOutlet private var step2TitleLabel: UILabel?
    @IBOutlet private var step3TitleLabel: UILabel?
    @IBOutlet private var step4TitleLabel: UILabel?
    
    #if !os(tvOS)
    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }
    #endif
    
    override func viewDidLoad()
    {
        super.viewDidLoad()

        // No Base.lproj: the storyboard's English strings are baked in,
        // so the visible strings are overridden in code.
        self.navigationItem.title = NSLocalizedString("How it works", comment: "")
        self.dismissButton.setTitle(NSLocalizedString("Got it", comment: ""), for: .normal)
        self.step2TitleLabel?.text = NSLocalizedString("Connect to Wi-Fi and VPN", comment: "")
        self.step3TitleLabel?.text = NSLocalizedString("Download Apps", comment: "")
        self.step4TitleLabel?.text = NSLocalizedString("Apps Refresh Automatically", comment: "")

        if UIScreen.main.isExtraCompactHeight
        {
            self.contentStackView.layoutMargins.top = 0
            self.contentStackView.layoutMargins.bottom = self.contentStackView.layoutMargins.left
        }
        
        self.dismissButton.clipsToBounds = true
        self.dismissButton.layer.cornerRadius = 16
        
        if self.showsBottomButton
        {
            #if !os(tvOS)
            self.navigationItem.hidesBackButton = true
            #endif
        }
        else
        {
            self.dismissButton.isHidden = true
        }
    }
}

private extension InstructionsViewController
{
    @IBAction func dismiss()
    {
        self.completionHandler?()
    }
}
