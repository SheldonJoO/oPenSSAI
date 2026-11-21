#if os(iOS)
//
//  LocationSimulationService.swift
//  oPenSSAI
//
//  Virtual location: transport-agnostic service interface plus two
//  implementations. The shell UI talks only to LocationSimulationManager;
//  the manager prefers the on-device transport (OnDeviceLocationService,
//  which drives the device's DVT location simulation service directly
//  through the vendored idevice FFI) and falls back to the Mac helper
//  (HelperLocationService, HTTP to a small Rust helper on the user's Mac,
//  tools/location-helper) when on-device is unavailable. The simulated
//  position is system-wide (Maps and every app read it from locationd).
//  See docs/location-simulation-design.md.
//
//  Copyright © 2026 oPenSSAI Contributors. All rights reserved.
//

import DeviceGatewayAPI
import Foundation
import Minimuxer
import UIKit

/// A coordinate to simulate.
struct SimulatedLocation: Codable, Equatable, Sendable
{
    var latitude: Double
    var longitude: Double
    /// Preset display name, if this came from a preset.
    var name: String?

    var isValid: Bool
    {
        (-90...90).contains(latitude) && (-180...180).contains(longitude)
    }

    var coordinateText: String
    {
        String(format: "%.5f, %.5f", latitude, longitude)
    }
}

/// Snapshot of the simulation state, as reported by the transport.
struct LocationSimulationStatus: Decodable, Equatable, Sendable
{
    var active: Bool
    var latitude: Double?
    var longitude: Double?
    /// Whether the helper currently holds a live device session.
    var connected: Bool

    var location: SimulatedLocation?
    {
        guard let latitude, let longitude else { return nil }
        return SimulatedLocation(latitude: latitude, longitude: longitude, name: nil)
    }
}

enum LocationSimulationError: Error, LocalizedError
{
    case invalidHelperAddress
    case invalidCoordinates
    case network(Error)
    case server(statusCode: Int, message: String?)
    case invalidResponse
    case noTransportAvailable
    case gatewayNotStarted
    case pairingFileInvalid
    case deviceConnectionFailed
    case backendUnsupported
    case developerModeDisabled
    case onDeviceFailed(String)

    var errorDescription: String?
    {
        switch self
        {
        case .invalidHelperAddress:
            return NSLocalizedString("Invalid helper address", comment: "")
        case .invalidCoordinates:
            return NSLocalizedString("Invalid coordinates", comment: "")
        case .network(let error):
            return error.localizedDescription
        case .server(let statusCode, let message):
            if let message, !message.isEmpty { return message }
            return String(format: NSLocalizedString("Helper error (%d)", comment: ""), statusCode)
        case .invalidResponse:
            return NSLocalizedString("Invalid response from helper", comment: "")
        case .noTransportAvailable:
            return NSLocalizedString("No location transport is available", comment: "")
        case .gatewayNotStarted:
            return NSLocalizedString("Device connection is not started. Pair the device or restart the app.", comment: "")
        case .pairingFileInvalid:
            return NSLocalizedString("The pairing file is invalid. Please pair again.", comment: "")
        case .deviceConnectionFailed:
            return NSLocalizedString("Cannot connect to the device. Make sure it is paired and on the same network.", comment: "")
        case .backendUnsupported:
            return NSLocalizedString("The current gateway backend does not support on-device location. Switch to the idevice backend in Settings.", comment: "")
        case .developerModeDisabled:
            return NSLocalizedString("Developer Mode is off. Turn it on in Settings > Privacy & Security > Developer Mode, then restart the device.", comment: "")
        case .onDeviceFailed(let detail):
            return String(format: NSLocalizedString("On-device location failed: %@", comment: ""), detail)
        }
    }
}

/// Transport-agnostic interface for location simulation.
protocol LocationSimulationService: AnyObject, Sendable
{
    func setLocation(_ location: SimulatedLocation) async throws
    func clearLocation() async throws
    func fetchStatus() async throws -> LocationSimulationStatus
}

/// Talks to the Mac helper over HTTP (see tools/location-helper).
final class HelperLocationService: LocationSimulationService, @unchecked Sendable
{
    private let baseURL: URL
    private let session: URLSession

    init(baseURL: URL, timeoutIntervalForRequest: TimeInterval = 15)
    {
        self.baseURL = baseURL
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeoutIntervalForRequest
        configuration.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: configuration)
    }

    func setLocation(_ location: SimulatedLocation) async throws
    {
        var request = URLRequest(url: baseURL.appendingPathComponent("location"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Double] = ["latitude": location.latitude, "longitude": location.longitude]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        _ = try await perform(request, expecting: LocationSimulationStatus.self)
    }

    func clearLocation() async throws
    {
        var request = URLRequest(url: baseURL.appendingPathComponent("location"))
        request.httpMethod = "DELETE"
        _ = try await perform(request, expecting: LocationSimulationStatus.self)
    }

    func fetchStatus() async throws -> LocationSimulationStatus
    {
        let request = URLRequest(url: baseURL.appendingPathComponent("status"))
        return try await perform(request, expecting: LocationSimulationStatus.self)
    }

    private func perform<T: Decodable>(_ request: URLRequest, expecting type: T.Type) async throws -> T
    {
        let (data, response): (Data, URLResponse)
        do
        {
            (data, response) = try await session.data(for: request)
        }
        catch
        {
            throw LocationSimulationError.network(error)
        }
        guard let httpResponse = response as? HTTPURLResponse else
        {
            throw LocationSimulationError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else
        {
            let message = (try? JSONDecoder().decode(HelperErrorResponse.self, from: data))?.error
            throw LocationSimulationError.server(statusCode: httpResponse.statusCode, message: message)
        }
        guard let decoded = try? JSONDecoder().decode(T.self, from: data) else
        {
            throw LocationSimulationError.invalidResponse
        }
        return decoded
    }

    private struct HelperErrorResponse: Decodable
    {
        var error: String?
    }
}

/// Drives the DVT location simulation service directly through the
/// vendored idevice FFI (IdeviceGateway) — no Mac involved at runtime.
/// Singleton: the background task identifier must outlive per-call
/// instances.
final class OnDeviceLocationService: LocationSimulationService, @unchecked Sendable
{
    static let shared = OnDeviceLocationService()

    @MainActor private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid

    private init() {}

    private var gateway: any DeviceGatewayAPI { Minimuxer.shared.gateway }

    func setLocation(_ location: SimulatedLocation) async throws
    {
        do
        {
            try await gateway.startLocationSimulation(latitude: location.latitude, longitude: location.longitude)
        }
        catch
        {
            // If Developer Mode is off, say so plainly instead of surfacing
            // the raw DVT error.
            if let developerMode = try? await gateway.isDeveloperModeEnabled(), !developerMode
            {
                throw LocationSimulationError.developerModeDisabled
            }
            throw Self.mapError(error)
        }
        await beginBackgroundTask()
    }

    func clearLocation() async throws
    {
        do
        {
            try await gateway.stopLocationSimulation()
        }
        catch
        {
            throw Self.mapError(error)
        }
        await endBackgroundTask()
    }

    func fetchStatus() async throws -> LocationSimulationStatus
    {
        let state: LocationSimulationState
        do
        {
            state = try await gateway.locationSimulationStatus()
        }
        catch
        {
            throw Self.mapError(error)
        }
        return LocationSimulationStatus(active: state.active, latitude: state.latitude, longitude: state.longitude, connected: state.connected)
    }

    /// Reads Developer Mode from the device (lockdown DeveloperModeStatus).
    func isDeveloperModeEnabled() async throws -> Bool
    {
        do
        {
            return try await gateway.isDeveloperModeEnabled()
        }
        catch
        {
            throw Self.mapError(error)
        }
    }

    // MARK: - Background task

    /// Keeps the app alive briefly after it leaves the foreground so the
    /// DVT session is not cut the moment the user switches apps. iOS still
    /// suspends the app after a few minutes — the screen tells the user to
    /// keep the app in the foreground while simulating.
    @MainActor
    private func beginBackgroundTask()
    {
        guard backgroundTaskID == .invalid else { return }
        backgroundTaskID = UIApplication.shared.beginBackgroundTask { [weak self] in
            debugLog("[LocationSimulation] background task expired; on-device session may drop")
            Task { @MainActor [weak self] in
                self?.endBackgroundTask()
            }
        }
    }

    @MainActor
    private func endBackgroundTask()
    {
        guard backgroundTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
    }

    // MARK: - Error mapping

    /// Maps gateway errors to user-facing errors with Chinese messages.
    private static func mapError(_ error: Error) -> LocationSimulationError
    {
        guard let gatewayError = error as? DeviceGatewayError else
        {
            return .onDeviceFailed(error.localizedDescription)
        }
        switch gatewayError.code
        {
        case .notInitialized:
            return .gatewayNotStarted
        case .invalidPairingFile:
            return .pairingFileInvalid
        case .connectionFailed, .deviceEndpointIpNotAvailable, .noConnection, .invalidTargetEndpoint:
            return .deviceConnectionFailed
        case .unsupportedOperation:
            return .backendUnsupported
        case .serviceError:
            let detail = gatewayError.reason.isEmpty ? gatewayError.localizedDescription : gatewayError.reason
            return .onDeviceFailed(detail)
        default:
            return .onDeviceFailed(gatewayError.localizedDescription)
        }
    }
}

/// Which transport a simulation runs on.
enum LocationTransport: String, Codable, Sendable
{
    case onDevice
    case helper

    var displayName: String
    {
        switch self
        {
        case .onDevice:
            return NSLocalizedString("On-Device", comment: "")
        case .helper:
            return NSLocalizedString("Mac Helper", comment: "")
        }
    }
}

/// On-device prerequisites, for the screen's Prerequisites section.
/// developerMode is nil when it could not be read (e.g. the gateway has
/// not started yet).
struct LocationPrerequisites: Equatable, Sendable
{
    var backendIsIdevice: Bool
    var hasRPPairingFile: Bool
    var developerMode: Bool?
}

/// Preset locations offered on the virtual-location screen. Coordinates are
/// WGS-84; inside China, Apple Maps displays GCJ-02, so the pin can appear
/// offset by a few hundred meters (see the screen's footnote).
enum LocationPresets
{
    static let all: [SimulatedLocation] = [
        SimulatedLocation(latitude: 37.54469, longitude: 121.36857, name: NSLocalizedString("Yantai", comment: "")),
        SimulatedLocation(latitude: 39.90420, longitude: 116.40740, name: NSLocalizedString("Beijing", comment: "")),
        SimulatedLocation(latitude: 31.23040, longitude: 121.47370, name: NSLocalizedString("Shanghai", comment: "")),
        SimulatedLocation(latitude: 22.54310, longitude: 114.05790, name: NSLocalizedString("Shenzhen", comment: "")),
        SimulatedLocation(latitude: 22.31930, longitude: 114.16940, name: NSLocalizedString("Hong Kong", comment: "")),
        SimulatedLocation(latitude: 35.67620, longitude: 139.65030, name: NSLocalizedString("Tokyo", comment: "")),
        SimulatedLocation(latitude: 40.71280, longitude: -74.00600, name: NSLocalizedString("New York", comment: "")),
        SimulatedLocation(latitude: 51.50740, longitude: -0.12780, name: NSLocalizedString("London", comment: "")),
        SimulatedLocation(latitude: 52.52000, longitude: 13.40500, name: NSLocalizedString("Berlin", comment: "")),
        SimulatedLocation(latitude: 37.77490, longitude: -122.41940, name: NSLocalizedString("San Francisco", comment: "")),
    ]
}

/// Owns the helper address + last simulation state; the single place the
/// shell reads virtual-location state from. Resolves the transport:
/// on-device first, Mac helper as the fallback.
@MainActor
final class LocationSimulationManager
{
    static let shared = LocationSimulationManager()

    private static let helperAddressDefaultsKey = "location.helperAddress"
    private static let lastLocationDefaultsKey = "location.lastLocation"
    private static let activeTransportDefaultsKey = "location.activeTransport"
    static let defaultHelperPort = 17878
    /// Short timeout for the secondary-transport status probe, so a
    /// powered-off Mac does not stall the screen.
    private static let secondaryProbeTimeout: TimeInterval = 5

    var helperAddress: String
    {
        get { UserDefaults.standard.string(forKey: Self.helperAddressDefaultsKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: Self.helperAddressDefaultsKey) }
    }

    var lastLocation: SimulatedLocation?
    {
        get
        {
            guard let data = UserDefaults.standard.data(forKey: Self.lastLocationDefaultsKey) else { return nil }
            return try? JSONDecoder().decode(SimulatedLocation.self, from: data)
        }
        set
        {
            if let value = newValue, let data = try? JSONEncoder().encode(value)
            {
                UserDefaults.standard.set(data, forKey: Self.lastLocationDefaultsKey)
            }
            else
            {
                UserDefaults.standard.removeObject(forKey: Self.lastLocationDefaultsKey)
            }
        }
    }

    /// Transport the simulation is running on, persisted so stop/clear goes
    /// to the same transport that started it.
    var activeTransport: LocationTransport
    {
        get
        {
            guard let raw = UserDefaults.standard.string(forKey: Self.activeTransportDefaultsKey),
                  let transport = LocationTransport(rawValue: raw) else { return .onDevice }
            return transport
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: Self.activeTransportDefaultsKey) }
    }

    /// Cheap synchronous check: idevice backend + an RP pairing file.
    /// (Developer Mode needs a device round-trip — see checkPrerequisites().)
    var onDeviceAvailable: Bool
    {
        selectedGatewayBackendCache == .idevice
            && PairingFileManager.shared.hasPairingFile(for: .rppairing)
    }

    var helperConfigured: Bool
    {
        !helperAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Last status fetched (nil = never checked).
    private(set) var lastStatus: LocationSimulationStatus?

    /// One-line status for the Me tab row.
    var statusSummary: String?
    {
        guard let lastStatus, lastStatus.active, let location = lastStatus.location else { return nil }
        return location.coordinateText
    }

    /// Reads the on-device prerequisites, including the Developer Mode
    /// state from the device (a lockdown round-trip).
    func checkPrerequisites() async -> LocationPrerequisites
    {
        let backendOK = selectedGatewayBackendCache == .idevice
        let pairingOK = PairingFileManager.shared.hasPairingFile(for: .rppairing)
        var developerMode: Bool? = nil
        if backendOK && pairingOK
        {
            developerMode = try? await OnDeviceLocationService.shared.isDeveloperModeEnabled()
        }
        return LocationPrerequisites(backendIsIdevice: backendOK, hasRPPairingFile: pairingOK, developerMode: developerMode)
    }

    /// Starts simulation on the preferred transport (on-device first),
    /// falling back to the helper when on-device fails. Returns the
    /// transport actually used.
    @discardableResult
    func setLocation(_ location: SimulatedLocation) async throws -> LocationTransport
    {
        var firstError: Error?
        for (index, transport) in preferredTransports().enumerated()
        {
            do
            {
                try await service(for: transport, shortTimeout: index > 0).setLocation(location)
                activeTransport = transport
                lastLocation = location
                return transport
            }
            catch
            {
                debugLog("[LocationSimulation] setLocation failed on \(transport): \(error)")
                firstError = firstError ?? error
            }
        }
        throw firstError ?? LocationSimulationError.noTransportAvailable
    }

    /// Clears the simulation on the transport it runs on; if that fails,
    /// tries the other transport once (a stale simulation is worse than a
    /// double clear).
    func clearLocation() async throws
    {
        var firstError: Error?
        for transport in clearOrder()
        {
            do
            {
                try await service(for: transport).clearLocation()
                return
            }
            catch
            {
                debugLog("[LocationSimulation] clearLocation failed on \(transport): \(error)")
                firstError = firstError ?? error
            }
        }
        throw firstError ?? LocationSimulationError.noTransportAvailable
    }

    @discardableResult
    func refreshStatus() async -> LocationSimulationStatus?
    {
        // Query in preference order. The first active status wins, so a
        // simulation started on the other transport does not go unnoticed;
        // otherwise the first idle status is returned.
        var idle: LocationSimulationStatus?
        for (index, transport) in preferredTransports().enumerated()
        {
            let status: LocationSimulationStatus
            do
            {
                status = try await service(for: transport, shortTimeout: index > 0).fetchStatus()
            }
            catch
            {
                debugLog("[LocationSimulation] status refresh failed on \(transport): \(error)")
                continue
            }
            if status.active
            {
                activeTransport = transport
                lastStatus = status
                if let location = status.location { lastLocation = location }
                return status
            }
            if idle == nil { idle = status }
        }
        if let idle
        {
            lastStatus = idle
            return idle
        }
        return nil
    }

    /// The Mac helper transport, regardless of on-device availability.
    /// Used by the Test Connection action.
    func makeHelperService(shortTimeout: Bool = false) throws -> LocationSimulationService
    {
        var address = helperAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty else { throw LocationSimulationError.invalidHelperAddress }
        if !address.contains("://") { address = "http://" + address }
        // A bare IP ("192.168.1.5") has no port, which would silently mean
        // port 80; the helper listens on defaultHelperPort (17878).
        guard var components = URLComponents(string: address), components.host != nil else
        {
            throw LocationSimulationError.invalidHelperAddress
        }
        if components.port == nil
        {
            components.port = Self.defaultHelperPort
        }
        guard let url = components.url else
        {
            throw LocationSimulationError.invalidHelperAddress
        }
        return HelperLocationService(baseURL: url, timeoutIntervalForRequest: shortTimeout ? Self.secondaryProbeTimeout : 15)
    }

    /// Transports in preference order (on-device first).
    private func preferredTransports() -> [LocationTransport]
    {
        var transports: [LocationTransport] = []
        if onDeviceAvailable { transports.append(.onDevice) }
        if helperConfigured { transports.append(.helper) }
        return transports
    }

    /// Clear order: the transport the simulation runs on first, then the other.
    private func clearOrder() -> [LocationTransport]
    {
        var order = preferredTransports()
        if let activeIndex = order.firstIndex(of: activeTransport)
        {
            order.remove(at: activeIndex)
            order.insert(activeTransport, at: 0)
        }
        return order
    }

    private func service(for transport: LocationTransport, shortTimeout: Bool = false) throws -> LocationSimulationService
    {
        switch transport
        {
        case .onDevice:
            return OnDeviceLocationService.shared
        case .helper:
            return try makeHelperService(shortTimeout: shortTimeout)
        }
    }
}
#endif
