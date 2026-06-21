import ActivityKit
import Foundation
import Security
import UIKit

@MainActor
final class DeparturesModel: ObservableObject {
    @Published var schedules: [DepartureSchedule] = []
    @Published var previewTrips: [TripSnapshot] = []
    @Published var serverBaseURL = URL(string: "https://departures.ryankontos.com/api")!
    @Published var errorMessage: String?

    let identity = AnonymousIdentity()
    private lazy var api = DeparturesAPI(baseURL: serverBaseURL, identity: identity)

    func bootstrap() async {
        api = DeparturesAPI(baseURL: serverBaseURL, identity: identity)
        await registerDevice()
        await loadSchedules()
    }

    func loadSchedules() async {
        do {
            schedules = try await api.get([DepartureSchedule].self, path: "schedules")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createExampleSchedule() async {
        do {
            _ = try await api.post(DepartureSchedule.self, path: "schedules", body: DepartureScheduleInput.hornsbyMorning)
            await loadSchedules()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func preview(_ input: DepartureScheduleInput = .hornsbyMorning) async {
        do {
            previewTrips = try await api.post([TripSnapshot].self, path: "journeys/preview", body: ["schedule": input])
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func registerDevice() async {
        let registration = DeviceRegistration(
            deviceId: identity.deviceId,
            userId: identity.userId,
            name: UIDevice.current.name,
            pushToStartToken: nil
        )
        do {
            try await api.postNoResponse(path: "devices", body: registration)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func handle(url: URL) {
        guard url.scheme == "departures" else { return }
    }
}

struct DeparturesAPI: Sendable {
    var baseURL: URL
    var identity: AnonymousIdentity

    func get<T: Decodable>(_ type: T.Type, path: String) async throws -> T {
        var request = URLRequest(url: baseURL.appending(path: path))
        configure(&request)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response)
        return try decoder.decode(T.self, from: data)
    }

    func post<T: Decodable, Body: Encodable>(_ type: T.Type, path: String, body: Body) async throws -> T {
        var request = URLRequest(url: baseURL.appending(path: path))
        configure(&request)
        request.httpMethod = "POST"
        request.httpBody = try encoder.encode(body)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response)
        return try decoder.decode(T.self, from: data)
    }

    func postNoResponse<Body: Encodable>(path: String, body: Body) async throws {
        var request = URLRequest(url: baseURL.appending(path: path))
        configure(&request)
        request.httpMethod = "POST"
        request.httpBody = try encoder.encode(body)
        let (_, response) = try await URLSession.shared.data(for: request)
        try validate(response)
    }

    private func configure(_ request: inout URLRequest) {
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(identity.userId, forHTTPHeaderField: "X-Departures-User")
    }

    private func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

final class AnonymousIdentity: @unchecked Sendable {
    let userId: String
    let deviceId: String

    init() {
        userId = Self.value(for: "departures.userId", prefix: "usr")
        deviceId = Self.value(for: "departures.deviceId", prefix: "dev")
    }

    private static func value(for key: String, prefix: String) -> String {
        if let existing = read(key: key) {
            return existing
        }
        let created = "\(prefix)_\(UUID().uuidString.lowercased())"
        save(key: key, value: created)
        return created
    }

    private static func read(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func save(key: String, value: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        SecItemAdd(attributes as CFDictionary, nil)
    }
}
