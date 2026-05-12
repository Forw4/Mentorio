import SwiftUI

@main
struct MentorioApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome: Bool = false
    @AppStorage("appTheme") private var appTheme: AppTheme = .system

    var body: some Scene {
        WindowGroup {
            Group {
                if !hasSeenWelcome {
                    WelcomeGateView(hasSeenWelcome: $hasSeenWelcome)
                } else {
                    RootView()
                }
            }
            .preferredColorScheme(appTheme.colorScheme)
            .animation(.easeInOut(duration: 0.3), value: appTheme)
            .background(MentorioTheme.background.ignoresSafeArea())
            .tint(MentorioTheme.accent)
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    NotificationManager.shared.handleAppBecameActive()
                }
            }
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
                    .foregroundStyle(MentorioTheme.primaryText)

                Text("Minimal tool for action over procrastination.")
                    .font(.body)
                    .foregroundStyle(MentorioTheme.secondaryText)

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
