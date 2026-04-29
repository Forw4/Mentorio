import SwiftUI
import PhotosUI

struct ArchiveDetailView: View {
    @Binding var note: Note
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var selectedPhotoData: Data? = nil
    @State private var currentReflectionInput: String = ""
    @State private var isReflectionPromptVisible = false
    @Binding var selectedNoteID: UUID?

    init(note: Binding<Note>, selectedNoteID: Binding<UUID?>) {
        _note = note
        _selectedNoteID = selectedNoteID
    }

    private var actionText: String {
        note.oneActionText.isEmpty ? note.text : note.oneActionText
    }


    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                headerBar
                headerSection
                artifactSection
                reflectionSection
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
            .padding(.bottom, 120)
        }
        .background(Color.black.opacity(0.88).ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var headerBar: some View {
        HStack {
            Spacer()

            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    selectedNoteID = nil
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color.white.opacity(0.8))
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.1))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(Self.dateFormatter.string(from: note.createdAt))
                .font(.system(size: 11, weight: .regular, design: .default))
                .monospacedDigit()
                .foregroundColor(Color(red: 85.0 / 255.0, green: 85.0 / 255.0, blue: 85.0 / 255.0))

            // TODO: matchedGeometryEffect
            Text(actionText)
                .font(.system(size: 28, weight: .bold, design: .serif))
                .foregroundColor(Color.white.opacity(0.9))
                .lineSpacing(4)
                .multilineTextAlignment(.leading)

            HStack(alignment: .center, spacing: 8) {
                Text("10–15 мин · выполнено")
                    .font(.system(size: 10, weight: .regular, design: .default))
                    .foregroundColor(Color(red: 0.533, green: 0.533, blue: 0.533))

                Spacer()

                if note.artifactImageName != nil {
                    artifactBadge
                }

                if note.reflectionStatus == .completed {
                    reflectionBadge
                }
            }
        }
    }


    private var artifactSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("АРТЕФАКТ / ПРУФ")
                .font(.system(size: 9, weight: .regular, design: .default))
                .tracking(1.3)
                .foregroundColor(Color(red: 85.0 / 255.0, green: 85.0 / 255.0, blue: 85.0 / 255.0))

            if note.artifactImageName == nil {
                PhotosPicker(
                    selection: $selectedPhotoItem,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(style: StrokeStyle(lineWidth: 1, dash: [6]))
                        .foregroundColor(Color.white.opacity(0.18))
                        .frame(height: 140)
                        .overlay(
                            VStack(spacing: 10) {
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(Color.white.opacity(0.6))
                                Text("Добавить пруф / воспоминание")
                                    .font(.system(size: 11, weight: .regular, design: .default))
                                    .foregroundColor(Color.white.opacity(0.55))
                            }
                        )
                }
                .onChange(of: selectedPhotoItem) { _, newItem in
                    Task {
                        if let data = try? await newItem?.loadTransferable(type: Data.self) {
                            selectedPhotoData = data
                            // For now we only keep it in memory.
                            // Use artifactImageName as a simple flag to indicate that an artifact exists.
                            note.artifactImageName = "local"
                        }
                    }
                }
            } else {
                if let data = selectedPhotoData,
                   let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 160)
                        .clipped()
                        .cornerRadius(14)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(red: 0.1, green: 0.1, blue: 0.1))
                            .frame(height: 140)
                            .overlay(
                                Image(systemName: "photo.fill")
                                    .foregroundColor(.gray)
                            )

                        Text("ПРУФ / ВОСПОМИНАНИЕ")
                            .font(.system(size: 9, weight: .regular, design: .default))
                            .foregroundColor(Color.mentorioPeach)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var reflectionSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            reflectionDivider

            if note.reflectionStatus == .pending {
                Text("ЗАКРЕПИТЬ ОПЫТ")
                    .font(.system(size: 10, weight: .medium, design: .default))
                    .textCase(.uppercase)
                    .tracking(1.3)
                    .foregroundColor(Color(red: 0.333, green: 0.333, blue: 0.333))

                Text("Коротко зафиксируй, что в этой победе было самым важным. Это поможет в следующий раз.")
                    .font(.system(size: 12, weight: .regular, design: .default))
                    .foregroundColor(Color.white.opacity(0.65))

                if isReflectionPromptVisible {
                    ChatBubble(
                        role: .mentor,
                        text: "Это был долгий путь. Вытащим это в привычку. Коротко зафиксируй, что в этой победе было самым важным."
                    )
                    .transition(.opacity.combined(with: .move(edge: .bottom)))

                    reflectionInput
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                if !isReflectionPromptVisible {
                    HStack {
                        Spacer()

                        Button {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                isReflectionPromptVisible = true
                            }
                        } label: {
                            Text("Обсудить, как это было")
                                .font(.system(size: 13, weight: .medium, design: .default))
                                .foregroundColor(Color.mentorioPeach)
                                .padding(.vertical, 12)
                                .padding(.horizontal, 20)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(Color(red: 0.066, green: 0.066, blue: 0.066))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(Color.mentorioPeach.opacity(0.3), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: 320)

                        Spacer()
                    }
                    .padding(.vertical, 6)
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ChatBubble(
                        role: .mentor,
                        text: "Это был долгий путь. Вытащим это в привычку. Коротко зафиксируй, что в этой победе было самым важным."
                    )
                    ChatBubble(role: .user, text: note.reflectionText ?? "")
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    private var reflectionInput: some View {
        HStack(alignment: .bottom, spacing: 10) {
            ZStack(alignment: .topLeading) {
                if currentReflectionInput.isEmpty {
                    Text("Коротко и честно...")
                        .font(.system(size: 12, weight: .regular, design: .default))
                        .foregroundColor(Color.white.opacity(0.35))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                }

                TextEditor(text: $currentReflectionInput)
                    .font(.system(size: 12, weight: .regular, design: .default))
                    .foregroundColor(.white)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 44, maxHeight: 90)
                    .padding(8)
            }
            .background(Color(red: 0.09, green: 0.09, blue: 0.09))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )

            Button {
                let trimmed = currentReflectionInput.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                withAnimation(.easeInOut(duration: 0.25)) {
                    note.reflectionText = trimmed
                    note.reflectionStatus = .completed
                    currentReflectionInput = ""
                    isReflectionPromptVisible = false
                }
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color.black)
                    .frame(width: 32, height: 32)
                    .background(Color.mentorioPeach)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
    }

    private var reflectionDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(height: 1)
    }

    private var reflectionBadge: some View {
        Text("РАЗОБРАНО")
            .font(.system(size: 9, weight: .semibold, design: .default))
            .foregroundColor(Color.mentorioPeach)
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

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "d MMM · HH:mm"
        return formatter
    }()
}


private struct ChatBubble: View {
    enum Role {
        case mentor
        case user
    }

    let role: Role
    let text: String

    var body: some View {
        HStack {
            if role == .user {
                Spacer(minLength: 40)
            }

            VStack(alignment: role == .user ? .trailing : .leading, spacing: 6) {
                if role == .mentor {
                    Text("Mentor")
                        .font(.system(size: 9, weight: .medium, design: .default))
                        .tracking(1.0)
                        .foregroundColor(Color(red: 0.333, green: 0.333, blue: 0.333))
                }

                Text(text)
                    .font(.system(size: 12, weight: .regular, design: .default))
                    .foregroundColor(role == .user ? .white : Color.white.opacity(0.86))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(role == .user ? Color.mentorioPeach.opacity(0.12) : Color(red: 0.066, green: 0.066, blue: 0.066))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(role == .user ? Color.mentorioPeach.opacity(0.35) : Color.white.opacity(0.06), lineWidth: 1)
                    )
            }
            .frame(maxWidth: 280, alignment: role == .user ? .trailing : .leading)

            if role == .mentor {
                Spacer(minLength: 40)
            }
        }
    }
}

extension Color {
    static let mentorioPeach = Color(red: 1.0, green: 0.671, blue: 0.569)
}

#Preview {
    ArchiveDetailPreview()
        .preferredColorScheme(.dark)
}

private struct ArchiveDetailPreview: View {
    @State private var note = Note(
        text: "Открыть проект",
        status: .archived,
        createdAt: Date(),
        artifactPlaceholder: nil
    )
    @State private var selectedNoteID: UUID? = UUID()

    var body: some View {
        ArchiveDetailView(note: $note, selectedNoteID: $selectedNoteID)
    }
}
