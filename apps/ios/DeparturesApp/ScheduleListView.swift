import SwiftUI

struct ScheduleListView: View {
    @EnvironmentObject private var model: DeparturesModel
    @State private var showingAddRoute = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    APIStatusRow(status: model.apiStatus)
                }

                Section {
                    ForEach(model.schedules) { schedule in
                        NavigationLink {
                            ScheduleDetailView(schedule: schedule)
                        } label: {
                            ScheduleRow(schedule: schedule)
                        }
                    }
                }

                Section {
                    Button {
                        showingAddRoute = true
                    } label: {
                        Label("Add route", systemImage: "plus")
                    }
                    .disabled(model.isCommunicatingWithAPI)
                }

                if !model.previewTrips.isEmpty {
                    Section("Preview") {
                        ForEach(model.previewTrips) { trip in
                            TripRow(trip: trip)
                        }
                    }
                }
            }
            .navigationTitle("Departures")
            .sheet(isPresented: $showingAddRoute) {
                AddRouteView()
            }
            .refreshable {
                await model.loadSchedules()
            }
            .overlay {
                if model.isCommunicatingWithAPI && model.schedules.isEmpty && model.previewTrips.isEmpty {
                    ProgressView()
                        .controlSize(.large)
                }
            }
            .alert("Departures", isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.errorMessage ?? "")
            }
        }
    }
}

struct APIStatusRow: View {
    var status: APIStatus

    var body: some View {
        HStack(spacing: 12) {
            statusIcon

            VStack(alignment: .leading, spacing: 3) {
                Text(status.title)
                    .font(.headline)
                Text(status.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch status {
        case .working:
            ProgressView()
                .frame(width: 28, height: 28)
        case .success:
            Image(systemName: status.systemImage)
                .font(.title3)
                .foregroundStyle(.green)
                .frame(width: 28, height: 28)
        case .failure:
            Image(systemName: status.systemImage)
                .font(.title3)
                .foregroundStyle(.red)
                .frame(width: 28, height: 28)
        case .idle:
            Image(systemName: status.systemImage)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
        }
    }
}

struct ScheduleRow: View {
    var schedule: DepartureSchedule

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(schedule.name)
                .font(.headline)
            Text("\(schedule.origin.name) to \(schedule.destination.name)")
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                ForEach(schedule.weekdays) { weekday in
                    Text(weekday.shortTitle)
                        .font(.caption.bold())
                        .frame(width: 22, height: 22)
                        .background(.tint.opacity(0.14), in: Circle())
                }
                Spacer()
                Text(schedule.arrivalWindowLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct ScheduleDetailView: View {
    @EnvironmentObject private var model: DeparturesModel
    var schedule: DepartureSchedule

    var body: some View {
        List {
            Section("Route") {
                LabeledContent("From", value: schedule.origin.name)
                LabeledContent("To", value: schedule.destination.name)
            }

            Section("Timing") {
                LabeledContent("Earliest arrival", value: schedule.arrivalWindowStartTime ?? schedule.activeStartTime)
                LabeledContent("Latest arrival", value: schedule.arrivalWindowEndTime ?? schedule.activeEndTime)
                LabeledContent("Walk", value: "\(schedule.walkMinutes) min")
                LabeledContent("Trips", value: "\(schedule.tripsToShow)")
            }

            Section {
                Button {
                    Task { await model.preview(schedule.input) }
                } label: {
                    Label("Preview next departures", systemImage: "clock")
                }
                .disabled(model.isCommunicatingWithAPI)

                Button {
                    Task { await model.testLiveActivity(for: schedule.input) }
                } label: {
                    Label("Test Live Activity now", systemImage: "rectangle.inset.filled.and.person.filled")
                }
                .disabled(model.isCommunicatingWithAPI)
            }
        }
        .navigationTitle(schedule.name)
    }
}

struct AddRouteView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: DeparturesModel

    @State private var name = ""
    @State private var origin: RouteEndpoint?
    @State private var destination: RouteEndpoint?
    @State private var earliestArrivalTime = TimeOfDay(hour: 8, minute: 30).date
    @State private var latestArrivalTime = TimeOfDay(hour: 9, minute: 30).date
    @State private var walkMinutes = 12
    @State private var tripsToShow = 3
    @State private var weekdays = Set(DeparturesWeekday.allCases.prefix(5))

    var body: some View {
        NavigationStack {
            Form {
                Section("Route") {
                    TextField(defaultRouteName, text: $name)
                    StationPickerRow(title: "From", selection: $origin)
                    StationPickerRow(title: "To", selection: $destination)
                }

                Section("Days") {
                    WeekdayToggleGrid(selection: $weekdays)
                }

                Section("Timing") {
                    DatePicker("Earliest arrival", selection: $earliestArrivalTime, displayedComponents: .hourAndMinute)
                    DatePicker("Latest arrival", selection: $latestArrivalTime, displayedComponents: .hourAndMinute)
                    Stepper("Walk \(walkMinutes) min", value: $walkMinutes, in: 0...60)
                    Stepper("Show \(tripsToShow) trips", value: $tripsToShow, in: 1...6)
                }

                Section {
                    Button {
                        guard let input else { return }
                        Task {
                            await model.saveSchedule(input)
                            dismiss()
                        }
                    } label: {
                        Label("Save route", systemImage: "checkmark")
                    }
                    .disabled(input == nil || model.isCommunicatingWithAPI)

                    Button {
                        guard let input else { return }
                        Task { await model.testLiveActivity(for: input) }
                    } label: {
                        Label("Test Live Activity now", systemImage: "rectangle.inset.filled.and.person.filled")
                    }
                    .disabled(input == nil || model.isCommunicatingWithAPI)
                }
            }
            .navigationTitle("New Route")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task {
                await model.loadInitialStations()
            }
        }
    }

    private var input: DepartureScheduleInput? {
        guard let origin, let destination, !weekdays.isEmpty else {
            return nil
        }
        return DepartureScheduleInput(
            name: resolvedRouteName,
            enabled: true,
            weekdays: DeparturesWeekday.allCases.filter { weekdays.contains($0) },
            activeStartTime: earliestArrivalTime.addingTimeInterval(-2 * 60 * 60).hhmmString,
            activeEndTime: latestArrivalTime.hhmmString,
            earliestLeaveTime: nil,
            arrivalWindowStartTime: earliestArrivalTime.hhmmString,
            arrivalWindowEndTime: latestArrivalTime.hhmmString,
            walkMinutes: walkMinutes,
            tripsToShow: tripsToShow,
            origin: origin,
            destination: destination
        )
    }

    private var defaultRouteName: String {
        guard let origin, let destination else {
            return "Route name"
        }
        return "\(origin.name) to \(destination.name)"
    }

    private var resolvedRouteName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? defaultRouteName : trimmed
    }
}

struct StationPickerRow: View {
    @EnvironmentObject private var model: DeparturesModel
    var title: String
    @Binding var selection: RouteEndpoint?
    @State private var query = ""
    @State private var showingPicker = false

    var body: some View {
        Button {
            showingPicker = true
        } label: {
            HStack {
                Text(title)
                Spacer()
                Text(selection?.name ?? "Choose station")
                    .foregroundStyle(selection == nil ? .secondary : .primary)
                    .multilineTextAlignment(.trailing)
            }
        }
        .sheet(isPresented: $showingPicker) {
            NavigationStack {
                List(model.stationResults) { station in
                    Button {
                        selection = RouteEndpoint(id: station.id, name: station.name)
                        showingPicker = false
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(station.name)
                                .foregroundStyle(.primary)
                            Text(station.id)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .navigationTitle(title)
                .searchable(text: $query, prompt: "Search stations")
                .onChange(of: query) { _, newValue in
                    Task { await model.searchStations(matching: newValue.isEmpty ? "Station" : newValue) }
                }
                .task {
                    await model.loadInitialStations()
                }
            }
        }
    }
}

struct WeekdayToggleGrid: View {
    @Binding var selection: Set<DeparturesWeekday>

    var body: some View {
        HStack(spacing: 8) {
            ForEach(DeparturesWeekday.allCases) { weekday in
                Button {
                    if selection.contains(weekday) {
                        selection.remove(weekday)
                    } else {
                        selection.insert(weekday)
                    }
                } label: {
                    Text(weekday.shortTitle)
                        .font(.caption.bold())
                        .frame(width: 32, height: 32)
                        .background(selection.contains(weekday) ? Color.accentColor : Color.secondary.opacity(0.16), in: Circle())
                        .foregroundStyle(selection.contains(weekday) ? .white : .primary)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct TripRow: View {
    var trip: TripSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(trip.routeSummary)
                    .font(.headline)
                Spacer()
                if trip.realtime {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .foregroundStyle(.green)
                }
            }
            HStack {
                Label {
                    Text(trip.leaveTime, format: .dateTime.hour().minute())
                } icon: {
                    Image(systemName: "figure.walk")
                }
                Spacer()
                Label {
                    Text(trip.departureTime, format: .dateTime.hour().minute())
                } icon: {
                    Image(systemName: "tram")
                }
                Spacer()
                Label {
                    Text(trip.arrivalTime, format: .dateTime.hour().minute())
                } icon: {
                    Image(systemName: "flag.checkered")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

private extension DepartureSchedule {
    var arrivalWindowLabel: String {
        let start = arrivalWindowStartTime ?? activeStartTime
        let end = arrivalWindowEndTime ?? activeEndTime
        return "\(start)-\(end)"
    }

    var input: DepartureScheduleInput {
        DepartureScheduleInput(
            name: name,
            enabled: enabled,
            weekdays: weekdays,
            activeStartTime: activeStartTime,
            activeEndTime: activeEndTime,
            earliestLeaveTime: earliestLeaveTime,
            arrivalWindowStartTime: arrivalWindowStartTime,
            arrivalWindowEndTime: arrivalWindowEndTime,
            walkMinutes: walkMinutes,
            tripsToShow: tripsToShow,
            origin: origin,
            destination: destination
        )
    }
}

private struct TimeOfDay {
    let hour: Int
    let minute: Int

    var date: Date {
        Calendar.current.date(from: DateComponents(hour: hour, minute: minute)) ?? Date()
    }
}

private extension Date {
    var hhmmString: String {
        let components = Calendar.current.dateComponents([.hour, .minute], from: self)
        return String(format: "%02d:%02d", components.hour ?? 0, components.minute ?? 0)
    }
}
