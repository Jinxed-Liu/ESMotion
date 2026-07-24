# ESMotion

ESMotion is an open-source Swift motion engine for iOS 26 and macOS 26. It keeps
`NavigationStack` as the routing authority while adding reusable motion budgets,
interruptible transition physics, shared-element transition adapters, Lottie
playback, Metal scene infrastructure, a versioned document model, and a native
authoring studio.

The project is in `0.x` development. Public APIs may change before 1.0 with a
documented migration path.

## Products

- `ESMotionCore`: clocks, runtime policy, springs, interactive progress, sequences,
  and metrics primitives.
- `ESMotionRuntime`: SwiftUI host integration, hybrid navigation transitions,
  Lottie playback, haptics, activation staging, and display coordination.
- `ESMotionMetal`: shared-display-link Metal surfaces and particle scenes.
- `ESMotionDocument`: the versioned `.esmotion` manifest and validation model.
- `esmotionc`: validation, deterministic ZIP packaging, integrity checks, and
  Swift symbol generation.
- `ESMotionStudio`: a native macOS layer/timeline/canvas authoring baseline.

## Swift Package Manager

```swift
.package(url: "https://github.com/Jinxed-Liu/ESMotion.git", from: "0.1.0")
```

Then depend on the umbrella product:

```swift
.product(name: "ESMotion", package: "ESMotion")
```

## Stable transition example

```swift
@State private var engine = MotionEngine()
@State private var selectedCard: Card?

MotionHost(engine: engine) {
    MotionTransitionHost { namespace in
        NavigationStack {
            Button {
                selectedCard = card
            } label: {
                CardView(card: card)
                    .motionTransitionSource(
                        id: MotionTransitionID(card.id),
                        in: namespace,
                        spec: .card
                    )
            }
            .navigationDestination(item: $selectedCard) { card in
                CardDetail(card: card)
                    .motionTransitionDestination(
                        id: MotionTransitionID(card.id),
                        in: namespace,
                        spec: .card
                    )
                    .motionInteractiveDismiss {
                        selectedCard = nil
                    }
            }
        }
    }
}
```

This namespace-based path uses the native zoom transition and is the only
transition compositor enabled by default. The 0.2 snapshot compositor is
quarantined behind
`MotionTransitionHost(renderingMode: .compositor)` while its
single-surface rewrite is validated. Do not enable it in a production host.

`Examples/ESMotionTransitionLab` is the isolated compositor target. It uses
one opaque `MTKView`, one display callback, one Metal render pass, and a
required static destination proxy.

## ESMotionDemo

`Examples/ESMotionDemo` is a standalone iOS host using the stable native
shared-element path. It covers card presentation, button and edge dismissal,
rapid-tap protection, deep-link entry, and system fallback.

```bash
cd Examples/ESMotionDemo
xcodegen generate
xcodebuild \
  -project ESMotionDemo.xcodeproj \
  -scheme ESMotionDemo \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  test
```

## Performance contract

- A host owns one `MotionDisplayCoordinator`.
- When the experimental compositor is explicitly enabled, a transition host
  owns one coordinator, one overlay, and at most one active transition session.
- Per-frame ticks use callbacks rather than Observation invalidation.
- Source and destination snapshots share a 32 MB session budget and are captured
  once.
- High-impact interactions request 80–120 Hz only while active.
- Ambient scenes use 30 Hz by default and reduce quality under power or thermal
  pressure.
- Background, critical thermal pressure, and Reduce Motion suspend continuous
  motion.
- Resource loading and Lottie parsing happen before playback, never inside an
  animation frame.

For refresh rates above 60 Hz, host apps must set
`CADisableMinimumFrameDurationOnPhone` to `YES`.

## Development

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift run esmotionc help
```

See [Architecture](Documentation/Architecture.md) and
[Performance](Documentation/Performance.md). The 0.1 compatibility notes are in
[Migrating to 0.2](Documentation/Migrating-to-0.2.md).

## License

Apache-2.0. Lottie is provided by Airbnb under Apache-2.0; see [NOTICE](NOTICE).
