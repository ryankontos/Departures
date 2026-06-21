import ActivityKit
import SwiftUI
import WidgetKit

struct DeparturesLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DepartureActivityAttributes.self) { context in
            LockScreenDepartureView(state: context.state)
                .activityBackgroundTint(Color(.systemBackground))
                .activitySystemActionForegroundColor(.primary)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.state.scheduleName)
                        .font(.headline)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let trip = context.state.focusTrip {
                        Text(trip.departureTime, style: .timer)
                            .monospacedDigit()
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    CompactTripList(state: context.state, maxRows: 2)
                }
            } compactLeading: {
                Image(systemName: "tram")
            } compactTrailing: {
                if let trip = context.state.focusTrip {
                    Text(trip.leaveTime, style: .timer)
                        .monospacedDigit()
                }
            } minimal: {
                Image(systemName: "tram")
            }
        }
    }
}

struct LockScreenDepartureView: View {
    var state: DepartureActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(state.scheduleName)
                    .font(.headline)
                Spacer()
                if let trip = state.focusTrip {
                    Label {
                        Text(trip.leaveTime, format: .dateTime.hour().minute())
                    } icon: {
                        Image(systemName: "figure.walk")
                    }
                        .font(.caption.bold())
                }
            }

            CompactTripList(state: state, maxRows: 4)
        }
        .padding()
    }
}

struct CompactTripList: View {
    var state: DepartureActivityAttributes.ContentState
    var maxRows: Int

    var body: some View {
        VStack(spacing: 8) {
            ForEach(Array(state.visibleTrips.prefix(maxRows))) { trip in
                CompactTripRow(
                    trip: trip,
                    scheduleId: state.scheduleId,
                    isSelected: state.selectedTripId == trip.id
                )
            }
        }
    }
}

struct CompactTripRow: View {
    var trip: TripSnapshot
    var scheduleId: UUID
    var isSelected: Bool

    private var destination: URL {
        URL(string: "departures://select-trip/\(trip.id)?scheduleId=\(scheduleId.uuidString)")!
    }

    var body: some View {
        Link(destination: destination) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(trip.routeSummary)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text("Leave \(trip.leaveTime.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(trip.departureTime, style: .timer)
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                    Text("arr \(trip.arrivalTime.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
    }
}

private extension DepartureActivityAttributes.ContentState {
    var visibleTrips: [TripSnapshot] {
        let cutoff = Date().addingTimeInterval(-3 * 60)
        return trips.filter { $0.leaveTime >= cutoff }
    }

    var focusTrip: TripSnapshot? {
        if let selectedTripId, let selected = trips.first(where: { $0.id == selectedTripId }) {
            return selected
        }
        return visibleTrips.first
    }
}
