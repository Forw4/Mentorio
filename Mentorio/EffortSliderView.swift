import SwiftUI

struct EffortSliderView: View {
    @Binding var effort: RealityCheckResult
    
    @State private var progress: CGFloat = 0.5
    @State private var isDragging: Bool = false
    @State private var hasInteracted: Bool = false
    
    private let generator = UIImpactFeedbackGenerator(style: .rigid)
    
    private let labels = [
        "Выживал",
        "С усилием",
        "Нормально",
        "Зашло легко",
        "На одном дыхании"
    ]
    
    var body: some View {
        VStack(spacing: 16) {
            Text(hasInteracted ? labels[currentZone] : "Оценить усилие")
                .font(.subheadline)
                .foregroundColor(hasInteracted ? MentorioTheme.primaryText : MentorioTheme.secondaryText)
                .animation(.easeInOut(duration: 0.2), value: hasInteracted)
                .animation(.none, value: currentZone)
            
            GeometryReader { geometry in
                let width = geometry.size.width
                
                ZStack(alignment: .leading) {
                    // Track background - just a thin string
                    Capsule()
                        .fill(MentorioTheme.secondaryText.opacity(0.15))
                        .frame(height: 2)
                        .padding(.vertical, 15) // Keep touch area height
                    
                    // Ticks
                    HStack(spacing: 0) {
                        ForEach(0..<5) { index in
                            Spacer()
                                .frame(width: index == 0 ? 0 : nil)
                            Circle()
                                .fill(tickColor(for: index))
                                .frame(width: 4, height: 4)
                                .shadow(color: tickGlowColor(for: index), radius: hasInteracted && currentZone == index ? 6 : 0)
                                .scaleEffect(hasInteracted && currentZone == index ? 1.6 : 1.0)
                                .animation(.spring(response: 0.3), value: currentZone)
                                .animation(.easeInOut, value: hasInteracted)
                            if index == 4 { Spacer().frame(width: 0) }
                        }
                    }
                    
                    // Thumb
                    Circle()
                        .fill(hasInteracted ? MentorioTheme.accent : MentorioTheme.card)
                        .stroke(hasInteracted ? MentorioTheme.accent : MentorioTheme.secondaryText.opacity(0.4), lineWidth: hasInteracted ? 0 : 1.5)
                        .shadow(color: hasInteracted ? MentorioTheme.accent.opacity(isDragging ? 0.4 : 0.2) : .clear, radius: isDragging ? 8 : 4)
                        .frame(width: 28, height: 28)
                        .scaleEffect(isDragging ? 1.15 : 1.0)
                        .offset(x: progress * width - 14)
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    if !isDragging {
                                        generator.prepare()
                                        isDragging = true
                                    }
                                    if !hasInteracted {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            hasInteracted = true
                                        }
                                    }
                                    
                                    let newProgress = min(max(value.location.x / width, 0), 1)
                                    let oldZone = currentZone
                                    progress = newProgress
                                    
                                    if oldZone != currentZone {
                                        triggerHaptic(for: currentZone)
                                        updateBinding()
                                    }
                                }
                                .onEnded { value in
                                    isDragging = false
                                    snapToNearestZone()
                                }
                        )
                        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: isDragging)
                }
            }
            .frame(height: 32)
        }
        .padding(.vertical, 8)
        .onAppear {
            progress = CGFloat(effort.effortScore - 1) / 4.0
        }
    }
    
    private var currentZone: Int {
        return min(max(Int(round(progress * 4)), 0), 4)
    }
    
    private func snapToNearestZone() {
        let zone = currentZone
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            progress = CGFloat(zone) / 4.0
        }
    }
    
    private func updateBinding() {
        if let result = RealityCheckResult(score: currentZone + 1) {
            effort = result
        }
    }
    
    private func triggerHaptic(for zone: Int) {
        if zone == 0 || zone == 4 {
            let heavy = UIImpactFeedbackGenerator(style: .heavy)
            heavy.impactOccurred()
        } else if zone == 2 {
            let light = UIImpactFeedbackGenerator(style: .light)
            light.impactOccurred()
        } else {
            let medium = UIImpactFeedbackGenerator(style: .rigid)
            medium.impactOccurred()
        }
    }
    
    private func tickColor(for index: Int) -> Color {
        if hasInteracted && currentZone == index {
            return MentorioTheme.accent
        }
        return MentorioTheme.secondaryText.opacity(0.3)
    }
    
    private func tickGlowColor(for index: Int) -> Color {
        if hasInteracted && currentZone == index {
            return MentorioTheme.accent.opacity(0.6)
        }
        return .clear
    }
}

#Preview {
    ZStack {
        MentorioTheme.background.ignoresSafeArea()
        EffortSliderView(effort: .constant(.normal))
            .padding()
    }
}
