import SwiftUI
import PhotosUI

struct WinStateView: View {
    @ObservedObject var viewModel: MentorioViewModel
    let noteID: UUID
    let onToArchive: () -> Void
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var selectedPhotoData: Data? = nil
    @State private var isShowingCamera = false
    @State private var capturedImage: UIImage? = nil

    var body: some View {
        ZStack {
            MentorioTheme.background.ignoresSafeArea()

            VStack(spacing: 26) {
                Spacer()

                Text("STEP DONE")
                    .font(.system(size: 44, weight: .black, design: .serif))
                    .foregroundStyle(MentorioTheme.primaryText)

                if let note = (viewModel.notes + viewModel.archivedNotes).first(where: { $0.id == noteID }) {
                    Text(note.finalAction ?? note.storedAction ?? note.text)
                        .font(.headline)
                        .foregroundStyle(MentorioTheme.secondaryText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                }

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
                    VStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.system(size: 32, weight: .bold))
                        Text("Add Photo/Artifact")
                            .font(.headline)
                    }
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(MentorioTheme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .padding(.horizontal, 24)
                .onChange(of: selectedPhotoItem) { _, newItem in
                    Task {
                        if let data = try? await newItem?.loadTransferable(type: Data.self) {
                            selectedPhotoData = data
                            if let note = (viewModel.notes + viewModel.archivedNotes).first(where: { $0.id == noteID }) {
                                note.photoData = data
                                note.completionProof = "local"
                            }
                            onToArchive()
                        }
                    }
                }
                .onChange(of: capturedImage) { _, newImage in
                    if let image = newImage, let data = image.jpegData(compressionQuality: 0.8) {
                        selectedPhotoData = data
                        if let note = (viewModel.notes + viewModel.archivedNotes).first(where: { $0.id == noteID }) {
                            note.photoData = data
                            note.completionProof = "local"
                        }
                        onToArchive()
                    }
                }
                .fullScreenCover(isPresented: $isShowingCamera) {
                    CameraImagePicker(selectedImage: $capturedImage)
                        .ignoresSafeArea()
                }

                Button("To Archive") {
                    onToArchive()
                }
                .font(.headline)
                .foregroundStyle(MentorioTheme.primaryText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(MentorioTheme.card)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.horizontal, 24)

                Spacer()
            }
        }
    }
}

#Preview {
    WinStateView(viewModel: makePreviewViewModel(), noteID: UUID(), onToArchive: {})
        .preferredColorScheme(.dark)
}
