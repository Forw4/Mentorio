import SwiftUI
import SwiftData

enum AppTab: Hashable {
    case focus
    case archive
}

struct RootView: View {
    @StateObject private var viewModel: MentorioViewModel
    @State private var selectedTab: AppTab = .focus

    init() {
        do {
            let container = try ModelContainer(
                for: BraindumpNote.self,
                MentorioSession.self,
                AnalyticsEventRecord.self
            )
            _viewModel = StateObject(wrappedValue: MentorioViewModel(modelContext: ModelContext(container)))
        } catch {
            fatalError("Failed to initialize SwiftData container: \(error)")
        }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            FocusDashboardView(viewModel: viewModel, selectedTab: $selectedTab)
                .tabItem {
                    Label("Focus", systemImage: "target")
                }
                .tag(AppTab.focus)

            ArchiveView()
                .tabItem {
                    Label("Archive", systemImage: "archivebox")
                }
                .tag(AppTab.archive)
        }
        .preferredColorScheme(.dark)
        .background(MentorioTheme.background.ignoresSafeArea())
        .environmentObject(viewModel)
    }
}

#Preview {
    RootView()
}
