import SwiftUI

@main
struct MentorioApp: App {
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome: Bool = false

    var body: some Scene {
        WindowGroup {
            Group {
                if !hasSeenWelcome {
                    WelcomeGateView(hasSeenWelcome: $hasSeenWelcome)
                } else {
                    RootView()
                }
            }
            .preferredColorScheme(.dark)
            .background(MentorioTheme.background.ignoresSafeArea())
            .tint(MentorioTheme.accent)
        }
    }
}

private struct WelcomeGateView: View {
    @Binding var hasSeenWelcome: Bool

    var body: some View {
        ZStack {
            MentorioTheme.background.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 20) {
                Spacer()

                Text("Mentorio")
                    .font(.largeTitle.bold())
                    .fontDesign(.serif)
                    .foregroundStyle(.white)

                Text("Minimal tool for action over procrastination.")
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.78))

                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        hasSeenWelcome = true
                    }
                } label: {
                    Text("Start")
                        .font(.headline)
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(MentorioTheme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }

                Spacer()
            }
            .padding(.horizontal, 24)
        }
    }
}
