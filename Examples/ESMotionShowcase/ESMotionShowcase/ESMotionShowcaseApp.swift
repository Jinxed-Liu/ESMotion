import ESMotion
import SwiftUI

@main
struct ESMotionShowcaseApp: App {
  @State private var engine = MotionEngine()
  @State private var selection: ShowcaseRoute?
  @State private var showsDebugHUD: Bool

  init() {
    _showsDebugHUD = State(
      initialValue: ProcessInfo.processInfo.arguments.contains(
        "--esmotion-debug-hud"
      )
    )
  }

  var body: some Scene {
    WindowGroup {
      ZStack(alignment: .topTrailing) {
        MotionPresentationHost(
          item: $selection,
          engine: engine,
          transitionID: \.transitionID
        ) {
          ShowcaseHome(
            showsDebugHUD: $showsDebugHUD,
            onPresent: {
              selection = .portal
            }
          )
        } destination: { route in
          PortalDetail(
            route: route,
            onClose: {
              selection = nil
            }
          )
          .motionPortalDestination(
            id: route.transitionID,
            cornerRadius: 0
          )
        }
        .ignoresSafeArea()

        if showsDebugHUD {
          MotionDebugHUD(engine: engine)
            .padding(.top, 16)
            .padding(.trailing, 12)
            .allowsHitTesting(false)
        }
      }
      .background {
        Color.black.ignoresSafeArea()
      }
      .preferredColorScheme(.dark)
    }
  }
}

private enum ShowcaseRoute: String, Identifiable {
  case portal

  var id: String { rawValue }
  var transitionID: MotionTransitionID { "showcase.portal" }
}

private struct ShowcaseHome: View {
  @Binding var showsDebugHUD: Bool
  let onPresent: () -> Void

  private let portalID = MotionTransitionID("showcase.portal")

  var body: some View {
    ZStack {
      ShowcaseBackdrop()

      ScrollView {
        VStack(alignment: .leading, spacing: 26) {
          header
          portalCard
          architecturePanel
          verificationPanel
        }
        .padding(.horizontal, 20)
        .padding(.top, 28)
        .padding(.bottom, 44)
      }
      .scrollIndicators(.hidden)
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("showcase-home")
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 8) {
        StatusChip(text: "0.2", color: .cyan)
        StatusChip(text: "ONE RUNTIME", color: .mint)
      }

      Text("Motion without\nvisual lies.")
        .font(.system(size: 44, weight: .bold, design: .rounded))
        .tracking(-1.5)
        .foregroundStyle(.white)

      Text(
        "One live-scene container, one state machine, "
          + "one portal surface."
      )
      .font(.title3)
      .foregroundStyle(.white.opacity(0.62))
      .fixedSize(horizontal: false, vertical: true)
    }
  }

  private var portalCard: some View {
    Button(action: onPresent) {
      PortalCard()
        .contentShape(.rect(cornerRadius: 32))
        .motionPortalSource(
          id: portalID,
          cornerRadius: 32
        )
    }
    .buttonStyle(PortalPressStyle())
    .accessibilityLabel("Open portal transition")
    .accessibilityIdentifier("showcase-portal-card")
  }

  private var architecturePanel: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text("REBUILT CONTRACT")
        .font(.caption.bold())
        .tracking(1.4)
        .foregroundStyle(.white.opacity(0.5))

      FeatureRow(
        symbol: "rectangle.2.swap",
        title: "Live scenes",
        detail: "No full-window backdrop capture or color patching."
      )
      FeatureRow(
        symbol: "waveform.path",
        title: "Analytic spring",
        detail: "The same trajectory at 60, 90, and 120 Hz."
      )
      FeatureRow(
        symbol: "memorychip",
        title: "Bounded snapshots",
        detail: "Only the declared source and destination portals."
      )
    }
    .padding(20)
    .showcaseGlassPanel()
  }

  private var verificationPanel: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        VStack(alignment: .leading, spacing: 4) {
          Text("Runtime telemetry")
            .font(.headline)
          Text("Visible only in the showcase")
            .font(.caption)
            .foregroundStyle(.white.opacity(0.55))
        }
        Spacer()
        Toggle("", isOn: $showsDebugHUD)
          .labelsHidden()
          .tint(.cyan)
          .accessibilityLabel("Show runtime telemetry")
          .accessibilityIdentifier("showcase-debug-toggle")
      }
    }
    .padding(20)
    .showcaseGlassPanel(interactive: true)
  }
}

private struct PortalCard: View {
  var body: some View {
    ZStack(alignment: .bottomLeading) {
      PortalGradient()

      Circle()
        .fill(.white.opacity(0.13))
        .frame(width: 180, height: 180)
        .blur(radius: 2)
        .offset(x: 190, y: -105)

      VStack(alignment: .leading, spacing: 18) {
        HStack {
          Image(systemName: "sparkles.rectangle.stack.fill")
            .font(.system(size: 29, weight: .semibold))
            .frame(width: 62, height: 62)
            .background(
              .white.opacity(0.16),
              in: .rect(cornerRadius: 19)
            )
          Spacer()
          Image(systemName: "arrow.up.right")
            .font(.title3.bold())
            .padding(12)
            .background(
              .white.opacity(0.14),
              in: .circle
            )
        }

        Spacer(minLength: 20)

        Text("Enter the portal")
          .font(.system(size: 28, weight: .bold, design: .rounded))
        Text("Tap, return, cancel, or swipe from the edge.")
          .font(.subheadline)
          .foregroundStyle(.white.opacity(0.72))
      }
      .padding(24)
    }
    .foregroundStyle(.white)
    .frame(maxWidth: .infinity)
    .frame(height: 286)
    .clipShape(.rect(cornerRadius: 32))
    .overlay {
      RoundedRectangle(cornerRadius: 32)
        .stroke(.white.opacity(0.16), lineWidth: 1)
    }
    .shadow(color: .cyan.opacity(0.14), radius: 32, y: 18)
  }
}

private struct PortalDetail: View {
  let route: ShowcaseRoute
  let onClose: () -> Void

  var body: some View {
    ZStack {
      PortalGradient()
        .ignoresSafeArea()

      GeometryReader { proxy in
        Circle()
          .fill(.white.opacity(0.12))
          .frame(width: proxy.size.width * 0.92)
          .blur(radius: 4)
          .offset(
            x: proxy.size.width * 0.42,
            y: -proxy.size.height * 0.12
          )
      }

      VStack(alignment: .leading, spacing: 0) {
        detailToolbar
          .padding(.horizontal, 20)
          .padding(.top, 18)

        Spacer()

        VStack(alignment: .leading, spacing: 18) {
          Image(systemName: "sparkles.rectangle.stack.fill")
            .font(.system(size: 54, weight: .semibold))
            .frame(width: 112, height: 112)
            .background(
              .white.opacity(0.16),
              in: .rect(cornerRadius: 30)
            )

          Text("One visual authority.")
            .font(
              .system(
                size: 42,
                weight: .bold,
                design: .rounded
              )
            )
            .tracking(-1.2)

          Text(
            "The root scene stays alive underneath this portal. "
              + "Only two explicit surfaces move; no duplicated "
              + "NavigationStack animation is hiding below."
          )
          .font(.title3)
          .foregroundStyle(.white.opacity(0.72))
          .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 28)

        Spacer()

        metricStrip
          .padding(.horizontal, 20)
          .padding(.bottom, 36)
      }
    }
    .foregroundStyle(.white)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.black)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("showcase-detail")
  }

  @ViewBuilder
  private var detailToolbar: some View {
    HStack {
      Text("PORTAL / \(route.rawValue.uppercased())")
        .font(.caption.bold())
        .tracking(1.2)
        .foregroundStyle(.white.opacity(0.64))
      Spacer()
      Button(action: onClose) {
        Image(systemName: "xmark")
          .font(.headline)
          .frame(width: 44, height: 44)
      }
      .showcaseGlassButton()
      .accessibilityLabel("Close portal")
      .accessibilityIdentifier("showcase-close")
    }
  }

  @ViewBuilder
  private var metricStrip: some View {
    if #available(iOS 26.0, *) {
      GlassEffectContainer(spacing: 10) {
        metricItems
      }
    } else {
      metricItems
    }
  }

  private var metricItems: some View {
    HStack(spacing: 10) {
      MetricPill(value: "24 MB", label: "hard cap")
      MetricPill(value: "120 Hz", label: "preferred")
      MetricPill(value: "2", label: "surfaces")
    }
  }
}

private struct FeatureRow: View {
  let symbol: String
  let title: String
  let detail: String

  var body: some View {
    HStack(alignment: .top, spacing: 14) {
      Image(systemName: symbol)
        .font(.headline)
        .foregroundStyle(.cyan)
        .frame(width: 36, height: 36)
        .background(.cyan.opacity(0.12), in: .rect(cornerRadius: 11))

      VStack(alignment: .leading, spacing: 3) {
        Text(title)
          .font(.headline)
        Text(detail)
          .font(.subheadline)
          .foregroundStyle(.white.opacity(0.58))
      }
    }
  }
}

private struct StatusChip: View {
  let text: String
  let color: Color

  var body: some View {
    Text(text)
      .font(.caption2.bold())
      .tracking(1)
      .foregroundStyle(color)
      .padding(.horizontal, 10)
      .padding(.vertical, 7)
      .background(color.opacity(0.12), in: .capsule)
      .overlay {
        Capsule().stroke(color.opacity(0.24), lineWidth: 1)
      }
  }
}

private struct MetricPill: View {
  let value: String
  let label: String

  var body: some View {
    VStack(spacing: 2) {
      Text(value)
        .font(.subheadline.bold())
      Text(label)
        .font(.caption2)
        .foregroundStyle(.white.opacity(0.58))
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 13)
    .showcaseGlassPanel()
  }
}

private struct ShowcaseBackdrop: View {
  var body: some View {
    ZStack {
      Color(red: 0.025, green: 0.032, blue: 0.055)
      RadialGradient(
        colors: [.indigo.opacity(0.34), .clear],
        center: .topTrailing,
        startRadius: 10,
        endRadius: 440
      )
      RadialGradient(
        colors: [.cyan.opacity(0.18), .clear],
        center: .bottomLeading,
        startRadius: 20,
        endRadius: 500
      )
    }
    .ignoresSafeArea()
  }
}

private struct PortalGradient: View {
  var body: some View {
    LinearGradient(
      colors: [
        Color(red: 0.20, green: 0.12, blue: 0.56),
        Color(red: 0.05, green: 0.42, blue: 0.66),
        Color(red: 0.02, green: 0.68, blue: 0.63),
      ],
      startPoint: .topLeading,
      endPoint: .bottomTrailing
    )
  }
}

private struct PortalPressStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(configuration.isPressed ? 0.985 : 1)
      .brightness(configuration.isPressed ? -0.05 : 0)
      .animation(
        .spring(response: 0.2, dampingFraction: 0.84),
        value: configuration.isPressed
      )
  }
}

extension View {
  @ViewBuilder
  fileprivate func showcaseGlassPanel(interactive: Bool = false) -> some View {
    if #available(iOS 26.0, *) {
      if interactive {
        glassEffect(
          .regular.interactive(),
          in: .rect(cornerRadius: 22)
        )
      } else {
        glassEffect(.regular, in: .rect(cornerRadius: 22))
      }
    } else {
      background(
        .ultraThinMaterial,
        in: RoundedRectangle(cornerRadius: 22)
      )
    }
  }

  @ViewBuilder
  fileprivate func showcaseGlassButton() -> some View {
    if #available(iOS 26.0, *) {
      buttonStyle(.glass)
    } else {
      buttonStyle(.bordered)
    }
  }
}
