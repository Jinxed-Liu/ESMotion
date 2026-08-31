# Changelog

## 0.2.0 - Unreleased

- Rebuilt ESMotion as a focused, dependency-free portal transition runtime.
- Replaced the mixed system/compositor paths with one live-scene container and
  one Core Animation overlay.
- Added a frame-rate-independent analytic spring and a single interruptible
  state machine for presentation, dismissal, cancellation, and reversal.
- Added explicit source and destination portal registration with optional
  static providers for continuously rendered content.
- Added a 24 MB two-snapshot budget, adaptive scale, warmed dismissal cache,
  memory-pressure release, and typed fallback metrics.
- Added an edge-driven interactive dismissal that does not claim or disable a
  native navigation-controller gesture.
- Added Reduce Motion, low-power, thermal, lifecycle, frame-statistic, and debug
  HUD support.
- Replaced the separate Demo and TransitionLab with one ESMotionShowcase target.
- Removed the 0.1 document, Lottie, Metal particle, CLI, Studio, and Gallery
  products from the 0.2 package boundary.

## 0.1.1 - 2026-07-23

- Rendered a deterministic first frame for suspended scenes.

## 0.1.0 - 2026-07-23

- Initial experimental motion platform.
