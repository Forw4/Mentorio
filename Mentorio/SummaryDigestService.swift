//
//  SummaryDigestService.swift
//  Mentorio
//

import Foundation

struct TopBlocker: Identifiable {
    let id = UUID()
    let title: String
    let hardWorkCount: Int
    let unfinishedCount: Int

    var energyScore: Int {
        (hardWorkCount * 2) + unfinishedCount
    }
}

struct ReviewDigest {
    let title: String
    let subtitle: String
    let easyPercentage: Int
    let hardPercentage: Int
    let completionPercentage: Int
    let skipPercentage: Int
    let totalCompleted: Int
    let totalSkipped: Int
    let weekSpanText: String
    let headline: String
    let supportingInsight: String
    let topBlockers: [TopBlocker]
}

enum SummaryDigestService {
    static func weeklyDigest(from notes: [BraindumpNote]) -> ReviewDigest? {
        digest(from: notes, within: 7, title: "Недельный обзор", subtitle: "Последние 7 дней")
    }

    static func monthlyDigest(from notes: [BraindumpNote]) -> ReviewDigest? {
        digest(from: notes, within: 30, title: "Месячный обзор", subtitle: "Последние 30 дней")
    }

    private static func digest(from notes: [BraindumpNote], within days: Int, title: String, subtitle: String) -> ReviewDigest? {
        let calendar = Calendar.current
        let cutoff = calendar.date(byAdding: .day, value: -days, to: Date()) ?? Date.distantPast
        let scopedNotes = notes.filter { !$0.isInTrash && $0.deletedAt == nil && ($0.completedAt ?? $0.createdAt) >= cutoff }

        let completedNotes = scopedNotes.filter { $0.isCompleted }
        let skippedNotes = scopedNotes.filter { !$0.isCompleted }

        guard !scopedNotes.isEmpty else { return nil }

        let easyCount = completedNotes.filter { $0.realityCheck == .easy || $0.realityCheck == .effortless }.count
        let hardCount = completedNotes.filter { $0.realityCheck == .survival || $0.realityCheck == .hard }.count
        let totalRealityChecks = max(1, easyCount + hardCount)

        let easyPercentage = Int((Double(easyCount) / Double(totalRealityChecks)) * 100)
        let hardPercentage = Int((Double(hardCount) / Double(totalRealityChecks)) * 100)
        let completionPercentage = Int((Double(completedNotes.count) / Double(scopedNotes.count)) * 100)
        let skipPercentage = Int((Double(skippedNotes.count) / Double(scopedNotes.count)) * 100)

        let blockerStats = blockerCounts(from: scopedNotes)
        let topBlockers = blockerStats
            .sorted { $0.value.energyScore > $1.value.energyScore }
            .prefix(3)
            .map { TopBlocker(title: $0.key, hardWorkCount: $0.value.hardWorkCount, unfinishedCount: $0.value.unfinishedCount) }

        let headline = generateHeadline(
            easyPercentage: easyPercentage,
            hardPercentage: hardPercentage,
            completionPercentage: completionPercentage,
            skipPercentage: skipPercentage,
            sampleSize: scopedNotes.count,
            topBlockers: topBlockers
        )

        let supportingInsight = generateSupportingInsight(
            easyPercentage: easyPercentage,
            hardPercentage: hardPercentage,
            completionPercentage: completionPercentage,
            skipPercentage: skipPercentage,
            topBlockers: topBlockers
        )

        return ReviewDigest(
            title: title,
            subtitle: subtitle,
            easyPercentage: easyPercentage,
            hardPercentage: hardPercentage,
            completionPercentage: completionPercentage,
            skipPercentage: skipPercentage,
            totalCompleted: completedNotes.count,
            totalSkipped: skippedNotes.count,
            weekSpanText: "\(days) days",
            headline: headline,
            supportingInsight: supportingInsight,
            topBlockers: topBlockers
        )
    }

    private static func blockerCounts(from notes: [BraindumpNote]) -> [String: (hardWorkCount: Int, unfinishedCount: Int, energyScore: Int)] {
        var counts: [String: (hardWorkCount: Int, unfinishedCount: Int, energyScore: Int)] = [:]

        for note in notes {
            let theme = themeName(for: note)
            let existing = counts[theme] ?? (0, 0, 0)
            var updated = existing

            if note.realityCheck == .survival || note.realityCheck == .hard {
                updated.hardWorkCount += 1
            }

            if !note.isCompleted {
                updated.unfinishedCount += 1
            }

            updated.energyScore = (updated.hardWorkCount * 2) + updated.unfinishedCount
            counts[theme] = updated
        }

        return counts
    }

    private static func themeName(for note: BraindumpNote) -> String {
        if let selectedTopic = note.selectedTopic?.trimmingCharacters(in: .whitespacesAndNewlines), !selectedTopic.isEmpty {
            return selectedTopic
        }

        let text = note.text.lowercased()
        let themes: [(String, [String])] = [
            ("Жилье", ["квартир", "жиль", "аренд", "дом", "belgrad", "belgrade"]),
            ("Работа", ["работ", "job", "офис", "карьер", "дедлайн"]),
            ("Учеба", ["учеб", "study", "экзам", "препод", "курс"]),
            ("Музыка", ["музык", "бит", "fl studio", "трек", "звук"]),
            ("Язык", ["серб", "язык", "duolingo", "english", "language"]),
            ("Отношения", ["отнош", "друг", "общен", "конфликт", "семья"]),
            ("Деньги", ["деньг", "money", "доход", "бюджет", "оплат"])
        ]

        for (theme, keywords) in themes {
            if keywords.contains(where: { text.contains($0) }) {
                return theme
            }
        }

        return "Другое"
    }

    private static func generateHeadline(
        easyPercentage: Int,
        hardPercentage: Int,
        completionPercentage: Int,
        skipPercentage: Int,
        sampleSize: Int,
        topBlockers: [TopBlocker]
    ) -> String {
        if sampleSize < 3 {
            return "Мало данных для анализа твоих слабостей. Делай больше"
        }

        switch (completionPercentage, skipPercentage, hardPercentage, easyPercentage) {
        case (let completion, _, _, _) where completion < 50:
            if let top = topBlockers.first {
                return "Ожидал прорыв, получил провал. Главный разрыв ожидание/реальность — \(top.title)."
            }
            return "Ожидал прорыв, получил провал. Реальность: ты повторяешь те же слабые паттерны."
        case (_, let skip, _, _) where skip >= 30:
            if let top = topBlockers.first {
                return "Ожидал дисциплину, получил сливы. Точка разрыва — \(top.title)."
            }
            return "Ожидал дисциплину, получил сливы. Реальность: ты чаще уходишь, чем входишь в задачу."
        case (_, _, let hard, let easy) where hard > easy:
            if let top = topBlockers.first {
                return "Ожидал, что будет терпимо, но реальность жестче: \(top.title) забирает больше всего энергии."
            }
            return "Ожидал, что втянуться будет легче. Реальность: цена входа всё ещё высокая."
        default:
            if let top = topBlockers.first {
                return "Ожидал стабильность, но реальность упряма: \(top.title) всё ещё повторно тебя стопорит."
            }
            return "Ожидал, что саботаж ушел. Реальность: его след всё ещё заметен."
        }
    }

    private static func generateSupportingInsight(
        easyPercentage: Int,
        hardPercentage: Int,
        completionPercentage: Int,
        skipPercentage: Int,
        topBlockers: [TopBlocker]
    ) -> String {
        let blockersText = topBlockers.prefix(3).map { blocker in
            "\(blocker.title) — \(blocker.energyScore)"
        }.joined(separator: ", ")

        if skipPercentage >= 30 {
            return "Проблема не только в сложности. У тебя заметный провал на входе, и он повторяется по одним и тем же темам: \(blockersText)."
        }

        if hardPercentage > easyPercentage {
            return "Часть задач реальная, но ты слишком часто упираешься в сопротивление. Больше всего энергии жрут: \(blockersText)."
        }

        if completionPercentage >= 70 {
            return "Ты уже закрываешь задачи, но повторные стопоры остались. Главные блокеры сейчас: \(blockersText)."
        }

        return "У тебя есть движение, но ряд тем снова забирает силу. Top blockers: \(blockersText)."
    }
}
