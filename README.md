# ESMotion 0.2

ESMotion 0.2 is a focused portal-transition runtime for SwiftUI applications on
iOS 26. It is a clean rewrite: the 0.1 document, Lottie, particle, Studio,
Gallery, CLI, and experimental compositor layers are not part of this release.

The runtime has one job: move between a live source scene and a live destination
scene without exposing a second navigation animation, duplicating content, or
capturing and patching an entire window.

## What changed

- One analytic, interruptible state machine drives presentation, dismissal,
  cancellation, and rapid reversal.
- One UIKit scene container keeps source and destination SwiftUI trees alive.
- One Core Animation overlay renders two explicit portal snapshots.
- Source and destination snapshots share a 24 MB hard limit and default to at
  most 2x scale.
- No full-window snapshots, sampled-color hole filling, runtime Metal shader
  compilation, or competing native/custom edge gestures.
- Reduce Motion uses a fixed destination frame with a short crossfade.
- The host binding remains authoritative when the runtime is resting.

## Package products

- `ESMotionCore`: spring solver, transition state machine, portal geometry,
  runtime policy, and frame statistics.
- `ESMotionRuntime`: SwiftUI registration, live-scene container, snapshot
  budgeting, display driver, edge interaction, metrics, and diagnostics.
- `ESMotion`: umbrella product that re-exports both modules.

The package has no third-party dependencies.

## Minimal integration

```swift
@State private var engine = MotionEngine()
@State private var route: Route?

MotionPresentationHost(
    item: $route,
    engine: engine,
    transitionID: \.motionID
) {
    Button {
        route = .detail
    } label: {
        CardView()
            .motionPortalSource(
                id: Route.detail.motionID,
                cornerRadius: 28
            )
    }
} destination: { route in
    DetailView {
        self.route = nil
    }
    .motionPortalDestination(
        id: route.motionID,
        cornerRadius: 0
    )
}
```

Apply the destination modifier to an opaque, full-scene view for a
card-to-screen portal. Metal, video, camera, and other continuously rendered
content should provide a prepared `MotionPortalSnapshotProvider`.

## Verification

```bash
swift test

xcodebuild \
  -project Examples/ESMotionShowcase/ESMotionShowcase.xcodeproj \
  -scheme ESMotionShowcase \
  -destination 'generic/platform=iOS Simulator' \
  build
```

Generate the example project after changing `project.yml`:

```bash
cd Examples/ESMotionShowcase
xcodegen generate
```

See [Architecture](Documentation/Architecture.md),
[Performance](Documentation/Performance.md), and
[Migrating to 0.2](Documentation/Migrating-to-0.2.md).

ESMotion 0.2 is not integrated into eSheepNext yet. That integration is a
separate acceptance phase after standalone visual and device validation.

## License

Apache-2.0.
