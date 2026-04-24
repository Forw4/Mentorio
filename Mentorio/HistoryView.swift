//
//  HistoryView.swift
//  Mentorio
//
 
import Foundation
import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var viewModel: MentorioViewModel
    let archivedNotes: [BraindumpNote]
    @State private var selectedNote: BraindumpNote? = nil
    @State private var showDetailView = false

    private var weeklyDigest: ReviewDigest? {
        SummaryDigestService.weeklyDigest(from: viewModel.notes + viewModel.archivedNotes)
    }
    
    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                // Background
                MentorioColor.paper
                    .ignoresSafeArea()
                
                if archivedNotes.isEmpty {
                    List {
                        Section {
                            WeeklyReviewCardView(digest: weeklyDigest)
                                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)

                            Text("Заверши хотя бы одно действие, чтобы пополнить архив")
                                .foregroundStyle(.secondary)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        } header: {
                            VStack(spacing: 8) {
                                Text("Архив")
                                    .font(MentorioType.title)
                                    .foregroundColor(MentorioColor.charcoal)
                                Text("История действий")
                                    .font(MentorioType.caption)
                                    .foregroundColor(MentorioColor.mentorGray)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                } else {
                    List {
                        Section {
                            WeeklyReviewCardView(digest: weeklyDigest)
                                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        }

                        Section {
                            ForEach(archivedNotes) { note in
                                NavigationLink(destination: NoteDetailView(note: note)) {
                                    ArchiveCardView(note: note)
                                        .padding(.vertical, 6)
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button("Удалить", role: .destructive) {
                                        viewModel.deleteNote(id: note.id)
                                    }
                                }
                                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                            }
                        } header: {
                            VStack(spacing: 8) {
                                Text("Архив")
                                    .font(MentorioType.title)
                                    .foregroundColor(MentorioColor.charcoal)
                                Text("История действий")
                                    .font(MentorioType.caption)
                                    .foregroundColor(MentorioColor.mentorGray)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(MentorioColor.paper)
        }
    }
}

// MARK: - Archive Card View

struct ArchiveCardView: View {
    let note: BraindumpNote
    
    var formattedDate: String {
        let calendar = Calendar.current
        
        if calendar.isDateInToday(note.completedAt ?? Date()) {
            return "Сегодня"
        } else if calendar.isDateInYesterday(note.completedAt ?? Date()) {
            return "Вчера"
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            return formatter.string(from: note.completedAt ?? Date())
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header with trophy and title
            HStack(spacing: 12) {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.yellow)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Действие зафиксировано")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(MentorioColor.accent)
                        .textCase(.uppercase)
                    
                    Text(note.text)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(MentorioColor.charcoal)
                        .lineLimit(2)
                }
                
                Spacer()
            }
            
            // Stats section
            VStack(alignment: .leading, spacing: 8) {
                if let choice = note.selectedChoice {
                    HStack(spacing: 8) {
                        Image(systemName: "lightbulb.fill")
                            .font(.system(size: 12))
                            .foregroundColor(MentorioColor.accent)
                        Text(choice)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(MentorioColor.charcoal)
                            .lineLimit(1)
                    }
                }
                
                if let action = note.finalAction {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(MentorioColor.accent)
                        Text(action)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(MentorioColor.charcoal)
                            .lineLimit(1)
                    }
                }
            }
            
            // Divider
            Divider()
                .padding(.vertical, 4)
            
            // Footer with date
            VStack(alignment: .leading, spacing: 8) {
                Text(formattedDate)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(MentorioColor.textSecondary)

                if let realityCheck = note.realityCheck {
                    Text(realityCheck.rawValue)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(MentorioColor.charcoal)
                } else if let completionProof = note.completionProof, !completionProof.isEmpty {
                    Text(completionProof)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(MentorioColor.charcoal)
                        .lineLimit(3)
                }
            }
        }
        .padding(16)
        .background(MentorioColor.surface)
        .cornerRadius(MentorioMetric.radiusM)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    MentorioColor.stroke,
                    lineWidth: 1
                )
        )
    }
}

struct WeeklyReviewCardView: View {
    let digest: ReviewDigest?
    @State private var isExpanded = false

    var body: some View {
        Button(action: {
            isExpanded.toggle()
        }) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(digest?.title ?? "Недельный обзор")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(MentorioColor.charcoal)
                    }

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(MentorioColor.accent)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .animation(.easeOut(duration: 0.16), value: isExpanded)
                }

                if let digest {
                    Text(digest.headline)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(MentorioColor.charcoal)
                        .fixedSize(horizontal: false, vertical: true)

                    if isExpanded {
                        VStack(alignment: .leading, spacing: 14) {
                            Text(digest.subtitle)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(MentorioColor.mentorGray)

                            ratioRow(easy: digest.easyPercentage, hard: digest.hardPercentage)

                            if !digest.topBlockers.isEmpty {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Топ блокеров")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(MentorioColor.mentorGray)

                                    ForEach(digest.topBlockers) { blocker in
                                        VStack(alignment: .leading, spacing: 4) {
                                            HStack {
                                                Text(blocker.title)
                                                    .font(.system(size: 14, weight: .semibold))
                                                    .foregroundColor(MentorioColor.charcoal)
                                                Spacer()
                                                Text("\(blocker.energyScore)")
                                                    .font(.system(size: 12, weight: .bold))
                                                    .foregroundColor(.red)
                                            }

                                            Text("сложно: \(blocker.hardWorkCount) · незавершено: \(blocker.unfinishedCount)")
                                                .font(.system(size: 12, weight: .regular))
                                                .foregroundColor(MentorioColor.mentorGray)
                                        }
                                        .padding(12)
                                        .background(MentorioColor.surface)
                                        .cornerRadius(12)
                                    }
                                }
                            }

                            Text(digest.supportingInsight)
                                .font(.system(size: 13, weight: .regular))
                                .foregroundColor(MentorioColor.mentorGray)
                                .fixedSize(horizontal: false, vertical: true)

                            Text("\(digest.totalCompleted) completed · \(digest.totalSkipped) skipped")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(MentorioColor.mentorGray)
                        }
                    }
                } else {
                    Text("Пока мало данных для weekly review. Заверши несколько задач, и здесь появится честная сводка по friction.")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(MentorioColor.mentorGray)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .buttonStyle(.plain)
        .padding(18)
        .background(
            LinearGradient(
                colors: [MentorioColor.surfaceElevated, MentorioColor.surface],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(MentorioColor.stroke, lineWidth: 1)
        )
        .cornerRadius(18)
    }

    private func ratioRow(easy: Int, hard: Int) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Оказалось проще")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(MentorioColor.mentorGray)
                Text("\(easy)%")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(MentorioColor.accent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Text("Пришлось попотеть")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(MentorioColor.mentorGray)
                Text("\(hard)%")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(MentorioColor.textPrimary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(MentorioColor.surface)
        .cornerRadius(14)
    }
}

#Preview {
    HistoryView(archivedNotes: [
        BraindumpNote(
            text: "Struggling with FL Studio workflow",
            isCompleted: true,
            selectedChoice: "Break down into steps",
            finalAction: "Watch 15-min FL Studio tutorial",
            completedAt: Date()
        )
    ])
    .environmentObject(makePreviewViewModel())
}
