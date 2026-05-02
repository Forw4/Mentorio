//
//  PrivacyView.swift
//  Mentorio
//

import SwiftUI

struct PrivacyView: View {
    private let bg         = Color(red: 0.051, green: 0.051, blue: 0.051)
    private let textPrimary = Color.white.opacity(0.9)

    var body: some View {
        ZStack {
            bg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    privacyBlock(
                        icon: "lock.shield.fill",
                        title: "Данные хранятся на устройстве",
                        body: "Mentorio не отправляет историю брайндампов и историю действий на внешние серверы хранения. Твой хаос остаётся у тебя."
                    )

                    privacyBlock(
                        icon: "network.slash",
                        title: "Нет облачной синхронизации",
                        body: "Все заметки, победы и черновики сохранены локально через SwiftData. Удаление приложения удалит все данные."
                    )

                    privacyBlock(
                        icon: "cpu",
                        title: "AI-запросы",
                        body: "Текст брайндампа отправляется в AI-модель через OpenRouter для генерации тактики. Запросы не хранятся на серверах Mentorio."
                    )
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .navigationTitle("Приватность")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(bg, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    private func privacyBlock(icon: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(Color(red: 1.0, green: 0.671, blue: 0.569))
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(textPrimary)

                Text(body)
                    .font(.subheadline)
                    .foregroundStyle(Color.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }
}

#Preview {
    NavigationStack {
        PrivacyView()
    }
    .preferredColorScheme(.dark)
}
