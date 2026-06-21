import SwiftUI

struct WatchDepartureListView: View {
    private let trips: [TripSnapshot] = []

    var body: some View {
        NavigationStack {
            List {
                if trips.isEmpty {
                    ContentUnavailableView("No departures", systemImage: "tram", description: Text("Your configured trips will sync here."))
                } else {
                    ForEach(trips) { trip in
                        VStack(alignment: .leading) {
                            Text(trip.routeSummary)
                                .font(.headline)
                            Text("Leave \(trip.leaveTime.formatted(date: .omitted, time: .shortened))")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Departures")
        }
    }
}

