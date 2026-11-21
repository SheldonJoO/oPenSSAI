#if os(iOS)
//
//  ShellTabBarController.swift
//  oPenSSAI
//
//  The shell's root container: three navigation stacks (Apps / Location /
//  Me) under a standard iOS tab bar, which stays visible on pushed screens
//  too.
//  Deep links are routed here: .ipa imports go to the Apps tab,
//  add-source links present the Sources UI modally, error-log requests open
//  the diagnostic log from the Me tab.
//
//  Copyright © 2026 oPenSSAI Contributors. All rights reserved.
//

import UIKit

final class ShellTabBarController: UITabBarController
{
    private let appsViewController = AppsViewController()
    private let locationViewController = LocationSimulationViewController()
    private let profileViewController = ProfileViewController()

    private lazy var appsNavigationController: UINavigationController = {
        makeNavigationController(rootViewController: appsViewController)
    }()

    private lazy var locationNavigationController: UINavigationController = {
        makeNavigationController(rootViewController: locationViewController)
    }()

    private lazy var profileNavigationController: UINavigationController = {
        makeNavigationController(rootViewController: profileViewController)
    }()

    // MARK: - Lifecycle

    override func viewDidLoad()
    {
        super.viewDidLoad()
        view.backgroundColor = ShellTheme.background
        // No applyAppearance here: view.window is nil in viewDidLoad (this
        // controller is created before its view joins a window), so the call
        // was a silent no-op. The launch-time application lives in
        // SceneDelegate.scene(willConnectTo:); viewWillAppear below is the
        // safety net.

        appsNavigationController.tabBarItem = UITabBarItem(
            title: NSLocalizedString("Apps", comment: ""),
            image: UIImage(systemName: "square.grid.2x2.fill"),
            tag: 0)
        locationNavigationController.tabBarItem = UITabBarItem(
            title: NSLocalizedString("Location", comment: ""),
            image: UIImage(systemName: "location.fill"),
            tag: 1)
        profileNavigationController.tabBarItem = UITabBarItem(
            title: NSLocalizedString("Me", comment: ""),
            image: UIImage(systemName: "person.crop.circle.fill"),
            tag: 2)
        viewControllers = [appsNavigationController, locationNavigationController, profileNavigationController]

        tabBar.tintColor = ShellTheme.accentColor

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
            self, selector: #selector(openPairingTutorial(_:)),
            name: ToastView.openPairingTutorialNotification, object: nil)
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
        // Safety net: re-apply the stored appearance whenever the shell
        // re-appears (e.g. after a modal dismiss). Resolves the window
        // itself instead of trusting view.window.
        ShellTheme.applyAppearance()
    }

    override var preferredStatusBarStyle: UIStatusBarStyle
    {
        return .lightContent
    }

    /// Keep the shell's own status bar style instead of deferring to the
    /// selected child navigation controller.
    override var childForStatusBarStyle: UIViewController?
    {
        return nil
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
    /// white titles, 34pt bold large titles.
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
        selectedIndex = index
    }

    @objc private func applyTheme()
    {
        appsNavigationController.navigationBar.tintColor = ShellTheme.accentColor
        locationNavigationController.navigationBar.tintColor = ShellTheme.accentColor
        profileNavigationController.navigationBar.tintColor = ShellTheme.accentColor
        tabBar.tintColor = ShellTheme.accentColor
    }

    @objc private func applyAppearance()
    {
        ShellTheme.applyAppearance()
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
        selectTab(2)
        DispatchQueue.main.async { [weak self] in
            self?.profileViewController.openDiagnosticLog()
        }
    }

    /// Presents the pairing tutorial modally (the target of pairing-error
    /// toasts). Skipped while another modal is already presented.
    @objc private func openPairingTutorial(_ notification: Notification)
    {
        guard presentedViewController == nil else { return }
        presentPairingTutorial()
    }
}
#endif
