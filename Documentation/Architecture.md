# Architecture

ESMotion separates slow-changing environment policy from display-synchronized
frame delivery.

1. `MotionEngine` owns lifecycle, accessibility, power, and thermal policy.
2. `MotionDisplayCoordinator` owns the display link and callback registry.
3. Scenes receive immutable `MotionFrame` values through callbacks or a
   `MotionTimelineView`.
4. SwiftUI Observation publishes environment decisions only; it never publishes
   every display frame.
5. Hybrid transitions decorate `NavigationStack` rather than replacing routing.
6. Lottie assets are loaded and parsed before playback.
7. `.esmotion` documents contain data only. They never execute scripts or compile
   remote shaders.

## Dependency direction

```text
ESMotionCore
├── ESMotionDocument
├── ESMotionRuntime + Lottie
│   └── ESMotionMetal
└── ESMotion umbrella
    ├── esmotionc
    └── ESMotionStudio
```

The umbrella target re-exports the public modules. Domain applications should
not be imported by any engine target.
