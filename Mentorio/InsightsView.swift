import SwiftUI

struct InsightsView: View {
    var body: some View {
        ZStack {
            MentorioTheme.background.ignoresSafeArea()

            VStack(spacing: 16) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 36, weight: .thin))
                    .foregroundStyle(MentorioTheme.accent.opacity(0.5))

                Text("Insights")
                    .font(.title3.weight(.semibold))
                    .fontDesign(.serif)
                    .foregroundStyle(MentorioTheme.primaryText)

                Text("Скоро здесь появятся инсайты\nо твоём прогрессе")
                    .font(.subheadline)
                    .foregroundStyle(MentorioTheme.secondaryText)
                    .multilineTextAlignment(.center)
            }
        }
    }
}

#Preview {
    InsightsView()
        .preferredColorScheme(.dark)
}
