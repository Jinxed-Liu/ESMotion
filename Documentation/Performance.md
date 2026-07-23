# Performance

## Frame budgets

| Workload | Minimum | Maximum | Preferred |
| --- | ---: | ---: | ---: |
| Interactive transition | 80 Hz | 120 Hz | 120 Hz |
| Foreground scene | 30 Hz | 60 Hz | 60 Hz |
| Ambient scene | 15 Hz | 30 Hz | 30 Hz |
| Low power ambient | 10 Hz | 20 Hz | 15 Hz |

The system may choose a different supported refresh rate. Motion must always use
timestamps rather than assuming a fixed frame delta.

## Rules

- Maintain one display link per host.
- Never parse JSON, decode images, sort collections, or perform networking in a
  frame callback.
- Register only visible scenes and unregister them on disappearance.
- Use stable IDs for transition sources and destinations.
- Reduce render scale using policy bands with hysteresis; do not react to every
  individual slow frame.
- Stop continuous display updates when no callback is registered.
- Profile Release builds on physical hardware using Animation Hitches, Time
  Profiler, and Metal System Trace.

## Acceptance reference

On an iPhone 16 Pro:

- transition p95 frame interval ≤ 8.33 ms;
- transition p99 frame interval ≤ 16.67 ms;
- no main-thread hang ≥ 100 ms;
- no leak after 50 repeated push/pop cycles;
- settled memory no more than 10 MB above the warmed baseline.
