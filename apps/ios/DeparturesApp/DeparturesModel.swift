import ActivityKit
import Foundation
import Security
import UIKit

@MainActor
final class DeparturesModel: ObservableObject {
    @Published var schedules: [DepartureSchedule] = []
    @Published var previewTrips: [TripSnapshot] = []
    @Published var stationResults: [StopSearchResult] = []
    @Published var serverBaseURL = URL(string: "https://departures.ryankontos.com/api")!
    @Published var errorMessage: String?
    @Published var apiStatus = APIStatus.idle
    @Published var isCommunicatingWithAPI = false

    let identity = AnonymousIdentity()
    private lazy var api = DeparturesAPI(baseURL: serverBaseURL, identity: identity)
    private var devicePushToken: String?
    private var pushToStartToken: String?
    private var tokenObserverTasks: [Task<Void, Never>] = []

    func bootstrap() async {
        api = DeparturesAPI(baseURL: serverBaseURL, identity: identity)
        apiStatus = .working("Connecting to Departures API")
        requestPushAuthorization()
        startActivityTokenObservers()
        await registerDevice()
        await loadSchedules()
    }

    func loadSchedules() async {
        await perform("Refreshing schedules", success: "Schedules are up to date") {
            schedules = try await api.get([DepartureSchedule].self, path: "schedules")
        }
    }

    func saveSchedule(_ input: DepartureScheduleInput) async {
        await perform("Saving live activity schedule", success: "Live activity schedule saved") {
            _ = try await api.post(DepartureSchedule.self, path: "schedules", body: input)
            schedules = try await api.get([DepartureSchedule].self, path: "schedules")
        }
    }

    func preview(_ input: DepartureScheduleInput) async {
        await perform("Loading next departures", success: "Departure preview loaded") {
            let request = JourneyPreviewRequest(schedule: input, now: Date())
            previewTrips = try await api.post([TripSnapshot].self, path: "journeys/preview", body: request)
        }
    }

    func searchStations(matching query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            stationResults = []
            return
        }
        await perform("Loading stations", success: "Stations loaded") {
            let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
            stationResults = try await api.get([StopSearchResult].self, path: "stations?q=\(encoded)")
        }
    }

    func loadInitialStations() async {
        await perform("Loading stations", success: "Stations loaded") {
            stationResults = try await api.get([StopSearchResult].self, path: "stations?q=Station")
        }
    }

    func testLiveActivity(for input: DepartureScheduleInput) async {
        await perform("Starting test Live Activity", success: "Test Live Activity started") {
            let request = JourneyPreviewRequest(schedule: input, now: Date())
            let trips = try await api.post([TripSnapshot].self, path: "journeys/preview", body: request)
            previewTrips = trips

            let scheduleId = UUID()
            let attributes = DepartureActivityAttributes(scheduleId: scheduleId, scheduleName: input.name)
            let state = DepartureActivityAttributes.ContentState(state: DepartureActivityState(
                scheduleId: scheduleId,
                scheduleName: input.name,
                generatedAt: Date(),
                walkMinutes: input.walkMinutes,
                selectedTripId: trips.first?.id,
                trips: trips
            ))

            _ = try Activity<DepartureActivityAttributes>.request(
                attributes: attributes,
                content: .init(state: state, staleDate: Date().addingTimeInterval(15 * 60)),
                pushType: .token
            )
        }
    }

    func updateDevicePushToken(_ tokenData: Data) {
        devicePushToken = tokenData.hexString
        Task { await registerDevice() }
    }

    func registerDevice() async {
        let registration = DeviceRegistration(
            deviceId: identity.deviceId,
            userId: identity.userId,
            name: UIDevice.current.name,
            devicePushToken: devicePushToken,
            pushToStartToken: pushToStartToken
        )
        await perform("Registering this iPhone", success: "This iPhone is linked to the API") {
            try await api.postNoResponse(path: "devices", body: registration)
        }
    }

    func handle(url: URL) {
        guard url.scheme == "departures" else { return }
    }

    private func perform(_ workingMessage: String, success successMessage: String, operation: () async throws -> Void) async {
        isCommunicatingWithAPI = true
        apiStatus = .working(workingMessage)
        do {
            try await operation()
            apiStatus = .success(successMessage)
        } catch {
            let message = APIStatus.userFacingMessage(for: error)
            errorMessage = message
            apiStatus = .failure(message)
        }
        isCommunicatingWithAPI = false
    }

    private func requestPushAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error {
                Task { @MainActor in
                    self.apiStatus = .failure("Push notification permission failed: \(error.localizedDescription)")
                }
                return
            }

            guard granted else {
                Task { @MainActor in
                    self.apiStatus = .failure("Push notifications are disabled for Departures.")
                }
                return
            }

            DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }

    private func startActivityTokenObservers() {
        guard tokenObserverTasks.isEmpty else { return }

        if #available(iOS 17.2, *) {
            tokenObserverTasks.append(Task { [weak self] in
                for await tokenData in Activity<DepartureActivityAttributes>.pushToStartTokenUpdates {
                    await MainActor.run {
                        self?.pushToStartToken = tokenData.hexString
                        Task { await self?.registerDevice() }
                    }
                }
            })
        }

        tokenObserverTasks.append(Task { [weak self] in
            for await activity in Activity<DepartureActivityAttributes>.activityUpdates {
                let activityId = activity.id
                let scheduleId = activity.attributes.scheduleId.uuidString
                Task {
                    for await tokenData in activity.pushTokenUpdates {
                        await self?.registerLiveActivityToken(tokenData.hexString, activityId: activityId, scheduleId: scheduleId)
                    }
                }
            }
        })
    }

    private func registerLiveActivityToken(_ token: String, activityId: String, scheduleId: String) async {
        let path = "live-activities/\(activityId)/token?scheduleId=\(scheduleId)&deviceId=\(identity.deviceId)"
        do {
            try await api.postNoResponse(path: path, body: PushTokenRegistration(token: token))
            apiStatus = .success("Live Activity push token registered")
        } catch {
            let message = APIStatus.userFacingMessage(for: error)
            errorMessage = message
            apiStatus = .failure(message)
        }
    }
}

final class DeparturesAppDelegate: NSObject, UIApplicationDelegate {
    weak var model: DeparturesModel?

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in
            model?.updateDevicePushToken(deviceToken)
        }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Task { @MainActor in
            model?.apiStatus = .failure("APNS registration failed: \(error.localizedDescription)")
        }
    }
}

enum APIStatus: Equatable {
    case idle
    case working(String)
    case success(String)
    case failure(String)

    var title: String {
        switch self {
        case .idle:
            "Ready"
        case .working:
            "Contacting API"
        case .success:
            "API Updated"
        case .failure:
            "API Error"
        }
    }

    var message: String {
        switch self {
        case .idle:
            "No API request has been made yet."
        case let .working(message), let .success(message), let .failure(message):
            message
        }
    }

    var systemImage: String {
        switch self {
        case .idle:
            "circle"
        case .working:
            "arrow.triangle.2.circlepath"
        case .success:
            "checkmark.circle.fill"
        case .failure:
            "exclamationmark.triangle.fill"
        }
    }

    var isFailure: Bool {
        if case .failure = self { return true }
        return false
    }

    static func userFacingMessage(for error: Error) -> String {
        if let apiError = error as? DeparturesAPIError {
            return apiError.localizedDescription
        }
        if let urlError = error as? URLError {
            return "Could not reach the Departures API: \(urlError.localizedDescription)"
        }
        return error.localizedDescription
    }
}

struct DeparturesAPI: Sendable {
    var baseURL: URL
    var identity: AnonymousIdentity

    func get<T: Decodable>(_ type: T.Type, path: String) async throws -> T {
        var request = URLRequest(url: url(for: path))
        configure(&request)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response, data: data)
        return try decoder.decode(T.self, from: data)
    }

    func post<T: Decodable, Body: Encodable>(_ type: T.Type, path: String, body: Body) async throws -> T {
        var request = URLRequest(url: url(for: path))
        configure(&request)
        request.httpMethod = "POST"
        request.httpBody = try encoder.encode(body)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response, data: data)
        return try decoder.decode(T.self, from: data)
    }

    func postNoResponse<Body: Encodable>(path: String, body: Body) async throws {
        var request = URLRequest(url: url(for: path))
        configure(&request)
        request.httpMethod = "POST"
        request.httpBody = try encoder.encode(body)
        let (_, response) = try await URLSession.shared.data(for: request)
        try validate(response, data: Data())
    }

    private func configure(_ request: inout URLRequest) {
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(identity.userId, forHTTPHeaderField: "X-Departures-User")
    }

    private func url(for path: String) -> URL {
        let separator = path.hasPrefix("/") ? "" : "/"
        return URL(string: "\(baseURL.absoluteString)\(separator)\(path)")!
    }

    private func validate(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw DeparturesAPIError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw DeparturesAPIError.httpStatus(http.statusCode, body: String(data: data, encoding: .utf8))
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

enum DeparturesAPIError: LocalizedError {
    case invalidResponse
    case httpStatus(Int, body: String?)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The Departures API returned an unreadable response."
        case let .httpStatus(status, body):
            if let body, !body.isEmpty {
                return "The Departures API returned HTTP \(status): \(body.prefix(160))"
            }
            return "The Departures API returned HTTP \(status)."
        }
    }
}

struct PushTokenRegistration: Codable, Sendable {
    var token: String
}

private extension Data {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
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
