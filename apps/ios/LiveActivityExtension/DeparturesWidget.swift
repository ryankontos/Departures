import SwiftUI
import WidgetKit

struct DeparturesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DeparturesWidget", provider: Provider()) { entry in
            VStack(alignment: .leading, spacing: 6) {
                Text("Departures")
                    .font(.headline)
                Text(entry.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .configurationDisplayName("Departures")
        .description("Shows your next configured departures.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> WidgetEntry {
        WidgetEntry(date: Date(), message: "Next trips appear here")
    }

    func getSnapshot(in context: Context, completion: @escaping (WidgetEntry) -> Void) {
        completion(WidgetEntry(date: Date(), message: "Next trips appear here"))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WidgetEntry>) -> Void) {
        completion(Timeline(entries: [WidgetEntry(date: Date(), message: "Open Departures to refresh")], policy: .after(Date().addingTimeInterval(900))))
    }
}

struct WidgetEntry: TimelineEntry {
    var date: Date
    var message: String
}

