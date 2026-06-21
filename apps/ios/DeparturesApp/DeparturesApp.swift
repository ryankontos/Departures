import SwiftUI

@main
struct DeparturesApp: App {
    @UIApplicationDelegateAdaptor(DeparturesAppDelegate.self) private var appDelegate
    @StateObject private var model = DeparturesModel()

    var body: some Scene {
        WindowGroup {
            ScheduleListView()
                .environmentObject(model)
                .task {
                    appDelegate.model = model
                    await model.bootstrap()
                }
                .onOpenURL { url in
                    model.handle(url: url)
                }
        }
    }
}
