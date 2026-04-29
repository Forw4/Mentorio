import SwiftUI

struct EntryOverlayView: View {
    @ObservedObject var viewModel: NotesViewModel
    @Binding var isPresented: Bool

    @State private var inputText: String = ""
    @State private var phase: EntryPhase = .input
    @State private var pendingDraftID: UUID?
    @State private var highlight: String = ""
    @State private var insight: String = ""
    @State private var choices: [String] = [
        "Open Xcode and create file",
        "Stand up and do 10 push-ups"
    ]

    @Namespace private var animation

    private enum EntryPhase {
        case input
        case transformation
    }

    var body: some View {
        ZStack {
            MentorioTheme.background.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Button("Close") {
                        isPresented = false
                    }
                    .foregroundStyle(.white.opacity(0.76))

                    Spacer()
                }

                if phase == .input {
                    inputPhase
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    transformationPhase
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 22)
            .padding(.top, 20)
            .animation(.spring(response: 0.46, dampingFraction: 0.9), value: phase)
        }
    }

    private var inputPhase: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("В чём затык?")
                .font(.largeTitle.bold())
                .fontDesign(.serif)
                .foregroundStyle(.white)

            TextEditor(text: $inputText)
                .font(.title3)
                .foregroundStyle(.white)
                .padding(8)
                .frame(minHeight: 320)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.white.opacity(0.07))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(MentorioTheme.stroke, lineWidth: 1)
                        )
                        .matchedGeometryEffect(id: "entryCard", in: animation)
                )

            Button {
                submitInput()
            } label: {
                Text("Transform")
                    .font(.headline)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(MentorioTheme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    private var transformationPhase: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("The Highlight")
                .font(.caption.weight(.semibold))
                .foregroundStyle(MentorioTheme.accent)

            Text("\"\(highlight)\"")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.white.opacity(0.07))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(MentorioTheme.stroke, lineWidth: 1)
                        )
                        .matchedGeometryEffect(id: "entryCard", in: animation)
                )

            Text("The Insight")
                .font(.caption.weight(.semibold))
                .foregroundStyle(MentorioTheme.accent)

            Text(insight)
                .font(.body)
                .foregroundStyle(.white.opacity(0.88))

            Text("The Two Choices")
                .font(.caption.weight(.semibold))
                .foregroundStyle(MentorioTheme.accent)
                .padding(.top, 6)

            ForEach(Array(choices.prefix(2).enumerated()), id: \.offset) { _, choice in
                Button {
                    applyChoice(choice)
                } label: {
                    Text(choice)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .padding(.horizontal, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color.white.opacity(0.09))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .stroke(MentorioTheme.accent.opacity(0.6), lineWidth: 1)
                                )
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func submitInput() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        pendingDraftID = viewModel.createDraft(from: trimmed)
        highlight = makeHighlight(from: trimmed)
        insight = makeInsight(from: trimmed)
        choices = makeChoices(from: trimmed)

        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            phase = .transformation
        }
    }

    private func applyChoice(_ choice: String) {
        if let pendingDraftID {
            viewModel.activateDraft(noteID: pendingDraftID, actionText: choice)
        } else {
            viewModel.activateNewAction(choice)
        }

        withAnimation(.easeInOut(duration: 0.25)) {
            isPresented = false
        }
    }

    private func makeHighlight(from text: String) -> String {
        let compact = text.replacingOccurrences(of: "\n", with: " ")
        if compact.count <= 80 {
            return compact
        }
        let index = compact.index(compact.startIndex, offsetBy: 80)
        return String(compact[..<index]) + "…"
    }

    private func makeInsight(from text: String) -> String {
        if text.count < 30 {
            return "You are not stuck. The task is undefined. Name one physical next step."
        }
        if text.split(separator: " ").count > 30 {
            return "This is cognitive load, not laziness. Reduce it to one visible move now."
        }
        return "You are delaying uncertainty. Action kills uncertainty faster than planning."
    }

    private func makeChoices(from text: String) -> [String] {
        let normalized = text.lowercased()

        if normalized.contains("xcode") || normalized.contains("swift") || normalized.contains("code") {
            return [
                "Open Xcode and create file",
                "Run project and fix one warning"
            ]
        }

        return [
            "Set a 5-minute timer and do first step",
            "Stand up, breathe, and write one concrete action"
        ]
    }
}

#Preview {
    EntryOverlayView(viewModel: NotesViewModel(), isPresented: .constant(true))
        .preferredColorScheme(.dark)
}
