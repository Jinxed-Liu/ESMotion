import ESMotion
import SwiftUI
import UIKit

@main
struct ESMotionTransitionLabApp: App {
    @State private var engine = MotionEngine()

    var body: some Scene {
        WindowGroup {
            MotionHost(engine: engine) {
                MotionTransitionHost(
                    showsDebugHUD: true,
                    renderingMode: .compositor
                ) {
                    TransitionLabRoot()
                }
            }
        }
    }
}

private struct TransitionLabRoot: View {
    @Environment(\.motionTransitionCoordinator) private var coordinator
    @State private var routeIsPresented = false
    @State private var isHandlingTap = false
    @State private var destinationProxy: MotionTransitionProxy

    private let transitionID = MotionTransitionID("lab-card")
    private let spec = MotionTransitionSpec(
        preset: .card,
        cornerRadius: 28,
        backgroundBlurRadius: 0,
        backgroundDimOpacity: 0
    )

    init() {
        _destinationProxy = State(
            initialValue: LabProxyFactory.detailProxy()
        )
    }

    var body: some View {
        NavigationStack {
            home
                .navigationDestination(isPresented: $routeIsPresented) {
                    detail
                }
        }
        .onChange(of: routeIsPresented) { _, isPresented in
            if !isPresented {
                isHandlingTap = false
            }
        }
    }

    private var home: some View {
        ZStack {
            Color(red: 0.055, green: 0.065, blue: 0.095)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 20) {
                Text("ESMotion Transition Lab")
                    .font(.largeTitle.bold())
                    .foregroundStyle(.white)

                Text("Single surface · single card · static proxy")
                    .foregroundStyle(.white.opacity(0.65))

                Button(action: present) {
                    LabCard()
                        .contentShape(.rect(cornerRadius: 28))
                        .motionTransitionSource(
                            id: transitionID,
                            spec: spec
                        )
                }
                .buttonStyle(MotionSurfaceButtonStyle(pressedScale: 0.985))
                .disabled(isHandlingTap)
                .accessibilityIdentifier("lab-card")

                Text("This target is intentionally isolated from the stable Demo.")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.48))

                Spacer()
            }
            .padding(22)
        }
        .navigationTitle("Lab")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var detail: some View {
        LabDetail(onDismiss: dismiss)
            .motionTransitionDestination(
                id: transitionID,
                spec: spec,
                proxy: destinationProxy
            )
            .motionInteractiveDismiss(
                id: transitionID,
                spec: spec,
                onDismiss: {
                    routeIsPresented = false
                }
            )
    }

    private func present() {
        guard !routeIsPresented, !isHandlingTap, let coordinator else {
            return
        }
        isHandlingTap = true
        coordinator.present(id: transitionID) {
            routeIsPresented = true
        }
    }

    private func dismiss() {
        guard routeIsPresented, let coordinator else { return }
        coordinator.dismiss(id: transitionID) {
            routeIsPresented = false
        }
    }
}

private struct LabCard: View {
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "waveform.path.ecg.rectangle")
                .font(.system(size: 31, weight: .semibold))
                .frame(width: 66, height: 66)
                .background(.white.opacity(0.16), in: .rect(cornerRadius: 20))

            VStack(alignment: .leading, spacing: 5) {
                Text("Single visual authority")
                    .font(.headline)
                Text("Tap to enter the compositor")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.68))
            }

            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(22)
        .frame(maxWidth: .infinity, minHeight: 154)
        .background(labGradient, in: .rect(cornerRadius: 28))
    }
}

private struct LabDetail: View {
    let onDismiss: @MainActor () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            labGradient.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 22) {
                Image(systemName: "waveform.path.ecg.rectangle")
                    .font(.system(size: 54, weight: .semibold))
                    .frame(width: 112, height: 112)
                    .background(.white.opacity(0.16), in: .rect(cornerRadius: 28))
                Text("Single visual authority")
                    .font(.largeTitle.bold())
                Text(
                    "The route exists below one opaque Metal surface. "
                        + "No second navigation animation is visible."
                )
                .font(.title3)
                .foregroundStyle(.white.opacity(0.75))
                Spacer()
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 28)
            .padding(.top, 34)
            .padding(.bottom, 40)
        }
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: onDismiss) {
                    Image(systemName: "chevron.left")
                }
                .accessibilityIdentifier("lab-back")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("lab-detail")
    }
}

private enum LabProxyFactory {
    @MainActor
    static func detailProxy() -> MotionTransitionProxy {
        let screen = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?
            .screen
        let size = screen?.bounds.size ?? CGSize(width: 440, height: 956)
        return MotionTransitionProxy(
            pointSize: size,
            isOpaque: true
        ) { request in
            let deviceScale = min(screen?.scale ?? 2, 2)
            let desiredScale = min(
                CGFloat(deviceScale),
                min(
                    CGFloat(request.preferredScale),
                    maxScaleForBudget(
                        pixelArea: size.width * size.height,
                        maxBytes: request.maximumByteCount
                    )
                )
            )
            let renderer = ImageRenderer(
                content: LabDetailProxyView()
                    .frame(width: size.width, height: size.height)
            )
            renderer.proposedSize = ProposedViewSize(size)
            renderer.scale = max(0.5, desiredScale)
            renderer.isOpaque = true
            return renderer.cgImage
        }
    }

    private static func maxScaleForBudget(
        pixelArea: Double,
        maxBytes: Int
    ) -> CGFloat {
        guard maxBytes > 0, pixelArea > 0 else { return 0.5 }
        let budgetedPixels = Double(maxBytes) / 4.0
        let budgetScale = sqrt(budgetedPixels / pixelArea)
        return max(0.5, CGFloat(min(budgetScale, 2)))
    }
}

private struct LabDetailProxyView: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            labGradient
            VStack(alignment: .leading, spacing: 22) {
                Image(systemName: "waveform.path.ecg.rectangle")
                    .font(.system(size: 54, weight: .semibold))
                    .frame(width: 112, height: 112)
                    .background(.white.opacity(0.16), in: .rect(cornerRadius: 28))
                Text("Single visual authority")
                    .font(.largeTitle.bold())
                Text(
                    "The route exists below one opaque Metal surface. "
                        + "No second navigation animation is visible."
                )
                .font(.title3)
                .foregroundStyle(.white.opacity(0.75))
                Spacer()
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 28)
            .padding(.top, 92)
            .padding(.bottom, 40)
        }
    }
}

private var labGradient: LinearGradient {
    LinearGradient(
        colors: [
            Color(red: 0.38, green: 0.19, blue: 0.78),
            Color(red: 0.08, green: 0.54, blue: 0.82),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}
