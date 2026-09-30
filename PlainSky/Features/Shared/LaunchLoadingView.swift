import SwiftUI

/// Matches the system launch screen (`LaunchBackground` in Info.plist) so the
/// handoff from launch to app is invisible. Shown while the app holds its first
/// reveal, and as the privacy cover while the app is not active.
struct LaunchLoadingView: View {
    var showsProgress = true

    /// Fast loads finish before the spinner appears, so they look like one
    /// uninterrupted launch screen.
    @State private var isSpinnerVisible = false

    var body: some View {
        ZStack {
            Color("LaunchBackground")
                .ignoresSafeArea()

            if showsProgress {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
                    .opacity(isSpinnerVisible ? 1 : 0)
            }
        }
        .task {
            guard showsProgress else { return }
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.2)) {
                isSpinnerVisible = true
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(showsProgress ? "Loading weather" : "")
        .accessibilityHidden(!showsProgress)
    }
}

#Preview {
    LaunchLoadingView()
}
