import ActivityKit
import SwiftUI
import WidgetKit

private let makeableTripGrace: TimeInterval = 2 * 60

private enum DeparturePalette {
    static let background = Color(red: 0.94, green: 0.98, blue: 0.97)
    static let accent = Color(red: 0.0, green: 0.42, blue: 0.48)
    static let accentSoft = Color(red: 0.80, green: 0.93, blue: 0.91)
    static let secondary = Color(red: 0.31, green: 0.40, blue: 0.41)
    static let warning = Color(red: 0.78, green: 0.34, blue: 0.08)
}

struct DeparturesLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DepartureActivityAttributes.self) { context in
            LockScreenDepartureView(state: context.state)
                .activityBackgroundTint(DeparturePalette.background)
                .activitySystemActionForegroundColor(DeparturePalette.accent)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.scheduleName)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        if let trip = context.state.focusTrip {
                            Text(trip.routeSummary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let trip = context.state.focusTrip {
                        CountdownBadge(trip: trip, size: .compact)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    CompactTripList(state: context.state, maxRows: 2, style: .island)
                }
            } compactLeading: {
                Image(systemName: "tram.fill")
                    .foregroundStyle(DeparturePalette.accent)
            } compactTrailing: {
                if let trip = context.state.focusTrip {
                    Text(trip.departureTime, style: .timer)
                        .monospacedDigit()
                        .foregroundStyle(DeparturePalette.accent)
                }
            } minimal: {
                Image(systemName: "tram.fill")
                    .foregroundStyle(DeparturePalette.accent)
            }
        }
    }
}

struct LockScreenDepartureView: View {
    var state: DepartureActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let trip = state.focusTrip {
                FocusTripPanel(scheduleName: state.scheduleName, trip: trip)
            } else {
                EmptyTripPanel(scheduleName: state.scheduleName)
            }

            CompactTripList(state: state, maxRows: 3, style: .lockScreen)
        }
        .padding(14)
    }
}

struct CompactTripList: View {
    enum Style {
        case lockScreen
        case island
    }

    var state: DepartureActivityAttributes.ContentState
    var maxRows: Int
    var style: Style

    var body: some View {
        VStack(spacing: style == .lockScreen ? 7 : 6) {
            ForEach(Array(state.secondaryTrips.prefix(maxRows))) { trip in
                CompactTripRow(
                    trip: trip,
                    scheduleId: state.scheduleId,
                    isSelected: state.selectedTripId == trip.id,
                    style: style
                )
            }
        }
    }
}

struct FocusTripPanel: View {
    var scheduleName: String
    var trip: TripSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(scheduleName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(DeparturePalette.secondary)
                        .lineLimit(1)
                    Text(trip.routeSummary)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    if let routeText = trip.compactRouteDetailText {
                        Label(routeText, systemImage: "arrow.triangle.branch")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(DeparturePalette.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                CountdownBadge(trip: trip, size: .large)
            }

            HStack(spacing: 8) {
                TimingPill(systemImage: "figure.walk", text: "Leave \(trip.leaveTime.formatted(date: .omitted, time: .shortened))")
                TimingPill(systemImage: "tram.fill", text: trip.departureClockText)
                TimingPill(systemImage: "flag.checkered", text: trip.arrivalClockText, isWarning: trip.delayText != nil)
            }
        }
        .padding(12)
        .background(DeparturePalette.accentSoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct EmptyTripPanel: View {
    var scheduleName: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "tram.fill")
                .foregroundStyle(DeparturePalette.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(scheduleName)
                    .font(.headline)
                Text("No makeable trips right now")
                    .font(.caption)
                    .foregroundStyle(DeparturePalette.secondary)
            }
        }
        .padding(12)
        .background(DeparturePalette.accentSoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct CountdownBadge: View {
    enum Size {
        case compact
        case large
    }

    var trip: TripSnapshot
    var size: Size

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(trip.departureTime, style: .timer)
                .font(size == .large ? .title3.monospacedDigit().weight(.bold) : .subheadline.monospacedDigit().weight(.bold))
                .foregroundStyle(DeparturePalette.accent)
                .lineLimit(1)
            Text("until train")
                .font(.caption2.weight(.medium))
                .foregroundStyle(DeparturePalette.secondary)
        }
        .padding(.horizontal, size == .large ? 9 : 7)
        .padding(.vertical, size == .large ? 7 : 5)
        .background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct TimingPill: View {
    var systemImage: String
    var text: String
    var isWarning = false

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .foregroundStyle(isWarning ? DeparturePalette.warning : DeparturePalette.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .background(.white.opacity(0.62), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

struct CompactTripRow: View {
    var trip: TripSnapshot
    var scheduleId: UUID
    var isSelected: Bool
    var style: CompactTripList.Style

    private var destination: URL {
        URL(string: "departures://select-trip/\(trip.id)?scheduleId=\(scheduleId.uuidString)")!
    }

    var body: some View {
        Link(destination: destination) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(isSelected ? DeparturePalette.accent : DeparturePalette.accent.opacity(0.28))
                    .frame(width: 3, height: style == .lockScreen ? 34 : 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(trip.routeSummary)
                        .font(style == .lockScreen ? .caption.weight(.semibold) : .caption2.weight(.semibold))
                        .lineLimit(1)
                    if let routeText = trip.compactRouteDetailText {
                        Text(routeText)
                            .font(.caption2)
                            .foregroundStyle(DeparturePalette.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 6)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(trip.departureClockText)
                        .font(.caption.monospacedDigit().weight(.bold))
                        .foregroundStyle(DeparturePalette.accent)
                    Text(trip.secondaryTimingText)
                        .font(.caption2)
                        .foregroundStyle(trip.delayText == nil ? DeparturePalette.secondary : DeparturePalette.warning)
                }
            }
            .padding(.horizontal, style == .lockScreen ? 8 : 0)
            .padding(.vertical, style == .lockScreen ? 6 : 0)
            .background(rowBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .foregroundStyle(.primary)
    }

    private var rowBackground: Color {
        guard style == .lockScreen else { return .clear }
        return isSelected ? DeparturePalette.accentSoft : .white.opacity(0.45)
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

    var departureClockText: String {
        departureTime.formatted(date: .omitted, time: .shortened)
    }

    var arrivalClockText: String {
        if let delayText {
            return "\(arrivalTime.formatted(date: .omitted, time: .shortened)) \(delayText)"
        }
        return arrivalTime.formatted(date: .omitted, time: .shortened)
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
        let cutoff = Date().addingTimeInterval(-makeableTripGrace)
        return trips
            .filter { $0.leaveTime >= cutoff }
            .sorted { $0.departureTime < $1.departureTime }
    }

    var focusTrip: TripSnapshot? {
        if let selectedTripId, let selected = visibleTrips.first(where: { $0.id == selectedTripId }) {
            return selected
        }
        return visibleTrips.first
    }

    var secondaryTrips: [TripSnapshot] {
        guard let focusTrip else { return [] }
        return visibleTrips.filter { $0.id != focusTrip.id }
    }
}
