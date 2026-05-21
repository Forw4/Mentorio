import SwiftUI
import UserNotifications
import UIKit

extension UUID: @retroactive Identifiable {
    public var id: UUID { self }
}

struct FocusDashboardView: View {
    @ObservedObject var viewModel: MentorioViewModel
    @Binding var selectedTab: AppTab

    @State private var isShowingEntry = false
    @State private var completedNoteID: UUID?
    @State private var selectedDraftNote: BraindumpNote? = nil
    @State private var showVictoryDeleteAlert = false
    @State private var showSettings = false
    @State private var isWiggleMode = false
    @AppStorage("shouldAutoOpenEntry") private var shouldAutoOpenEntry: Bool = false

    private var activeNote: BraindumpNote? {
        if let execId = viewModel.executingNoteId,
           let note = viewModel.notes.first(where: { $0.id == execId }),
           note.status == .active {
            return note
        }
        return viewModel.notes.first(where: { $0.status == .active && !$0.isCompleted && !$0.isInTrash })
    }

    private var draftNotes: [BraindumpNote] {
        viewModel.notes.filter { $0.status != .active }
    }

    /// True when Focus Mode owns the screen (hides tab bar)
    var isFocusModeActive: Bool {
        activeNote != nil
    }

    var body: some View {
        Group {
            if let active = activeNote {
                // MARK: - Focus Mode (replaces entire dashboard)
                FocusModeView(
                    viewModel: viewModel,
                    note: active,
                    onComplete: {
                        // Set completedNoteID to trigger WinState fullScreenCover
                        completedNoteID = active.id
                    },
                    onCancel: {
                        viewModel.executingNoteId = nil
                        viewModel.deleteNote(id: active.id)
                    }
                )
            } else {
                // MARK: - Normal Dashboard
                dashboardContent
            }
        }
        .fullScreenCover(item: $completedNoteID) { noteID in
            WinStateView(
                viewModel: viewModel,
                noteID: noteID,
                onToArchive: {
                    // Archive here — after WinState is done
                    viewModel.archiveNote(id: noteID)
                    viewModel.executingNoteId = nil
                    completedNoteID = nil
                    selectedTab = .archive
                }
            )
        }
    }

    // MARK: - Dashboard Content

    private var dashboardContent: some View {
        ZStack(alignment: .bottom) {
            MentorioTheme.background.ignoresSafeArea()
                .onTapGesture {
                    if isWiggleMode {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            isWiggleMode = false
                        }
                    }
                }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .center) {
                        Text("Mentorio")
                            .font(.largeTitle.bold())
                            .fontDesign(.serif)
                            .foregroundStyle(MentorioTheme.primaryText)

                        Spacer()

                        Button {
                            showSettings = true
                        } label: {
                            Image(systemName: "gearshape")
                                .font(.system(size: 19, weight: .medium))
                        }
                        .buttonStyle(GearButtonStyle())
                    }
                    .padding(.top, 24)

                    HStack {
                        Text("Drafts")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.76))

                        Spacer()

                        if isWiggleMode && !draftNotes.isEmpty {
                            Button("Готово") {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    isWiggleMode = false
                                }
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(MentorioTheme.primaryText)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(.ultraThinMaterial)
                            )
                            .overlay(
                                Capsule()
                                    .stroke(MentorioTheme.stroke, lineWidth: 1)
                            )
                            .shadow(color: Color.black.opacity(0.15), radius: 4, y: 2)
                            .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .padding(.top, 6)

                    if draftNotes.isEmpty {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(MentorioTheme.card)
                            .overlay(
                                Text("No drafts right now")
                                    .font(.subheadline)
                                    .foregroundStyle(.white.opacity(0.65))
                            )
                            .frame(height: 92)
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(draftNotes) { note in
                                DraftCard(
                                    text: note.text,
                                    isWiggleMode: isWiggleMode,
                                    onDelete: {
                                        let impact = UIImpactFeedbackGenerator(style: .medium)
                                        impact.impactOccurred()
                                        withAnimation {
                                            handleDelete(note)
                                        }
                                    }
                                )
                                .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .onLongPressGesture(minimumDuration: 0.5) {
                                    let impact = UIImpactFeedbackGenerator(style: .heavy)
                                    impact.impactOccurred()
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                                        isWiggleMode = true
                                    }
                                }
                                .onTapGesture {
                                    if isWiggleMode {
                                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                            isWiggleMode = false
                                        }
                                    } else {
                                        selectedDraftNote = note
                                        withAnimation(.spring(response: 0.42, dampingFraction: 0.88)) {
                                            isShowingEntry = true
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 120)
            }

            if !isWiggleMode {
                Button {
                    selectedDraftNote = nil
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.88)) {
                        isShowingEntry = true
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(width: 68, height: 68)
                        .background(MentorioTheme.accent)
                        .clipShape(Circle())
                        .shadow(color: MentorioTheme.accent.opacity(0.4), radius: 12, x: 0, y: 8)
                }
                .padding(.bottom, 10)
                .safeAreaPadding(.bottom, 8)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .fullScreenCover(isPresented: $isShowingEntry, onDismiss: {
            selectedDraftNote = nil
        }) {
            EntryOverlayView(viewModel: viewModel, isPresented: $isShowingEntry, existingNote: selectedDraftNote)
        }
        .animation(.easeInOut(duration: 0.24), value: viewModel.notes.first?.id)
        .alert("Победы нельзя удалить. Это часть твоей истории.", isPresented: $showVictoryDeleteAlert) {
            Button("OK", role: .cancel) {}
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(viewModel)
        }
        .onChange(of: draftNotes.isEmpty) { _, isEmpty in
            if isEmpty && isWiggleMode {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    isWiggleMode = false
                }
            }
        }
        .onAppear {
            // Auto-open EntryOverlay after demo onboarding
            if shouldAutoOpenEntry {
                shouldAutoOpenEntry = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    selectedDraftNote = nil
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.88)) {
                        isShowingEntry = true
                    }
                }
            }
        }
    }

    private func handleDelete(_ note: BraindumpNote) {
        if note.isCompleted {
            showVictoryDeleteAlert = true
            return
        }
        viewModel.deleteNote(id: note.id)
    }
}


private struct DraftCard: View {
    let text: String
    let isWiggleMode: Bool
    let onDelete: () -> Void

    @State private var isWiggling = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Text(text)
                .font(.body)
                .foregroundStyle(MentorioTheme.primaryText.opacity(0.82))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(MentorioTheme.card)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(isWiggleMode ? MentorioTheme.accent.opacity(0.5) : MentorioTheme.stroke, lineWidth: 1)
                        )
                )
                .opacity(0.72)
                .blur(radius: 0.25)
            
            if isWiggleMode {
                Button(action: {
                    onDelete()
                }) {
                    Image(systemName: "minus")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(MentorioTheme.primaryText.opacity(0.75))
                        .frame(width: 22, height: 22)
                        .background(
                            Circle()
                                .fill(.ultraThinMaterial)
                        )
                        .overlay(
                            Circle()
                                .stroke(MentorioTheme.stroke, lineWidth: 1)
                        )
                        .shadow(color: Color.black.opacity(0.15), radius: 3, y: 1.5)
                        .offset(x: 6, y: -6)
                }
                .transition(.scale.combined(with: .opacity))
                .zIndex(2)
            }
        }
        .rotationEffect(.degrees(isWiggleMode ? (isWiggling ? 1.0 : -1.0) : 0))
        .offset(y: isWiggleMode ? (isWiggling ? 0.8 : -0.8) : 0)
        .onChange(of: isWiggleMode) { _, newValue in
            if newValue {
                startWiggle()
            } else {
                isWiggling = false
            }
        }
        .onAppear {
            if isWiggleMode {
                startWiggle()
            }
        }
    }

    private func startWiggle() {
        let delay = Double.random(in: 0...0.15)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            withAnimation(Animation.easeInOut(duration: 0.12).repeatForever(autoreverses: true)) {
                isWiggling = true
            }
        }
    }
}

private struct GearButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Image(systemName: "gearshape")
            .font(.system(size: 19, weight: .medium))
            .foregroundStyle(configuration.isPressed ? MentorioTheme.accent : MentorioTheme.secondaryText)
            .frame(width: 44, height: 44)
            .background(MentorioTheme.card)
            .clipShape(Circle())
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
            .animation(.spring(response: 0.15, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

#Preview {
    FocusDashboardView(viewModel: makePreviewViewModel(), selectedTab: .constant(.focus))
        .preferredColorScheme(.dark)
}
