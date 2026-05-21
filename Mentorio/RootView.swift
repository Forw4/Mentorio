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

    /// Check if there's an active (executing) note — hides tab bar
    private var hasActiveStep: Bool {
        if let execId = viewModel.executingNoteId,
           viewModel.notes.contains(where: { $0.id == execId && $0.status == .active }) {
            return true
        }
        return viewModel.notes.contains(where: { $0.status == .active && !$0.isCompleted && !$0.isInTrash })
    }

    var body: some View {
        Group {
            if hasActiveStep {
                // Focus Mode takes over — no tab bar
                FocusDashboardView(viewModel: viewModel, selectedTab: $selectedTab)
            } else {
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
            }
        }
        .preferredColorScheme(.dark)
        .background(MentorioTheme.background.ignoresSafeArea())
        .environmentObject(viewModel)
    }
}

#Preview {
    RootView()
}
