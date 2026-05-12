//
//  DiagnosticsView.swift
//  Mentorio
//

import SwiftUI
import UserNotifications
import UIKit

struct DiagnosticsView: View {

    // MARK: - Event Filter

    private enum EventLogFilter: String, CaseIterable, Identifiable {
        case all, product, debug
        var id: String { rawValue }
        var title: String {
            switch self {
            case .all:     return "Все"
            case .product: return "Product"
            case .debug:   return "Debug"
            }
        }
        var analyticsChannel: String? {
            switch self {
            case .all:     return nil
            case .product: return "product"
            case .debug:   return "debug"
            }
        }
    }

    // MARK: - Funnel

    private struct Funnel {
        let braindumps: Int
        let mirrors: Int
        let accepted: Int
        let started: Int
        let completed: Int
        let mirrorRate: Double?
        let acceptRate: Double?
        let startRate: Double?
        let doneRate: Double?
        let realityRate: Double?
        let avgAcceptSec: TimeInterval?
        let avgDoneSec: TimeInterval?

        static let empty = Funnel(
            braindumps: 0, mirrors: 0, accepted: 0,
            started: 0, completed: 0,
            mirrorRate: nil, acceptRate: nil,
            startRate: nil, doneRate: nil, realityRate: nil,
            avgAcceptSec: nil, avgDoneSec: nil
        )

        /// Понятное summary для главной плашки
        var headline: String {
            if braindumps == 0 { return "Ещё не было ни одного брейндампа" }
            if completed > 0 {
                return "\(completed) из \(braindumps) брейндампов привели к выполненному шагу"
            }
            if started > 0 {
                return "\(started) человек взяли шаг — ещё никто не завершил"
            }
            if accepted > 0 {
                return "\(accepted) шагов принято, никто ещё не начинал выполнять"
            }
            return "\(braindumps) брейндампов — шагов пока не принято"
        }

        var avgAcceptLabel: String? {
            guard let t = avgAcceptSec else { return nil }
            return "В среднем \(fmtDuration(t)) от мысли до принятия шага"
        }

        var avgDoneLabel: String? {
            guard let t = avgDoneSec else { return nil }
            return "В среднем \(fmtDuration(t)) от мысли до выполнения"
        }

        private func fmtDuration(_ t: TimeInterval) -> String {
            let s = Int(t.rounded())
            let m = s / 60
            let sec = s % 60
            if m == 0 { return "\(sec) сек" }
            if sec == 0 { return "\(m) мин" }
            return "\(m) мин \(sec) сек"
        }
    }

    // MARK: - State

    @EnvironmentObject var viewModel: MentorioViewModel
    @State private var analyticsEvents: [AnalyticsEventSnapshot] = []
    @State private var notifications: [NotificationDebugItem] = []
    @State private var authStatus: UNAuthorizationStatus = .notDetermined
    @State private var funnel: Funnel = .empty
    @State private var eventFilter: EventLogFilter = .all
    @State private var isWipingData = false
    @State private var copyStatus: String? = nil
    @State private var showEventLog = false

    // MARK: - Body

    var body: some View {
        ZStack {
            MentorioTheme.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    pageTitle

                    // 1. Что сейчас в приложении
                    liveStateCard

                    // 2. Воронка — понятным языком
                    funnelCard

                    // 3. Уведомления
                    notificationsCard

                    // 4. Лог событий (свернут по умолчанию)
                    eventLogCard

                    // 5. Опасная зона
                    dangerCard
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 48)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task { await refreshAll() }
        .refreshable { await refreshAll() }
        .onChange(of: eventFilter) { _, _ in refreshAnalytics() }
    }

    // MARK: - Page Title

    private var pageTitle: some View {
        Text("Диагностика")
            .font(.largeTitle.bold())
            .fontDesign(.serif)
            .foregroundStyle(MentorioTheme.primaryText)
            .padding(.top, 24)
            .padding(.bottom, 2)
    }

    // MARK: - Live State Card

    private var liveStateCard: some View {
        card(title: "Что сейчас происходит") {
            let active  = viewModel.notes.filter { !$0.isCompleted && !$0.isInTrash }
            let inWork  = active.filter { if case .executing = $0.state { return true }; return false }
            let thinking = active.filter { if case .analyzing = $0.state { return true }; return false }
            let drafts  = active.filter { $0.status == .draft && $0.storedHighlight == nil }
            let waiting = active.filter { $0.storedHighlight != nil && $0.storedAction != nil && $0.status == .draft }

            if active.isEmpty && viewModel.archivedNotes.isEmpty {
                infoRow(icon: "tray", text: "Приложение чистое — нет ни одной заметки")
            } else {
                if !inWork.isEmpty {
                    highlightRow(
                        icon: "bolt.fill",
                        color: MentorioTheme.accent,
                        text: inWork.count == 1
                            ? "1 шаг сейчас в работе"
                            : "\(inWork.count) шага сейчас в работе"
                    )
                }
                if !thinking.isEmpty {
                    highlightRow(icon: "waveform", color: .orange,
                        text: "AI анализирует \(thinking.count) заметку прямо сейчас")
                }
                if !waiting.isEmpty {
                    highlightRow(icon: "eye.fill", color: .purple,
                        text: "\(waiting.count) заметка ждёт — зеркало готово, шаг ещё не принят")
                }
                if !drafts.isEmpty {
                    infoRow(icon: "square.dashed",
                        text: "\(drafts.count) черновик лежит без действия")
                }
                if viewModel.archivedNotes.count > 0 {
                    infoRow(icon: "archivebox.fill",
                        text: "\(viewModel.archivedNotes.count) шагов выполнено и архивировано")
                }
                if inWork.isEmpty && thinking.isEmpty && waiting.isEmpty && drafts.isEmpty {
                    infoRow(icon: "checkmark.circle", text: "Всё спокойно — нет активных сессий")
                }
            }
        }
    }

    // MARK: - Funnel Card

    private var funnelCard: some View {
        card(title: "Как работает флоу") {
            // Headline insight
            Text(funnel.headline)
                .font(.body.weight(.semibold))
                .foregroundStyle(MentorioTheme.primaryText)
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(MentorioTheme.accent.opacity(0.12))
                )

            if funnel.braindumps == 0 {
                Text("Пройди полный флоу — напиши брейндамп, прими шаг, выполни — и здесь появится статистика.")
                    .font(.caption)
                    .foregroundStyle(MentorioTheme.secondaryText)
            } else {
                VStack(spacing: 0) {
                    funnelStep(
                        number: "1",
                        title: "Написали брейндамп",
                        subtitle: "Человек открыл приложение и выговорился",
                        count: funnel.braindumps,
                        rate: nil
                    )
                    funnelConnector(rate: funnel.mirrorRate, label: "AI сгенерировал зеркало")
                    funnelStep(
                        number: "2",
                        title: "Зеркало получено",
                        subtitle: "AI отразил суть и предложил шаг",
                        count: funnel.mirrors,
                        rate: funnel.mirrorRate
                    )
                    funnelConnector(rate: funnel.acceptRate, label: "Человек принял шаг")
                    funnelStep(
                        number: "3",
                        title: "Шаг принят",
                        subtitle: "Нажал «Возьму этот шаг»",
                        count: funnel.accepted,
                        rate: funnel.acceptRate
                    )
                    funnelConnector(rate: funnel.startRate, label: "Удержал кнопку «Начать»")
                    funnelStep(
                        number: "4",
                        title: "Шаг начат",
                        subtitle: "Удержал кнопку — взял на себя обязательство",
                        count: funnel.started,
                        rate: funnel.startRate
                    )
                    funnelConnector(rate: funnel.doneRate, label: "Отметил выполнение")
                    funnelStep(
                        number: "5",
                        title: "Шаг выполнен ✓",
                        subtitle: "Прошёл reality check — дело сделано",
                        count: funnel.completed,
                        rate: funnel.doneRate,
                        isLast: true
                    )
                }

                Divider().background(MentorioTheme.stroke).padding(.vertical, 6)

                // Timing
                VStack(spacing: 8) {
                    if let label = funnel.avgAcceptLabel {
                        timingRow(icon: "timer", text: label)
                    }
                    if let label = funnel.avgDoneLabel {
                        timingRow(icon: "flag.fill", text: label)
                    }
                    if let rr = funnel.realityRate {
                        timingRow(
                            icon: "checkmark.seal.fill",
                            text: "\(pct(rr)) людей честно ответили на reality check (не пропустили)"
                        )
                    }
                }
            }
        }
    }

    // MARK: - Notifications Card

    private var notificationsCard: some View {
        card(title: "Уведомления") {
            switch authStatus {
            case .authorized, .provisional:
                highlightRow(icon: "bell.fill", color: .green,
                    text: "Уведомления включены — напомним вернуться")
            case .denied:
                highlightRow(icon: "bell.slash", color: .red,
                    text: "Уведомления отключены — зайди в Настройки iOS")
            default:
                highlightRow(icon: "bell", color: MentorioTheme.secondaryText,
                    text: "Разрешение не запрошено")
            }

            if !notifications.isEmpty {
                Divider().background(MentorioTheme.stroke)
                Text("Запланировано \(notifications.count) уведомлений")
                    .font(.caption)
                    .foregroundStyle(MentorioTheme.secondaryText)
                ForEach(notifications) { n in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(n.title).font(.subheadline.weight(.medium)).foregroundStyle(MentorioTheme.primaryText)
                        Text("⏰ \(n.nextTriggerDescription)").font(.caption).foregroundStyle(MentorioTheme.secondaryText)
                    }
                    .padding(.vertical, 2)
                }
            }

            Button("Отправить тест (через 10 сек)") {
                NotificationManager.shared.scheduleTestNotification()
                Task { await refreshAll() }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(MentorioTheme.accent)
            .disabled(authStatus == .denied || authStatus == .notDetermined)
        }
    }

    // MARK: - Event Log Card

    private var eventLogCard: some View {
        card(title: "Лог событий") {
            Button {
                withAnimation(.spring(response: 0.3)) { showEventLog.toggle() }
            } label: {
                HStack {
                    Text(showEventLog ? "Скрыть лог" : "Показать последние события")
                        .font(.subheadline)
                        .foregroundStyle(MentorioTheme.accent)
                    Spacer()
                    Image(systemName: showEventLog ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(MentorioTheme.secondaryText)
                }
            }
            .buttonStyle(.plain)

            if showEventLog {
                Picker("Канал", selection: $eventFilter) {
                    ForEach(EventLogFilter.allCases) { f in Text(f.title).tag(f) }
                }
                .pickerStyle(.segmented)

                if let copyStatus {
                    Text(copyStatus).font(.caption).foregroundStyle(MentorioTheme.secondaryText)
                }

                Button {
                    copyEvents()
                } label: {
                    Label("Скопировать все", systemImage: "doc.on.doc")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(MentorioTheme.accent)
                }
                .buttonStyle(.plain)

                if analyticsEvents.isEmpty {
                    Text("Нет событий").font(.caption).foregroundStyle(MentorioTheme.secondaryText)
                } else {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(analyticsEvents) { event in
                            let ch = event.properties["channel"] ?? "product"
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(ch == "debug" ? Color.orange : Color.green)
                                        .frame(width: 5, height: 5)
                                    Text(humanEventName(event.name))
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(MentorioTheme.primaryText)
                                    Spacer()
                                    Text(event.timestamp.formatted(date: .omitted, time: .standard))
                                        .font(.caption2)
                                        .foregroundStyle(MentorioTheme.secondaryText)
                                }
                                let propsLine = readableProps(event.properties)
                                if !propsLine.isEmpty {
                                    Text(propsLine)
                                        .font(.caption)
                                        .foregroundStyle(MentorioTheme.secondaryText.opacity(0.8))
                                        .lineLimit(1)
                                }
                            }
                            .padding(.vertical, 4)
                            .padding(.horizontal, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(MentorioTheme.background.opacity(0.5))
                            )
                        }
                    }
                }
            }
        }
    }

    // MARK: - Danger Card

    private var dangerCard: some View {
        card(title: "Опасная зона") {
            Text("Только для разработки. Действия необратимы.")
                .font(.caption)
                .foregroundStyle(.red.opacity(0.7))

            Button(role: .destructive) {
                isWipingData = true
                viewModel.deleteAllData()
                AnalyticsManager.shared.track("diagnostics_god_mode_wipe_data", properties: ["channel": "debug"])
                Task {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    isWipingData = false
                    await refreshAll()
                }
            } label: {
                HStack {
                    Image(systemName: isWipingData ? "hourglass" : "trash.fill")
                    Text(isWipingData ? "Удаляю..." : "Удалить все данные и начать заново")
                    Spacer()
                    if isWipingData { ProgressView() }
                }
                .font(.body.weight(.medium))
                .foregroundStyle(.red)
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
            .disabled(isWipingData)
        }
    }

    // MARK: - Reusable View Builders

    @ViewBuilder
    private func card<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline.weight(.semibold))
                .fontDesign(.serif)
                .foregroundStyle(MentorioTheme.secondaryText)
            content()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(MentorioTheme.card)
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(MentorioTheme.stroke, lineWidth: 1))
        )
    }

    private func highlightRow(icon: String, color: Color, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(color)
                .frame(width: 22)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(MentorioTheme.primaryText)
        }
        .padding(.vertical, 2)
    }

    private func infoRow(icon: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(MentorioTheme.secondaryText)
                .frame(width: 22)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(MentorioTheme.secondaryText)
        }
        .padding(.vertical, 2)
    }

    private func timingRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(MentorioTheme.accent)
                .frame(width: 18)
                .padding(.top, 2)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(MentorioTheme.primaryText)
        }
    }

    // MARK: - Funnel Step & Connector

    private func funnelStep(
        number: String,
        title: String,
        subtitle: String,
        count: Int,
        rate: Double?,
        isLast: Bool = false
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // Number badge
            ZStack {
                Circle()
                    .fill(count > 0 ? MentorioTheme.accent.opacity(0.18) : MentorioTheme.background)
                    .frame(width: 28, height: 28)
                Text(number)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(count > 0 ? MentorioTheme.accent : MentorioTheme.secondaryText)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(count > 0 ? MentorioTheme.primaryText : MentorioTheme.secondaryText)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(MentorioTheme.secondaryText)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(count)")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(count > 0 ? MentorioTheme.primaryText : MentorioTheme.secondaryText)
                    .monospacedDigit()
                if let r = rate {
                    Text(pct(r))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(rateColor(r))
                }
            }
        }
        .padding(.vertical, 6)
    }

    private func funnelConnector(rate: Double?, label: String) -> some View {
        HStack(spacing: 12) {
            // Align with number badge center (width 28, padding 0)
            Color.clear.frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Image(systemName: "arrow.down")
                    .font(.caption2)
                    .foregroundStyle(MentorioTheme.secondaryText.opacity(0.4))
                if let r = rate {
                    Text("\(pct(r)) — \(label)")
                        .font(.caption)
                        .foregroundStyle(rateColor(r))
                } else {
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(MentorioTheme.secondaryText.opacity(0.5))
                }
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }

    private func rateColor(_ r: Double) -> Color {
        r >= 0.7 ? .green : r >= 0.4 ? .orange : .red
    }

    private func pct(_ v: Double) -> String {
        "\(Int((v * 100).rounded()))%"
    }

    // MARK: - Human-readable event names

    private func humanEventName(_ raw: String) -> String {
        switch raw {
        case "braindump_started":          return "Написал брейндамп"
        case "mirror_generated":           return "Зеркало сгенерировано"
        case "one_action_accepted":        return "Шаг принят"
        case "one_action_started":         return "Начал выполнять шаг"
        case "one_action_completed":       return "Шаг выполнен ✓"
        case "reality_check_selected":     return "Reality check пройден"
        case "reality_check_skipped":      return "Reality check пропущен"
        case "action_skipped":             return "Шаг отложен"
        case "intent_route_detected":      return "Маршрут определён"
        case "clarification_submitted":    return "Уточнение отправлено"
        case "choice_tapped_from_card":    return "Выбрана тактика"
        default:                           return raw
        }
    }

    private func readableProps(_ props: [String: String]) -> String {
        var parts: [String] = []
        if let state = props["note_state"], state != "idle" { parts.append("состояние: \(state)") }
        if let source = props["entry_point"] { parts.append("откуда: \(source)") }
        if let skip = props["skip_reason"] { parts.append("причина: \(skip)") }
        return parts.joined(separator: " · ")
    }

    // MARK: - Data Refresh

    private func refreshAll() async {
        authStatus = await NotificationManager.shared.fetchAuthorizationStatus()
        notifications = await NotificationManager.shared.fetchPendingNotifications()
        refreshAnalytics()
    }

    private func refreshAnalytics() {
        analyticsEvents = AnalyticsManager.shared.recentEvents(limit: 20, channel: eventFilter.analyticsChannel)
        let productEvents = AnalyticsManager.shared.recentEvents(limit: 500, channel: "product")
        funnel = computeFunnel(from: productEvents)
    }

    // MARK: - Funnel Computation

    private func computeFunnel(from events: [AnalyticsEventSnapshot]) -> Funnel {
        var bIDs = Set<String>()
        var mIDs = Set<String>()
        var aIDs = Set<String>()
        var sIDs = Set<String>()
        var cIDs = Set<String>()
        var rSelIDs = Set<String>()
        var rSkipIDs = Set<String>()
        var bAt: [String: Date] = [:]
        var aAt: [String: Date] = [:]
        var cAt: [String: Date] = [:]

        for e in events {
            guard let nid = e.properties["note_id"], !nid.isEmpty else { continue }
            switch e.name {
            case "braindump_started":       bIDs.insert(nid); if bAt[nid] == nil { bAt[nid] = e.timestamp }
            case "mirror_generated":        mIDs.insert(nid)
            case "one_action_accepted":     aIDs.insert(nid); if aAt[nid] == nil { aAt[nid] = e.timestamp }
            case "one_action_started":      sIDs.insert(nid)
            case "one_action_completed":    cIDs.insert(nid); if cAt[nid] == nil { cAt[nid] = e.timestamp }
            case "reality_check_selected":  rSelIDs.insert(nid)
            case "reality_check_skipped":   rSkipIDs.insert(nid)
            default: break
            }
        }

        func r(_ n: Int, _ d: Int) -> Double? { d > 0 ? Double(n) / Double(d) : nil }

        let rtotal = rSelIDs.union(rSkipIDs).count

        var ttaList: [TimeInterval] = []
        var ttcList: [TimeInterval] = []
        for (nid, start) in bAt {
            if let acc = aAt[nid], acc >= start { ttaList.append(acc.timeIntervalSince(start)) }
            if let done = cAt[nid], done >= start { ttcList.append(done.timeIntervalSince(start)) }
        }

        func avg(_ list: [TimeInterval]) -> TimeInterval? {
            list.isEmpty ? nil : list.reduce(0, +) / Double(list.count)
        }

        return Funnel(
            braindumps: bIDs.count,
            mirrors: mIDs.count,
            accepted: aIDs.count,
            started: sIDs.count,
            completed: cIDs.count,
            mirrorRate: r(mIDs.count, bIDs.count),
            acceptRate: r(aIDs.count, mIDs.count),
            startRate: r(sIDs.count, aIDs.count),
            doneRate: r(cIDs.count, sIDs.count),
            realityRate: rtotal > 0 ? Double(rSelIDs.count) / Double(rtotal) : nil,
            avgAcceptSec: avg(ttaList),
            avgDoneSec: avg(ttcList)
        )
    }

    private func copyEvents() {
        let lines = AnalyticsManager.shared
            .recentEvents(limit: 200, channel: eventFilter.analyticsChannel)
            .map { e in
                let t = e.timestamp.formatted(date: .numeric, time: .standard)
                let props = e.properties.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ", ")
                return "[\(t)] \(e.name)  \(props)"
            }
            .joined(separator: "\n")
        UIPasteboard.general.string = lines
        copyStatus = "Скопировано"
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run { copyStatus = nil }
        }
    }
}

#Preview {
    NavigationStack {
        DiagnosticsView()
    }
    .environmentObject(makePreviewViewModel())
}
