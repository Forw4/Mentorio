import SwiftUI
import PhotosUI
import SwiftData

struct ArchiveDetailView: View {
    @EnvironmentObject var viewModel: MentorioViewModel
    @Bindable var note: BraindumpNote
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var selectedPhotoData: Data? = nil
    @State private var currentReflectionInput: String = ""
    @Binding var selectedNoteID: UUID?
    
    @State private var isShowingCamera = false
    @State private var capturedImage: UIImage? = nil

    private var actionText: String {
        note.finalAction ?? note.storedAction ?? note.text
    }

    private var reflectionText: String {
        note.userClarification ?? ""
    }

    private var hasReflection: Bool {
        reflectionText.isEmpty == false
    }

    private var hasArtifact: Bool {
        (note.completionProof ?? "").isEmpty == false
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
            Text(Self.dateFormatter.string(from: note.completedAt ?? note.createdAt))
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

                if hasArtifact {
                    artifactBadge
                }

                if hasReflection {
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

            if !hasArtifact {
                Menu {
                    Button {
                        isShowingCamera = true
                    } label: {
                        Label("Сделать фото", systemImage: "camera")
                    }

                    PhotosPicker(
                        selection: $selectedPhotoItem,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        Label("Выбрать из галереи", systemImage: "photo.on.rectangle")
                    }
                } label: {
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
                            note.photoData = data
                            note.completionProof = "local"
                        }
                    }
                }
                .onChange(of: capturedImage) { _, newImage in
                    if let image = newImage, let data = image.jpegData(compressionQuality: 0.8) {
                        selectedPhotoData = data
                        note.photoData = data
                        note.completionProof = "local"
                    }
                }
                .fullScreenCover(isPresented: $isShowingCamera) {
                    CameraImagePicker(selectedImage: $capturedImage)
                        .ignoresSafeArea()
                }
            } else {
                if let data = selectedPhotoData ?? note.photoData,
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

            Text("ЗАМЕТКИ К ПОБЕДЕ")
                .font(.system(size: 10, weight: .medium, design: .default))
                .textCase(.uppercase)
                .tracking(1.3)
                .foregroundColor(Color(red: 0.333, green: 0.333, blue: 0.333))

            ZStack(alignment: .topLeading) {
                if currentReflectionInput.isEmpty {
                    Text("Что было самым важным в этой победе? (опционально)")
                        .font(.system(size: 14, weight: .regular, design: .default))
                        .foregroundColor(Color.white.opacity(0.35))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 14)
                        .allowsHitTesting(false)
                }

                TextEditor(text: $currentReflectionInput)
                    .font(.system(size: 14, weight: .regular, design: .default))
                    .foregroundColor(.white)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 100)
                    .padding(8)
            }
            .background(Color(red: 0.066, green: 0.066, blue: 0.066))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )
        }
        .padding(.top, 10)
        .padding(.bottom, 8)
        .onAppear {
            currentReflectionInput = note.userClarification ?? ""
        }
        .onChange(of: currentReflectionInput) { _, newValue in
            note.userClarification = newValue.isEmpty ? nil : newValue
        }
    }



    private var reflectionDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(height: 1)
    }

    private var reflectionBadge: some View {
        Text("ЗАМЕТКА")
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




extension Color {
    static let mentorioPeach = Color(red: 1.0, green: 0.671, blue: 0.569)
}

#Preview {
    ArchiveDetailPreview()
        .preferredColorScheme(.dark)
}

private struct ArchiveDetailPreview: View {
    @State private var note = BraindumpNote(
        text: "Открыть проект",
        createdAt: Date(),
        state: .idle
    )
    @State private var selectedNoteID: UUID? = UUID()

    var body: some View {
        ArchiveDetailView(note: note, selectedNoteID: $selectedNoteID)
    }
}

// MARK: - Camera Image Picker

struct CameraImagePicker: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?
    @Environment(\.presentationMode) var presentationMode

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .camera
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: CameraImagePicker

        init(_ parent: CameraImagePicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let uiImage = info[.originalImage] as? UIImage {
                parent.selectedImage = uiImage
            }
            parent.presentationMode.wrappedValue.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.presentationMode.wrappedValue.dismiss()
        }
    }
}
