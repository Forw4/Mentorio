//
//  MainDashboardView.swift
//  Mentorio
//

import SwiftUI
import UIKit

struct MainDashboardView: View {
    @EnvironmentObject var viewModel: MentorioViewModel
    @State private var braindumpInput = ""
    @State private var showSettings = false
    @State private var keyboardInset: CGFloat = 0
    @FocusState private var isBraindumpFocused: Bool

    private var visibleNotes: [BraindumpNote] {
        viewModel.notes.filter { !$0.isInTrash && !$0.isCompleted }
    }
    
    var body: some View {
        ZStack(alignment: .top) {
            // LAYER 1: The Pool (Background)
            VStack(spacing: 0) {
                // Scroll content
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 0) {
                        // Header
                        VStack(spacing: 12) {
                            HStack {
                                Spacer()

                                Button(action: {
                                    showSettings = true
                                }) {
                                    Image(systemName: "gearshape")
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundColor(MentorioColor.textPrimary)
                                        .frame(width: 32, height: 32)
                                        .background(MentorioColor.surface)
                                        .clipShape(Circle())
                                }
                                .buttonStyle(.plain)
                            }

                            Text("Mentorio")
                                .font(MentorioType.title)
                                .foregroundColor(MentorioColor.textPrimary)
                            
                            Text("В чём затык?")
                                .font(MentorioType.caption)
                                .foregroundColor(MentorioColor.textSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 24)
                        .padding(.horizontal, 16)
                        
                        // Input Area with proper spacing
                        VStack(spacing: 16) {
                            ZStack(alignment: .topLeading) {
                                if braindumpInput.isEmpty {
                                    Text("Без структуры. Без фильтров. Пиши как есть.")
                                        .foregroundColor(MentorioColor.textSecondary)
                                        .padding(16)
                                }
                                
                                TextEditor(text: $braindumpInput)
                                    .focused($isBraindumpFocused)
                                    .scrollContentBackground(.hidden)
                                    .foregroundStyle(MentorioColor.textPrimary)
                                    .frame(minHeight: 100)
                                    .padding(MentorioMetric.spaceM)
                                    .background(MentorioColor.surface)
                                    .cornerRadius(MentorioMetric.radiusM)
                            }
                            
                            Button(action: {
                                if !braindumpInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    viewModel.addNote(braindumpInput)
                                    braindumpInput = ""
                                }
                            }) {
                                Text("Выгрузить хаос")
                                    .frame(maxWidth: .infinity)
                                    .padding(MentorioMetric.spaceM)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(MentorioColor.surfaceElevated)
                                    .background(MentorioColor.accent)
                                    .cornerRadius(MentorioMetric.radiusM)
                            }
                        }
                        .padding(.horizontal, MentorioMetric.spaceL)
                        .padding(.bottom, MentorioMetric.spaceXL)
                        
                        // Notes Pool (Active notes only)
                            if visibleNotes.isEmpty {
                                VStack(spacing: 12) {
                                    Image(systemName: "brain.head.profile")
                                        .font(.system(size: 40))
                                        .foregroundColor(MentorioColor.textSecondary)
                                    Text("Нет активных задач")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(MentorioColor.textSecondary)
                                    Text("Опиши проблему выше, чтобы начать")
                                        .font(.system(size: 13, weight: .regular))
                                        .foregroundColor(MentorioColor.textSecondary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 60)
                            } else {
                                LazyVStack(spacing: 16) {
                                    ForEach(visibleNotes) { note in
                                        NoteCardView(
                                            note: note,
                                            viewModel: viewModel,
                                            focusedNoteID: viewModel.focusedNoteID,
                                            onAnswerFieldFocus: { noteId in
                                                withAnimation(.easeInOut(duration: 0.22)) {
                                                    proxy.scrollTo(noteId, anchor: .center)
                                                }
                                            }
                                        )
                                        .id(note.id)
                                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                                    }
                                }
                                .padding(MentorioMetric.spaceL)
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                    .scrollDismissesKeyboard(.interactively)
                    .background(MentorioColor.background)
                    .onChange(of: viewModel.focusedNoteID) { _, noteId in
                        guard let noteId else { return }
                        withAnimation(.easeInOut(duration: 0.22)) {
                            proxy.scrollTo(noteId, anchor: .center)
                        }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notification in
                        updateKeyboardInset(from: notification)
                        guard let noteId = viewModel.focusedNoteID else { return }
                        withAnimation(.easeInOut(duration: 0.22)) {
                            proxy.scrollTo(noteId, anchor: .center)
                        }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                        withAnimation(.easeInOut(duration: 0.22)) {
                            keyboardInset = 0
                        }
                    }
                }
            }
            .blur(radius: viewModel.executingNoteId != nil ? 3 : 0)
            .opacity(viewModel.executingNoteId != nil ? 0.82 : 1.0)
            .allowsHitTesting(viewModel.executingNoteId == nil)
            .animation(.easeInOut(duration: 0.22), value: viewModel.executingNoteId)
            
            // LAYER 2: One Action Overlay (Glassmorphism)
            if let noteId = viewModel.executingNoteId,
               let note = viewModel.notes.first(where: { $0.id == noteId }),
               case .executing(let action) = note.state {
                OneActionOverlay(
                    action: action,
                    note: note,
                    viewModel: viewModel
                )
                .transition(.scale(scale: 0.8).combined(with: .opacity))
                .zIndex(100)
            }
            
            // LAYER 3: Error Toast (Safe area aware)
            if let error = viewModel.errorMessage {
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(MentorioColor.textOnAccent)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(error)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(MentorioColor.textOnAccent)
                                .lineLimit(3)
                            
                            if viewModel.lastFailedNoteId != nil {
                                Text("Нажми, чтобы повторить").font(.system(size: 10, weight: .regular))
                                    .foregroundColor(MentorioColor.textOnAccent.opacity(0.8))
                            }
                        }
                        
                        Spacer()
                        
                        // Retry button if operation is available
                        if viewModel.lastFailedNoteId != nil {
                            Button(action: {
                                viewModel.retryLastOperation()
                            }) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(MentorioColor.textOnAccent)
                            }
                        }
                    }
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                MentorioColor.danger,
                                MentorioColor.dangerDeep
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .cornerRadius(12)
                    .shadow(color: MentorioColor.danger.opacity(0.3), radius: 6, x: 0, y: 3)
                }
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(101)
            }
        }
        .background(MentorioColor.background)
        .safeAreaInset(edge: .bottom) {
            Color.clear
                .frame(height: keyboardInset)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(viewModel)
        }
    }

    private func updateKeyboardInset(from notification: Notification) {
        guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
            return
        }

        let bottomSafeArea = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first(where: { $0.isKeyWindow })?
            .safeAreaInsets.bottom ?? 0

        let overlap = max(0, frame.height - bottomSafeArea)
        withAnimation(.easeInOut(duration: 0.22)) {
            // Add adaptive breathing room while relying on system keyboard avoidance.
            keyboardInset = overlap > 0 ? min(120, max(12, overlap * 0.28)) : 0
        }
    }
}

// MARK: - One Action Overlay

struct OneActionOverlay: View {
    @Environment(\.colorScheme) private var colorScheme
    let action: String
    let note: BraindumpNote
    let viewModel: MentorioViewModel
    @State private var showRealityCheckSheet = false
    @State private var holdProgress: CGFloat = 0
    @State private var isHolding = false
    @State private var holdCompleted = false
    @State private var lastHapticStep = 0
    @State private var holdTimer: Timer? = nil

    private var holdButtonBaseColor: Color {
        colorScheme == .dark ? Color.black.opacity(0.78) : Color.black.opacity(0.74)
    }

    private var overlayTint: Color {
        colorScheme == .dark ? Color.black.opacity(0.62) : Color.black.opacity(0.36)
    }

    private var actionCardBackground: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(MentorioColor.surfaceElevated)
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(MentorioColor.stroke.opacity(0.55), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.34 : 0.18), radius: 26, x: 0, y: 12)
    }
    
    var body: some View {
        ZStack {
            Rectangle()
                .fill(overlayTint)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                Spacer().frame(height: 54)
                Spacer()
                
                VStack(spacing: 18) {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 10) {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(MentorioColor.accent)
                            Text("One Action")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(MentorioColor.textSecondary)
                        }

                        Text(action)
                            .font(.system(size: 22, weight: .semibold, design: .default))
                            .foregroundStyle(MentorioColor.textPrimary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("Сделай это сейчас или оставь в фокусе")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(MentorioColor.textSecondary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 22)
                    .frame(maxWidth: .infinity)
                    .background(actionCardBackground)
                    .padding(.horizontal, 20)
                    
                    VStack(spacing: 12) {
                        holdToCompleteButton
                        
                        Button(action: {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                viewModel.continueWithNextStep(for: note.id)
                            }
                        }) {
                            Text("Оставить в фокусе")
                                .frame(maxWidth: .infinity)
                                .padding(16)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(MentorioColor.textPrimary)
                                .background(MentorioColor.surface)
                                .cornerRadius(14)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .padding(.horizontal, 20)
                }
                
                Spacer()
            }
            .padding(.bottom, 30)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.97)))
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: note.state)
        .sheet(isPresented: $showRealityCheckSheet) {
            NavigationStack {
                VStack(spacing: 18) {
                    Text("Ожидание vs Реальность?")
                        .font(.title3.weight(.bold))
                        .multilineTextAlignment(.center)
                        .foregroundColor(MentorioColor.charcoal)

                    Text("Выбери честно. Это лучше любого текста.")
                        .font(.subheadline)
                        .foregroundColor(MentorioColor.mentorGray)
                        .multilineTextAlignment(.center)

                    VStack(spacing: 12) {
                        realityCheckButton(
                            title: RealityCheckResult.easierThanExpected.rawValue,
                            subtitle: "Задача оказалась легче, чем выглядела",
                            style: .accent,
                            action: {
                                commitRealityCheck(.easierThanExpected)
                            }
                        )

                        realityCheckButton(
                            title: RealityCheckResult.hardWork.rawValue,
                            subtitle: "Пришлось продавить трение",
                            style: .dark,
                            action: {
                                commitRealityCheck(.hardWork)
                            }
                        )
                    }

                    Spacer()
                }
                .padding(20)
                .navigationTitle("Результат")
                .navigationBarTitleDisplayMode(.inline)
            }
            .interactiveDismissDisabled(true)
            .presentationDetents([.height(320)])
            .presentationDragIndicator(.visible)
        }
        .onDisappear {
            resetHoldState()
        }
    }

    private var holdToCompleteButton: some View {
        GeometryReader { proxy in
            let width = proxy.size.width

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 14)
                    .fill(holdButtonBaseColor)

                RoundedRectangle(cornerRadius: 14)
                    .fill(
                        LinearGradient(
                            colors: [MentorioColor.accent, MentorioColor.accent.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(8, width * holdProgress))

                VStack(spacing: 2) {
                    Text(holdCompleted ? "Готово ✓" : "Зажми, чтобы закрыть")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                    Text(holdCompleted ? "" : "Зажми 3 секунды")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(.white.opacity(0.85))
                        .opacity(holdCompleted ? 0 : 1)
                }
                .frame(maxWidth: .infinity, minHeight: 56)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.white.opacity(isHolding ? 0.32 : 0.12), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 14))
            .simultaneousGesture(holdTrackingGesture)
            .highPriorityGesture(longPressGesture)
        }
        .frame(height: 56)
    }

    private var holdTrackingGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                if !isHolding && !holdCompleted {
                    startHold()
                }
            }
            .onEnded { _ in
                if !holdCompleted {
                    resetHoldState()
                }
            }
    }

    private var longPressGesture: some Gesture {
        LongPressGesture(minimumDuration: 3.0, maximumDistance: 18)
            .onEnded { _ in
                if !holdCompleted {
                    completeHold()
                }
            }
    }

    private func startHold() {
        isHolding = true
        holdProgress = 0
        holdCompleted = false
        lastHapticStep = 0

        let generator = UIImpactFeedbackGenerator(style: .rigid)
        generator.prepare()
        generator.impactOccurred(intensity: 0.25)

        holdTimer?.invalidate()
        holdTimer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { _ in
            guard isHolding, !holdCompleted else { return }
            holdProgress = min(1, holdProgress + 0.0067)

            let currentStep = min(4, Int(holdProgress * 4))
            if currentStep > lastHapticStep {
                lastHapticStep = currentStep
                let stepGenerator = UIImpactFeedbackGenerator(style: .rigid)
                stepGenerator.impactOccurred(intensity: CGFloat(currentStep) / 4.0)
            }

            if holdProgress >= 1 {
                completeHold()
            }
        }
        RunLoop.main.add(holdTimer!, forMode: .common)
    }

    private func completeHold() {
        guard !holdCompleted else { return }
        holdCompleted = true
        holdProgress = 1
        stopHoldTimer()

        let snap = UIImpactFeedbackGenerator(style: .heavy)
        snap.impactOccurred(intensity: 1)
        UINotificationFeedbackGenerator().notificationOccurred(.success)

        showRealityCheckSheet = true
    }

    private func resetHoldState() {
        stopHoldTimer()
        isHolding = false
        holdCompleted = false
        holdProgress = 0
        lastHapticStep = 0
        showRealityCheckSheet = false
    }

    private func stopHoldTimer() {
        holdTimer?.invalidate()
        holdTimer = nil
        isHolding = false
    }

    private func commitRealityCheck(_ result: RealityCheckResult) {
        viewModel.completeAction(noteId: note.id, realityCheck: result)
        resetHoldState()
    }

    private func realityCheckButton(
        title: String,
        subtitle: String,
        style: RealityCheckButtonStyle,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                    Text(subtitle)
                        .font(.system(size: 11, weight: .regular))
                        .opacity(0.8)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .opacity(0.8)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(style.background)
            .cornerRadius(16)
        }
        .buttonStyle(.plain)
    }

    private enum RealityCheckButtonStyle {
        case accent
        case dark

        var background: some View {
            switch self {
            case .accent:
                return AnyView(
                    LinearGradient(
                        colors: [MentorioColor.accent, MentorioColor.accent.opacity(0.8)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
            case .dark:
                return AnyView(
                    LinearGradient(
                        colors: [MentorioColor.neutralStrong, MentorioColor.neutralStrongAlt],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
            }
        }
    }
}

// MARK: - Preview

#Preview {
    MainDashboardView()
    .environmentObject(makePreviewViewModel())
}
