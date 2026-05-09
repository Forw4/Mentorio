import SwiftUI

struct ArchiveView: View {
    @EnvironmentObject var viewModel: MentorioViewModel

    @State private var isExpanded = false

    var body: some View {
        NavigationStack {
            ZStack {
                MentorioTheme.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        // Header
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Essential Space")
                                .font(.largeTitle.bold())
                                .fontDesign(.serif)
                                .foregroundStyle(MentorioTheme.primaryText)

                            Text("Your archive of real wins.")
                                .font(.subheadline)
                                .foregroundStyle(MentorioTheme.secondaryText)
                        }

                        // Monthly summary
                        if !viewModel.archivedNotes.isEmpty {
                            monthlySummaryCard
                        }

                        // Win cards grouped by day
                        if viewModel.archivedNotes.isEmpty {
                            emptyState
                        } else {
                            dayGroupedCards
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 120)
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Rectangle()
                .fill(Color.mentorioPeach.opacity(0.15))
                .frame(height: 1)
                .padding(.vertical, 8)

            Text("No completed actions yet.")
                .font(.subheadline)
                .foregroundStyle(MentorioTheme.secondaryText)

            Text("Start a braindump on the Focus tab.")
                .font(.caption)
                .foregroundStyle(MentorioTheme.secondaryText.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    // MARK: - Monthly Summary Card

    private var monthlySummaryCard: some View {
        let stats = computeMonthlyStats()

        return VStack(alignment: .leading, spacing: 0) {
            // Header row (always visible)
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Text("\(stats.monthName) · \(stats.totalWins) \(winsWord(stats.totalWins)) · \(stats.daysWithActions) \(daysWord(stats.daysWithActions)) с действиями")
                        .font(.headline.weight(.bold))
                        .fontDesign(.serif)
                        .foregroundStyle(MentorioTheme.primaryText)

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.mentorioPeach)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            // Subtitle (always visible)
            Text(stats.ratioPhrase)
                .font(.subheadline)
                .foregroundStyle(MentorioTheme.secondaryText)
                .padding(.horizontal, 16)
                .padding(.bottom, isExpanded ? 8 : 14)

            // Expanded content
            if isExpanded {
                expandedContent(stats: stats)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(MentorioTheme.card)
                .overlay(
                    HStack(spacing: 0) {
                        Rectangle()
                            .fill(Color.mentorioPeach)
                            .frame(width: 2)
                        Spacer()
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(MentorioTheme.stroke, lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    private func expandedContent(stats: MonthlyStats) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
                .background(MentorioTheme.stroke)
                .padding(.horizontal, 16)

            // Observations
            VStack(alignment: .leading, spacing: 8) {
                if stats.longestStreak > 0 {
                    Text("Самый долгий streak — \(stats.longestStreak) \(daysWord(stats.longestStreak)) подряд.")
                        .font(.subheadline)
                        .foregroundStyle(MentorioTheme.secondaryText)
                }

                if let mostActiveDay = stats.mostActiveWeekday {
                    Text("Твой самый продуктивный день недели: \(mostActiveDay).")
                        .font(.subheadline)
                        .foregroundStyle(MentorioTheme.secondaryText)
                }
            }
            .padding(.horizontal, 16)

            // Activity dots
            activityDotsView(activityDots: stats.activityDots)
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
        }
    }

    // MARK: - Activity Dots

    private func activityDotsView(activityDots: [MonthlyStats.DayDot?]) -> some View {
        let columns = 7 // days per week row
        let rows = stride(from: 0, to: activityDots.count, by: columns).map { start in
            Array(activityDots[start..<min(start + columns, activityDots.count)])
        }

        return VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, week in
                HStack(spacing: 6) {
                    ForEach(Array(week.enumerated()), id: \.offset) { _, dot in
                        if let dot = dot {
                            ZStack {
                                Circle()
                                    .fill(dot.isActive ? Color.mentorioPeach : Color(white: 0.2))
                                    .frame(width: 16, height: 16)
                                
                                if dot.isToday {
                                    Text("\(dot.day)")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(dot.isActive ? MentorioTheme.background : .white)
                                }
                            }
                        } else {
                            // Empty padding for true calendar layout
                            Spacer()
                                .frame(width: 16, height: 16)
                        }
                    }
                    Spacer()
                }
            }
        }
    }

    // MARK: - Day Grouped Cards

    private var dayGroupedCards: some View {
        let groups = groupByDay(viewModel.archivedNotes)

        return ForEach(groups, id: \.title) { group in
            VStack(alignment: .leading, spacing: 10) {
                // Section header
                HStack {
                    Text(group.title)
                        .font(.system(size: 12, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(Color.mentorioPeach)

                    Spacer()

                    Text("\(group.notes.count) \(winsWord(group.notes.count).uppercased())")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(MentorioTheme.secondaryText)
                }

                // Win cards
                ForEach(group.notes) { note in
                    WinCard(note: note, onDelete: {
                        viewModel.permanentlyDeleteNote(id: note.id)
                    })
                }
            }
        }
    }

    // MARK: - Day Grouping Logic

    private struct DayGroup {
        let title: String
        let notes: [BraindumpNote]
    }

    private func groupByDay(_ notes: [BraindumpNote]) -> [DayGroup] {
        let calendar = Calendar.current
        let now = Date()

        var groups: [String: [BraindumpNote]] = [:]
        var order: [String] = []

        for note in notes.sorted(by: { ($0.completedAt ?? $0.createdAt) > ($1.completedAt ?? $1.createdAt) }) {
            let date = note.completedAt ?? note.createdAt
            let title: String

            if calendar.isDateInToday(date) {
                title = "TODAY"
            } else if calendar.isDateInYesterday(date) {
                title = "YESTERDAY"
            } else if let daysAgo = calendar.dateComponents([.day], from: date, to: now).day, daysAgo < 7 {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US")
                formatter.dateFormat = "EEE, d MMM"
                title = formatter.string(from: date).uppercased()
            } else {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US")
                formatter.dateFormat = "MMM d"
                title = formatter.string(from: date).uppercased()
            }

            if groups[title] == nil {
                order.append(title)
            }
            groups[title, default: []].append(note)
        }

        return order.map { DayGroup(title: $0, notes: groups[$0] ?? []) }
    }

    // MARK: - Monthly Stats

    private struct MonthlyStats {
        struct DayDot {
            let day: Int
            let isActive: Bool
            let isToday: Bool
        }
        
        let monthName: String
        let totalWins: Int
        let daysWithActions: Int
        let ratioPhrase: String
        let longestStreak: Int
        let topTheme: String?
        let topThemeCount: Int
        let mostActiveWeekday: String?
        let inactiveDays: Int
        let activityDots: [DayDot?] // one per cell, nil for padding
    }

    private func computeMonthlyStats() -> MonthlyStats {
        let calendar = Calendar.current
        let now = Date()
        let month = calendar.component(.month, from: now)
        let year = calendar.component(.year, from: now)

        let monthFormatter = DateFormatter()
        monthFormatter.locale = Locale(identifier: "ru_RU")
        monthFormatter.dateFormat = "LLLL"
        let monthName = monthFormatter.string(from: now).capitalized

        // Filter notes for current month
        let monthNotes = viewModel.archivedNotes.filter { note in
            let date = note.completedAt ?? note.createdAt
            return calendar.component(.month, from: date) == month
                && calendar.component(.year, from: date) == year
        }

        let totalWins = monthNotes.count

        // Top theme from highlights
        var themeCounts: [String: Int] = [:]
        for note in monthNotes {
            if let highlight = note.storedHighlight, !highlight.isEmpty {
                // Use first few words as a rough theme
                let words = highlight.split(separator: " ").prefix(3).joined(separator: " ")
                themeCounts[words, default: 0] += 1
            }
        }
        let topThemeEntry = themeCounts.max(by: { $0.value < $1.value })
        let topTheme = topThemeEntry.map { $0.key.lowercased() }
        let topThemeCount = topThemeEntry?.value ?? 0

        // Most active weekday
        var weekdayCounts: [Int: Int] = [:]
        for note in monthNotes {
            let date = note.completedAt ?? note.createdAt
            let weekday = calendar.component(.weekday, from: date)
            weekdayCounts[weekday, default: 0] += 1
        }
        let topWeekday = weekdayCounts.max(by: { $0.value < $1.value })?.key
        let weekdayFormatter = DateFormatter()
        weekdayFormatter.locale = Locale(identifier: "ru_RU")
        let weekdayNames = weekdayFormatter.weekdaySymbols ?? []
        let mostActiveWeekday = topWeekday.flatMap { wd in
            wd > 0 && wd <= weekdayNames.count ? weekdayNames[wd - 1] : nil
        }

        // Activity dots with calendar padding
        let daysInMonth = calendar.range(of: .day, in: .month, for: now)?.count ?? 30
        var activeDays = Set<Int>()
        for note in monthNotes {
            let date = note.completedAt ?? note.createdAt
            let day = calendar.component(.day, from: date)
            activeDays.insert(day)
        }
        
        var components = calendar.dateComponents([.year, .month], from: now)
        components.day = 1
        let firstDayOfMonth = calendar.date(from: components) ?? now
        let weekdayOfFirstDay = calendar.component(.weekday, from: firstDayOfMonth)
        
        let firstWeekday = calendar.firstWeekday
        var leadingPaddingCount = weekdayOfFirstDay - firstWeekday
        if leadingPaddingCount < 0 {
            leadingPaddingCount += 7
        }
        
        let today = calendar.component(.day, from: now)
        var activityDots: [MonthlyStats.DayDot?] = Array(repeating: nil, count: leadingPaddingCount)
        
        let dots = (1...daysInMonth).map { day in
            MonthlyStats.DayDot(day: day, isActive: activeDays.contains(day), isToday: day == today)
        }
        activityDots.append(contentsOf: dots)
        
        let remainder = activityDots.count % 7
        if remainder > 0 {
            activityDots.append(contentsOf: Array(repeating: nil, count: 7 - remainder))
        }

        let inactiveDays = (1...today).filter { !activeDays.contains($0) }.count
        let daysWithActions = activeDays.count
        
        // Ratio logic
        let passedDays = max(1, today)
        let ratio = Double(daysWithActions) / Double(passedDays)
        let ratioPhrase: String
        
        if ratio == 0 {
            ratioPhrase = "В этом месяце ты почти не заходил — уже важное наблюдение."
        } else if ratio < 0.25 {
            ratioPhrase = "Ты делал шаги редко — система пока не встроилась в рутину."
        } else if ratio < 0.45 {
            ratioPhrase = "Ты не каждый день действовал, но регулярно к этому возвращался."
        } else if ratio <= 0.55 {
            ratioPhrase = "Половину месяца ты выбирал действовать, а не откладывать."
        } else if ratio < 0.8 {
            ratioPhrase = "Чаще всего в этом месяце ты действовал."
        } else if ratio < 1.0 {
            ratioPhrase = "Этот месяц почти целиком прошёл под знаком “сделано, а не отложено”."
        } else {
            ratioPhrase = "Каждый день этого месяца ты делал хотя бы один шаг — молодец!"
        }
        
        // Streak logic
        var longestStreak = 0
        var currentStreak = 0
        for day in 1...today {
            if activeDays.contains(day) {
                currentStreak += 1
                if currentStreak > longestStreak {
                    longestStreak = currentStreak
                }
            } else {
                currentStreak = 0
            }
        }

        return MonthlyStats(
            monthName: monthName,
            totalWins: totalWins,
            daysWithActions: daysWithActions,
            ratioPhrase: ratioPhrase,
            longestStreak: longestStreak,
            topTheme: totalWins > 0 ? topTheme : nil,
            topThemeCount: topThemeCount,
            mostActiveWeekday: totalWins > 0 ? mostActiveWeekday : nil,
            inactiveDays: inactiveDays,
            activityDots: activityDots
        )
    }

    // MARK: - Localization Helpers

    private func winsWord(_ count: Int) -> String {
        let mod10 = count % 10
        let mod100 = count % 100
        if mod10 == 1 && mod100 != 11 { return "win" }
        return "wins"
    }

    private func daysWord(_ count: Int) -> String {
        let mod10 = count % 10
        let mod100 = count % 100
        if mod10 == 1 && mod100 != 11 { return "день" }
        if mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14) { return "дня" }
        return "дней"
    }
}

// MARK: - Win Card

private struct WinCard: View {
    @Bindable var note: BraindumpNote
    let onDelete: () -> Void

    @State private var showDeleteConfirmation = false

    private var actionText: String {
        note.finalAction ?? note.storedAction ?? note.text
    }

    private var highlightText: String {
        note.storedHighlight ?? ""
    }

    private var timeText: String {
        WinCard.timeFormatter.string(from: note.completedAt ?? note.createdAt)
    }

    private var emojiText: String {
        note.actionEmoji ?? "⚡"
    }

    private var hasPhoto: Bool {
        note.photoData != nil
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // Thumbnail: photo or emoji
            thumbnailView
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            // Text content
            VStack(alignment: .leading, spacing: 4) {
                Text(actionText)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(MentorioTheme.primaryText)
                    .lineLimit(2)

                if !highlightText.isEmpty {
                    Text(highlightText)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(MentorioTheme.secondaryText)
                        .italic()
                        .lineLimit(2)
                }

                Text(timeText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.mentorioPeach)
            }

            Spacer(minLength: 4)

            // Context menu
            Menu {
                ShareLink(
                    item: "Я сделал: \(actionText) ✅\n— Mentorio",
                    subject: Text("Моя победа"),
                    message: Text(actionText)
                ) {
                    Label("Поделиться", systemImage: "square.and.arrow.up")
                }

                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Label("Удалить", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(MentorioTheme.secondaryText)
                    .frame(width: 24, height: 28)
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(red: 0.051, green: 0.051, blue: 0.051))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.05), lineWidth: 1)
                )
        )
        .alert("Удалить победу?", isPresented: $showDeleteConfirmation) {
            Button("Удалить", role: .destructive) {
                onDelete()
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Эту победу нельзя будет восстановить.")
        }
    }

    @ViewBuilder
    private var thumbnailView: some View {
        if hasPhoto, let data = note.photoData, let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .saturation(0.7)
        } else {
            ZStack {
                Color(white: 0.1)
                Text(emojiText)
                    .font(.title)
            }
        }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

// MARK: - Preview

#Preview {
    ArchiveView()
        .environmentObject(makePreviewViewModel())
        .preferredColorScheme(.dark)
}
