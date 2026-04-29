import SwiftUI
import PhotosUI

struct WinStateView: View {
    @ObservedObject var viewModel: NotesViewModel
    let noteID: UUID
    let onToArchive: () -> Void
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var selectedPhotoData: Data? = nil

    var body: some View {
        ZStack {
            MentorioTheme.background.ignoresSafeArea()

            VStack(spacing: 26) {
                Spacer()

                Text("STEP DONE")
                    .font(.system(size: 44, weight: .black, design: .serif))
                    .foregroundStyle(.white)

                if let note = viewModel.note(for: noteID) {
                    Text(note.text)
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.84))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                }

                PhotosPicker(
                    selection: $selectedPhotoItem,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
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
                            viewModel.setArtifactImageName(noteID: noteID, name: "local")
                            onToArchive()
                        }
                    }
                }

                Button("To Archive") {
                    onToArchive()
                }
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.white.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.horizontal, 24)

                Spacer()
            }
        }
    }
}

#Preview {
    WinStateView(viewModel: NotesViewModel(), noteID: UUID(), onToArchive: {})
        .preferredColorScheme(.dark)
}
