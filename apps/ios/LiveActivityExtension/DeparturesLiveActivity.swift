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
                    if let routeText = trip.compactRouteDetailText {
                        Text(routeText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Text("Leave \(trip.leaveTime.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(trip.departureTime, style: .timer)
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                    if trip.delayText == nil {
                        Text(trip.secondaryTimingText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(trip.secondaryTimingText)
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
        .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
    }
}

private extension TripSnapshot {
    var compactRouteDetailText: String? {
        let transferPoints = legs.transferPointNames
        guard !transferPoints.isEmpty else { return nil }

        let labels = legs
            .filter { !$0.isTrivialWalkLeg }
            .compactMap(\.routeLabel)
            .filter { !$0.isEmpty }
            .uniqued()
            .joined(separator: " -> ")

        let via = "via \(transferPoints.joined(separator: ", "))"
        return labels.isEmpty ? via : "\(labels) \(via)"
    }

    var delayText: String? {
        let delay = max(departureDelayMinutes ?? 0, arrivalDelayMinutes ?? 0)
        guard delay > 0 else { return nil }
        return "delay \(delay)m"
    }

    var secondaryTimingText: String {
        if let delayText {
            return "\(delayText) arr \(arrivalTime.formatted(date: .omitted, time: .shortened))"
        }
        return "arr \(arrivalTime.formatted(date: .omitted, time: .shortened))"
    }

    var departureDelayMinutes: Int? {
        delayMinutes(planned: plannedDepartureTime, live: departureTime)
    }

    var arrivalDelayMinutes: Int? {
        delayMinutes(planned: plannedArrivalTime, live: arrivalTime)
    }

    private func delayMinutes(planned: Date?, live: Date) -> Int? {
        guard let planned else { return nil }
        let minutes = Int((live.timeIntervalSince(planned) / 60).rounded())
        return minutes > 0 ? minutes : nil
    }
}

private extension Array where Element == TripLeg {
    var transferPointNames: [String] {
        let publicLegs = filter { !$0.isTrivialWalkLeg }
        guard publicLegs.count > 1 else { return [] }
        return publicLegs
            .dropLast()
            .map { $0.destinationName.stationDisplayName }
            .uniqued()
    }
}

private extension TripLeg {
    var isTrivialWalkLeg: Bool {
        mode.localizedCaseInsensitiveContains("walk") || mode.localizedCaseInsensitiveContains("footpath")
    }
}

private extension String {
    var stationDisplayName: String {
        replacingOccurrences(of: " Station", with: "")
            .replacingOccurrences(of: #", Platform \d+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: ", Sydney", with: "")
            .replacingOccurrences(of: ", Hornsby", with: "")
            .replacingOccurrences(of: ", Chatswood", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
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
