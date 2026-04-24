//
//  RootView.swift
//  Mentorio
//

import SwiftUI
import SwiftData
import UIKit

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
    private static var didConfigureSegmentedControlAppearance = false

    private var isExecutionOverlayVisible: Bool {
        viewModel.executingNoteId != nil
    }

    init(modelContext: ModelContext) {
        Self.configureSegmentedControlAppearance()
        _viewModel = StateObject(wrappedValue: MentorioViewModel(modelContext: modelContext))
    }

    private static func configureSegmentedControlAppearance() {
        guard !didConfigureSegmentedControlAppearance else { return }
        didConfigureSegmentedControlAppearance = true

        let appearance = UISegmentedControl.appearance()
        appearance.selectedSegmentTintColor = UIColor(MentorioColor.accent)
        appearance.backgroundColor = UIColor(MentorioColor.surface)
        appearance.setTitleTextAttributes([
            .foregroundColor: UIColor(MentorioColor.textPrimary)
        ], for: .normal)
        appearance.setTitleTextAttributes([
            .foregroundColor: UIColor(MentorioColor.textOnAccent)
        ], for: .selected)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            switch selectedTab {
            case .focus:
                MainDashboardView()
                    .id(AppTab.focus)
            case .archive:
                HistoryView(archivedNotes: viewModel.archivedNotes)
                    .id(AppTab.archive)
            }

            if !isExecutionOverlayVisible {
                TabSwitcher(selectedTab: $selectedTab)
                    .padding(.horizontal, 8)
                    .padding(.top, 8)
                    .padding(.bottom, 6)
                    .frame(maxWidth: .infinity)
                    .background(MentorioColor.background)
                    .ignoresSafeArea(.keyboard, edges: .bottom)
            }
        }
        .environmentObject(viewModel)
        .onChange(of: isExecutionOverlayVisible) { _, visible in
            if visible && selectedTab != .focus {
                selectedTab = .focus
            }
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .background(MentorioColor.background.ignoresSafeArea())
    }
}

private struct TabSwitcher: View {
    @Binding var selectedTab: AppTab

    var body: some View {
        Picker("Навигация", selection: $selectedTab) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                Text(tab.title).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .controlSize(.large)
    }
}

#Preview {
    RootView(modelContext: makePreviewModelContext())
}
