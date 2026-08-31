# ESMotionShowcase

`ESMotionShowcase` is the only 0.2 example. It exercises the same runtime path
for tap presentation, close-button dismissal, edge-driven interaction,
cancellation, re-entry, Reduce Motion, and telemetry.

Generate and build:

```bash
cd Examples/ESMotionShowcase
xcodegen generate

xcodebuild \
  -project ESMotionShowcase.xcodeproj \
  -scheme ESMotionShowcase \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  test
```

Query `xcodebuild -showdestinations` first and use an available simulator
runtime or UUID. A passing UI test proves interaction endpoints only; review the
actual animation and metrics before accepting the engine.
