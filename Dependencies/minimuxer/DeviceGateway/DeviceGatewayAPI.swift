//
//  DeviceGatewayAPI.swift
//  Minimuxer
//
//  Created by Magesh K on 22/08/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import Foundation
import MinimuxerCommon

public struct PairedDeviceRecord: Sendable {
    public let name: String
    public let model: String
    public let pairingFilePath: String
    public let pairingFile: any PairingFile

    public init(name: String, model: String, pairingFilePath: String, pairingFile: any PairingFile) {
        self.name = name
        self.model = model
        self.pairingFilePath = pairingFilePath
        self.pairingFile = pairingFile
    }
}

/// Snapshot of the on-device location simulation session, as held by the
/// gateway. Mirrors the Mac helper's /status shape so the shell can treat
/// both transports the same way.
///
/// `active` is the gateway's local belief (a session handle is held and a
/// coordinate was set); it can go stale when iOS suspends the app and the
/// DVT session drops without the gateway noticing. `confirmed` is only
/// true when the device actually acknowledged a coordinate set — i.e. the
/// state was verified with the device, not just read back locally.
public struct LocationSimulationState: Sendable {
    public let active: Bool
    public let latitude: Double?
    public let longitude: Double?
    /// Whether the gateway currently holds a live DVT session to the device.
    public let connected: Bool
    /// Whether the active state was confirmed by the device (a coordinate
    /// set succeeded). False for plain status reads, which never touch
    /// the device.
    public let confirmed: Bool

    public init(active: Bool, latitude: Double?, longitude: Double?, connected: Bool, confirmed: Bool = false) {
        self.active = active
        self.latitude = latitude
        self.longitude = longitude
        self.connected = connected
        self.confirmed = confirmed
    }
}

public protocol DeviceGatewayAPI: AnyObject, Sendable {
    var requiresUsbmuxd: Bool { get }
    var pairingFileType: PairingProtocol { get }
    var pairingFileData: Data? { get }
    var pairingDataDict: [String: any Sendable]? { get }

    func getPort(for protocolType: PairingProtocol) -> UInt16
    func setPort(_ port: UInt16, for protocolType: PairingProtocol)

    func start(pairingFileContent: String, preferred: PairingProtocol?) async throws
    func stop() async throws
    func setDeviceEndpointIp(_ ip: String?)
    func setLogging(_ enabled: Bool)

    func fetchUDID() async throws -> String
    func getLockdownValue(key: String) async throws -> String

    func isDDIMounted() async throws -> Bool
    func mountDeveloperImage(image: Data, signature: Data) async throws
    func mountPersonalizedDdi(image: Data, trustcache: Data, manifest: Data) async throws

    func installProvisioningProfile(profile: Data) async throws
    func removeProvisioningProfile(id: String) async throws
    func dumpProfiles(docsPath: String) async throws -> String
    func removeApp(bundleId: String) async throws
    func sendIpaAfc(bundleId: String, ipaBytes: Data) async throws
    func sendAppBundleAfc(bundleId: String, appURL: URL) async throws
    func installIpa(bundleId: String) async throws
    func installAppBundle(bundleId: String, appName: String) async throws
    func wipeContainer(identifier: String) async throws

    func debugApp(appId: String) async throws
    func debugProcess(pid: UInt32) async throws

    func performHeartbeat(interval: UInt64) async throws -> UInt64

    /// Starts (or reuses) the persistent DVT location simulation session and
    /// sets the simulated coordinate. The session stays alive across calls
    /// until stopLocationSimulation() — the gateway re-sends the coordinate
    /// periodically to keep the simulation active. Requires an initialized
    /// gateway in remote-pairing mode (the DVT channel is only reachable
    /// through the RP tunnel) and Developer Mode on the device.
    func startLocationSimulation(latitude: Double, longitude: Double) async throws
    /// Clears the simulated coordinate and tears the session down. Best
    /// effort: succeeds even when no session is currently held.
    func stopLocationSimulation() async throws
    /// Snapshot of the current session state. Cheap — never touches the
    /// device, so `confirmed` is always false: this is the gateway's local
    /// belief, which can go stale when iOS suspends the app and the DVT
    /// session drops. Use verifyLocationSimulation() for a checked state.
    func locationSimulationStatus() async throws -> LocationSimulationState
    /// Re-confirms an active simulation with the device and returns the
    /// checked state (`confirmed` is true when the device acknowledged
    /// the coordinate). The DVT location simulation API has no status
    /// query (the idevice FFI only exposes new/set/clear/free), so
    /// verification re-sets the active coordinate on the device —
    /// re-establishing the DVT session first when it dropped while the
    /// app was suspended — and reports the outcome. A failed re-set tears
    /// the local session down and reports inactive. When nothing is
    /// locally active this is a cheap local read, like
    /// locationSimulationStatus().
    func verifyLocationSimulation() async throws -> LocationSimulationState
    /// Whether Developer Mode is enabled on the device (lockdown
    /// DeveloperModeStatus in the com.apple.security.mac.amfi domain).
    func isDeveloperModeEnabled() async throws -> Bool

    func startWirelessPair(
        hostName: String,
        hostModel: String,
        outPath: String,
        resolveFileName: (@Sendable (String, String) -> String)?,
        onReady: @escaping @Sendable (String, UInt16, [String: String]) -> Void,
        onPin: @escaping @Sendable (String) -> Void
    ) async throws -> PairedDeviceRecord

    func triggerWirelessPair(
        targetIp: String,
        targetPort: UInt16,
        hostName: String,
        hostModel: String,
        outPath: String,
        resolveFileName: (@Sendable (String, String) -> String)?,
        onRequestPin: @escaping @Sendable (@escaping @Sendable (String) -> Void) -> Void
    ) async throws -> PairedDeviceRecord

    func afcListDirectory(bundleId: String, path: String) async throws -> [String]
    func afcReadFile(bundleId: String, path: String) async throws -> Data
    func afcGetFileInfo(bundleId: String, path: String) async throws -> (isDirectory: Bool, fileSize: Int64)
}

public extension DeviceGatewayAPI {
    func start(pairingFileContent: String, preferred: PairingProtocol? = nil) async throws {
        try await start(pairingFileContent: pairingFileContent, preferred: preferred)
    }

    // Active service port for the currently loaded pairing file mode
    var servicePort: UInt16 {
        getPort(for: pairingFileType)
    }
}
