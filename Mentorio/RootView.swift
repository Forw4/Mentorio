import SwiftUI

enum AppTab: Hashable {
    case focus
    case archive
}

struct RootView: View {
    @StateObject private var viewModel = NotesViewModel()
    @State private var selectedTab: AppTab = .focus

    var body: some View {
        TabView(selection: $selectedTab) {
            FocusDashboardView(viewModel: viewModel, selectedTab: $selectedTab)
                .tabItem {
                    Label("Focus", systemImage: "target")
                }
                .tag(AppTab.focus)

            ArchiveView(viewModel: viewModel)
                .tabItem {
                    Label("Archive", systemImage: "archivebox")
                }
                .tag(AppTab.archive)
        }
        .preferredColorScheme(.dark)
        .background(MentorioTheme.background.ignoresSafeArea())
    }
}

#Preview {
    RootView()
}
