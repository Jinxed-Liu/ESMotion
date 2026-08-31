# ESMotion 0.2 architecture

## Product boundary

0.2 is a portal transition runtime, not a general animation authoring platform.
It does not own business data, navigation models, networking, assets, or
application routing. A host binding is authoritative before and after a
transition.

## Dependency direction

```text
ESMotionCore
    transition state + analytic spring + geometry + policy + metrics
        ↓
ESMotionRuntime
    SwiftUI registration + live-scene host + snapshots + display driver
        ↓
ESMotion
    umbrella exports only
```

No target imports an application module.

## One transition path

1. The host binding changes from `nil` to an item.
2. `MotionPresentationHost` mounts the destination scene above the still-live
   source scene.
3. The registry resolves exactly one source portal and one destination portal
   with the same `MotionTransitionID`.
4. The runtime snapshots only those two registered regions. A custom provider
   can replace view capture for Metal, video, or camera content.
5. The live portal views are hidden. One Core Animation overlay becomes the
   visual authority.
6. One display link advances one analytic spring and renders portal geometry.
7. At the boundary, the destination live view is made visible before the
   overlay is removed.
8. Dismissal reuses the same cached surfaces in reverse. An edge pan scrubs the
   same state machine and either settles to source or cancels to destination.

## Why both scenes remain live

The old runtime mutated `NavigationStack`, captured a window, guessed the
background behind the source, and then attempted to cover the second animation.
That architecture created duplicated layers, transparent holes, fragile route
settlement timing, and large three-surface memory pressure.

The 0.2 container keeps both scenes mounted. The root is visible around the
expanding portal, while the destination is already laid out and can be captured
without a route-settlement poll. There is no fabricated backdrop.

## State ownership

- The application owns `Binding<Item?>`.
- `MotionPresentationHost` owns the two hosting controllers.
- `MotionEngine` owns the transition machine, runtime conditions, and metrics.
- `MotionElementRegistry` owns weak portal registrations.
- `MotionPortalOverlayView` owns only the current two image layers.
- `MotionDisplayDriver` exists only while a spring is advancing.

SwiftUI Observation publishes phase and completed metrics. Per-frame progress is
explicitly excluded from Observation and is consumed directly by the UIKit
renderer.

## Failure behavior

Missing registrations, invalid frames, failed snapshots, budget exhaustion, an
inactive scene, or interruption never trap the host. The runtime lands on the
binding-requested boundary, removes temporary surfaces, records a typed failure
in `MotionTransitionMetrics`, and leaves routing usable.

## Deliberate exclusions

- No full-window snapshot or sampled-color background patch.
- No hidden second NavigationStack transition.
- No Lottie, particle, document archive, CLI, Studio, or Gallery targets.
- No remote code, shader, or asset execution.
- No eSheepNext integration in this phase.
