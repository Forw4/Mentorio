//
//  NoteDetailView.swift
//  Mentorio
//

import SwiftUI

struct NoteDetailView: View {
    @Environment(\.dismiss) var dismiss
    let note: BraindumpNote
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .center, spacing: 16) {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.yellow)
                    
                    Text("Твоя победа")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(MentorioColor.charcoal)
                    
                    if let date = note.completedAt {
                        Text(formatDate(date))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(MentorioColor.mentorGray)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                
                // The Story Sections
                VStack(alignment: .leading, spacing: 20) {
                    // Section 1: The Blocker (Original Braindump)
                    StorySection(
                        title: "1. Блокер",
                        subtitle: "Что тебя тормозило",
                        content: note.text,
                        icon: "cloud.fill",
                        iconColor: MentorioColor.textSecondary
                    )
                    
                    // Section 2: The Mirror (Conditional - only if insight or user answer/clarification exists)
                    if shouldShowMirror() {
                        getMirrorSection()
                    }
                    
                    // Section 3: The Path (Selected Strategy)
                    if let choice = note.selectedChoice {
                        StorySection(
                            title: "3. Путь",
                            subtitle: "Стратегия, которую ты выбрал",
                            content: choice,
                            icon: "signpost.right.fill",
                            iconColor: MentorioColor.accent
                        )
                    }

                    // Section 4: The One Action (Final Action)
                    if let action = note.finalAction {
                        StorySection(
                            title: "4. Один шаг",
                            subtitle: "Что ты сделал",
                            content: action.uppercased(),
                            icon: "checkmark.circle.fill",
                            iconColor: MentorioColor.accent,
                            emphasized: true
                        )
                    }

                    // Section 5: Reality Check (Post-action friction signal)
                    if let realityCheck = note.realityCheck {
                        StorySection(
                            title: "5. Проверка реальностью",
                            subtitle: "Ожидание и реальность",
                            content: realityCheck.rawValue,
                            icon: "scale.3d",
                            iconColor: MentorioColor.accent
                        )
                    } else if let completionProof = note.completionProof, !completionProof.isEmpty {
                        StorySection(
                            title: "5. Результат",
                            subtitle: "Что изменилось после шага",
                            content: completionProof,
                            icon: "text.quote",
                            iconColor: MentorioColor.accent
                        )
                    }
                }
                .padding(.horizontal, 16)
                
                Spacer()
            }
            .padding(.vertical, 24)
        }
        .background(MentorioColor.paper)
        .scrollIndicators(.hidden)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: { dismiss() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Назад")
                    }
                    .foregroundColor(MentorioColor.accent)
                }
            }
        }
    }
    
    // MARK: - Mirror Section Logic
    
    private func shouldShowMirror() -> Bool {
        // Show mirror if we have insight or user clarification
        return (note.insight != nil && !note.insight!.isEmpty) ||
               (note.userClarification != nil && !note.userClarification!.isEmpty) ||
               (note.userAnswer != nil && !note.userAnswer!.isEmpty)
    }
    
    @ViewBuilder
    private func getMirrorSection() -> some View {
        // Check if we had a clarifying question from the AI
        if case .clarifying(let question) = note.state {
            // Show the question and the user's answer
            StorySection(
                title: "2. Зеркало",
                subtitle: "Вопрос, который сдвинул взгляд",
                content: question,
                icon: "lightbulb.fill",
                iconColor: Color.yellow
            )
            
            if let answer = note.userClarification ?? note.userAnswer {
                StorySection(
                    title: "2b. Твой инсайт",
                    subtitle: "Как изменился твой взгляд",
                    content: answer,
                    icon: "sparkles",
                    iconColor: MentorioColor.accent
                )
            }
        } else if let insight = note.insight, !insight.isEmpty {
            // Direct analysis - show insight as the shifted perspective
            StorySection(
                title: "2. Зеркало",
                subtitle: "Как изменился твой взгляд",
                content: insight,
                icon: "lightbulb.fill",
                iconColor: Color.yellow
            )
        } else if let answer = note.userClarification ?? note.userAnswer {
            // Fallback to user answer if available
            StorySection(
                title: "2. Твой инсайт",
                subtitle: "Как изменился твой взгляд",
                content: answer,
                icon: "sparkles",
                iconColor: MentorioColor.accent
            )
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return "Завершено: " + formatter.string(from: date)
    }
}

// MARK: - Story Section Component

struct StorySection: View {
    let title: String
    let subtitle: String
    let content: String
    let icon: String
    let iconColor: Color
    var emphasized: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Title with icon
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(iconColor)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(MentorioColor.charcoal)
                    
                    Text(subtitle)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(MentorioColor.mentorGray)
                }
                
                Spacer()
            }
            
            // Content
            if emphasized {
                Text(content)
                    .font(.system(size: 14, weight: .bold, design: .default))
                    .foregroundColor(MentorioColor.surfaceElevated)
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(MentorioColor.accent)
                    )
            } else {
                Text(content)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(MentorioColor.charcoal)
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(MentorioColor.surface)
                    )
            }
        }
    }
}

#Preview {
    let note = BraindumpNote(
        text: "I've been struggling with FL Studio for a month. I want to make beats but I feel stuck on the workflow.",
        selectedTopic: "Music Production",
        userAnswer: "I haven't been breaking down the steps - I'm trying to learn everything at once",
        isCompleted: true,
        insight: "Breaking complex tasks into smaller, manageable steps is key to overcoming overwhelm.",
        selectedChoice: "Start with fundamentals",
        finalAction: "Watch a 15-minute beginner FL Studio tutorial",
        completedAt: Date()
    )
    
    NoteDetailView(note: note)
}
