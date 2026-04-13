//
//  ComposeView.swift
//  Mentorio
//

import SwiftUI

struct ComposeView: View {
    @Binding var draft: String
    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        NavigationStack {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $draft)
                    .font(.body)
                    .fontDesign(.serif)
                    .foregroundStyle(MentorioColor.charcoal)
                    .scrollContentBackground(.hidden)
                    .lineSpacing(6)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Начни писать.")
                        .font(.body)
                        .fontDesign(.serif)
                        .foregroundStyle(MentorioColor.charcoal.opacity(0.28))
                        .padding(.horizontal, 28)
                        .padding(.top, 16)
                        .allowsHitTesting(false)
                }
            }
            .mentorioPaperBackground()
            .navigationTitle("Новая запись")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") {
                        onCancel()
                    }
                    .foregroundStyle(MentorioColor.charcoal.opacity(0.65))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        onSave()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(MentorioColor.charcoal.opacity(saveDisabled ? 0.35 : 0.95))
                    .disabled(saveDisabled)
                }
            }
            .toolbarBackground(MentorioColor.paper, for: .navigationBar)
        }
    }

    private var saveDisabled: Bool {
        draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

#Preview {
    ComposeView(draft: .constant(""), onCancel: {}, onSave: {})
}
