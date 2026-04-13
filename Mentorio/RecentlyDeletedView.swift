//
//  RecentlyDeletedView.swift
//  Mentorio
//

import SwiftUI

struct RecentlyDeletedView: View {
    @EnvironmentObject var viewModel: MentorioViewModel

    var body: some View {
        List {
            if viewModel.deletedNotes.isEmpty {
                Text("Корзина пуста")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.deletedNotes) { note in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(note.text)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .lineLimit(3)

                        if let deletedAt = note.deletedAt {
                            Text(deletedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        Button("Восстановить") {
                            viewModel.restoreNote(id: note.id)
                        }
                        .tint(MentorioColor.accent)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button("Удалить навсегда", role: .destructive) {
                            viewModel.permanentlyDeleteNote(id: note.id)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Недавно удаленные")
    }
}

#Preview {
    RecentlyDeletedView()
    .environmentObject(makePreviewViewModel())
}
