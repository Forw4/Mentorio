//
//  ComposeView.swift
//  Mentorio
//

import SwiftUI

struct ComposeView: View {
    @Binding var draft: String
    let onCancel: () -> Void
    let onSave: () -> Void

    private let bg = Color(red: 0.051, green: 0.051, blue: 0.051)

    var body: some View {
        NavigationStack {
            ZStack(alignment: .topLeading) {
                bg.ignoresSafeArea()

                TextEditor(text: $draft)
                    .font(.body)
                    .fontDesign(.serif)
                    .foregroundStyle(Color.white.opacity(0.9))
                    .scrollContentBackground(.hidden)
                    .lineSpacing(6)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Начни писать.")
                        .font(.body)
                        .fontDesign(.serif)
                        .foregroundStyle(Color.white.opacity(0.28))
                        .padding(.horizontal, 28)
                        .padding(.top, 16)
                        .allowsHitTesting(false)
                }
            }
            .navigationTitle("Новая запись")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(bg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") {
                        onCancel()
                    }
                    .foregroundStyle(Color.white.opacity(0.65))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        onSave()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.white.opacity(saveDisabled ? 0.3 : 0.95))
                    .disabled(saveDisabled)
                }
            }
        }
    }

    private var saveDisabled: Bool {
        draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

#Preview {
    ComposeView(draft: .constant(""), onCancel: {}, onSave: {})
        .preferredColorScheme(.dark)
}
