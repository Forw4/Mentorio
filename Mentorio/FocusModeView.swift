import SwiftUI

struct FocusModeView: View {
    @ObservedObject var viewModel: MentorioViewModel
    let note: BraindumpNote
    let onComplete: () -> Void
    let onCancel: () -> Void

    @State private var elapsedSeconds: Int = 0
    @State private var timer: Timer? = nil

    // Hold
    @State private var holdProgress: CGFloat = 0
    @State private var holdIntensity: CGFloat = 0   // 0..1 — drives background brightness
    @State private var didFinishHold = false
    @State private var holdTimer: Timer? = nil

    // Cancel confirmation
    @State private var showCancelAlert = false

    // Lava lamp blob positions (start spread out, not at center)
    @State private var blob1Pos: CGPoint = CGPoint(x: 0.3, y: 0.25)
    @State private var blob2Pos: CGPoint = CGPoint(x: 0.7, y: 0.6)
    @State private var blob3Pos: CGPoint = CGPoint(x: 0.4, y: 0.8)
    // Blob scale pulsing (breathing)
    @State private var blob1Scale: CGFloat = 1.0
    @State private var blob2Scale: CGFloat = 1.1
    @State private var blob3Scale: CGFloat = 0.95

    // Appear
    @State private var appeared = false

    private var actionText: String {
        note.finalAction ?? note.storedAction ?? note.text
    }

    private var emojiText: String {
        note.actionEmoji ?? "⚡"
    }

    private var highlightText: String {
        note.storedHighlight ?? ""
    }

    private var elapsedFormatted: String {
        let m = elapsedSeconds / 60
        if m > 0 { return "\(m) мин" }
        return "\(elapsedSeconds) сек"
    }

    // Glass darkness: gets lighter as hold progresses
    private var glassDarkness: Double {
        return 0.55 - (Double(holdIntensity) * 0.4)
    }

    // Blob brightness multiplier during hold
    private var blobBrightness: Double {
        return 1.0 + (Double(holdIntensity) * 2.5)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // MARK: - Lava lamp background
                lavaLampBackground(size: geo.size)

                // MARK: - Content
                VStack(spacing: 0) {
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
                    .padding(.top, 16)

                    Spacer()

                    // Center: emoji + action + hint
                    VStack(spacing: 20) {
                        Text(emojiText)
                            .font(.system(size: 48))
                            .opacity(appeared ? 1 : 0)
                            .scaleEffect(appeared ? 1 : 0.5)

                        Text(actionText)
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 32)
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 12)

                        if !highlightText.isEmpty {
                            Text(highlightText)
                                .font(.system(size: 14, weight: .regular, design: .serif))
                                .foregroundStyle(MentorioTheme.accent.opacity(0.7))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)
                                .opacity(appeared ? 1 : 0)
                        }

                        Text("~15 мин")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.25))
                            .opacity(appeared ? 1 : 0)
                    }

                    Spacer()

                    // Hold button
                    holdButton
                        .padding(.bottom, 28)
                        .opacity(appeared ? 1 : 0)
                        .scaleEffect(appeared ? 1 : 0.85)

                    // Cancel
                    Button {
                        showCancelAlert = true
                    } label: {
                        Text("отменить шаг")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(.white.opacity(0.18))
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 20)
                    .safeAreaPadding(.bottom, 8)
                    .opacity(appeared ? 1 : 0)
                }
            }
        }
        .ignoresSafeArea()
        .alert("Отменить шаг?", isPresented: $showCancelAlert) {
            Button("Отменить шаг", role: .destructive) { onCancel() }
            Button("Остаться", role: .cancel) {}
        } message: {
            Text("Брейндамп и one action будут удалены. Это нельзя отменить.")
        }
        .onAppear {
            startElapsedTimer()
            startLavaLamp()
            withAnimation(.easeOut(duration: 0.7).delay(0.1)) {
                appeared = true
            }
        }
        .onDisappear {
            timer?.invalidate()
            holdTimer?.invalidate()
        }
        .statusBarHidden(true)
    }

    // MARK: - Lava Lamp Background

    private func lavaLampBackground(size: CGSize) -> some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Blob 1 — warm peach (largest, slowest)
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 1.0, green: 0.6, blue: 0.45).opacity(0.7 * blobBrightness),
                            Color(red: 1.0, green: 0.5, blue: 0.35).opacity(0.25 * blobBrightness),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 180
                    )
                )
                .frame(width: 350, height: 300)
                .scaleEffect(blob1Scale)
                .position(
                    x: size.width * blob1Pos.x,
                    y: size.height * blob1Pos.y
                )
                .blur(radius: 50)

            // Blob 2 — coral/rose
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.95, green: 0.35, blue: 0.3).opacity(0.55 * blobBrightness),
                            Color(red: 0.9, green: 0.3, blue: 0.25).opacity(0.18 * blobBrightness),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 150
                    )
                )
                .frame(width: 280, height: 320)
                .scaleEffect(blob2Scale)
                .position(
                    x: size.width * blob2Pos.x,
                    y: size.height * blob2Pos.y
                )
                .blur(radius: 45)

            // Blob 3 — amber/gold
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.9, green: 0.55, blue: 0.2).opacity(0.5 * blobBrightness),
                            Color(red: 0.85, green: 0.45, blue: 0.15).opacity(0.15 * blobBrightness),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 130
                    )
                )
                .frame(width: 260, height: 240)
                .scaleEffect(blob3Scale)
                .position(
                    x: size.width * blob3Pos.x,
                    y: size.height * blob3Pos.y
                )
                .blur(radius: 40)

            // Dark glass overlay — dims during idle, brightens during Hold
            Color.black.opacity(glassDarkness)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.4), value: holdIntensity)

            // Film grain texture overlay
            GrainOverlay()
                .opacity(0.12)
                .blendMode(.overlay)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }

    // MARK: - Hold Button

    private var holdButton: some View {
        ZStack {
            // Outer ambient glow — pulses during hold
            Circle()
                .fill(MentorioTheme.accent.opacity(holdProgress > 0 ? 0.15 : 0.03))
                .frame(width: 130, height: 130)
                .scaleEffect(1.0 + holdIntensity * 0.25)
                .animation(.easeInOut(duration: 0.3), value: holdIntensity)

            // Track
            Circle()
                .stroke(.white.opacity(0.08), lineWidth: 3)
                .frame(width: 92, height: 92)

            // Progress ring
            Circle()
                .trim(from: 0, to: holdProgress)
                .stroke(
                    MentorioTheme.accent,
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .frame(width: 92, height: 92)

            Text("Hold")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(holdProgress > 0 ? MentorioTheme.accent : .white.opacity(0.6))
                .animation(.easeInOut(duration: 0.15), value: holdProgress)
        }
        .frame(width: 150, height: 150)
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
        holdIntensity = 0

        let gen = UIImpactFeedbackGenerator(style: .light)
        gen.prepare(); gen.impactOccurred()

        withAnimation(.linear(duration: 3.0)) {
            holdProgress = 1
        }

        // Escalating haptics + background brightness
        var secs = 0
        holdTimer?.invalidate()
        holdTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            secs += 1

            // Brightness escalation: 0 → 0.33 → 0.66 → 1.0
            withAnimation(.easeInOut(duration: 0.8)) {
                holdIntensity = min(CGFloat(secs) / 3.0, 1.0)
            }

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
                holdIntensity = 0
            }
        }
    }

    private func finishHold() {
        holdTimer?.invalidate(); holdTimer = nil
        let gen = UINotificationFeedbackGenerator(); gen.prepare(); gen.notificationOccurred(.success)
        didFinishHold = true
        holdProgress = 1
        onComplete()
    }

    // MARK: - Elapsed Timer

    private func startElapsedTimer() {
        if let accepted = note.acceptedAt {
            elapsedSeconds = max(0, Int(Date().timeIntervalSince(accepted)))
        }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            elapsedSeconds += 1
        }
    }

    // MARK: - Lava Lamp Animation

    private func startLavaLamp() {
        // Staggered start so blobs don't all move in sync
        driftBlob1()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { pulseBlob1() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { driftBlob2() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { pulseBlob2() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { driftBlob3() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { pulseBlob3() }
    }

    // -- Drift (position) --

    private func driftBlob1() {
        let target = CGPoint(
            x: CGFloat.random(in: 0.1...0.7),
            y: CGFloat.random(in: 0.1...0.5)
        )
        let dur = Double.random(in: 4...6)
        withAnimation(.timingCurve(0.4, 0.0, 0.2, 1.0, duration: dur)) {
            blob1Pos = target
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + dur * 0.85) {
            driftBlob1()
        }
    }

    private func driftBlob2() {
        let target = CGPoint(
            x: CGFloat.random(in: 0.3...0.9),
            y: CGFloat.random(in: 0.3...0.75)
        )
        let dur = Double.random(in: 3.5...5.5)
        withAnimation(.timingCurve(0.3, 0.0, 0.3, 1.0, duration: dur)) {
            blob2Pos = target
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + dur * 0.85) {
            driftBlob2()
        }
    }

    private func driftBlob3() {
        let target = CGPoint(
            x: CGFloat.random(in: 0.15...0.75),
            y: CGFloat.random(in: 0.5...0.9)
        )
        let dur = Double.random(in: 4.5...7)
        withAnimation(.timingCurve(0.35, 0.0, 0.25, 1.0, duration: dur)) {
            blob3Pos = target
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + dur * 0.85) {
            driftBlob3()
        }
    }

    // -- Pulse (scale breathing) --

    private func pulseBlob1() {
        let target = CGFloat.random(in: 0.85...1.2)
        let dur = Double.random(in: 3...5)
        withAnimation(.easeInOut(duration: dur)) {
            blob1Scale = target
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + dur) {
            pulseBlob1()
        }
    }

    private func pulseBlob2() {
        let target = CGFloat.random(in: 0.9...1.25)
        let dur = Double.random(in: 2.5...4.5)
        withAnimation(.easeInOut(duration: dur)) {
            blob2Scale = target
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + dur) {
            pulseBlob2()
        }
    }

    private func pulseBlob3() {
        let target = CGFloat.random(in: 0.8...1.15)
        let dur = Double.random(in: 3.5...5.5)
        withAnimation(.easeInOut(duration: dur)) {
            blob3Scale = target
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + dur) {
            pulseBlob3()
        }
    }
}

// MARK: - Preview

#Preview {
    let note = BraindumpNote(
        text: "не могу сесть за курсовую",
        storedHighlight: "Ты прячешься за мелочами, чтобы не касаться главного.",
        storedAction: "Открой файл и напиши первый абзац введения, 100 слов, не редактируя",
        actionEmoji: "📄",
        acceptedAt: Date().addingTimeInterval(-720)
    )
    FocusModeView(
        viewModel: makePreviewViewModel(),
        note: note,
        onComplete: {},
        onCancel: {}
    )
}

// MARK: - Film Grain Overlay

/// Generates a static noise/grain texture using Canvas.
/// Renders a grid of semi-random opacity dots to create a film grain / spray paint look.
private struct GrainOverlay: View {
    var body: some View {
        Canvas { context, size in
            // Use a seeded random generator for consistent grain pattern
            var rng = SeededRandomNumberGenerator(seed: 42)
            let step: CGFloat = 3
            let cols = Int(size.width / step)
            let rows = Int(size.height / step)

            for row in 0..<rows {
                for col in 0..<cols {
                    let opacity = Double.random(in: 0...0.5, using: &rng)
                    let x = CGFloat(col) * step + CGFloat.random(in: -1...1, using: &rng)
                    let y = CGFloat(row) * step + CGFloat.random(in: -1...1, using: &rng)
                    let dotSize = CGFloat.random(in: 0.8...1.8, using: &rng)

                    context.opacity = opacity
                    context.fill(
                        Path(ellipseIn: CGRect(x: x, y: y, width: dotSize, height: dotSize)),
                        with: .color(.white)
                    )
                }
            }
        }
    }
}

/// Simple seeded RNG for deterministic grain pattern (avoids re-randomizing on state changes)
private struct SeededRandomNumberGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
