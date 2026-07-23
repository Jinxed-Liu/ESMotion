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

## Hybrid transition example

```swift
@Namespace private var transitionNamespace

Button {
    selectedCard = card
} label: {
    CardView(card: card)
        .motionTransitionSource(
            id: MotionTransitionID(card.id),
            in: transitionNamespace,
            spec: .card
        )
}
.buttonStyle(MotionSurfaceButtonStyle())

.navigationDestination(item: $selectedCard) { card in
    CardDetail(card: card)
        .motionTransitionDestination(
            id: MotionTransitionID(card.id),
            in: transitionNamespace,
            spec: .card
        )
}
```

The system navigation stack, deep links, and ordinary back behavior remain in
charge. If a transition cannot be resolved, navigation still succeeds.

## Performance contract

- A host owns one `MotionDisplayCoordinator`.
- Per-frame ticks use callbacks rather than Observation invalidation.
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
[Performance](Documentation/Performance.md).

## License

Apache-2.0. Lottie is provided by Airbnb under Apache-2.0; see [NOTICE](NOTICE).
