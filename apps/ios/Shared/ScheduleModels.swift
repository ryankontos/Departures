import Foundation

public enum DeparturesWeekday: String, Codable, CaseIterable, Identifiable, Sendable {
    case monday, tuesday, wednesday, thursday, friday, saturday, sunday

    public var id: String { rawValue }

    public var shortTitle: String {
        switch self {
        case .monday: "M"
        case .tuesday: "T"
        case .wednesday: "W"
        case .thursday: "T"
        case .friday: "F"
        case .saturday: "S"
        case .sunday: "S"
        }
    }
}

public struct RouteEndpoint: Codable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var type: String

    public init(id: String, name: String, type: String = "stop") {
        self.id = id
        self.name = name
        self.type = type
    }
}

public struct DepartureScheduleInput: Codable, Sendable {
    public var name: String
    public var enabled: Bool
    public var weekdays: [DeparturesWeekday]
    public var activeStartTime: String
    public var activeEndTime: String
    public var earliestLeaveTime: String?
    public var arrivalWindowStartTime: String?
    public var arrivalWindowEndTime: String?
    public var walkMinutes: Int
    public var tripsToShow: Int
    public var origin: RouteEndpoint
    public var destination: RouteEndpoint
}

public struct DepartureSchedule: Codable, Identifiable, Sendable {
    public var id: UUID
    public var userId: String
    public var name: String
    public var enabled: Bool
    public var weekdays: [DeparturesWeekday]
    public var activeStartTime: String
    public var activeEndTime: String
    public var earliestLeaveTime: String?
    public var arrivalWindowStartTime: String?
    public var arrivalWindowEndTime: String?
    public var walkMinutes: Int
    public var tripsToShow: Int
    public var origin: RouteEndpoint
    public var destination: RouteEndpoint
    public var createdAt: Date
    public var updatedAt: Date
}

public struct TripLeg: Codable, Hashable, Sendable {
    public var mode: String
    public var routeLabel: String?
    public var originName: String
    public var destinationName: String
    public var departureTime: Date?
    public var arrivalTime: Date?
}

public struct TripSnapshot: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var routeSummary: String
    public var departureTime: Date
    public var arrivalTime: Date
    public var leaveTime: Date
    public var realtime: Bool
    public var legs: [TripLeg]
}

public struct DepartureActivityState: Codable, Hashable, Sendable {
    public var scheduleId: UUID
    public var scheduleName: String
    public var generatedAt: Date
    public var walkMinutes: Int
    public var selectedTripId: String?
    public var trips: [TripSnapshot]
}

public struct DeviceRegistration: Codable, Sendable {
    public var deviceId: String
    public var userId: String
    public var name: String?
    public var pushToStartToken: String?
}

public extension DepartureScheduleInput {
    static let hornsbyMorning = DepartureScheduleInput(
        name: "Morning commute",
        enabled: true,
        weekdays: [.monday, .tuesday, .wednesday, .thursday, .friday],
        activeStartTime: "07:00",
        activeEndTime: "09:00",
        earliestLeaveTime: "07:28",
        arrivalWindowStartTime: nil,
        arrivalWindowEndTime: "09:15",
        walkMinutes: 12,
        tripsToShow: 3,
        origin: RouteEndpoint(id: "10101100", name: "Hornsby Station"),
        destination: RouteEndpoint(id: "10101429", name: "Martin Place Station")
    )
}
