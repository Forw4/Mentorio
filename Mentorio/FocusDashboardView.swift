import SwiftUI
import UIKit

extension UUID: @retroactive Identifiable {
    public var id: UUID { self }
}

struct FocusDashboardView: View {
    @ObservedObject var viewModel: MentorioViewModel
    @Binding var selectedTab: AppTab

    // Entry overlay
    @State private var isShowingEntry = false
    @AppStorage("shouldAutoOpenEntry") private var shouldAutoOpenEntry: Bool = false

    // Win state
    @State private var completedNoteID: UUID?

    // Settings
    @State private var showSettings = false

    // Calendar
    @State private var weekOffset: Int = 0
    @State private var selectedPastDate: Date? = nil

    // Hold mechanics (State 3)
    @State private var holdProgress: CGFloat = 0
    @State private var didFinishHold = false
    @State private var holdTimer: Timer? = nil

    // Elapsed timer (State 3)
    @State private var elapsedSeconds: Int = 0
    @State private var elapsedTimer: Timer? = nil

    // Blinking cursor (State 1)
    @State private var cursorVisible = true

    // Card press animation
    @State private var isCardPressed = false

    // MARK: - Computed Properties

    private var activeNote: BraindumpNote? {
        if let execId = viewModel.executingNoteId,
           let note = viewModel.notes.first(where: { $0.id == execId }),
           note.status == .active {
            return note
        }
        return viewModel.notes.first(where: {
            $0.status == .active && !$0.isCompleted && !$0.isInTrash
        })
    }

    var isFocusModeActive: Bool {
        activeNote != nil
    }

    private var lastWin: BraindumpNote? {
        viewModel.archivedNotes
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
            .first
    }

    private enum CardState: Equatable {
        case empty
        case ready
        case executing
    }

    private var cardState: CardState {
        if activeNote != nil { return .executing }
        if lastWin != nil { return .ready }
        return .empty
    }

    // Calendar helpers
    private var cal: Calendar { Calendar.current }
    private var today: Date { cal.startOfDay(for: Date()) }

    private func mondayOfWeek(offset: Int) -> Date {
        let weekday = cal.component(.weekday, from: today)
        let daysFromMonday = (weekday + 5) % 7
        let thisMonday = cal.date(byAdding: .day, value: -daysFromMonday, to: today)!
        return cal.date(byAdding: .weekOfYear, value: offset, to: thisMonday)!
    }

    private func winsForDate(_ date: Date) -> [BraindumpNote] {
        viewModel.archivedNotes.filter { note in
            guard let completedAt = note.completedAt else { return false }
            return cal.isDate(completedAt, inSameDayAs: date)
        }
    }

    private var currentStreak: Int {
        var streak = 0
        var checkDate = today
        if winsForDate(checkDate).isEmpty {
            checkDate = cal.date(byAdding: .day, value: -1, to: checkDate)!
        }
        while !winsForDate(checkDate).isEmpty {
            streak += 1
            checkDate = cal.date(byAdding: .day, value: -1, to: checkDate)!
        }
        return streak
    }

    private var elapsedFormatted: String {
        let m = elapsedSeconds / 60
        if m > 0 { return "\(m) мин" }
        return "\(elapsedSeconds) сек"
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            MentorioTheme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header (Stoic-style)
                headerRow
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                // Week Calendar (Stoic-style)
                weekCalendarSection
                    .padding(.top, 14)
                    .padding(.bottom, 10)

                // Content area
                if let pastDate = selectedPastDate {
                    pastDayView(for: pastDate)
                        .transition(.opacity)
                } else {
                    centralCard
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                        .padding(.bottom, 16)
                        .safeAreaPadding(.bottom, 4)
                        .transition(.opacity)
                }
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: selectedPastDate == nil)
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: cardState)
        .fullScreenCover(item: $completedNoteID) { noteID in
            WinStateView(
                viewModel: viewModel,
                noteID: noteID,
                onToArchive: {
                    viewModel.archiveNote(id: noteID)
                    viewModel.executingNoteId = nil
                    completedNoteID = nil
                    selectedTab = .archive
                }
            )
        }
        .fullScreenCover(isPresented: $isShowingEntry) {
            EntryOverlayView(
                viewModel: viewModel,
                isPresented: $isShowingEntry
            )
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(viewModel)
        }
        .onAppear {
            if shouldAutoOpenEntry {
                shouldAutoOpenEntry = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    isShowingEntry = true
                }
            }
            if cardState == .executing, let note = activeNote {
                startElapsedTimer(from: note)
            }
        }
        .onDisappear {
            elapsedTimer?.invalidate()
            holdTimer?.invalidate()
        }
        .onChange(of: cardState) { _, newValue in
            if newValue == .executing, let note = activeNote {
                startElapsedTimer(from: note)
            } else if newValue != .executing {
                elapsedTimer?.invalidate()
            }
        }
    }

    // MARK: - Header (Stoic-style)

    private var headerRow: some View {
        ZStack {
            // Center: app name
            Text("mentorio.")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(MentorioTheme.primaryText)

            HStack {
                // Left: streak pill
                HStack(spacing: 5) {
                    Image(systemName: "flame")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                    Text("\(currentStreak)")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.1))
                )

                Spacer()

                // Right: settings (person icon like Stoic)
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Week Calendar (Stoic-style scrollable)

    private var weekCalendarSection: some View {
        let monday = mondayOfWeek(offset: weekOffset)
        let dayNames = ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]

        return HStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { index in
                let dayDate = cal.date(byAdding: .day, value: index, to: monday)!
                let dayNumber = cal.component(.day, from: dayDate)
                let isToday = cal.isDate(dayDate, inSameDayAs: today)
                let isFuture = dayDate > today
                let hasWin = !winsForDate(dayDate).isEmpty
                let isSelected = {
                    if let pastDate = selectedPastDate {
                        return cal.isDate(dayDate, inSameDayAs: pastDate)
                    }
                    return isToday && selectedPastDate == nil
                }()

                Button {
                    handleDayTap(date: dayDate, isToday: isToday, isFuture: isFuture)
                } label: {
                    VStack(spacing: 6) {
                        Text(dayNames[index])
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(
                                isFuture
                                    ? .white.opacity(0.2)
                                    : .white.opacity(0.45)
                            )

                        ZStack {
                            if isToday && isSelected {
                                Circle()
                                    .fill(.white)
                                    .frame(width: 36, height: 36)
                            } else if isSelected {
                                Circle()
                                    .fill(Color.white.opacity(0.15))
                                    .frame(width: 36, height: 36)
                            } else if hasWin {
                                Circle()
                                    .stroke(MentorioTheme.accent.opacity(0.5), lineWidth: 1.5)
                                    .frame(width: 36, height: 36)
                            }

                            Text("\(dayNumber)")
                                .font(.system(size: 15, weight: isToday ? .bold : .regular))
                                .foregroundStyle(
                                    isToday && isSelected
                                        ? .black
                                        : isFuture
                                            ? .white.opacity(0.2)
                                            : .white.opacity(0.85)
                                )
                        }
                        .frame(width: 36, height: 36)
                    }
                }
                .buttonStyle(.plain)
                .disabled(isFuture)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 40, coordinateSpace: .local)
                .onEnded { value in
                    if value.translation.width < -50 {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            weekOffset = min(weekOffset + 1, 0)
                            selectedPastDate = nil
                        }
                    } else if value.translation.width > 50 {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            weekOffset = max(weekOffset - 1, -12)
                            selectedPastDate = nil
                        }
                    }
                }
        )
    }

    private func handleDayTap(date: Date, isToday: Bool, isFuture: Bool) {
        guard !isFuture else { return }

        if isToday {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedPastDate = nil
            }
            if cardState != .executing {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isShowingEntry = true
                }
            }
        } else {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedPastDate = date
            }
        }
    }

    // MARK: - Central Card

    private var centralCard: some View {
        Group {
            switch cardState {
            case .empty:
                emptyStateContent
            case .ready:
                readyStateContent
            case .executing:
                executingStateContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color(red: 0.05, green: 0.05, blue: 0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color.mentorioPeach.opacity(0.12), lineWidth: 1)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .scaleEffect(isCardPressed ? 0.98 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isCardPressed)
        .onTapGesture {
            guard cardState != .executing else { return }
            isCardPressed = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                isCardPressed = false
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                isShowingEntry = true
            }
        }
    }

    // MARK: - State 1: Empty

    private var emptyStateContent: some View {
        VStack(spacing: 16) {
            Spacer()

            Text("MENTORIO")
                .font(.system(size: 11, weight: .heavy))
                .tracking(4)
                .foregroundStyle(MentorioTheme.accent.opacity(0.6))

            HStack(spacing: 0) {
                Text("Что мешает прямо сейчас?")
                    .font(.system(size: 22, weight: .semibold, design: .serif))
                    .foregroundStyle(MentorioTheme.primaryText)

                Text("|")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(MentorioTheme.accent)
                    .opacity(cursorVisible ? 1 : 0)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                            cursorVisible = false
                        }
                    }
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)

            Text("тап чтобы начать")
                .font(.system(size: 12))
                .foregroundStyle(MentorioTheme.secondaryText.opacity(0.5))

            Spacer()
        }
        .padding(24)
    }

    // MARK: - State 2: Ready (has history)

    private var readyStateContent: some View {
        VStack(spacing: 16) {
            Spacer()

            if let highlight = lastWin?.storedHighlight, !highlight.isEmpty {
                Text(highlight)
                    .font(.system(size: 14, weight: .regular, design: .serif))
                    .italic()
                    .foregroundStyle(MentorioTheme.secondaryText.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .lineLimit(3)
            }

            Text("Что мешает сегодня?")
                .font(.system(size: 22, weight: .semibold, design: .serif))
                .foregroundStyle(MentorioTheme.primaryText)
                .multilineTextAlignment(.center)

            if let completedAt = lastWin?.completedAt {
                Text("Последняя победа: \(relativeDate(completedAt))")
                    .font(.system(size: 12))
                    .foregroundStyle(MentorioTheme.accent.opacity(0.4))
            }

            Spacer()
        }
        .padding(24)
    }

    // MARK: - State 3: Executing

    private var executingStateContent: some View {
        let note = activeNote

        return VStack(spacing: 0) {
            // Top: elapsed time
            HStack {
                Spacer()
                HStack(spacing: 5) {
                    Circle()
                        .fill(MentorioTheme.accent.opacity(0.6))
                        .frame(width: 5, height: 5)
                    Text(elapsedFormatted)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.3))
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)

            Spacer()

            // Braindump echo
            if let text = note?.text {
                Text(text)
                    .font(.system(size: 13, weight: .regular, design: .serif))
                    .italic()
                    .foregroundStyle(.white.opacity(0.25))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, 24)
            }

            // Divider
            Rectangle()
                .fill(MentorioTheme.stroke)
                .frame(height: 0.5)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)

            // Highlight
            if let highlight = note?.storedHighlight, !highlight.isEmpty {
                Text(highlight)
                    .font(.system(size: 14, weight: .regular, design: .serif))
                    .foregroundStyle(MentorioTheme.accent.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)
            }

            // Action
            HStack(spacing: 8) {
                Text(note?.actionEmoji ?? "⚡")
                    .font(.system(size: 28))
                Text(note?.finalAction ?? note?.storedAction ?? "")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 24)

            Text("~15 мин")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.25))
                .padding(.top, 8)

            Spacer()

            // Hold button
            holdButton
                .padding(.bottom, 12)

            // Postpone
            Button {
                if let note = activeNote {
                    viewModel.continueWithNextStep(for: note.id)
                }
            } label: {
                Text("отложить")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.18))
            }
            .buttonStyle(.plain)
            .padding(.bottom, 20)
        }
    }

    // MARK: - Hold Button

    private var holdButton: some View {
        ZStack {
            // Ambient glow
            Circle()
                .fill(MentorioTheme.accent.opacity(holdProgress > 0 ? 0.15 : 0.03))
                .frame(width: 110, height: 110)
                .scaleEffect(1.0 + holdProgress * 0.15)

            // Track
            Circle()
                .stroke(.white.opacity(0.08), lineWidth: 3)
                .frame(width: 80, height: 80)

            // Progress ring
            Circle()
                .trim(from: 0, to: holdProgress)
                .stroke(
                    MentorioTheme.accent,
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .frame(width: 80, height: 80)

            Text("Hold")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(holdProgress > 0 ? MentorioTheme.accent : .white.opacity(0.6))
        }
        .frame(width: 120, height: 120)
        .contentShape(Circle())
        .onLongPressGesture(minimumDuration: 3.0, maximumDistance: 20, pressing: { pressing in
            if pressing { startHold() } else { cancelHold() }
        }, perform: {
            finishHold()
        })
    }

    // MARK: - Hold Mechanics

    private func startHold() {
        didFinishHold = false
        holdProgress = 0

        let gen = UIImpactFeedbackGenerator(style: .light)
        gen.prepare(); gen.impactOccurred()

        withAnimation(.linear(duration: 3.0)) {
            holdProgress = 1
        }

        var secs = 0
        holdTimer?.invalidate()
        holdTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            secs += 1
            if secs == 1 {
                let g = UIImpactFeedbackGenerator(style: .medium); g.prepare(); g.impactOccurred()
            } else if secs == 2 {
                let g = UIImpactFeedbackGenerator(style: .rigid); g.prepare(); g.impactOccurred()
            }
        }
    }

    private func cancelHold() {
        holdTimer?.invalidate(); holdTimer = nil
        if !didFinishHold {
            withAnimation(.easeOut(duration: 0.3)) {
                holdProgress = 0
            }
        }
    }

    private func finishHold() {
        holdTimer?.invalidate(); holdTimer = nil
        let gen = UINotificationFeedbackGenerator(); gen.prepare(); gen.notificationOccurred(.success)
        didFinishHold = true
        holdProgress = 1

        guard let note = activeNote else { return }
        completedNoteID = note.id
    }

    // MARK: - Elapsed Timer

    private func startElapsedTimer(from note: BraindumpNote) {
        if let accepted = note.acceptedAt {
            elapsedSeconds = max(0, Int(Date().timeIntervalSince(accepted)))
        }
        elapsedTimer?.invalidate()
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            elapsedSeconds += 1
        }
    }

    // MARK: - Past Day View

    private func pastDayView(for date: Date) -> some View {
        let wins = winsForDate(date)
        let topWin = wins.sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }.first

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "ru_RU")
        dateFormatter.dateFormat = "d MMMM"

        return VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 16) {
                    // Date
                    Text(dateFormatter.string(from: date))
                        .font(.system(size: 28, weight: .bold, design: .serif))
                        .foregroundStyle(MentorioTheme.primaryText)
                        .padding(.top, 32)

                    if let win = topWin {
                        // Highlight
                        if let highlight = win.storedHighlight, !highlight.isEmpty {
                            Text(highlight)
                                .font(.system(size: 15, weight: .regular, design: .serif))
                                .italic()
                                .foregroundStyle(MentorioTheme.secondaryText)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 28)
                        }

                        // Action
                        HStack(spacing: 8) {
                            Text(win.actionEmoji ?? "⚡")
                                .font(.title2)
                            Text(win.finalAction ?? win.storedAction ?? win.text)
                                .font(.headline.weight(.bold))
                                .foregroundStyle(MentorioTheme.primaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.horizontal, 28)
                        .padding(.top, 8)

                        // Photo
                        if let photoData = win.photoData, let uiImage = UIImage(data: photoData) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(maxHeight: 220)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .padding(.horizontal, 28)
                                .padding(.top, 8)
                        }

                        // Reflection
                        if let reflection = win.userClarification, !reflection.isEmpty {
                            Text(reflection)
                                .font(.body)
                                .foregroundStyle(MentorioTheme.secondaryText.opacity(0.8))
                                .padding(.horizontal, 28)
                                .padding(.top, 8)
                        }

                        // Extra wins count
                        if wins.count > 1 {
                            Text("+\(wins.count - 1) ещё")
                                .font(.system(size: 12))
                                .foregroundStyle(MentorioTheme.accent.opacity(0.5))
                                .padding(.top, 8)
                        }

                    } else {
                        // No wins
                        Text("В этот день шагов не было")
                            .font(.subheadline)
                            .foregroundStyle(MentorioTheme.secondaryText)
                            .padding(.top, 16)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)

            Spacer(minLength: 0)

            // Back button
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectedPastDate = nil
                    weekOffset = 0
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Сегодня")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(MentorioTheme.accent)
                .padding(.vertical, 10)
                .padding(.horizontal, 20)
                .background(
                    Capsule()
                        .fill(MentorioTheme.accent.opacity(0.12))
                )
            }
            .buttonStyle(.plain)
            .padding(.bottom, 16)
            .safeAreaPadding(.bottom, 8)
        }
    }

    // MARK: - Helpers

    private func relativeDate(_ date: Date) -> String {
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: date), to: today).day ?? 0
        switch days {
        case 0: return "сегодня"
        case 1: return "вчера"
        default:
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "ru_RU")
            formatter.dateFormat = "d MMM"
            return formatter.string(from: date)
        }
    }
}

#Preview {
    FocusDashboardView(viewModel: makePreviewViewModel(), selectedTab: .constant(.focus))
        .preferredColorScheme(.dark)
}
