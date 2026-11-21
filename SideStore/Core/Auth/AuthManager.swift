//
//  AuthManager.swift
//  SideStore
//
//  Created by Magesh K on 1/8/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

@preconcurrency import UIKit
import Foundation
import SideSign
import CoreData

public final class AuthManager: @unchecked Sendable {
    public static let shared = AuthManager()
    
    private var portalProxy: DeveloperPortalProxyWithAuth {
        DeveloperPortalProxy.shared as! DeveloperPortalProxyWithAuth
    }
    
    private init() {}
    
    private var team: ALTTeam?
    private var session: ALTAppleAPISession?

    /// Whether the app holds credentials that identify a signed-in Apple
    /// ID: an email plus a password and/or an Xcode token. This is a
    /// credential-presence check only — building a session additionally
    /// needs a valid adsid + token pair (see
    /// `getAuthenticatedSession()`, which silently re-authenticates with
    /// the stored password when the tokens are gone, so a `true` here
    /// does not promise a session can be built without a network round
    /// trip).
    public var isAuthenticated: Bool {
        let hasEmail = Keychain.shared.appleIDEmailAddress != nil
        let hasPassword = Keychain.shared.appleIDPassword != nil
        let hasToken = Keychain.shared.appleIDXcodeToken != nil
        return hasEmail && (hasPassword || hasToken)
    }
    
    public var currentAppleID: String? {
        get { Keychain.shared.appleIDEmailAddress }
        set { Keychain.shared.appleIDEmailAddress = newValue }
    }
    
    public var password: String? {
        get { Keychain.shared.appleIDPassword }
        set { Keychain.shared.appleIDPassword = newValue }
    }
    
    public var adsid: String? {
        get { Keychain.shared.appleIDAdsid }
        set { Keychain.shared.appleIDAdsid = newValue }
    }
    
    public var xcodeToken: String? {
        get { Keychain.shared.appleIDXcodeToken }
        set { Keychain.shared.appleIDXcodeToken = newValue }
    }
    
    public var hasStoredPassword: Bool {
        return Keychain.shared.appleIDPassword != nil
    }
    
    public var hasStoredXcodeToken: Bool {
        return Keychain.shared.appleIDXcodeToken != nil
    }
    
    public func signOut(
        keepCertificate: Bool = false,
        keepAnisetteData: Bool = true,
        keepAnisetteHeaders: Bool = true,
        keepSideSignHeaders: Bool = true
    ) async {
        self.session = nil
        self.team = nil
        if !keepCertificate {
            debugLog("[AuthManager] Clearing signing certificate in cert manager and keychain.")
            CertificateManager.shared.clearActiveCertificate()
            debugLog("[AuthManager] Cleared signing certificate in cert manager and keychain.")

        } else {
            debugLog("[AuthManager] Preserved signing certificate in cert manager and keychain.")
        }
        debugLog("[AuthManager] Clearing account and team info in database.")
        await DatabaseManager.shared.deactivateActiveAccountAndTeam()
        debugLog("[AuthManager] Cleared account and team info in database.")

        debugLog("[AuthManager] Clearing sign-in info from keychain.")
        Keychain.shared.clearSignInInfo(keepAnisetteData: keepAnisetteData)
        debugLog("[AuthManager] Cleared sign-in info from keychain.")

        if !keepAnisetteHeaders {
            debugLog("[AuthManager] Resetting Anisette header customizations to defaults.")
            AnisetteConfigManager.shared.resetToDefaults()
        }

        if !keepSideSignHeaders {
            debugLog("[AuthManager] Resetting SideSign header customizations to defaults.")
            SideSignConfigManager.shared.resetToDefaults()
        }

        AnisetteDataManager.shared.clearCache()
    }
    
    @discardableResult
    public func getAuthenticatedSession() async throws -> ALTAppleAPISession {
        return try await TaskChainCoalescer.shared.coalesce(key: "apple_auth_session") {
            if let adsid = self.adsid,
               let xcodeToken = self.xcodeToken
            {
                return try await self.buildSession(adsid: adsid, xcodeToken: xcodeToken)
            }

            // Tokens are gone but the password survived (e.g. a partial
            // Keychain wipe): `isAuthenticated` still reports signed-in,
            // so try once to re-authenticate silently with the stored
            // password instead of failing straight away. If Apple asks
            // for a verification code there is no handler to answer it,
            // so the attempt throws and the caller falls back to
            // interactive sign-in. Needs proper testing: verify a
            // token-less, password-present account recovers without
            // prompting.
            if let appleID = self.currentAppleID, let password = self.password {
                debugLog("[AuthManager] Session tokens missing; attempting silent re-authentication with the stored password.")
                do {
                    return try await self.silentReauthenticate(appleID: appleID, password: password)
                } catch {
                    debugLog("[AuthManager] Silent re-authentication failed: \(error)")
                }
            }

            debugLog("[AuthManager] No stored tokens found.")
            throw OperationError.notAuthenticated
        }
    }

    private func buildSession(adsid: String, xcodeToken: String) async throws -> ALTAppleAPISession {
        let anisetteData = try await AnisetteProvider.fetch()   // one time pass
        let xcodeVersion = await AnisetteConfigManager.shared.resolvedXcodeVersion()

        let session = ALTAppleAPISession(
            dsid: adsid,
            authToken: xcodeToken,
            anisetteData: anisetteData,
            xcodeVersion: xcodeVersion
        )
        self.session = session
        return session
    }

    /// Re-authenticates with a stored Apple ID + password and persists
    /// the fresh adsid/token pair, mirroring what SignInOperation stores
    /// after an interactive sign-in. No verification handler: any 2FA or
    /// account-repair challenge fails the attempt instead of prompting.
    private func silentReauthenticate(appleID: String, password: String) async throws -> ALTAppleAPISession {
        let anisetteData = try await AnisetteProvider.fetch()
        let xcodeVersion = await AnisetteConfigManager.shared.resolvedXcodeVersion()

        let (_, session) = try await self.portalProxy.signIn(
            appleID: appleID,
            password: password,
            anisetteData: anisetteData,
            xcodeVersion: xcodeVersion,
            verificationHandler: nil
        )

        self.adsid = session.dsid
        self.xcodeToken = session.authToken
        self.session = session
        return session
    }

    public func getAuthenticatedTeam() async throws -> ALTTeam {
        if let team = self.team {
            return team
        }
        
        let team = try await self.resolveActiveTeam()
        self.team = team
        return team
    }

    private func resolveActiveTeam() async throws -> ALTTeam {
        try await DatabaseManager.shared.persistentContainer.performBackgroundTask { context in
            guard let dbTeam = DatabaseManager.shared.activeTeam(in: context) else {
                throw OperationError.notAuthenticated
            }
            return ALTTeam(identifier: dbTeam.identifier, name: dbTeam.name, type: dbTeam.type)
        }
    }
    
    /// Makes the team with the given identifier the active team (and its
    /// account the active account), clearing the cached authenticated
    /// team/session so the next signing or refresh operation re-resolves
    /// from the database.
    ///
    /// This only flips local Core Data flags; it does not touch the
    /// Keychain. Callers must make sure the stored credentials belong to
    /// the team's Apple ID — otherwise the next authenticated call fails
    /// and the user has to sign in again with that Apple ID.
    public func switchActiveTeam(to teamIdentifier: String) async throws {
        try await DatabaseManager.shared.activateTeam(identifier: teamIdentifier)
        self.team = nil
        self.session = nil
    }
    
    @discardableResult
    func signIn(
        presentingViewController: UIViewController? = nil,
        skipDeviceRegistration: Bool = false,
        skipCertificateProvisioning: Bool = false,
        skipResign: Bool = false,
        skipHowTos: Bool = false
    ) async throws -> SignInResult {
        let dbBackgroundContext = DatabaseManager.shared.persistentContainer.newBackgroundContext()
        let signInFlowHandler = SignInFlowHandler(presentingViewController: presentingViewController)
        let context = StandaloneOperationContext(
            steps: .signIn,
            dbBackgroundContext: dbBackgroundContext
        )
        
        let signInOperation = try SignInOperation(
            context: context,
            signInHandler: signInFlowHandler,
            anisetteServerHandler: signInFlowHandler,
            skipDeviceRegistration: skipDeviceRegistration,
            skipCertificateProvisioning: skipCertificateProvisioning,
            skipResign: skipResign,
            skipHowTos: skipHowTos
        )
        let result = try await signInOperation.execute()
        self.team = result.team
        self.session = result.session
        return result
    }
    
    
    // Developer Portal Operations
    public func signIn(appleID: String, 
                       password: String, 
                       anisetteData: ALTAnisetteData, 
                       xcodeVersion: String, 
                       machinePassword: String? = nil,
                       accountRepairHandler: DeveloperPortal.AccountRepairHandler = DeveloperPortal.defaultAccountRepairHandler,
                       verificationHandler: DeveloperPortal.VerificationHandler?) async throws -> (ALTAccount, ALTAppleAPISession) 
    {
        return try await self.portalProxy.signIn(
            appleID: appleID, 
            password: password, 
            anisetteData: anisetteData, 
            xcodeVersion: xcodeVersion, 
            machinePassword: machinePassword,
            accountRepairHandler: accountRepairHandler, 
            verificationHandler: verificationHandler
        )
    }
}

fileprivate extension DatabaseManager {
    //TODO: this is not clean, but for now this should be fine, ie we should later make this proper async instead of blocking
    func deactivateActiveAccountAndTeam() async {
        guard self.isStarted else {
            debugLog("[AuthManager] DatabaseManager is not started. Skipping CoreData active account/team deactivation.")
            return
        }
        let bgContext = self.persistentContainer.newBackgroundContext()
        await bgContext.perform {
            if let account = self.activeAccount(in: bgContext) {
                account.isActiveAccount = false
            }
            if let team = self.activeTeam(in: bgContext) {
                team.isActiveTeam = false
            }
            do {
                try bgContext.save()
            } catch {
                debugLog("[AuthManager] Failed to save CoreData context when deactivating active account and team: \(error)")
            }
        }
        
        await self.viewContext.perform {
            self.viewContext.processPendingChanges()
            self.viewContext.refreshAllObjects()
        }
    }
    
    /// Activates the team with the given identifier (and its account),
    /// deactivating all other teams/accounts, and refreshes the
    /// active-apps limit for the new team's type (same rule
    /// SignInOperation applies on sign-in).
    func activateTeam(identifier: String) async throws {
        guard self.isStarted else {
            debugLog("[AuthManager] DatabaseManager is not started. Cannot switch active team.")
            throw OperationError.notAuthenticated
        }
        let bgContext = self.persistentContainer.newBackgroundContext()
        try await bgContext.perform {
            let teams = try bgContext.fetch(Team.fetchRequest())
            guard let team = teams.first(where: { $0.identifier == identifier }) else {
                throw OperationError.invalidParameters("No stored team with identifier \(identifier).")
            }
            for otherTeam in teams {
                otherTeam.isActiveTeam = (otherTeam == team)
            }
            let accounts = try bgContext.fetch(Account.fetchRequest())
            for account in accounts {
                account.isActiveAccount = (account == team.account)
            }
            UserDefaults.standard.activeAppsLimit = nil
            if team.type == .free {
                let isSparseRestorePatched = ProcessInfo().sparseRestorePatched
                let isAppLimitDisabled = UserDefaults.standard.isAppLimitDisabled
                if !isAppLimitDisabled && isSparseRestorePatched ||
                    isAppLimitDisabled && !isSparseRestorePatched {
                    UserDefaults.standard.activeAppsLimit = InstalledApp.freeAccountActiveAppsLimit
                }
            }
            try bgContext.save()
        }
        
        await self.viewContext.perform {
            self.viewContext.processPendingChanges()
            self.viewContext.refreshAllObjects()
        }
    }
}
