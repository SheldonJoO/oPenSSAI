//
//  PairingCodeLiveActivity.swift
//  AltWidgetExtension
//
//  Copyright © 2026 SideStore. All rights reserved.
//

import ActivityKit
import SwiftUI
import WidgetKit

/// Live Activity for the wireless-pairing code: shows the code in the
/// Dynamic Island (and on the Lock Screen) while pairing waits for the user
/// to enter it on the other device. The attributes type lives in
/// `Shared/PairingCodeActivityAttributes.swift`, shared with the app target.
///
/// Needs proper testing: Live Activities only render on a real device —
/// verify on-device that the island shows the code when the PIN sheet
/// appears and disappears when pairing ends.
@available(iOS 16.1, *)
struct PairingCodeLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PairingCodeAttributes.self) { context in
            // Lock Screen banner.
            HStack(spacing: 12) {
                Image(systemName: "person.badge.key.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pairing Code")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(context.state.pinCode)
                        .font(.system(size: 28, weight: .bold, design: .monospaced))
                }
                Spacer()
            }
            .padding()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text("Pairing Code")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Image(systemName: "person.badge.key.fill")
                        .foregroundStyle(.secondary)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 4) {
                        Text(context.state.pinCode)
                            .font(.system(size: 36, weight: .bold, design: .monospaced))
                        Text("Enter this 6-digit code on the connecting device to complete pairing.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
            } compactLeading: {
                Image(systemName: "person.badge.key.fill")
            } compactTrailing: {
                Text(context.state.pinCode)
                    .font(.system(.caption, design: .monospaced).bold())
            } minimal: {
                Image(systemName: "person.badge.key.fill")
            }
        }
    }
}
