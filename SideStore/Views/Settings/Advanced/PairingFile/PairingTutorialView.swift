#if os(iOS)
//
//  PairingTutorialView.swift
//  SideStore
//
//  In-app pairing tutorial (shell style): what pairing is, turning on
//  Developer Mode, pairing wirelessly or by importing a pairing file, and
//  what the pairing code is for. Reached from the pairing management
//  screen and from pairing-required errors (alert + toast). The tutorial
//  is a guide only: wireless pairing reuses WirelessPairView, and file
//  import reuses PairingFileManager (the management screen keeps the full
//  protocol-mismatch flow).
//
//  Copyright © 2026 SideStore. All rights reserved.
//

import SwiftUI
import UniformTypeIdentifiers

struct PairingTutorialView: View {
    /// When true the tutorial was presented modally (from an alert or a
    /// toast) and shows a Done button; when pushed from the pairing
    /// management screen the navigation back button is enough.
    var isModal = false

    @Environment(\.dismiss) private var dismiss

    @State private var isPaired = PairingFileManager.shared.hasPairingFile()
    @State private var showFileImporter = false
    @State private var importStatus: String? = nil
    @State private var isStartingConnection = false

    var body: some View {
        // Explicit showsIndicators: a bare ScrollView { } is ambiguous
        // between SwiftUI's two inits here (isolated vs nonisolated
        // overloads) under Xcode 16.4; passing the parameter pins the
        // first overload. Other files' bare ScrollViews resolve fine,
        // so this is specific to this view's content closure.
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                statusCard
                introSection
                developerModeSection
                pairSection
                pairingCodeSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
        .background(Color(uiColor: ShellTheme.background).ignoresSafeArea())
        .navigationTitle(Text("Pairing Tutorial"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isModal {
                ToolbarItem(placement: .navigationBarLeading) {
                    SwiftUI.Button {
                        dismiss()
                    } label: {
                        Text("Done")
                    }
                }
            }
        }
        .onAppear {
            isPaired = PairingFileManager.shared.hasPairingFile()
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: PairingFileManager.supportedContentTypes,
            allowsMultipleSelection: false
        ) { result in
            // The [URL] overload (same pattern as the other fileImporter
            // call sites in this codebase): the single-URL overload does
            // not take allowsMultipleSelection, so annotating Result<URL>
            // here makes the compiler reject the closure outright.
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                handleImportResult(.success(url))
            case .failure(let error):
                handleImportResult(.failure(error))
            }
        }
    }

    // MARK: - Sections

    private var statusCard: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(isPaired ? Color.green : Color.red)
                .frame(width: 10, height: 10)
                .shadow(color: (isPaired ? Color.green : Color.red).opacity(0.8), radius: 3)

            Text("Pairing Status")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Color(uiColor: ShellTheme.primaryText))

            Spacer()

            Text(isPaired ? "Paired" : "Not Paired")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(isPaired ? Color.green : Color.red)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill((isPaired ? Color.green : Color.red).opacity(0.15)))
        }
        .padding(.horizontal, 16)
        .frame(height: 50)
        .background(Color(uiColor: ShellTheme.card))
        .cornerRadius(ShellTheme.cardCornerRadius)
    }

    private var introSection: some View {
        section(title: "What Is Pairing?") {
            Text("oPenSSAI signs apps on your device, and iOS only allows that over a trusted pairing connection. Pair once, and installs and refreshes can reach your device without a computer.")
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(Color(uiColor: ShellTheme.secondaryText))
        }
    }

    private var developerModeSection: some View {
        section(title: "Step 1: Turn On Developer Mode") {
            Text("Open Settings → Privacy & Security → Developer Mode, turn it on, and restart your device when asked. Wireless pairing and on-device signing need Developer Mode.")
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(Color(uiColor: ShellTheme.secondaryText))
        }
    }

    private var pairSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Step 2: Pair Your Device")

            VStack(alignment: .leading, spacing: 0) {
                Text("You only need one method — pick whichever is easier.")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(Color(uiColor: ShellTheme.secondaryText))
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 12)

                NavigationLink(destination: WirelessPairView()) {
                    actionRow(
                        icon: "antenna.radiowaves.left.and.right",
                        title: "Wireless Pairing",
                        subtitle: "No computer needed."
                    )
                }

                Divider()
                    .background(Color(uiColor: ShellTheme.separator))
                    .padding(.horizontal, 16)

                SwiftUI.Button {
                    showFileImporter = true
                } label: {
                    actionRow(
                        icon: "square.and.arrow.down",
                        title: "Import a Pairing File",
                        subtitle: "From iloader or idevice_pair on your computer."
                    )
                }
                .buttonStyle(.plain)

                if let importStatus {
                    HStack(spacing: 8) {
                        if isStartingConnection {
                            ProgressView()
                        }
                        Text(importStatus)
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(Color(uiColor: ShellTheme.secondaryText))
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 16)
                } else {
                    Spacer()
                        .frame(height: 16)
                }
            }
            .background(Color(uiColor: ShellTheme.card))
            .cornerRadius(ShellTheme.cardCornerRadius)
        }
    }

    private var pairingCodeSection: some View {
        section(title: "What Is the Pairing Code For?") {
            Text("During wireless pairing, your device shows a 6-digit pairing code. Entering it on the connecting device proves the pairing request comes from you and your device. Each pairing shows a new code — never share it with anyone else.")
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(Color(uiColor: ShellTheme.secondaryText))
        }
    }

    // MARK: - Helpers

    private func sectionTitle(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.system(size: 15, weight: .bold))
            .foregroundColor(Color(uiColor: ShellTheme.secondaryText))
            .padding(.horizontal, 4)
    }

    private func section<Content: View>(title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(title)
            content()
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(uiColor: ShellTheme.card))
                .cornerRadius(ShellTheme.cardCornerRadius)
        }
    }

    private func actionRow(icon: String, title: LocalizedStringKey, subtitle: LocalizedStringKey) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(Color(uiColor: ShellTheme.accentColor))
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(Color(uiColor: ShellTheme.primaryText))
                Text(subtitle)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(Color(uiColor: ShellTheme.secondaryText))
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Color(uiColor: ShellTheme.secondaryText))
        }
        .padding(.horizontal, 16)
        .frame(height: 60)
    }

    // MARK: - Import

    private func handleImportResult(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            do {
                try PairingFileManager.shared.importPairingFile(from: url)
                isPaired = PairingFileManager.shared.hasPairingFile()
                importStatus = NSLocalizedString("Pairing file imported. Starting the connection…", comment: "")
                Task { @MainActor in
                    await startConnectionAfterImport()
                }
            } catch {
                importStatus = String(
                    format: NSLocalizedString("Failed to import pairing file: %@", comment: ""),
                    error.localizedDescription
                )
            }
        case .failure(let error):
            // Cancelling the picker is not an error.
            if (error as NSError).code == NSUserCancelledError { return }
            importStatus = String(
                format: NSLocalizedString("Failed to import pairing file: %@", comment: ""),
                error.localizedDescription
            )
        }
    }

    /// Starts minimuxer with the freshly imported file so the user does
    /// not have to restart oPenSSAI. If it fails, the file is still saved
    /// and a restart picks it up at boot. Needs proper testing on device.
    @MainActor
    private func startConnectionAfterImport() async {
        isStartingConnection = true
        defer { isStartingConnection = false }
        guard let pairingString = PairingFileManager.shared.fetchPairingFile() else {
            importStatus = NSLocalizedString("Pairing file imported. If installs still fail, restart oPenSSAI and try again.", comment: "")
            return
        }
        do {
            try await AppBootManager.shared.startMinimuxer(pairingFile: pairingString)
            importStatus = NSLocalizedString("Paired successfully. You can install and refresh apps now.", comment: "")
        } catch {
            debugLog("[PairingTutorial] startMinimuxer after import failed: \(error)")
            importStatus = NSLocalizedString("Pairing file imported. If installs still fail, restart oPenSSAI and try again.", comment: "")
        }
    }
}

/// Presents the pairing tutorial modally in its own navigation stack, for
/// UIKit callers (pairing-required alerts, error toasts).
extension UIViewController {
    func presentPairingTutorial(animated: Bool = true) {
        let tutorial = ShellHostingController(rootView: PairingTutorialView(isModal: true))
        let navigationController = UINavigationController(rootViewController: tutorial)
        let appearance = ShellTabBarController.makeNavigationBarAppearance()
        navigationController.navigationBar.standardAppearance = appearance
        navigationController.navigationBar.scrollEdgeAppearance = appearance
        navigationController.navigationBar.compactAppearance = appearance
        navigationController.navigationBar.tintColor = ShellTheme.accentColor
        present(navigationController, animated: animated)
    }
}
#endif
