#if os(iOS)
//
//  ShellAuthenticationViewController.swift
//  oPenSSAI
//
//  The Apple ID sign-in screen, rebuilt in code in the shell's Seal style
//  (black background, dark cards, magenta accent). It replaces the
//  storyboard AuthenticationViewController on iOS: the storyboard's
//  .strings never apply at runtime (the storyboard was never
//  base-internationalized), so the login page stayed English on a purple
//  background. Same contract as the original — `authenticationHandler` /
//  `completionHandler` — so SignInFlowHandler drives it identically.
//
//  Copyright © 2026 oPenSSAI Contributors. All rights reserved.
//

@preconcurrency import UIKit

import SideSign

final class ShellAuthenticationViewController: UIViewController
{
    var authenticationHandler: ((String, String, @escaping (Result<(ALTAccount, ALTAppleAPISession), Error>) -> Void) -> Void)?
    var completionHandler: (((ALTAccount, ALTAppleAPISession, String)?) -> Void)?

    private weak var toastView: ToastView?

    private let scrollView = UIScrollView()
    private let contentStackView = UIStackView()

    private let appleIDTextField = UITextField()
    private let passwordTextField = UITextField()
    private let signInButton = UIButton(type: .system)

    override func viewDidLoad()
    {
        super.viewDidLoad()

        // Fetch anisette servers asap when loading Auth Screen (if list is empty)
        Task {
            if await AnisetteServersManager.shared.getActiveServerURLs().isEmpty {
                let sourceURL = UserDefaults.standard.menuAnisetteList
                do {
                    _ = try await AnisetteServersManager.shared.syncWithRemote(sourceURLString: sourceURL, forceRemote: true)
                    debugLog("ShellAuthenticationViewController: Server list refresh request completed for sourceURL: \(sourceURL)")
                } catch {
                    debugLog("ShellAuthenticationViewController: Server list refresh request Failed for sourceURL: \(sourceURL) Error: \(error)")
                }
            }
        }

        view.backgroundColor = ShellTheme.background

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: NSLocalizedString("Cancel", comment: ""),
            style: .plain, target: self, action: #selector(cancel))

        buildLayout()
        configureFields()

        self.signInButton.activityIndicatorView.style = .medium
        self.signInButton.activityIndicatorView.color = .white

        self.appleIDTextField.delegate = self
        self.passwordTextField.delegate = self

        NotificationCenter.default.addObserver(self, selector: #selector(textFieldDidChangeText(_:)), name: UITextField.textDidChangeNotification, object: self.appleIDTextField)
        NotificationCenter.default.addObserver(self, selector: #selector(textFieldDidChangeText(_:)), name: UITextField.textDidChangeNotification, object: self.passwordTextField)

        self.update()
    }

    override func viewDidDisappear(_ animated: Bool)
    {
        super.viewDidDisappear(animated)

        self.signInButton.isIndicatingActivity = false
        self.toastView?.dismiss()
    }

    override var preferredStatusBarStyle: UIStatusBarStyle
    {
        return .lightContent
    }

    override var keyCommands: [UIKeyCommand]?
    {
        return [
            UIKeyCommand(input: "\t", modifierFlags: [], action: #selector(handleTabKey(_:))),
            UIKeyCommand(input: "\t", modifierFlags: .shift, action: #selector(handleShiftTabKey(_:)))
        ]
    }

    @objc private func handleTabKey(_ command: UIKeyCommand)
    {
        if self.appleIDTextField.isFirstResponder {
            self.passwordTextField.becomeFirstResponder()
        } else if self.passwordTextField.isFirstResponder {
            self.appleIDTextField.becomeFirstResponder()
        }
    }

    @objc private func handleShiftTabKey(_ command: UIKeyCommand)
    {
        if self.passwordTextField.isFirstResponder {
            self.appleIDTextField.becomeFirstResponder()
        } else if self.appleIDTextField.isFirstResponder {
            self.passwordTextField.becomeFirstResponder()
        }
    }
}

private extension ShellAuthenticationViewController
{
    func buildLayout()
    {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        contentStackView.axis = .vertical
        contentStackView.spacing = UIScreen.main.isExtraCompactHeight ? 20 : 24
        contentStackView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStackView)

        NSLayoutConstraint.activate([
            contentStackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 24),
            contentStackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 24),
            contentStackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -24),
            contentStackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            contentStackView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -48),
        ])

        let titleLabel = UILabel()
        titleLabel.text = NSLocalizedString("Welcome to oPenSSAI.", comment: "")
        titleLabel.font = .systemFont(ofSize: 32, weight: .bold)
        titleLabel.textColor = ShellTheme.primaryText
        titleLabel.numberOfLines = 0
        contentStackView.addArrangedSubview(titleLabel)

        let subtitleLabel = UILabel()
        subtitleLabel.text = NSLocalizedString("Sign in with your Apple ID to get started.", comment: "")
        subtitleLabel.font = .systemFont(ofSize: 17, weight: .regular)
        subtitleLabel.textColor = ShellTheme.secondaryText
        subtitleLabel.numberOfLines = 0
        contentStackView.addArrangedSubview(subtitleLabel)

        let appleIDCaption = captionLabel(NSLocalizedString("APPLE ID", comment: ""))
        contentStackView.addArrangedSubview(appleIDCaption)
        contentStackView.addArrangedSubview(fieldContainer(for: appleIDTextField))

        let passwordCaption = captionLabel(NSLocalizedString("PASSWORD", comment: ""))
        contentStackView.addArrangedSubview(passwordCaption)
        contentStackView.addArrangedSubview(fieldContainer(for: passwordTextField))

        signInButton.setTitle(NSLocalizedString("Sign in", comment: ""), for: .normal)
        signInButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        signInButton.setTitleColor(.white, for: .normal)
        signInButton.backgroundColor = ShellTheme.accentColor
        signInButton.clipsToBounds = true
        signInButton.layer.cornerRadius = 16
        signInButton.addTarget(self, action: #selector(authenticate), for: .touchUpInside)
        signInButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            signInButton.heightAnchor.constraint(equalToConstant: 52),
        ])
        contentStackView.addArrangedSubview(signInButton)

        let whyLabel = UILabel()
        whyLabel.text = NSLocalizedString("Why do we need this?", comment: "")
        whyLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        whyLabel.textColor = ShellTheme.primaryText
        whyLabel.numberOfLines = 0
        contentStackView.addArrangedSubview(whyLabel)

        let explanationLabel = UILabel()
        explanationLabel.text = NSLocalizedString("Your Apple ID is used to configure apps so they can be installed on this device. Your credentials will be stored securely in this device's Keychain and sent only to Apple for authentication.", comment: "")
        explanationLabel.font = .systemFont(ofSize: 15, weight: .regular)
        explanationLabel.textColor = ShellTheme.secondaryText
        explanationLabel.numberOfLines = 0
        contentStackView.addArrangedSubview(explanationLabel)

        // Tighten the gap between each caption and its field.
        contentStackView.setCustomSpacing(8, after: appleIDCaption)
        contentStackView.setCustomSpacing(8, after: passwordCaption)
        contentStackView.setCustomSpacing(8, after: whyLabel)
    }

    func captionLabel(_ text: String) -> UILabel
    {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = ShellTheme.secondaryText
        return label
    }

    func fieldContainer(for textField: UITextField) -> UIView
    {
        let container = UIView()
        container.backgroundColor = ShellTheme.card
        container.clipsToBounds = true
        container.layer.cornerRadius = 16
        container.translatesAutoresizingMaskIntoConstraints = false

        textField.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(textField)

        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 50),
            textField.topAnchor.constraint(equalTo: container.topAnchor),
            textField.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            textField.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            textField.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
        ])

        return container
    }

    func configureFields()
    {
        appleIDTextField.placeholder = "name@email.com"
        appleIDTextField.textColor = ShellTheme.primaryText
        appleIDTextField.autocapitalizationType = .none
        appleIDTextField.autocorrectionType = .no
        appleIDTextField.spellCheckingType = .no
        appleIDTextField.smartQuotesType = .no
        appleIDTextField.smartDashesType = .no
        appleIDTextField.smartInsertDeleteType = .no
        appleIDTextField.keyboardType = .emailAddress
        appleIDTextField.textContentType = .username
        appleIDTextField.returnKeyType = .next

        passwordTextField.placeholder = "••••••••"
        passwordTextField.textColor = ShellTheme.primaryText
        passwordTextField.isSecureTextEntry = true
        passwordTextField.autocapitalizationType = .none
        passwordTextField.autocorrectionType = .no
        passwordTextField.spellCheckingType = .no
        passwordTextField.smartQuotesType = .no
        passwordTextField.smartDashesType = .no
        passwordTextField.smartInsertDeleteType = .no
        passwordTextField.textContentType = .password
        passwordTextField.returnKeyType = .go
    }

    func update()
    {
        if let _ = self.validate()
        {
            self.signInButton.isEnabled = true
            self.signInButton.alpha = 1.0
        }
        else
        {
            self.signInButton.isEnabled = false
            self.signInButton.alpha = 0.6
        }
    }

    func validate() -> (String, String)?
    {
        guard
            let emailAddress = self.appleIDTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines), !emailAddress.isEmpty,
            let password = self.passwordTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines), !password.isEmpty
        else { return nil }

        return (emailAddress, password)
    }
}

private extension ShellAuthenticationViewController
{
    @objc func authenticate()
    {
        guard let (emailAddress, password) = self.validate() else { return }

        self.appleIDTextField.resignFirstResponder()
        self.passwordTextField.resignFirstResponder()

        self.signInButton.isIndicatingActivity = true

        self.authenticationHandler?(emailAddress, password) { (result) in
            switch result
            {
            case .failure(DeveloperPortalError.userCancelled):
                debugLog("ShellAuthenticationViewController: Two-factor authentication cancelled by user.")
                DispatchQueue.main.async {
                    self.signInButton.isIndicatingActivity = false
                }

            case .failure(DeveloperPortalError.accountRepairRequired):
                debugLog("ShellAuthenticationViewController: Account repair cancelled by user.")
                DispatchQueue.main.async {
                    self.signInButton.isIndicatingActivity = false
                }

            case .failure(let error as NSError):
                debugLog("ShellAuthenticationViewController: Authentication failed with error: \(error)")
                DispatchQueue.main.async {
                    let error = error.withLocalizedTitle(NSLocalizedString("Failed to Sign In", comment: ""))
                    let toastView = ToastView(error: error)
                    toastView.show(in: self)
                    toastView.backgroundColor = .white
                    toastView.textLabel.textColor = .altPrimary
                    toastView.detailTextLabel.textColor = .altPrimary
                    self.toastView = toastView

                    self.signInButton.isIndicatingActivity = false
                }

            case .success((let account, let session)):
                DispatchQueue.main.async {
                    UIView.performWithoutAnimation {
                        let title = NSLocalizedString("Authenticated", comment: "")
                        let image = UIImage(systemName: "checkmark.circle.fill")
                        self.signInButton.setTitle(title, for: .normal)
                        self.signInButton.setImage(image, for: .normal)
                        self.signInButton.isIndicatingActivity = false
                        self.signInButton.layoutIfNeeded()
                    }
                }
                self.completionHandler?((account, session, password))
            }

            DispatchQueue.main.async {
                self.scrollView.setContentOffset(CGPoint(x: 0, y: -self.view.safeAreaInsets.top), animated: true)
            }
        }
    }

    @objc func cancel()
    {
        self.dismiss(animated: true) { [weak self] in
            self?.completionHandler?(nil)
        }
    }
}

extension ShellAuthenticationViewController: UITextFieldDelegate
{
    func textFieldShouldReturn(_ textField: UITextField) -> Bool
    {
        switch textField
        {
        case self.appleIDTextField: self.passwordTextField.becomeFirstResponder()
        case self.passwordTextField: self.authenticate()
        default: break
        }

        self.update()

        return false
    }

    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool
    {
        if string == "\t"
        {
            switch textField
            {
            case self.appleIDTextField: self.passwordTextField.becomeFirstResponder()
            case self.passwordTextField: self.appleIDTextField.becomeFirstResponder()
            default: break
            }
            return false
        }
        return true
    }

    func textFieldDidBeginEditing(_ textField: UITextField)
    {
        guard UIScreen.main.isExtraCompactHeight else { return }

        // Position all the controls within visible frame.
        var contentOffset = self.scrollView.contentOffset
        contentOffset.y = 44
        self.scrollView.setContentOffset(contentOffset, animated: true)
    }
}

extension ShellAuthenticationViewController
{
    @objc func textFieldDidChangeText(_ notification: Notification)
    {
        self.update()
    }
}
#endif
