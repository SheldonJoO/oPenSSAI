#if os(iOS)
//
//  ShellTabBarController.swift
//  oPenSSAI
//
//  The shell's root container: two navigation stacks (Apps / Me) with a
//  custom floating pill tab bar. The pill floats above the child navigation
//  controllers, so it stays visible on pushed screens too (as in the
//  reference). Deep links are routed here: .ipa imports go to the Apps tab,
//  add-source links present the Sources UI modally, error-log requests open
//  the diagnostic log from the Me tab.
//
//  Copyright © 2026 oPenSSAI Contributors. All rights reserved.
//

import UIKit

final class ShellTabBarController: UIViewController
{
    private let appsViewController = AppsViewController()
    private let profileViewController = ProfileViewController()

    private lazy var appsNavigationController: UINavigationController = {
        makeNavigationController(rootViewController: appsViewController)
    }()

    private lazy var profileNavigationController: UINavigationController = {
        makeNavigationController(rootViewController: profileViewController)
    }()

    private var selectedIndex = 0

    /// The currently selected navigation controller (used by the launch
    /// sequence to present toasts).
    var selectedViewController: UIViewController?
    {
        selectedIndex == 0 ? appsNavigationController : profileNavigationController
    }

    // MARK: - Pill tab bar

    private let pillView: UIView = {
        let view = UIView()
        view.backgroundColor = ShellTheme.pillBackground
        view.layer.cornerRadius = ShellTheme.pillHeight / 2
        view.layer.borderColor = ShellTheme.separator.cgColor
        view.layer.borderWidth = 1
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOpacity = 0.35
        view.layer.shadowRadius = 16
        view.layer.shadowOffset = CGSize(width: 0, height: 8)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let selectionIndicator: UIView = {
        let view = UIView()
        view.backgroundColor = ShellTheme.pillSelectedBackground
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var appsTabButton = PillTabButton(
        iconSystemName: "square.grid.2x2.fill",
        title: NSLocalizedString("Apps", comment: ""),
        onTap: { [weak self] in self?.selectTab(0) }
    )

    private lazy var profileTabButton = PillTabButton(
        iconSystemName: "person.crop.circle.fill",
        title: NSLocalizedString("Me", comment: ""),
        onTap: { [weak self] in self?.selectTab(1) }
    )

    private var selectionIndicatorCenterXConstraint: NSLayoutConstraint!

    // MARK: - Lifecycle

    override func viewDidLoad()
    {
        super.viewDidLoad()
        view.backgroundColor = ShellTheme.background
        ShellTheme.applyAppearance(to: view.window)

        addChild(appsNavigationController)
        view.addSubview(appsNavigationController.view)
        appsNavigationController.view.frame = view.bounds
        appsNavigationController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        appsNavigationController.didMove(toParent: self)

        view.addSubview(pillView)
        pillView.addSubview(selectionIndicator)
        pillView.addSubview(appsTabButton)
        pillView.addSubview(profileTabButton)

        let pillWidth: CGFloat = 280
        selectionIndicatorCenterXConstraint = selectionIndicator.centerXAnchor.constraint(
            equalTo: appsTabButton.centerXAnchor)

        NSLayoutConstraint.activate([
            pillView.widthAnchor.constraint(equalToConstant: pillWidth),
            pillView.heightAnchor.constraint(equalToConstant: ShellTheme.pillHeight),
            pillView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            pillView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -ShellTheme.pillBottomMargin),

            selectionIndicator.widthAnchor.constraint(equalToConstant: pillWidth / 2 - 8),
            selectionIndicator.heightAnchor.constraint(equalToConstant: ShellTheme.pillHeight - 16),
            selectionIndicator.centerYAnchor.constraint(equalTo: pillView.centerYAnchor),
            selectionIndicatorCenterXConstraint,

            appsTabButton.leadingAnchor.constraint(equalTo: pillView.leadingAnchor, constant: 4),
            appsTabButton.topAnchor.constraint(equalTo: pillView.topAnchor, constant: 8),
            appsTabButton.bottomAnchor.constraint(equalTo: pillView.bottomAnchor, constant: -8),
            appsTabButton.widthAnchor.constraint(equalToConstant: pillWidth / 2 - 8),

            profileTabButton.trailingAnchor.constraint(equalTo: pillView.trailingAnchor, constant: -4),
            profileTabButton.topAnchor.constraint(equalTo: pillView.topAnchor, constant: 8),
            profileTabButton.bottomAnchor.constraint(equalTo: pillView.bottomAnchor, constant: -8),
            profileTabButton.widthAnchor.constraint(equalToConstant: pillWidth / 2 - 8),
        ])

        selectionIndicator.layer.cornerRadius = (ShellTheme.pillHeight - 16) / 2
        updateTabButtonStates()

        NotificationCenter.default.addObserver(
            self, selector: #selector(importAppDeepLink(_:)),
            name: AppDelegate.importAppDeepLinkNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(addSourceDeepLink(_:)),
            name: AppDelegate.addSourceDeepLinkNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(openErrorLog(_:)),
            name: ToastView.openErrorLogNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(applyTheme),
            name: ShellTheme.accentDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(applyAppearance),
            name: ShellTheme.appearanceDidChangeNotification, object: nil)
    }

    override func viewWillAppear(_ animated: Bool)
    {
        super.viewWillAppear(animated)
        ShellTheme.applyAppearance(to: view.window)
    }

    override var preferredStatusBarStyle: UIStatusBarStyle
    {
        return .lightContent
    }

    // MARK: - Navigation controllers

    private func makeNavigationController(rootViewController: UIViewController) -> UINavigationController
    {
        let navigationController = UINavigationController(rootViewController: rootViewController)
        let appearance = Self.makeNavigationBarAppearance()
        navigationController.navigationBar.standardAppearance = appearance
        navigationController.navigationBar.scrollEdgeAppearance = appearance
        navigationController.navigationBar.compactAppearance = appearance
        navigationController.navigationBar.prefersLargeTitles = true
        navigationController.navigationBar.tintColor = ShellTheme.accentColor
        return navigationController
    }

    /// Dark shell navigation bar: opaque black background, no shadow line,
    /// white titles, 40pt heavy large titles.
    static func makeNavigationBarAppearance() -> UINavigationBarAppearance
    {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = ShellTheme.background
        appearance.shadowColor = .clear
        appearance.titleTextAttributes = [
            .foregroundColor: ShellTheme.primaryText,
            .font: UIFont.systemFont(ofSize: 17, weight: .semibold),
        ]
        appearance.largeTitleTextAttributes = [
            .foregroundColor: ShellTheme.primaryText,
            .font: ShellTheme.largeTitleFont,
        ]
        appearance.backButtonAppearance.normal.titleTextAttributes = [
            .foregroundColor: UIColor.clear,
            .font: UIFont.systemFont(ofSize: 17, weight: .regular),
        ]
        return appearance
    }

    // MARK: - Tab selection

    private func selectTab(_ index: Int)
    {
        guard index != selectedIndex else { return }
        selectedIndex = index

        let outgoing = index == 0 ? profileNavigationController : appsNavigationController
        let incoming = index == 0 ? appsNavigationController : profileNavigationController

        outgoing.willMove(toParent: nil)
        outgoing.view.removeFromSuperview()
        outgoing.removeFromParent()

        addChild(incoming)
        view.insertSubview(incoming.view, belowSubview: pillView)
        incoming.view.frame = view.bounds
        incoming.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        incoming.didMove(toParent: self)

        // Move the selection indicator to the tapped segment.
        selectionIndicatorCenterXConstraint.isActive = false
        selectionIndicatorCenterXConstraint = selectionIndicator.centerXAnchor.constraint(
            equalTo: (index == 0 ? appsTabButton : profileTabButton).centerXAnchor)
        selectionIndicatorCenterXConstraint.isActive = true

        UIView.animate(withDuration: 0.25) {
            self.view.layoutIfNeeded()
        }
        updateTabButtonStates()
    }

    private func updateTabButtonStates()
    {
        appsTabButton.isSelected = selectedIndex == 0
        profileTabButton.isSelected = selectedIndex == 1
    }

    @objc private func applyTheme()
    {
        appsNavigationController.navigationBar.tintColor = ShellTheme.accentColor
        profileNavigationController.navigationBar.tintColor = ShellTheme.accentColor
        updateTabButtonStates()
    }

    @objc private func applyAppearance()
    {
        ShellTheme.applyAppearance(to: view.window)
    }

    // MARK: - Deep links

    @objc private func importAppDeepLink(_ notification: Notification)
    {
        selectTab(0)
        // AppsViewController observes the same notification and queues the file.
    }

    @objc private func addSourceDeepLink(_ notification: Notification)
    {
        presentSources()
    }

    /// Presents the Sources UI modally (the shell has no Sources tab).
    /// Also the target of the launch sequence's "sources failed to load" toast.
    @objc func presentSources()
    {
        guard presentedViewController == nil else { return }

        let storyboard = UIStoryboard(name: "Sources", bundle: nil)
        let sourcesViewController = storyboard.instantiateViewController(withIdentifier: "sourcesViewController")

        let navigationController = UINavigationController(rootViewController: sourcesViewController)
        let appearance = Self.makeNavigationBarAppearance()
        navigationController.navigationBar.standardAppearance = appearance
        navigationController.navigationBar.scrollEdgeAppearance = appearance
        navigationController.navigationBar.compactAppearance = appearance
        navigationController.navigationBar.prefersLargeTitles = true
        navigationController.navigationBar.tintColor = ShellTheme.accentColor

        sourcesViewController.navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(dismissPresentedSources))

        present(navigationController, animated: true)
    }

    @objc private func dismissPresentedSources()
    {
        dismiss(animated: true)
    }

    @objc private func openErrorLog(_ notification: Notification)
    {
        selectTab(1)
        DispatchQueue.main.async { [weak self] in
            self?.profileViewController.openDiagnosticLog()
        }
    }
}

// MARK: - Pill tab button

/// One segment of the floating pill tab bar: icon above label. Selected
/// segments are magenta; unselected segments are white icon + gray label.
private final class PillTabButton: UIControl
{
    private let onTap: () -> Void

    private let iconImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = ShellTheme.tabLabelFont
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    override var isSelected: Bool
    {
        didSet { updateColors() }
    }

    init(iconSystemName: String, title: String, onTap: @escaping () -> Void)
    {
        self.onTap = onTap
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        iconImageView.image = UIImage(
            systemName: iconSystemName,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 26, weight: .regular))

        titleLabel.text = title

        let stack = UIStackView(arrangedSubviews: [iconImageView, titleLabel])
        stack.axis = .vertical
        stack.spacing = 2
        stack.alignment = .center
        stack.isUserInteractionEnabled = false
        stack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 28),
            iconImageView.heightAnchor.constraint(equalToConstant: 28),
        ])

        addTarget(self, action: #selector(tapped), for: .touchUpInside)
        updateColors()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder)
    {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func tapped()
    {
        onTap()
    }

    private func updateColors()
    {
        if isSelected
        {
            iconImageView.tintColor = ShellTheme.accentColor
            titleLabel.textColor = ShellTheme.accentColor
        }
        else
        {
            iconImageView.tintColor = ShellTheme.primaryText
            titleLabel.textColor = ShellTheme.secondaryText
        }
    }
}
#endif
