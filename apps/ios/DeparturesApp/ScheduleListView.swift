import SwiftUI

struct ScheduleListView: View {
    @EnvironmentObject private var model: DeparturesModel

    var body: some View {
        NavigationStack {
            List {
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
                        Task { await model.createExampleSchedule() }
                    } label: {
                        Label("Add Hornsby morning commute", systemImage: "plus")
                    }

                    Button {
                        Task { await model.preview() }
                    } label: {
                        Label("Preview next trips", systemImage: "clock")
                    }
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
            .refreshable {
                await model.loadSchedules()
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
                Text("\(schedule.activeStartTime)-\(schedule.activeEndTime)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct ScheduleDetailView: View {
    var schedule: DepartureSchedule

    var body: some View {
        List {
            Section("Route") {
                LabeledContent("From", value: schedule.origin.name)
                LabeledContent("To", value: schedule.destination.name)
            }

            Section("Timing") {
                LabeledContent("Starts", value: schedule.activeStartTime)
                LabeledContent("Stops", value: schedule.activeEndTime)
                LabeledContent("Walk", value: "\(schedule.walkMinutes) min")
                LabeledContent("Trips", value: "\(schedule.tripsToShow)")
            }
        }
        .navigationTitle(schedule.name)
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
