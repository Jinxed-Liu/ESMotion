# Migrating to ESMotion 0.2

ESMotion 0.2 keeps the namespace-based 0.1 transition API. Existing hosts do
not need a source change and continue to use the system zoom transition.

The host-level snapshot overlay is currently experimental and disabled by
default because automatic window capture can duplicate live NavigationStack
content. Production hosts should stay on the namespace-based system zoom path.

To test the isolated compositor prototype:

1. Put
   `MotionTransitionHost(renderingMode: .compositor)` below
   `MotionHost`.
2. Remove the explicit `Namespace` argument from registered source and
   destination modifiers.
3. Mutate the route inside `MotionTransitionCoordinator.present` and
   `dismiss`.
4. Provide a `MotionTransitionProxy` to the destination registration.
5. Add `motionInteractiveDismiss(id:onDismiss:)` when the destination should
   support the engine's edge-driven return.

The route binding or `NavigationPath` remains the source of truth. ESMotion
does not own, replace, or serialize navigation state.

Do not enable this prototype in eSheepNext or another production host until
the single-surface compositor passes the Demo visual and interaction gates.

## Static proxies

Metal, Lottie, camera, and other continuously rendered surfaces must provide
a `MotionTransitionProxy`. Render a static, visually compatible proxy before
the transition begins; never parse resources, decode images, or query business
data in the provider.

## Fallback

Missing hosts, registrations, snapshots, or snapshot budget automatically
execute the route mutation without blocking navigation. Hosts can inspect
`latestMetrics.fallbackReason` or enable the DEBUG HUD to diagnose the reason.
