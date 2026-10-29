import SwiftUI

struct OpenWorldEasterEggView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var openCodes: Set<String> = []
    @State private var showMessage = false
    @State private var finished = false

    private let openColor = Color(red: 0.36, green: 0.82, blue: 0.52)

    var body: some View {
        ZStack {
            LinearGradient(
                colors: TravelCardPalette.colors,
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 36) {
                Spacer()

                WorldMapView(visitedCodes: openCodes, visitedColor: openColor)
                    .padding(.horizontal)
                    .accessibilityHidden(true)

                VStack(spacing: 14) {
                    Text("easteregg.message")
                        .font(.title2.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                    Text("easteregg.subtitle")
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.75))
                    Text(verbatim: "——\(AppInfo.displayName)")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(.top, 8)
                }
                .padding(.horizontal, 32)
                .opacity(showMessage ? 1 : 0)
                .offset(y: showMessage ? 0 : 12)

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 52, height: 52)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .circle)
                .accessibilityLabel("Close")
                .opacity(showMessage ? 1 : 0)
                .padding(.bottom)
            }
        }
        .preferredColorScheme(.dark)
        .sensoryFeedback(.success, trigger: finished)
        .task { await openTheWorld() }
    }

    private func openTheWorld() async {
        let codes = Set(WorldShapeStore.shared.map(\.iso)).filter { !$0.isEmpty }
        if reduceMotion {
            openCodes = codes
        } else {
            try? await Task.sleep(for: .milliseconds(500))
            let shuffled = codes.shuffled()
            let steps = 40
            let batch = max(1, Int((Double(shuffled.count) / Double(steps)).rounded(.up)))
            for start in stride(from: 0, to: shuffled.count, by: batch) {
                guard !Task.isCancelled else { return }
                openCodes.formUnion(shuffled[start..<min(start + batch, shuffled.count)])
                try? await Task.sleep(for: .milliseconds(60))
            }
        }
        finished = true
        withAnimation(.easeOut(duration: 1.2).delay(0.3)) {
            showMessage = true
        }
    }
}

#Preview {
    OpenWorldEasterEggView()
}
