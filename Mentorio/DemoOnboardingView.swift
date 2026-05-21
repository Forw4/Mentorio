import SwiftUI

/// Self-contained demo — plays the Mentorio loop like a short film.
/// No interaction until the end. Mirror card has no buttons.
/// CTA "Попробовать на себе" appears after the card settles.
struct DemoOnboardingView: View {
    let onComplete: () -> Void

    // MARK: - Phases

    private enum DemoPhase: Equatable {
        case ready
        case typing
        case analyzing
        case intake
        case mirror       // Card appears, no interaction
        case cta           // "Попробовать на себе →" slides in
    }

    @State private var phase: DemoPhase = .ready
    @State private var displayedText: String = ""
    @State private var charIndex: Int = 0
    @State private var typeTimer: Timer? = nil

    // Demo content — dry facts, no psychologism
    private let demoBraindump = "не могу начать курсовую, уже неделю откладываю, каждый раз нахожу отмазку"
    private let demoIntake = "Одна тема. Одно действие. Без оправданий."
    private let demoHighlight = "Неделю откладываешь. Файл ни разу не открыт. Каждая новая отмазка — ещё один день без первого абзаца."
    private let demoAction = "Открой файл курсовой и напиши первые 3 предложения введения, не редактируя"
    private let demoEmoji = "📄"

    // MARK: - Annotation per phase

    private var annotationText: String {
        switch phase {
        case .ready:     return "Смотри, как это работает"
        case .typing:    return "Выгружаешь хаос — что мешает прямо сейчас"
        case .analyzing: return "Ментор сжимает до сути"
        case .intake:    return "Одна тема. Одно действие."
        case .mirror:    return "Диагноз и один конкретный шаг. Без теории."
        case .cta:       return "Это был пример. Теперь твоя очередь."
        }
    }

    // MARK: - Body

    var body: some View {
        VStack {
            // Top annotation — always visible, changes per phase
            annotationArea
                .padding(.top, 16)
                .padding(.bottom, 8)

            Spacer(minLength: 0)

            // Single unified Dialog card
            dialogCard
                .frame(maxWidth: 520)

        }
        .padding(.horizontal, 18)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(backgroundLayer)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { startDemo() }
        }
        .onDisappear { typeTimer?.invalidate() }
        .animation(.spring(response: 0.5, dampingFraction: 0.88), value: phase)
    }

    // MARK: - Annotation Area

    private var annotationArea: some View {
        VStack(spacing: 8) {
            Text("DEMO")
                .font(.system(size: 11, weight: .heavy))
                .tracking(3)
                .foregroundStyle(MentorioTheme.accent.opacity(0.8))

            Text(annotationText)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
                .shadow(color: Color.black.opacity(0.5), radius: 4, x: 0, y: 2)
                .id(annotationText) // forces re-animation
                .transition(.opacity)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 80)
    }

    // MARK: - Background (identical to EntryOverlayView)

    private var backgroundLayer: some View {
        ZStack {
            MentorioTheme.background.ignoresSafeArea()

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

    // MARK: - Unified Dialog Card

    private var dialogCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            headerRow

            // Chat content
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {

                        if phase != .ready {
                            bubble(text: "Коротко. Что мешает прямо сейчас?", role: .mentor)
                        }

                        if !displayedText.isEmpty {
                            bubble(
                                text: displayedText + (phase == .typing ? "▊" : ""),
                                role: .user
                            )
                        }

                        if phase == .analyzing {
                            bubble(text: "Сжимаю суть...", role: .mentor)
                        }

                        if phase == .intake || phase == .mirror || phase == .cta {
                            bubble(text: demoIntake, role: .mentor)
                        }

                        // Mirror Card inside scrollview
                        if phase == .mirror || phase == .cta {
                            demoMirrorCard
                                .padding(.top, 16)
                                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 32)
                    .padding(.bottom, 8)
                    .id("DemoBottom")
                }
                .frame(maxHeight: 600)
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
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
                .padding(.top, -8)
                .onChange(of: phase) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation { proxy.scrollTo("DemoBottom", anchor: .bottom) }
                    }
                }
                .onChange(of: displayedText) {
                    withAnimation { proxy.scrollTo("DemoBottom", anchor: .bottom) }
                }
            }

            // Bottom controls
            bottomControls
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
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: Color.black.opacity(0.35), radius: 24, x: 0, y: 16)
    }

    private var headerRow: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Mentorio")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MentorioTheme.accent)

                Text(headerTitle)
                    .font(.title3.weight(.semibold))
                    .fontDesign(.serif)
                    .foregroundStyle(MentorioTheme.primaryText)
            }
            Spacer()
        }
    }

    private var headerTitle: String {
        switch phase {
        case .ready:               return "Как это работает"
        case .typing:              return "В чем затык?"
        case .analyzing:           return "Сжимаю суть"
        case .intake:              return "Принял"
        case .mirror, .cta:        return "Зеркало"
        }
    }

    @ViewBuilder
    private var bottomControls: some View {
        switch phase {
        case .ready:
            ProgressView()
                .tint(MentorioTheme.accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)

        case .typing:
            HStack(alignment: .bottom, spacing: 8) {
                Text("смотри...")
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.25))
                    .padding(.vertical, 10)
                    .padding(.leading, 14)
                Spacer()
                Circle()
                    .fill(MentorioTheme.primaryText.opacity(0.1))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Image(systemName: "arrow.up")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(MentorioTheme.primaryText.opacity(0.3))
                    )
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

        case .analyzing, .intake:
            ProgressView()
                .tint(MentorioTheme.accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)

        case .mirror:
            // Empty space while mirror card is read, before CTA appears
            EmptyView()

        case .cta:
            Button(action: onComplete) {
                Text("Попробовать на себе →")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(MentorioTheme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }

    // MARK: - Demo Flow

    private func startDemo() {
        withAnimation(.easeOut(duration: 0.3)) { phase = .typing }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { startTyping() }
    }

    private func startTyping() {
        charIndex = 0
        displayedText = ""
        typeTimer?.invalidate()

        typeTimer = Timer.scheduledTimer(withTimeInterval: 0.04, repeats: true) { timer in
            guard charIndex < demoBraindump.count else {
                timer.invalidate()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    withAnimation(.easeOut(duration: 0.3)) { phase = .analyzing }

                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        withAnimation(.easeOut(duration: 0.3)) { phase = .intake }

                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                            withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) {
                                phase = .mirror
                            }

                            // CTA appears 2s after card
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                                withAnimation(.easeOut(duration: 0.5)) { phase = .cta }
                            }
                        }
                    }
                }
                return
            }
            let idx = demoBraindump.index(demoBraindump.startIndex, offsetBy: charIndex)
            displayedText.append(demoBraindump[idx])
            charIndex += 1
        }
    }

    // MARK: - Bubble

    private enum BubbleRole { case mentor, user }

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
        }

        return HStack {
            if role == .user { Spacer(minLength: 24) }
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
            if role != .user { Spacer(minLength: 24) }
        }
    }

    // MARK: - Demo Mirror Card (pure visual — NO buttons)

    private var demoMirrorCard: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let a1 = Angle.degrees(t * 35)
            let a2 = Angle.degrees(t * -25)

            let auraColors: [Color] = [
                Color(red: 0.95, green: 0.50, blue: 0.35),
                Color(red: 1.00, green: 0.63, blue: 0.67),
                Color(red: 1.00, green: 0.73, blue: 0.59),
                Color(red: 1.00, green: 0.63, blue: 0.67),
                Color(red: 0.95, green: 0.50, blue: 0.35)
            ]

            let cr: CGFloat = 18

            VStack(alignment: .leading, spacing: 10) {
                Text("СУТЬ")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(.white.opacity(0.3))
                    .tracking(2)

                Text(demoHighlight)
                    .font(.system(size: 14, weight: .regular, design: .serif))
                    .foregroundStyle(MentorioTheme.primaryText.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)

                Rectangle()
                    .fill(MentorioTheme.stroke)
                    .frame(height: 1)
                    .padding(.vertical, 4)

                HStack(alignment: .top, spacing: 8) {
                    Text(demoEmoji)
                        .font(.system(size: 22))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("ОДИН ШАГ")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(.white.opacity(0.3))
                            .tracking(2)
                        Text(demoAction)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(MentorioTheme.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            // 1. Solid dark base
            .background(
                RoundedRectangle(cornerRadius: cr, style: .continuous)
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

            // 2. WIDE SOFT AURA (matches EntryOverlayView)
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
    }
}

#Preview {
    DemoOnboardingView(onComplete: {})
        .preferredColorScheme(.dark)
}
