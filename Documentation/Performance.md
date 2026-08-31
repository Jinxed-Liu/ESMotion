# ESMotion 0.2 performance contract

## Runtime invariants

- One display link exists only while a spring is animating.
- Per-frame progress does not invalidate SwiftUI Observation.
- A session contains exactly two portal snapshots.
- The default combined snapshot budget is 24 MB.
- Automatic capture is capped at 2x scale and can degrade to 0.75x.
- Snapshot capture, image downsampling, layout settlement, and provider work
  happen before the display driver starts.
- Dismissal reuses a warmed session so an edge gesture can display its first
  portal frame without recapturing.
- Cached snapshots are invalidated on size changes, explicit invalidation, or
  memory pressure.

## Runtime policy

| Condition | Preferred refresh | Snapshot multiplier | Behavior |
| --- | ---: | ---: | --- |
| Nominal | 120 Hz | 1.00 | Portal spring |
| Low power | 60 Hz | 0.80 | Portal spring |
| Fair thermal | 90 Hz | 0.90 | Portal spring |
| Serious thermal | 60 Hz | 0.72 | Portal spring |
| Reduce Motion | 60 Hz | 0.80 | Fixed-frame crossfade |
| Inactive / critical | stopped | n/a | Land on requested boundary |

The display may choose a supported rate different from the preference. The
analytic solver uses timestamps and does not assume a fixed refresh rate.

## Acceptance gates

Package and UI endpoint tests are necessary but do not prove visual quality.
Release acceptance requires all of the following on the target device path:

- no duplicate source or destination layer;
- no transparent hole or sampled-color patch;
- no competing custom and system edge gesture;
- no visible flash during live-view handoff;
- presentation, dismissal, cancellation, and rapid reversal share one path;
- Reduce Motion uses no spatial portal movement;
- first animated frame latency below 100 ms with a warmed session;
- p95 frame interval at or below 8.33 ms on a 120 Hz target;
- p99 frame interval at or below 16.67 ms;
- no main-thread stall at or above 100 ms;
- memory returns to within 10 MB of the warmed baseline after 50 cycles.

Use a Release build, Animation Hitches, Time Profiler, and representative
frame/video review. Report build, interaction, visual, performance, and physical
device evidence separately.
