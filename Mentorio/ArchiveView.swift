import SwiftUI

struct ArchiveView: View {
    @ObservedObject var viewModel: NotesViewModel
    @State private var selectedNoteID: UUID?

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                MentorioTheme.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("АРХИВ")
                                .font(.system(size: 10, weight: .medium, design: .default))
                                .tracking(1.4)
                                .foregroundStyle(Color(red: 0.333, green: 0.333, blue: 0.333))

                            Text("Essential Space")
                                .font(.system(size: 28, weight: .bold, design: .serif))
                                .foregroundStyle(.white)
                        }

                        if viewModel.archived.isEmpty {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(MentorioTheme.card)
                                .frame(height: 110)
                                .overlay(
                                    Text("No completed actions yet")
                                        .font(.subheadline)
                                        .foregroundStyle(.white.opacity(0.68))
                                )
                        } else {
                            LazyVGrid(columns: columns, spacing: 12) {
                                ForEach(viewModel.archived) { note in
                                    ArchiveCard(note: note)
                                        // TODO: matchedGeometryEffect
                                        .onTapGesture {
                                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                                selectedNoteID = note.id
                                            }
                                        }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .padding(.bottom, 90)
                }
                .blur(radius: selectedNoteID == nil ? 0 : 15)
                .disabled(selectedNoteID != nil)

                     if let noteID = selectedNoteID,
                   let noteBinding = viewModel.binding(for: noteID) {
                    ZStack {
                        Color.black.opacity(0.3)
                            .background(.ultraThinMaterial)
                            .ignoresSafeArea()
                            .onTapGesture {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    selectedNoteID = nil
                                }
                            }

                        ArchiveDetailView(note: noteBinding, selectedNoteID: $selectedNoteID)
                            .background(Color(red: 0.05, green: 0.05, blue: 0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 48)
                            .shadow(color: .black.opacity(0.5), radius: 30, x: 0, y: 20)
                            .transition(.opacity.combined(with: .scale(scale: 0.95)))
                            .onTapGesture { }
                    }
                    .zIndex(100)
                }
            }
        }
        .toolbar(selectedNoteID == nil ? .visible : .hidden, for: .tabBar)
    }
}

private struct ArchiveCard: View {
    let note: Note

    private var dateText: String {
        ArchiveCard.dateFormatter.string(from: note.createdAt)
    }

    private var actionText: String {
        note.oneActionText.isEmpty ? note.text : note.oneActionText
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(dateText)
                .font(.system(size: 11, weight: .regular, design: .default))
                .monospacedDigit()
                .foregroundStyle(Color(red: 0.533, green: 0.533, blue: 0.533))

            Text(actionText)
                .font(.system(size: 18, weight: .bold, design: .serif))
                .foregroundStyle(Color.white.opacity(0.9))
                .lineSpacing(4)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("10–15 мин · выполнено")
                .font(.system(size: 9, weight: .regular, design: .default))
                .foregroundStyle(Color(red: 0.533, green: 0.533, blue: 0.533))

            HStack {
                Spacer()
                statusBadges
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .frame(height: 180)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(red: 0.051, green: 0.051, blue: 0.051))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.05), lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    private var statusBadges: some View {
        HStack(spacing: 6) {
            if note.artifactImageName != nil {
                artifactBadge
            }

            if note.reflectionStatus == .completed {
                reflectionBadge
            }
        }
    }

    private var artifactBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "photo")
                .font(.system(size: 8, weight: .semibold))
            Text("пруф")
                .font(.system(size: 9, weight: .regular, design: .default))
        }
        .foregroundStyle(Color(red: 0.667, green: 0.667, blue: 0.667))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(red: 0.102, green: 0.102, blue: 0.102))
        .clipShape(Capsule())
    }

    private var reflectionBadge: some View {
        Text("РАЗОБРАНО")
            .font(.system(size: 9, weight: .semibold, design: .default))
            .foregroundStyle(Color.mentorioPeach)
            .fixedSize()
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.mentorioPeach.opacity(0.05))
            .overlay(
                Capsule()
                    .stroke(Color.mentorioPeach.opacity(0.3), lineWidth: 1)
            )
            .clipShape(Capsule())
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "d MMM · HH:mm"
        return formatter
    }()
}

#Preview {
    ArchiveView(viewModel: NotesViewModel())
        .preferredColorScheme(.dark)
}
