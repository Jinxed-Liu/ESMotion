import ESMotion
import SwiftUI

@main
struct ESMotionDemoApp: App {
    @State private var engine = MotionEngine()

    var body: some Scene {
        WindowGroup {
            MotionHost(engine: engine) {
                MotionTransitionHost(
                    showsDebugHUD: ProcessInfo.processInfo.environment[
                        "ESMOTION_DEBUG_HUD"
                    ] == "1"
                ) { namespace in
                    DemoNavigationRoot(namespace: namespace)
                }
            }
        }
    }
}

private enum DemoRoute: String, Identifiable {
    case card
    case fallback

    var id: String { rawValue }
}

private struct DemoNavigationRoot: View {
    @State private var route: DemoRoute?

    let namespace: Namespace.ID
    private let transitionID = MotionTransitionID("demo-card")

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    title
                    Button {
                        presentCard()
                    } label: {
                        DemoCard()
                            .contentShape(.rect(cornerRadius: 28))
                            .motionTransitionSource(
                                id: transitionID,
                                in: namespace,
                                spec: transitionSpec,
                                background: .clear
                            )
                    }
                    .buttonStyle(MotionSurfaceButtonStyle(pressedScale: 0.98))
                    .accessibilityIdentifier("demo-card")

                    Button("Test system fallback") {
                        presentFallback()
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("demo-fallback")

                    Text(
                        "Tap the card, use the back button, or swipe from the screen edge. "
                            + "The NavigationStack remains the route authority."
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
                .padding(20)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("ESMotion 0.2")
            .navigationDestination(item: $route) { destination in
                switch destination {
                case .card:
                    detail
                case .fallback:
                    FallbackDetail()
                }
            }
        }
        .onAppear {
            if ProcessInfo.processInfo.arguments.contains(
                "ESMOTION_DEEP_LINK_DEMO"
            ) {
                route = .card
            }
        }
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Native card transition")
                .font(.title2.bold())
            Text("System-owned navigation and interactive return.")
                .foregroundStyle(.secondary)
        }
    }

    private var detail: some View {
        DemoDetail()
            .motionTransitionDestination(
                id: transitionID,
                in: namespace,
                spec: transitionSpec
            )
    }

    private func presentCard() {
        guard route == nil else { return }
        route = .card
    }

    private func presentFallback() {
        guard route == nil else { return }
        route = .fallback
    }

    private var transitionSpec: MotionTransitionSpec {
        MotionTransitionSpec(
            preset: .card,
            cornerRadius: 28,
            backgroundBlurRadius: 16,
            backgroundDimOpacity: 0.10
        )
    }

}

private struct DemoCard: View {
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 32, weight: .semibold))
                .frame(width: 64, height: 64)
                .background(.white.opacity(0.20), in: .rect(cornerRadius: 18))

            VStack(alignment: .leading, spacing: 6) {
                Text("Shared-element motion")
                    .font(.headline)
                Text("Tap to expand")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.76))
            }

            Spacer(minLength: 0)
            Image(systemName: "arrow.up.right")
                .font(.headline)
        }
        .foregroundStyle(.white)
        .padding(22)
        .frame(maxWidth: .infinity, minHeight: 150)
        .background(demoGradient, in: .rect(cornerRadius: 28))
        .shadow(color: .indigo.opacity(0.22), radius: 24, y: 12)
    }
}

private struct DemoDetail: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            demoGradient
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 22) {
                Image(systemName: "sparkles")
                    .font(.system(size: 48, weight: .semibold))
                    .frame(width: 104, height: 104)
                    .background(
                        .white.opacity(0.20),
                        in: .rect(cornerRadius: 26)
                    )

                Text("Shared-element motion")
                    .font(.largeTitle.bold())

                Text(
                    "The system zoom transition keeps presentation, the back "
                        + "button, and the edge gesture on one navigation state machine."
                )
                .font(.title3)
                .foregroundStyle(.white.opacity(0.80))

                Spacer()
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 30)
            .padding(.top, 30)
            .padding(.bottom, 40)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("demo-detail")
    }
}

private struct FallbackDetail: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            ContentUnavailableView(
                "System fallback",
                systemImage: "arrow.triangle.branch",
                description: Text(
                    "The route still succeeds when no transition source is registered."
                )
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("fallback-detail")
        .navigationTitle("Fallback")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Back") {
                    dismiss()
                }
            }
        }
    }
}

private var demoGradient: LinearGradient {
    LinearGradient(
        colors: [
            Color(red: 0.24, green: 0.18, blue: 0.70),
            Color(red: 0.14, green: 0.48, blue: 0.90),
            Color(red: 0.08, green: 0.72, blue: 0.82),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}
