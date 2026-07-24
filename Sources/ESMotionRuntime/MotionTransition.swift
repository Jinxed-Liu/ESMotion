import ESMotionCore
import SwiftUI

private struct MotionTransitionCoordinatorEnvironmentKey: EnvironmentKey {
    static let defaultValue: MotionTransitionCoordinator? = nil
}

public extension EnvironmentValues {
    var motionTransitionCoordinator: MotionTransitionCoordinator? {
        get { self[MotionTransitionCoordinatorEnvironmentKey.self] }
        set { self[MotionTransitionCoordinatorEnvironmentKey.self] = newValue }
    }
}

public struct MotionTransitionID: Hashable, Sendable {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public init<Value: CustomStringConvertible & Hashable & Sendable>(
        _ value: Value
    ) {
        rawValue = value.description
    }
}

public enum MotionTransitionPreset: String, Codable, Sendable {
    case card
    case avatar
    case listItem
    case sheet
    case numeric
}

public struct MotionTransitionSpec: Equatable, Sendable {
    public let preset: MotionTransitionPreset
    public let cornerRadius: CGFloat
    public let backgroundBlurRadius: CGFloat
    public let backgroundDimOpacity: Double
    public let spring: MotionSpring
    public let reducedMotionDuration: TimeInterval
    public let progressThreshold: Double
    public let velocityThreshold: Double

    public init(
        preset: MotionTransitionPreset,
        cornerRadius: CGFloat,
        backgroundBlurRadius: CGFloat = 0,
        backgroundDimOpacity: Double = 0,
        spring: MotionSpring = .transition,
        reducedMotionDuration: TimeInterval = 0.18,
        progressThreshold: Double = 0.35,
        velocityThreshold: Double = 900
    ) {
        self.preset = preset
        self.cornerRadius = max(cornerRadius, 0)
        self.backgroundBlurRadius = max(backgroundBlurRadius, 0)
        self.backgroundDimOpacity = min(max(backgroundDimOpacity, 0), 1)
        self.spring = spring
        self.reducedMotionDuration = max(reducedMotionDuration, 0)
        self.progressThreshold = min(max(progressThreshold, 0), 1)
        self.velocityThreshold = max(velocityThreshold, 0)
    }

    public static let card = MotionTransitionSpec(
        preset: .card,
        cornerRadius: 24,
        backgroundBlurRadius: 12,
        backgroundDimOpacity: 0.08
    )
    public static let avatar = MotionTransitionSpec(
        preset: .avatar,
        cornerRadius: 999
    )
    public static let listItem = MotionTransitionSpec(
        preset: .listItem,
        cornerRadius: 16
    )
    public static let sheet = MotionTransitionSpec(
        preset: .sheet,
        cornerRadius: 28,
        backgroundBlurRadius: 16,
        backgroundDimOpacity: 0.12
    )
    public static let numeric = MotionTransitionSpec(
        preset: .numeric,
        cornerRadius: 0
    )
}

@MainActor
public struct MotionTransitionHost<Content: View>: View {
    @Environment(\.motionTransitionCoordinator)
    private var inheritedCoordinator

    @Namespace private var namespace
    @State private var localCoordinator = MotionTransitionCoordinator()
    private let content: (Namespace.ID) -> Content
    private let showsDebugHUD: Bool
    private let renderingMode: MotionTransitionRenderingMode

    public init(
        showsDebugHUD: Bool = false,
        renderingMode: MotionTransitionRenderingMode = .system,
        @ViewBuilder content: @escaping (Namespace.ID) -> Content
    ) {
        self.showsDebugHUD = showsDebugHUD
        self.renderingMode = renderingMode
        self.content = content
    }

    public init(
        showsDebugHUD: Bool = false,
        renderingMode: MotionTransitionRenderingMode = .system,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.showsDebugHUD = showsDebugHUD
        self.renderingMode = renderingMode
        self.content = { _ in content() }
    }

    public var body: some View {
        let coordinator = inheritedCoordinator ?? localCoordinator
        content(namespace)
            .environment(
                \.motionTransitionCoordinator,
                coordinator
            )
            .overlay {
            #if os(iOS)
            if renderingMode == .compositor {
                MotionTransitionOverlayBridge(coordinator: coordinator)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            } else {
                Color.clear
            }
            #else
            Color.clear
            #endif
            }
            .overlay(alignment: .topTrailing) {
                if showsDebugHUD {
                    MotionTransitionDebugHUD(coordinator: coordinator)
                        .padding(12)
                        .allowsHitTesting(false)
                }
            }
    }
}

public extension View {
    func motionTransitionSource(
        id: MotionTransitionID,
        spec: MotionTransitionSpec = .card,
        snapshotPolicy: MotionTransitionSnapshotPolicy = .automatic
    ) -> some View {
        modifier(
            MotionTransitionRegistrationModifier(
                id: id,
                role: .source,
                spec: spec,
                snapshotPolicy: snapshotPolicy,
                proxy: nil
            )
        )
    }

    func motionTransitionDestination(
        id: MotionTransitionID,
        spec: MotionTransitionSpec = .card,
        proxy: MotionTransitionProxy
    ) -> some View {
        modifier(
            MotionTransitionRegistrationModifier(
                id: id,
                role: .destination,
                spec: spec,
                snapshotPolicy: .proxy,
                proxy: proxy
            )
        )
    }

    func motionTransitionSource(
        id: MotionTransitionID,
        in namespace: Namespace.ID,
        spec: MotionTransitionSpec = .card,
        background: Color = .clear
    ) -> some View {
        matchedTransitionSource(id: id, in: namespace) { source in
            source
                .background(background)
                .clipShape(.rect(cornerRadius: spec.cornerRadius))
        }
    }

    func motionTransitionDestination(
        id: MotionTransitionID,
        in namespace: Namespace.ID,
        spec: MotionTransitionSpec = .card
    ) -> some View {
        modifier(
            MotionTransitionDestinationModifier(
                id: id,
                namespace: namespace,
                spec: spec
            )
        )
    }

    func motionInteractiveDismiss(
        spec: MotionTransitionSpec = .card,
        edgeWidth: CGFloat = 32,
        onDismiss: @escaping @MainActor () -> Void
    ) -> some View {
        modifier(
            MotionInteractiveDismissModifier(
                spec: spec,
                edgeWidth: edgeWidth,
                transitionID: nil,
                onDismiss: onDismiss
            )
        )
    }

    func motionInteractiveDismiss(
        id: MotionTransitionID,
        spec: MotionTransitionSpec = .card,
        edgeWidth: CGFloat = 32,
        onDismiss: @escaping @MainActor () -> Void
    ) -> some View {
        modifier(
            MotionInteractiveDismissModifier(
                spec: spec,
                edgeWidth: edgeWidth,
                transitionID: id,
                onDismiss: onDismiss
            )
        )
    }
}

private struct MotionTransitionRegistrationModifier: ViewModifier {
    @Environment(\.motionTransitionCoordinator) private var coordinator

    let id: MotionTransitionID
    let role: MotionTransitionRegistrationRole
    let spec: MotionTransitionSpec
    let snapshotPolicy: MotionTransitionSnapshotPolicy
    let proxy: MotionTransitionProxy?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let coordinator {
            #if os(iOS)
            content.background {
                MotionTransitionRegistrationBridge(
                    coordinator: coordinator,
                    id: id,
                    role: role,
                    spec: spec,
                    snapshotPolicy: snapshotPolicy,
                    proxy: proxy
                )
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            #else
            content
            #endif
        } else {
            content
        }
    }
}

private struct MotionTransitionDestinationModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let id: MotionTransitionID
    let namespace: Namespace.ID
    let spec: MotionTransitionSpec

    @ViewBuilder
    func body(content: Content) -> some View {
        #if os(iOS)
        if reduceMotion {
            content
                .transition(.opacity)
                .animation(
                    .easeOut(duration: spec.reducedMotionDuration),
                    value: reduceMotion
                )
        } else {
            content.navigationTransition(
                .zoom(sourceID: id, in: namespace)
            )
        }
        #else
        content
            .transition(.opacity)
            .animation(
                .easeOut(duration: spec.reducedMotionDuration),
                value: reduceMotion
            )
        #endif
    }
}

private struct MotionInteractiveDismissModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.motionTransitionCoordinator) private var coordinator

    let spec: MotionTransitionSpec
    let edgeWidth: CGFloat
    let transitionID: MotionTransitionID?
    let onDismiss: @MainActor () -> Void

    @State private var translation: CGFloat = 0
    @State private var gestureStartedAtEdge = false
    @State private var containerWidth: CGFloat = 320

    func body(content: Content) -> some View {
        content
            .offset(x: reduceMotion ? 0 : max(translation, 0))
            .scaleEffect(
                reduceMotion
                    ? 1
                    : 1 - min(max(translation / 1_800, 0), 0.035)
            )
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { width in
                containerWidth = max(width, 1)
            }
            .modifier(
                MotionInteractiveGestureModifier(
                    coordinator: coordinator,
                    transitionID: transitionID,
                    spec: spec,
                    edgeWidth: edgeWidth,
                    containerWidth: containerWidth,
                    translation: $translation,
                    gestureStartedAtEdge: $gestureStartedAtEdge,
                    onDismiss: onDismiss
                )
            )
    }
}

private struct MotionInteractiveGestureModifier: ViewModifier {
    let coordinator: MotionTransitionCoordinator?
    let transitionID: MotionTransitionID?
    let spec: MotionTransitionSpec
    let edgeWidth: CGFloat
    let containerWidth: CGFloat
    @Binding var translation: CGFloat
    @Binding var gestureStartedAtEdge: Bool
    let onDismiss: @MainActor () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        #if os(iOS)
        if let coordinator, coordinator.activeTransitionID != nil {
            content.overlay {
                MotionTransitionEdgePanBridge(
                    coordinator: coordinator,
                    transitionID: transitionID,
                    routeMutation: onDismiss
                )
            }
        } else {
            legacyGesture(content)
        }
        #else
        legacyGesture(content)
        #endif
    }

    private func legacyGesture(_ content: Content) -> some View {
        content.simultaneousGesture(
            DragGesture(minimumDistance: 8)
                .onChanged { value in
                    if !gestureStartedAtEdge {
                        gestureStartedAtEdge =
                            value.startLocation.x <= edgeWidth
                    }
                    guard gestureStartedAtEdge else { return }
                    translation = max(value.translation.width, 0)
                }
                .onEnded { value in
                    defer { gestureStartedAtEdge = false }
                    guard gestureStartedAtEdge else { return }

                    var progress = MotionInteractiveProgress(
                        progress: min(
                            translation / max(containerWidth, 1),
                            1
                        )
                    )
                    let completedProgress = min(
                        max(
                            value.translation.width
                                / max(containerWidth, 1),
                            0
                        ),
                        1
                    )
                    let velocity = max(value.velocity.width, 0)
                    let completes = progress.finish(
                        projectedProgress: completedProgress,
                        velocity: velocity,
                        progressThreshold: spec.progressThreshold,
                        velocityThreshold: spec.velocityThreshold
                    )

                    if completes {
                        onDismiss()
                        translation = 0
                    } else {
                        withAnimation(
                            .spring(
                                duration: spec.spring.response,
                                bounce: max(
                                    0,
                                    1 - spec.spring.dampingRatio
                                )
                            )
                        ) {
                            translation = 0
                        }
                    }
                }
        )
    }
}
