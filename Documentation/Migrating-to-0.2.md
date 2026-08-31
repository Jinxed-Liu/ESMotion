# Migrating to ESMotion 0.2

0.2 is intentionally source-breaking. It replaces the 0.1 platform rather than
layering another transition mode on top of it.

## Removed products

- `ESMotionDocument`
- `ESMotionMetal`
- `esmotionc`
- `ESMotionStudio`
- `ESMotionGallery`

Lottie playback, particles, document archives, generated symbols, and the
authoring applications can return later as independent packages if they have a
real product contract. They are not transition-runtime responsibilities.

## Removed transition APIs

- `MotionTransitionHost`
- `MotionTransitionCoordinator`
- `MotionTransitionRenderingMode`
- `MotionTransitionProxy`
- `MotionTransitionSnapshotPolicy`
- namespace-based source/destination overloads
- the compositor `present` and `dismiss` route-mutation calls

There is no stable/experimental mode split in 0.2.

## New host model

Use one `MotionPresentationHost` around the source and destination scenes.
Register an opaque source portal with `motionPortalSource` and an opaque
destination portal with `motionPortalDestination`. Change the item binding to
present or dismiss.

If the destination scene is active at initial launch, the host displays it
without inventing a source transition and warms a dismissal cache when both
registrations become available.

## Custom rendered content

Automatic view capture is appropriate for ordinary SwiftUI/UIKit content.
Continuously rendered surfaces must provide a static
`MotionPortalSnapshotProvider`. The provider receives the point size, remaining
byte count, and preferred scale; it must not perform networking, data queries,
or resource parsing during a transition.

## Application integration

Do not replace an existing production navigation path merely to adopt 0.2.
First validate the standalone Showcase visually and on hardware, then design a
small adapter at the intended application boundary. eSheepNext remains
unchanged during this rebuild.
