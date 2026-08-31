# ``ESMotion``

Build interruptible portal transitions with one live-scene runtime.

## Overview

ESMotion 0.2 keeps source and destination SwiftUI scenes alive in one container,
captures only explicitly registered portal regions, and drives one Core
Animation overlay from a frame-rate-independent state machine.

Use ``MotionPresentationHost`` with an application-owned item binding. Mark the
portal endpoints with ``SwiftUI/View/motionPortalSource(id:cornerRadius:isOpaque:snapshotProvider:)``
and ``SwiftUI/View/motionPortalDestination(id:cornerRadius:isOpaque:snapshotProvider:)``.

## Topics

### Host and engine

- ``MotionEngine``
- ``MotionPresentationHost``
- ``MotionEngineSnapshot``
- ``MotionDebugHUD``

### Portal registration

- ``MotionTransitionID``
- ``MotionPortalSnapshotProvider``
- ``MotionPortalSnapshotRequest``
- ``MotionSnapshotBudget``

### State and policy

- ``MotionTransitionMachine``
- ``MotionTransitionPhase``
- ``MotionTransitionConfiguration``
- ``MotionRuntimeConditions``
- ``MotionRuntimeDecision``
- ``MotionTransitionMetrics``
