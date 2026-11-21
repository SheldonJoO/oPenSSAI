#if os(iOS)
//
//  LocationSimulationService.swift
//  oPenSSAI
//
//  Virtual location: transport-agnostic service interface plus the Mac-helper
//  implementation. The shell UI talks only to LocationSimulationService; the
//  helper implementation posts coordinates to a small Rust helper running on
//  the user's Mac (tools/location-helper), which drives the device's DVT
//  location simulation service through the idevice library. A future
//  on-device implementation can replace the transport without touching the
//  UI — see docs/location-simulation-design.md §5.
//
//  Copyright © 2026 oPenSSAI Contributors. All rights reserved.
//

import Foundation

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
    case notImplemented

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
        case .notImplemented:
            return NSLocalizedString("On-device location simulation is not implemented yet", comment: "")
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

    init(baseURL: URL)
    {
        self.baseURL = baseURL
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
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

/// Placeholder for the on-device implementation (Phase 2): drives the DVT
/// location simulation service directly through the vendored idevice FFI.
/// Not implemented yet — see docs/location-simulation-design.md §5.
final class OnDeviceLocationService: LocationSimulationService, @unchecked Sendable
{
    func setLocation(_ location: SimulatedLocation) async throws
    {
        throw LocationSimulationError.notImplemented
    }

    func clearLocation() async throws
    {
        throw LocationSimulationError.notImplemented
    }

    func fetchStatus() async throws -> LocationSimulationStatus
    {
        throw LocationSimulationError.notImplemented
    }
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
/// shell reads virtual-location state from.
@MainActor
final class LocationSimulationManager
{
    static let shared = LocationSimulationManager()

    private static let helperAddressDefaultsKey = "location.helperAddress"
    private static let lastLocationDefaultsKey = "location.lastLocation"
    static let defaultHelperPort = 17878

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

    /// Last status fetched from the helper (nil = never checked).
    private(set) var lastStatus: LocationSimulationStatus?

    /// One-line status for the Me tab row.
    var statusSummary: String?
    {
        guard let lastStatus, lastStatus.active, let location = lastStatus.location else { return nil }
        return location.coordinateText
    }

    func makeService() throws -> LocationSimulationService
    {
        var address = helperAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty else { throw LocationSimulationError.invalidHelperAddress }
        if !address.contains("://") { address = "http://" + address }
        guard let url = URL(string: address), url.host != nil else
        {
            throw LocationSimulationError.invalidHelperAddress
        }
        return HelperLocationService(baseURL: url)
    }

    @discardableResult
    func refreshStatus() async -> LocationSimulationStatus?
    {
        do
        {
            let status = try await makeService().fetchStatus()
            lastStatus = status
            if status.active, let location = status.location
            {
                lastLocation = location
            }
            return status
        }
        catch
        {
            debugLog("[LocationSimulation] status refresh failed: \(error)")
            return nil
        }
    }
}
#endif
