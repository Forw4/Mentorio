import SwiftUI

struct EntryOverlayView: View {
    @ObservedObject var viewModel: MentorioViewModel
    @Binding var isPresented: Bool
    private let existingNote: BraindumpNote?

    init(
        viewModel: MentorioViewModel,
        isPresented: Binding<Bool>,
        existingNote: BraindumpNote? = nil
    ) {
        self.viewModel = viewModel
        self._isPresented = isPresented
        self.existingNote = existingNote
    }

    // MARK: - State

    private enum EntryState: Equatable {
        case braindump
        case analyzing
        case intake(text: String)  // Brief "received" confirmation before mirror card
        case mirror(highlight: String, action: String, emoji: String)
    }

    @State private var entryState: EntryState = .braindump
    @State private var inputText = ""
    @State private var braindumpText = ""
    @State private var errorMessage: String? = nil
    @State private var pendingDraftID: UUID? = nil
    @State private var activeTask: Task<Void, Never>? = nil
    @State private var didLoadExisting = false

    @FocusState private var isInputFocused: Bool

    // Chat history — simpler than before, just braindump + mentor responses
    private struct ChatMessage: Identifiable, Equatable {
        let id: UUID
        let isAI: Bool
        let text: String

        init(id: UUID = UUID(), isAI: Bool, text: String) {
            self.id = id
            self.isAI = isAI
            self.text = text
        }
    }

    @State private var chatHistory: [ChatMessage] = []

    // MARK: - Body

    var body: some View {
        if #available(iOS 16.4, *) {
            content.presentationBackground(.clear)
        } else {
            content
        }
    }

    private var content: some View {
        VStack {
            Spacer(minLength: 0)
            dialogCard
                .frame(maxWidth: 520)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            backgroundLayer
                .onTapGesture {
                    isInputFocused = false
                }
        )
        .onAppear {
            if !didLoadExisting {
                didLoadExisting = true
                if let existingNote {
                    hydrateFromExisting(existingNote)
                }
            }
            if entryState == .braindump {
                isInputFocused = true
            }
        }
        .onDisappear {
            activeTask?.cancel()
        }
        .animation(.spring(response: 0.46, dampingFraction: 0.9), value: entryState)
    }

    // MARK: - Background

    private var backgroundLayer: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

            LinearGradient(
                colors: [
                    MentorioTheme.accent.opacity(0.22),
                    Color.white.opacity(0.04),
                    Color.black.opacity(0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            RadialGradient(
                colors: [MentorioTheme.accent.opacity(0.18), Color.clear],
                center: .top,
                startRadius: 40,
                endRadius: 320
            )
            .ignoresSafeArea()
        }
    }

    // MARK: - Dialog Card

    private var dialogCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerRow

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        // 1. Welcome or user braindump
                        if entryState == .braindump {
                            bubble(text: "Коротко. Что мешает прямо сейчас?", role: .mentor)
                        } else if !braindumpText.isEmpty {
                            bubble(text: braindumpText, role: .user)
                        }

                        // 2. Chat history (previous attempts shown here)
                        ForEach(chatHistory) { message in
                            bubble(text: message.text, role: message.isAI ? .mentor : .user)
                        }

                        // 3. Loading indicator
                        if entryState == .analyzing {
                            bubble(text: "Сжимаю суть...", role: .mentor)
                        }


                        // 4. Mirror card (highlight + action + buttons)
                        if case .mirror(let highlight, let action, let emoji) = entryState {
                            mirrorCardBubble(highlight: highlight, action: action, emoji: emoji)
                        }

                        // 5. Error
                        if let errorMessage {
                            bubble(text: errorMessage, role: .error)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // Space at the top so the first message isn't blurred by the fade-out
                    .padding(.top, 32)
                    .id("BottomSpacer")
                }
                .frame(maxHeight: 600)
                .scrollIndicators(.hidden)
                // Turn off default ScrollView clipping
                .scrollClipDisabled()
                // Apply a custom gradient mask:
                // 1. Fades out smoothly at the top (0.0 to 0.08)
                // 2. Extends infinitely horizontally (scale x: 10) so glow never clips
                // 3. Extends infinitely downwards (padding bottom -1000) so messages scroll right to the edge
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.0),
                            .init(color: .black, location: 0.02),
                            .init(color: .black, location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .scaleEffect(x: 10, y: 1.0, anchor: .center)
                    .padding(.bottom, -1000)
                )
                // Shift the scroll area up slightly to reduce the gap below "Зеркало"
                .padding(.top, -8)
                .onTapGesture {
                    isInputFocused = false
                }
                .onChange(of: chatHistory.count) {
                    withAnimation { proxy.scrollTo("BottomSpacer", anchor: .bottom) }
                }
                .onChange(of: entryState) {
                    withAnimation { proxy.scrollTo("BottomSpacer", anchor: .bottom) }
                }
            }

            controlsSection
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(MentorioTheme.stroke, lineWidth: 1)
                )
        )
        // Clip everything to the exact shape of the gray bubble.
        // This ensures messages can scroll all the way to the edge, but never outside.
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: Color.black.opacity(0.35), radius: 24, x: 0, y: 16)
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Mentorio")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MentorioTheme.accent)

                Text(titleText)
                    .font(.title3.weight(.semibold))
                    .fontDesign(.serif)
                    .foregroundStyle(MentorioTheme.primaryText)
            }

            Spacer()

            Button {
                closeOverlay()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(MentorioTheme.primaryText.opacity(0.8))
                    .frame(width: 30, height: 30)
                    .background(MentorioTheme.stroke)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
    }

    private var titleText: String {
        switch entryState {
        case .braindump: return "В чем затык?"
        case .analyzing: return "Сжимаю суть"
        case .intake: return "Принял"
        case .mirror: return "Зеркало"
        }
    }

    // MARK: - Controls

    @ViewBuilder
    private var controlsSection: some View {
        switch entryState {
        case .braindump:
            braindumpInputField
        case .analyzing, .intake:
            ProgressView()
                .tint(MentorioTheme.accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        case .mirror:
            // Buttons are inside the mirror card itself
            EmptyView()
        }
    }

    private var braindumpInputField: some View {
        let isTextEmpty = inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        return HStack(alignment: .bottom, spacing: 8) {
            TextField("Хаос мыслей...", text: $inputText, axis: .vertical)
                .lineLimit(1...15)
                .textInputAutocapitalization(.sentences)
                .disableAutocorrection(false)
                .foregroundStyle(MentorioTheme.primaryText)
                .focused($isInputFocused)
                .padding(.vertical, 10)
                .padding(.leading, 14)

            Button(action: submitBraindump) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(isTextEmpty ? MentorioTheme.primaryText.opacity(0.3) : .black)
                    .frame(width: 32, height: 32)
                    .background(isTextEmpty ? MentorioTheme.primaryText.opacity(0.1) : MentorioTheme.accent)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(isTextEmpty)
            .padding(.trailing, 6)
            .padding(.bottom, 6)
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(MentorioTheme.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(MentorioTheme.stroke, lineWidth: 1)
                )
        )
    }

    // MARK: - Mirror Card Bubble (Animated)

    private func mirrorCardBubble(highlight: String, action: String, emoji: String) -> some View {
        MirrorCardView(
            highlight: highlight,
            action: action,
            emoji: emoji,
            onAccept: { acceptMirrorAction(action: action, highlight: highlight, emoji: emoji) },
            onReject: { regenerateAction() }
        )
    }
}

// MARK: - Animated Mirror Card

private struct MirrorCardView: View {
    let highlight: String
    let action: String
    let emoji: String
    let onAccept: () -> Void
    let onReject: () -> Void

    @State private var appeared: Bool = false
    private let cr: CGFloat = 18

    // Soft Mentorio palette for the glow
    private let auraColors: [Color] = [
        Color(red: 0.95, green: 0.50, blue: 0.35), // Mentorio Peach (based)
        Color(red: 1.00, green: 0.63, blue: 0.67), // Rose Peach
        Color(red: 1.00, green: 0.73, blue: 0.59), // Warm Cream
        Color(red: 1.00, green: 0.63, blue: 0.67), // Rose Peach
        Color(red: 0.95, green: 0.50, blue: 0.35)  // Loop back
    ]

    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let a1 = Angle.degrees(t * 35)
            let a2 = Angle.degrees(t * -25)

            cardContent
                // 1. Solid dark base
                .background(
                    RoundedRectangle(cornerRadius: cr, style: .continuous)
                        // Slightly transparent blocker so the neon glow barely shines through
                        .fill(Color.black.opacity(0.85))
                        .overlay(
                            RoundedRectangle(cornerRadius: cr, style: .continuous)
                                .fill(MentorioTheme.card)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: cr, style: .continuous)
                                .stroke(MentorioTheme.stroke, lineWidth: 1)
                        )
                )
                .clipShape(RoundedRectangle(cornerRadius: cr, style: .continuous))

                // 2. WIDE SOFT AURA
                .background(
                    RoundedRectangle(cornerRadius: cr + 8, style: .continuous)
                        .fill(
                            AngularGradient(colors: auraColors, center: .center, angle: a1)
                        )
                        .padding(-8)
                        .blur(radius: 16)
                        .opacity(0.5)
                )

                // 3. INNER CORE AURA
                .background(
                    RoundedRectangle(cornerRadius: cr + 3, style: .continuous)
                        .fill(
                            AngularGradient(colors: auraColors, center: .center, angle: a2)
                        )
                        .padding(-3)
                        .blur(radius: 8)
                        .opacity(0.35)
                )

                // 4. Very subtle, crisp glass edge
                .overlay(
                    RoundedRectangle(cornerRadius: cr, style: .continuous)
                        .stroke(
                            AngularGradient(colors: auraColors.map { $0.opacity(0.6) }, center: .center, angle: a1),
                            lineWidth: 0.5
                        )
                )
        }
        .padding(.top, 16)
        // Entrance animation
        .opacity(appeared ? 1 : 0)
        .scaleEffect(appeared ? 1 : 0.95)
        .offset(y: appeared ? 0 : 10)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.82)) {
                appeared = true
            }
        }
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("СУТЬ")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(Color.white.opacity(0.45))
                Text(highlight)
                    .font(.body.weight(.medium))
                    .fontDesign(.serif)
                    .foregroundStyle(MentorioTheme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 0.5)
                .padding(.horizontal, 16)

            VStack(alignment: .leading, spacing: 6) {
                Text("ОДИН ШАГ")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(Color(red: 0.88, green: 0.70, blue: 0.58).opacity(0.8))
                HStack(alignment: .top, spacing: 8) {
                    Text(emoji)
                        .font(.title2)
                    Text(action)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(MentorioTheme.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 16)

            HStack(spacing: 10) {
                Button(action: onAccept) {
                    Text("Возьму этот шаг")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(MentorioTheme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)

                Button(action: onReject) {
                    Text("Не то")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.white.opacity(0.5))
                        .padding(.vertical, 12)
                        .padding(.horizontal, 20)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.white.opacity(0.04))
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
    }
}

// MARK: - Bubble, Actions, Helpers

extension EntryOverlayView {

    // MARK: - Bubble

    private enum BubbleRole {
        case mentor
        case user
        case error
    }

    private func bubble(text: String, role: BubbleRole) -> some View {
        let fill: Color
        let stroke: Color

        switch role {
        case .mentor:
            fill = MentorioTheme.card
            stroke = MentorioTheme.stroke
        case .user:
            fill = Color.mentorioPeach.opacity(0.22)
            stroke = Color.mentorioPeach.opacity(0.6)
        case .error:
            fill = Color.red.opacity(0.18)
            stroke = Color.red.opacity(0.55)
        }

        return HStack {
            if role == .user {
                Spacer(minLength: 24)
            }

            Text(text)
                .font(.body)
                .foregroundStyle(MentorioTheme.primaryText)
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(fill)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(stroke, lineWidth: 1)
                        )
                )

            if role != .user {
                Spacer(minLength: 24)
            }
        }
    }

    // MARK: - Actions

    private func submitBraindump() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        braindumpText = trimmed
        inputText = ""
        chatHistory = []
        errorMessage = nil
        isInputFocused = false

        ensureDraft(for: trimmed)
        entryState = .analyzing

        activeTask?.cancel()
        activeTask = Task {
            await runMirrorAnalysis(text: trimmed, retryHint: nil)
        }
    }

    private func runMirrorAnalysis(text: String, retryHint: String?) async {
        guard let noteId = pendingDraftID else { return }

        do {
            let mirror = try await viewModel.analyzeBraindump(
                noteId: noteId,
                text: text,
                retryHint: retryHint
            )

            guard !Task.isCancelled else { return }

            // Step 1: Show intake bubble ("Три проблемы. Беру одну.")
            await MainActor.run {
                chatHistory.append(ChatMessage(isAI: true, text: mirror.intake))
                entryState = .intake(text: mirror.intake)
            }

            // Step 2: Brief pause so user registers the intake
            try? await Task.sleep(for: .seconds(2.0))
            guard !Task.isCancelled else { return }

            // Step 3: Transition to mirror card
            await MainActor.run {
                entryState = .mirror(
                    highlight: mirror.highlight,
                    action: mirror.action,
                    emoji: mirror.emoji
                )
            }
        } catch {
            guard !Task.isCancelled else { return }
            await MainActor.run {
                errorMessage = error.localizedDescription
                entryState = .braindump
            }
        }
    }

    private func acceptMirrorAction(action: String, highlight: String, emoji: String) {
        guard let noteId = pendingDraftID else { return }

        viewModel.acceptMirrorAction(
            noteId: noteId,
            action: action,
            highlight: highlight,
            emoji: emoji
        )
        closeOverlay()
    }

    private func regenerateAction() {
        guard case .mirror(let prevHighlight, let prevAction, _) = entryState else { return }

        // Append user rejection bubble to maintain chat rhythm
        chatHistory.append(ChatMessage(isAI: false, text: "Не то"))

        entryState = .analyzing
        errorMessage = nil

        activeTask?.cancel()
        activeTask = Task {
            // Pass previous highlight + action so AI can consciously change direction
            let hint = """
            Предыдущий highlight: \(prevHighlight)
            Предыдущий action: \(prevAction)
            Пользователь нажал "Не то". Дай ДРУГОЙ highlight и ДРУГОЕ действие.
            """
            await runMirrorAnalysis(
                text: braindumpText,
                retryHint: hint
            )
        }
    }

    // MARK: - Hydration

    private func hydrateFromExisting(_ note: BraindumpNote) {
        pendingDraftID = note.id
        braindumpText = note.text
        errorMessage = nil

        // If note is already executing — close overlay, user should see ActiveBar
        if case .executing = note.state {
            closeOverlay()
            return
        }

        // If note has stored highlight + action (was in mirror state before closing),
        // restore the mirror card
        if let storedHighlight = note.storedHighlight,
           let storedAction = note.storedAction,
           !storedHighlight.isEmpty, !storedAction.isEmpty,
           note.status != .active {
            entryState = .mirror(
                highlight: storedHighlight,
                action: storedAction,
                emoji: note.actionEmoji ?? "⚡"
            )
            return
        }

        // Otherwise start fresh — show braindump
        entryState = .braindump
    }

    // MARK: - Helpers

    private func closeOverlay() {
        activeTask?.cancel()

        // Save mirror state to note before closing — so draft can be restored
        if case .mirror(let highlight, let action, let emoji) = entryState,
           let noteId = pendingDraftID,
           let note = viewModel.notes.first(where: { $0.id == noteId }) {
            note.storedHighlight = highlight
            note.storedAction = action
            note.actionEmoji = emoji
            viewModel.saveNotes()
        }

        withAnimation(.easeInOut(duration: 0.22)) {
            isPresented = false
        }
    }

    private func ensureDraft(for text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if let currentPendingID = pendingDraftID,
           let note = viewModel.notes.first(where: { $0.id == currentPendingID }) {
            if note.text != trimmed {
                note.text = trimmed
                viewModel.saveNotes()
            }
            return
        }

        viewModel.addNote(trimmed, source: "entry_overlay", status: .draft)
        pendingDraftID = viewModel.selectedNoteId
    }
}

#Preview {
    @Previewable @State var isPresented = true
    EntryOverlayView(
        viewModel: makePreviewViewModel(),
        isPresented: $isPresented
    )
    .preferredColorScheme(.dark)
}
