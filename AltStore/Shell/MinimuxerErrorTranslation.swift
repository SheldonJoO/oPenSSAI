#if os(iOS)
//
//  MinimuxerErrorTranslation.swift
//  openSSS
//
//  Display-time Chinese translations for the common minimuxer readiness
//  errors. The engine (Dependencies/minimuxer) reports English reasons;
//  this mapper translates them where they are shown (ToastView), without
//  touching the engine. Each translation names the cause in Chinese and
//  gives a concrete next step.
//
//  Matching is by substring on the error's localized description, which
//  covers both OperationError (whose rawDescription embeds the minimuxer
//  reason verbatim) and MinimuxerError surfaced directly from install
//  paths (whose description is "NoDevice: <reason>", etc.). Unknown errors
//  return nil and keep the existing English display.
//
//  Copyright © 2026 openSSS Contributors. All rights reserved.
//

import Foundation

/// A Chinese title + detail (cause + next step) for a minimuxer error.
struct MinimuxerErrorTranslation
{
    let title: String
    let detail: String
}

enum MinimuxerErrorTranslator
{
    /// Returns the Chinese translation for a known minimuxer error, or nil
    /// when the error is not one of the mapped readiness failures.
    static func translation(for error: Error) -> MinimuxerErrorTranslation?
    {
        let message = (error as NSError).localizedDescription

        // Order matters: check the most specific patterns first.
        if message.contains("tunnel peer IP is not yet reachable")
        {
            // Local VPN mode: the tunnel is up but the device endpoint
            // (tunnel peer) is not reachable.
            return MinimuxerErrorTranslation(
                title: NSLocalizedString("Device Endpoint Unreachable", comment: ""),
                detail: NSLocalizedString("Local VPN Endpoint Unreachable", comment: ""))
        }
        if message.contains("Remote endpoint IP is not configured or reachable")
        {
            // Remote Direct mode: no endpoint configured or not reachable.
            return MinimuxerErrorTranslation(
                title: NSLocalizedString("Remote Endpoint Unreachable", comment: ""),
                detail: NSLocalizedString("Remote Endpoint Not Configured", comment: ""))
        }
        if message.contains("TCP port poll failed")
        {
            // The endpoint IP is known but the service-port probe failed.
            if message.contains("Remote endpoint")
            {
                return MinimuxerErrorTranslation(
                    title: NSLocalizedString("Remote Endpoint Unreachable", comment: ""),
                    detail: NSLocalizedString("Remote Endpoint TCP Probe Failed", comment: ""))
            }
            return MinimuxerErrorTranslation(
                title: NSLocalizedString("Device Endpoint Unreachable", comment: ""),
                detail: NSLocalizedString("Local VPN TCP Probe Failed", comment: ""))
        }
        if message.contains("No utun interface detected")
        {
            // Local VPN mode with no VPN interface at all.
            return MinimuxerErrorTranslation(
                title: NSLocalizedString("VPN Not Connected", comment: ""),
                detail: NSLocalizedString("No VPN Interface", comment: ""))
        }
        if message.contains("no ipsec/IKEv2 interface found")
        {
            // Local VPN mode on iOS 26.4+ with a lockdown pairing file:
            // utun is up but the VPN has no IKEv2 interface.
            return MinimuxerErrorTranslation(
                title: NSLocalizedString("VPN Protocol Unsupported", comment: ""),
                detail: NSLocalizedString("IPSec Interface Missing", comment: ""))
        }
        if message.contains("No valid pairing file has been loaded")
        {
            return MinimuxerErrorTranslation(
                title: NSLocalizedString("Pairing Required", comment: ""),
                detail: NSLocalizedString("Pairing Required Detail", comment: ""))
        }
        if message.contains("Connection mode not configured")
        {
            return MinimuxerErrorTranslation(
                title: NSLocalizedString("Connection Mode Not Configured", comment: ""),
                detail: NSLocalizedString("Connection Mode Not Configured Detail", comment: ""))
        }
        if message.contains("No wifi interface satisfied")
        {
            return MinimuxerErrorTranslation(
                title: NSLocalizedString("No Wi-Fi Connection", comment: ""),
                detail: NSLocalizedString("No Wi-Fi Connection Detail", comment: ""))
        }
        return nil
    }
}
#endif
