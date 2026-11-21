//
//  PairingCodeActivityAttributes.swift
//  SideStore
//
//  Copyright © 2026 SideStore. All rights reserved.
//

import ActivityKit
import Foundation

/// Attributes for the pairing-code Live Activity shown in the Dynamic Island
/// (and on the Lock Screen) while wireless pairing waits for the user to
/// enter the code on the other device.
///
/// This file is compiled into both the app target and the AltWidgetExtension
/// target (via the shared `Shared/` synchronized group): ActivityKit matches
/// a running activity to its `ActivityConfiguration` by this type, so both
/// sides must see the exact same definition. Do not move it into a
/// target-specific directory.
///
/// Live Activities need iOS 16.1+, while the project deployment target is
/// iOS 15.0, so everything here is availability-gated.
@available(iOS 16.1, *)
struct PairingCodeAttributes: ActivityAttributes {
    /// No fixed attributes: the code only arrives once a device connects,
    /// so it lives in `ContentState` and can be updated if a new code arrives.
    struct ContentState: Codable, Hashable {
        /// The pairing code to display (typically 6 digits).
        var pinCode: String
    }
}
