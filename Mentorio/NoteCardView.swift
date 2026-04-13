//
//  NoteCardView.swift
//  Mentorio
//

import SwiftUI

// MARK: - Helper: Relative Time String

func relativeTimeString(from date: Date) -> String {
    let calendar = Calendar.current
    let now = Date()
    let components = calendar.dateComponents([.day, .hour, .minute], from: date, to: now)
    
    if let day = components.day, day > 0 {
        if day == 1 {
            return "Вчера"
        } else if day < 7 {
            return "\(day) дн. назад"
        } else {
            return "\(day / 7) нед. назад"
        }
    } else if let hour = components.hour, hour > 0 {
        return "\(hour) ч назад"
    } else if let minute = components.minute, minute > 0 {
        return "\(minute) мин назад"
    } else {
        return "Только что"
    }
}

// MARK: - Helper: Topic to Emoji Badge

func topicToBadge(_ topic: String) -> String {
    let lowercased = topic.lowercased()
    
    // Topic-to-emoji mapping
    let emojiMap: [String: String] = [
        "музыка": "🎹", "биты": "🎹", "fl studio": "🎹", "звук": "🎹",
        "жилищ": "🏠", "квартир": "🏠", "аренд": "🏠", "белград": "🇷🇸",
        "сербск": "🇷🇸", "язык": "🇷🇸", "duolingo": "🇷🇸",
        "учеб": "📚", "конспект": "📚", "задач": "📚", "преподав": "📚",
        "работ": "💼", "проект": "💼", "код": "💻", "программ": "💻",
        "отношен": "❤️", "друг": "❤️", "любовь": "❤️", "общен": "👥"
    ]
    
    for (key, emoji) in emojiMap {
        if lowercased.contains(key) {
            return emoji
        }
    }
    
    return "⚡" // Default
}

// MARK: - Note Card View (Minimalist Design)

struct NoteCardView: View {
    let note: BraindumpNote
    let viewModel: MentorioViewModel
    let focusedNoteID: UUID?
    let onAnswerFieldFocus: ((UUID) -> Void)?
    @State private var answerInput: String = ""
    @FocusState private var isAnswerFieldFocused: Bool
    
    // Computed property: is this note the focused one?
    private var isFocused: Bool {
        focusedNoteID == note.id
    }
    
    var body: some View {
        Group {
            if isFocused {
                // EXPANDED VIEW: Full interactive card
                expandedCard()
            } else {
                // COLLAPSED VIEW: Single-line preview
                collapsedCard()
            }
        }
        .onChange(of: isAnswerFieldFocused) { _, focused in
            if focused {
                onAnswerFieldFocus?(note.id)
            }
        }
    }
    
    // MARK: - Expanded Card (Full Interactive)
    
    @ViewBuilder
    private func expandedCard() -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // MAIN CONTENT AREA (20pt padding)
            VStack(alignment: .leading, spacing: 12) {
                Text(note.text)
                    .font(MentorioType.body)
                    .foregroundColor(MentorioColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                
                // State-specific content (above divider)
                stateContent()
            }
            .padding(20)
            
            // DIVIDER (thin light gray)
            Divider()
                .frame(height: 0.5)
                .background(MentorioColor.stroke)
            
            // FOOTER (Time + Action Zone)
            HStack(spacing: 12) {
                // Left: Relative time (muted gray)
                Text(relativeTimeString(from: note.createdAt))
                    .font(MentorioType.caption)
                    .foregroundColor(MentorioColor.textSecondary)
                
                Spacer()

                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        viewModel.deleteNote(id: note.id)
                    }
                }) {
                    Image(systemName: "trash")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(MentorioColor.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(MentorioColor.accentMuted)
                        .cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())
                
                // Right: Action Zone (Interactive)
                footerAction()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .background(MentorioColor.surfaceElevated)
        .cornerRadius(MentorioMetric.radiusL)
        .shadow(
            color: Color.black.opacity(0.08),
            radius: 12,
            x: 0,
            y: 4
        )
        .animation(.easeInOut(duration: 0.3), value: note.state)
    }
    
    // MARK: - Collapsed Card (Single-line Preview)
    
    @ViewBuilder
    private func collapsedCard() -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Single line text preview with ellipsis
            HStack(spacing: 12) {
                Text(note.text)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(MentorioColor.textSecondary)
                    .lineLimit(1)
                
                Spacer()
                
                // Tap hint
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(MentorioColor.textSecondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(MentorioColor.surface)
        .cornerRadius(MentorioMetric.radiusM)
        .shadow(
            color: Color.black.opacity(0.05),
            radius: 8,
            x: 0,
            y: 2
        )
        .onTapGesture {
            // Expand this note on tap
            viewModel.focusedNoteID = note.id
            viewModel.presentStoredActionIfAvailable(for: note.id)
        }
    }
    
    // MARK: - State-Specific Content (Above Divider)
    
    @ViewBuilder
    private func stateContent() -> some View {
        switch note.state {
        case .idle:
            // Empty in idle state - action is in footer only
            EmptyView()
            
        case .analyzing:
            HStack(spacing: 8) {
                ProgressView()
                    .tint(MentorioColor.accent)
                    .scaleEffect(0.8)
                Text("Анализ...")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(MentorioColor.textSecondary)
            }
            
        case .needsTopic(let topics):
            VStack(alignment: .leading, spacing: 10) {
                Text("Выбери фокус")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(MentorioColor.textSecondary)
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(topics, id: \.self) { topic in
                            Button(action: {
                                viewModel.selectTopic(topic, for: note.id)
                            }) {
                                Text(topic)
                                    .font(.system(size: 11, weight: .medium))
                                    .padding(.horizontal, 11)
                                    .padding(.vertical, 6)
                                    .background(MentorioColor.accentMuted)
                                    .foregroundColor(MentorioColor.accent)
                                    .cornerRadius(6)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
            
        case .clarifying(let question):
            VStack(alignment: .leading, spacing: 10) {
                Text(question)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(MentorioColor.textPrimary)
                
                HStack(spacing: 8) {
                    TextField("Напиши ответ мне сюда", text: $answerInput)
                        .focused($isAnswerFieldFocused)
                        .submitLabel(.done)
                        .onSubmit {
                            isAnswerFieldFocused = false
                        }
                        .font(.system(size: 12, weight: .regular))
                        .padding(10)
                        .background(MentorioColor.surface)
                        .cornerRadius(8)
                    
                    Button(action: {
                        let answer = answerInput.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !answer.isEmpty {
                            viewModel.submitAnswer(answer, for: note.id)
                            answerInput = ""
                            isAnswerFieldFocused = false
                        }
                    }) {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(MentorioColor.surfaceElevated)
                            .frame(width: 32, height: 32)
                            .background(MentorioColor.accent)
                            .cornerRadius(8)
                    }
                    .buttonStyle(PlainButtonStyle())
                }

            }
            
        case .hasTactics(let choices, let highlight, let insight, _):
            VStack(alignment: .leading, spacing: 12) {
                // "Key Point" - only if highlight exists
                if !highlight.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Суть")
                            .font(.system(size: 10, weight: .semibold, design: .default))
                            .foregroundColor(MentorioColor.textSecondary)
                            .tracking(0.5)
                        Text(highlight)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(MentorioColor.textPrimary)
                    }
                }
                
                // "The Gist" - only if insight exists
                if !insight.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Анализ")
                            .font(.system(size: 10, weight: .semibold, design: .default))
                            .foregroundColor(MentorioColor.textSecondary)
                            .tracking(0.5)
                        Text(insight)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(MentorioColor.textSecondary)
                    }
                }
                
                // Strategic Paths (Choices)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Твои ходы")
                        .font(.system(size: 10, weight: .semibold, design: .default))
                        .foregroundColor(MentorioColor.textSecondary)
                        .tracking(0.5)
                    
                    VStack(spacing: 8) {
                        ForEach(Array(choices.enumerated()), id: \.offset) { index, choice in
                            Button(action: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    viewModel.selectChoice(index, for: note.id)
                                }
                            }) {
                                HStack(spacing: 10) {
                                    Text(choice)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(MentorioColor.surfaceElevated)
                                    
                                    Spacer()
                                    
                                    Image(systemName: "arrow.right.circle.fill")
                                        .font(.system(size: 11))
                                        .foregroundColor(MentorioColor.surfaceElevated.opacity(0.82))
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(MentorioColor.accent)
                                .cornerRadius(9)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }
            }
            
        case .executing:
            EmptyView()
        }
    }
    
    // MARK: - Footer Action Zone (Bottom-Right)
    
    @ViewBuilder
    private func footerAction() -> some View {
        switch note.state {
        case .idle:
            // Light blue Transform button with lightning
            Button(action: {
                viewModel.startTransformation(for: note)
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Разобрать")
                        .font(.system(size: 11, weight: .semibold))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .foregroundColor(MentorioColor.accent)
                .background(MentorioColor.accentMuted)
                .cornerRadius(6)
            }
            .buttonStyle(PlainButtonStyle())
            
        case .analyzing:
            // Subtle gray pill badge
            HStack(spacing: 4) {
                Image(systemName: "hourglass.bottomhalf.filled")
                    .font(.system(size: 9, weight: .semibold))
                Text("Разбор")
                    .font(.system(size: 11, weight: .medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .foregroundColor(MentorioColor.textSecondary)
            .background(MentorioColor.surface)
            .cornerRadius(6)
            
        case .needsTopic(_):
            // Category selection badge
            HStack(spacing: 4) {
                Image(systemName: "tag.fill")
                    .font(.system(size: 9, weight: .semibold))
                Text("Выбрать тему")
                    .font(.system(size: 11, weight: .medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .foregroundColor(MentorioColor.accent)
            .background(MentorioColor.accentMuted)
            .cornerRadius(6)
            
        case .clarifying(_):
            // Clarification badge
            HStack(spacing: 4) {
                Image(systemName: "questionmark.circle.fill")
                    .font(.system(size: 9, weight: .semibold))
                Text("Ответ")
                    .font(.system(size: 11, weight: .medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .foregroundColor(MentorioColor.accent)
            .background(MentorioColor.accentMuted)
            .cornerRadius(6)
            
        case .hasTactics(_, _, _, let topics):
            // Context-aware badge based on topics
            if let topics = topics, !topics.isEmpty {
                // Show first topic with emoji
                let firstTopic = topics[0]
                let emoji = topicToBadge(firstTopic)
                HStack(spacing: 6) {
                    Text(emoji)
                        .font(.system(size: 12, weight: .semibold))
                    Text(firstTopic)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .foregroundColor(MentorioColor.accent)
                .background(MentorioColor.accentMuted)
                .cornerRadius(6)
            } else {
                // Fallback: generic ready badge
                HStack(spacing: 4) {
                    Image(systemName: "bolt.circle.fill")
                        .font(.system(size: 9, weight: .semibold))
                    Text("Ждет действий")
                        .font(.system(size: 11, weight: .semibold))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .foregroundColor(MentorioColor.accent)
                .background(MentorioColor.accentMuted)
                .cornerRadius(6)
            }
            
        case .executing:
            // Acting badge
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 9, weight: .semibold))
                Text("Шаг готов")
                    .font(.system(size: 11, weight: .semibold))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .foregroundColor(MentorioColor.accent)
            .background(MentorioColor.accentMuted)
            .cornerRadius(6)
        }
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        MentorioColor.background.ignoresSafeArea()
        
        VStack(spacing: 16) {
            let noteID = UUID()
            NoteCardView(
                note: BraindumpNote(
                    id: noteID,
                    text: "I want to learn FL Studio but keep procrastinating",
                    createdAt: Date().addingTimeInterval(-3600)
                ),
                viewModel: makePreviewViewModel(),
                focusedNoteID: noteID,
                onAnswerFieldFocus: nil
            )
            
            Spacer()
        }
        .padding(16)
    }
}
