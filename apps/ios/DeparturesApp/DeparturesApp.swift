import SwiftUI

@main
struct DeparturesApp: App {
    @StateObject private var model = DeparturesModel()

    var body: some Scene {
        WindowGroup {
            ScheduleListView()
                .environmentObject(model)
                .task {
                    await model.bootstrap()
                }
                .onOpenURL { url in
                    model.handle(url: url)
                }
        }
    }
}

