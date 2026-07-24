# Changelog

All notable changes follow Semantic Versioning.

## 0.2.0-alpha.1 - Unreleased

- Replaced the window-snapshot/multi-CALayer prototype with an isolated,
  opt-in single-surface Metal compositor. The Demo remains on native zoom;
  experimental work lives in `ESMotionTransitionLab`.
- Added a host-level transition coordinator with explicit route mutations,
  interruptible state, same-ID retargeting, and safe system fallback.
- Added one opaque `MTKView`, one display callback, one Metal render pass,
  precompiled shaders, source background patching, and required static target
  proxies.
- Added a 32 MB texture budget, route-settlement timeout handling, and O(1)
  `(transitionID, role)` registration lookup.
- Added edge-driven dismissal with 35%/900 pt/s completion thresholds, RTL
  support, cancellation, spring settling, and synchronized haptics.
- Added Reduce Motion crossfades, power/thermal quality degradation,
  `os_signpost` instrumentation, metrics, and the DEBUG HUD.
- Added the independent stable ESMotionDemo and isolated
  ESMotionTransitionLab targets with navigation UI tests and fixed
  0/25/50/75/100% container geometry goldens.
- Preserved all 0.1 namespace transition overloads.
- Added budget-aware destination proxy capture for compositor mode with automatic
  down-sampling when source/cleanBackdrop snapshots consume the shared limit.
- Made TransitionLab destination proxy generation aware of transition snapshot
  budgets so sample devices reduce capture scale before upload.

## 0.1.1 - 2026-07-23

- Rendered a deterministic first frame before display-link activation so suspended
  scenes never expose a transparent frame during navigation transitions.

## 0.1.0 - 2026-07-23

- Added Swift 6 package foundations for iOS 26 and macOS 26.
- Added shared display coordination, runtime policy, spring, sequencing, and metrics.
- Added hybrid SwiftUI navigation transition APIs and interactive-dismiss thresholds.
- Added Lottie loading, caching, playback, haptics, and Metal particle foundations.
- Added versioned motion documents, validation, deterministic JSON, CLI tools, and the initial Studio application.
