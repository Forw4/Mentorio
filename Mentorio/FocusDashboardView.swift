import SwiftUI

struct FocusDashboardView: View {
    @ObservedObject var viewModel: NotesViewModel
    @Binding var selectedTab: AppTab

    @State private var isShowingEntry = false
    @State private var isShowingWinState = false
    @State private var completedNoteID: UUID?

    var body: some View {
        ZStack(alignment: .bottom) {
            MentorioTheme.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Mentorio")
                        .font(.largeTitle.bold())
                        .fontDesign(.serif)
                        .foregroundStyle(.white)
                        .padding(.top, 8)

                    if let active = viewModel.activeNote {
                        ActiveStickyBar(noteText: active.text) {
                            guard let archived = viewModel.completeCurrentActiveNote() else { return }
                            completedNoteID = archived.id
                            withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
                                isShowingWinState = true
                            }
                        }
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    Text("Drafts")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.76))
                        .padding(.top, 6)

                    if viewModel.drafts.isEmpty {
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
                            ForEach(viewModel.drafts) { note in
                                DraftCard(text: note.text)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 120)
            }

            Button {
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
        }
        .fullScreenCover(isPresented: $isShowingEntry) {
            EntryOverlayView(viewModel: viewModel, isPresented: $isShowingEntry)
        }
        .fullScreenCover(isPresented: $isShowingWinState) {
            if let completedNoteID {
                WinStateView(
                    viewModel: viewModel,
                    noteID: completedNoteID,
                    onToArchive: {
                        isShowingWinState = false
                        selectedTab = .archive
                    }
                )
            }
        }
        .animation(.easeInOut(duration: 0.24), value: viewModel.activeNote?.id)
    }
}

private struct ActiveStickyBar: View {
    let noteText: String
    let onComplete: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("ACTIVE")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MentorioTheme.accent)

                Text(noteText)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            HoldToCompleteButton(onComplete: onComplete)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(MentorioTheme.accent.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(MentorioTheme.accent, lineWidth: 1)
                )
        )
    }
}

private struct HoldToCompleteButton: View {
    let onComplete: () -> Void

    @State private var progress: CGFloat = 0
    @State private var didFinish = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.22), lineWidth: 4)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    MentorioTheme.accent,
                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            Text("Hold")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
        }
        .frame(width: 68, height: 68)
        .contentShape(Circle())
        .onLongPressGesture(minimumDuration: 3.0, maximumDistance: 44, pressing: { pressing in
            if pressing {
                didFinish = false
                progress = 0
                withAnimation(.linear(duration: 3.0)) {
                    progress = 1
                }
            } else if !didFinish {
                withAnimation(.easeOut(duration: 0.2)) {
                    progress = 0
                }
            }
        }, perform: {
            didFinish = true
            progress = 1
            onComplete()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                progress = 0
                didFinish = false
            }
        })
    }
}

private struct DraftCard: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.body)
            .foregroundStyle(.white.opacity(0.82))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(MentorioTheme.stroke, lineWidth: 1)
                    )
            )
            .opacity(0.72)
            .blur(radius: 0.25)
    }
}

#Preview {
    FocusDashboardView(viewModel: NotesViewModel(), selectedTab: .constant(.focus))
        .preferredColorScheme(.dark)
}
