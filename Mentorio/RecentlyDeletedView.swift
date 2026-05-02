//
//  RecentlyDeletedView.swift
//  Mentorio
//

import SwiftUI

struct RecentlyDeletedView: View {
    @EnvironmentObject var viewModel: MentorioViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showVictoryDeleteAlert = false

    private let background = Color(red: 0.051, green: 0.051, blue: 0.051)
    private let cardFill = Color.white.opacity(0.05)
    private let cardStroke = Color.white.opacity(0.08)
    private let textPrimary = Color.white.opacity(0.9)

    var body: some View {
        ZStack {
            background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    headerRow

                    if viewModel.deletedNotes.isEmpty {
                        emptyState
                    } else {
                        ForEach(viewModel.deletedNotes) { note in
                            deletedCard(note)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 28)
            }
        }
        .navigationBarHidden(true)
        .alert("Победы нельзя удалить. Это часть твоей истории.", isPresented: $showVictoryDeleteAlert) {
            Button("OK", role: .cancel) {}
        }
    }

    private var headerRow: some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Color.mentorioPeach)
                    .frame(width: 32, height: 32)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            Text("Недавно удаленные")
                .font(.title2.weight(.semibold))
                .fontDesign(.serif)
                .foregroundStyle(textPrimary)

            Spacer()
        }
        .padding(.top, 6)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Корзина пуста")
                .font(.headline.weight(.semibold))
                .foregroundStyle(textPrimary)

            Text("Удаленные черновики появятся здесь.")
                .font(.subheadline)
                .foregroundStyle(Color.white.opacity(0.6))
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(cardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(cardStroke, lineWidth: 1)
                )
        )
    }

    private func deletedCard(_ note: BraindumpNote) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(note.text)
                .font(.body)
                .foregroundStyle(textPrimary)
                .lineLimit(3)

            if let deletedAt = note.deletedAt {
                Text(deletedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.55))
            }

            HStack(spacing: 10) {
                Button {
                    viewModel.restoreNote(id: note.id)
                } label: {
                    Label("Восстановить", systemImage: "arrow.uturn.left")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.mentorioPeach)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)

                Button {
                    if note.isCompleted {
                        showVictoryDeleteAlert = true
                    } else {
                        viewModel.permanentlyDeleteNote(id: note.id)
                    }
                } label: {
                    Text("Удалить навсегда")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.white.opacity(0.15), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(cardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(cardStroke, lineWidth: 1)
                )
        )
    }
}

#Preview {
    RecentlyDeletedView()
    .environmentObject(makePreviewViewModel())
}
