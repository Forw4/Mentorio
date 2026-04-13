//
//  RootView.swift
//  Mentorio
//

import SwiftUI
import SwiftData

private enum AppTab: Int, CaseIterable {
    case focus = 0
    case archive = 1

    var title: String {
        switch self {
        case .focus:
            return "Фокус"
        case .archive:
            return "Архив"
        }
    }

    var icon: String {
        switch self {
        case .focus:
            return "brain.head.profile"
        case .archive:
            return "archivebox.fill"
        }
    }
}

struct RootView: View {
    @StateObject private var viewModel: MentorioViewModel
    @State private var selectedTab: AppTab = .focus

    private var guardedSelection: Binding<AppTab> {
        Binding(
            get: { selectedTab },
            set: { newValue in
                // Hard lock tab navigation while One Action overlay is active.
                selectedTab = isExecutionOverlayVisible ? .focus : newValue
            }
        )
    }

    private var isExecutionOverlayVisible: Bool {
        viewModel.executingNoteId != nil
    }

    init(modelContext: ModelContext) {
        _viewModel = StateObject(wrappedValue: MentorioViewModel(modelContext: modelContext))
    }

    var body: some View {
        TabView(selection: guardedSelection) {
            MainDashboardView()
                .tag(AppTab.focus)

            HistoryView(archivedNotes: viewModel.archivedNotes)
                .tag(AppTab.archive)
        }
        .environmentObject(viewModel)
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !isExecutionOverlayVisible {
                TabSwitcher(selectedTab: $selectedTab)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 6)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onChange(of: isExecutionOverlayVisible) { _, visible in
            if visible && selectedTab != .focus {
                selectedTab = .focus
            }
        }
        .animation(.easeInOut(duration: 0.18), value: isExecutionOverlayVisible)
        .background(MentorioColor.background.ignoresSafeArea())
    }
}

private struct TabSwitcher: View {
    @Binding var selectedTab: AppTab

    var body: some View {
        MaterialTabSwitcherFallback(selectedTab: $selectedTab)
    }
}

private struct MaterialTabSwitcherFallback: View {
    @Binding var selectedTab: AppTab

    var body: some View {
        HStack(spacing: 8) {
            ForEach(AppTab.allCases, id: \.rawValue) { tab in
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                        selectedTab = tab
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 15, weight: .semibold))
                        Text(tab.title)
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(tab == selectedTab ? MentorioColor.accent : MentorioColor.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(tab == selectedTab ? MentorioColor.accentMuted : Color.clear)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.25), lineWidth: 0.8)
        )
        .shadow(color: Color.black.opacity(0.12), radius: 14, x: 0, y: 6)
    }
}

#Preview {
    RootView(modelContext: makePreviewModelContext())
}
