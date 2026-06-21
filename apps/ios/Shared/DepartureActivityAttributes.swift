import ActivityKit
import Foundation

public struct DepartureActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var scheduleId: UUID
        public var scheduleName: String
        public var generatedAt: Date
        public var walkMinutes: Int
        public var selectedTripId: String?
        public var trips: [TripSnapshot]

        public init(state: DepartureActivityState) {
            scheduleId = state.scheduleId
            scheduleName = state.scheduleName
            generatedAt = state.generatedAt
            walkMinutes = state.walkMinutes
            selectedTripId = state.selectedTripId
            trips = state.trips
        }
    }

    public var scheduleId: UUID
    public var scheduleName: String

    public init(scheduleId: UUID, scheduleName: String) {
        self.scheduleId = scheduleId
        self.scheduleName = scheduleName
    }
}

