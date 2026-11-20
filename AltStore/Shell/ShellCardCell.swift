#if os(iOS)
//
//  ShellCardCell.swift
//  oPenSSAI
//
//  Base table cell for the shell's card lists. Each section renders as one
//  rounded card (20pt corners, Seal-style); the cell draws its slice of the
//  card background depending on its position in the section.
//
//  Copyright © 2026 oPenSSAI Contributors. All rights reserved.
//

import UIKit

/// Position of a cell inside its card section; drives corner rounding.
enum ShellCardPosition
{
    case top
    case middle
    case bottom
    case single
}

/// Base cell that paints the shell card background (and its highlighted
/// variant) for its position inside a card section.
class ShellCardCell: UITableViewCell
{
    private let cardBackgroundView = UIView()
    private let cardSelectedBackgroundView = UIView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?)
    {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        contentView.backgroundColor = .clear

        cardBackgroundView.backgroundColor = ShellTheme.card
        cardBackgroundView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        backgroundView = cardBackgroundView

        cardSelectedBackgroundView.backgroundColor = ShellTheme.cardHighlighted
        cardSelectedBackgroundView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        selectedBackgroundView = cardSelectedBackgroundView
    }

    @available(*, unavailable)
    required init?(coder: NSCoder)
    {
        fatalError("init(coder:) has not been implemented")
    }

    func configureCardBackground(position: ShellCardPosition)
    {
        let radius = ShellTheme.cardCornerRadius
        let corners: CACornerMask
        switch position
        {
        case .top:
            corners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        case .middle:
            corners = []
        case .bottom:
            corners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        case .single:
            corners = [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        }

        for view in [cardBackgroundView, cardSelectedBackgroundView]
        {
            view.layer.cornerRadius = corners.isEmpty ? 0 : radius
            view.layer.maskedCorners = corners
            view.layer.masksToBounds = true
        }
    }
}
#endif
