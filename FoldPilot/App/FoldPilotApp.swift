import SwiftData
import SwiftUI

@main
struct FoldPilotApp: App {
    private let container: ModelContainer
    @State private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    init() {
        do {
            container = try ModelContainer(for: LookupRecord.self, StudyCard.self, ReviewEntry.self)
        } catch {
            fatalError("SwiftData store failed to open: \(error)")
        }
        _model = State(initialValue: AppModel(context: container.mainContext))
    }

    var body: some Scene {
        WindowGroup {
            TabView(selection: $model.tab) {
                Tab("查词", systemImage: "character.book.closed", value: AppTab.lookup) {
                    LookupView(model: model)
                }
                Tab("历史", systemImage: "clock.arrow.circlepath", value: AppTab.history) {
                    HistoryView(model: model)
                }
                Tab("卡片", systemImage: "rectangle.stack", value: AppTab.cards) {
                    CardsHomeView()
                }
            }
        }
        .modelContainer(container)
        .onChange(of: scenePhase, initial: true) { _, phase in
            // In split view the half the user is not touching is foreground but `.inactive`,
            // which is exactly when FoldPilot must keep watching. Stop only in the background.
            if phase == .background { model.watcher.stop() } else { model.watcher.start() }
        }
    }
}
