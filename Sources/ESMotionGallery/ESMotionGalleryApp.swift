import ESMotion
import SwiftUI

@main
struct ESMotionGalleryApp: App {
    var body: some Scene {
        WindowGroup {
            MotionHost {
                GalleryRootView()
            }
        }
    }
}

private enum GalleryRoute: Hashable {
    case weather
}

private struct GalleryRootView: View {
    var body: some View {
        MotionTransitionHost { namespace in
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("ESMotion Gallery")
                            .font(.largeTitle.bold())
                        Text("Hybrid navigation keeps the system route and adds registered visual continuity.")
                            .foregroundStyle(.secondary)

                        NavigationLink(value: GalleryRoute.weather) {
                            WeatherCard()
                        }
                        .buttonStyle(MotionSurfaceButtonStyle())
                        .motionTransitionSource(
                            id: MotionTransitionID("gallery.weather"),
                            in: namespace,
                            spec: .card
                        )
                    }
                    .padding(24)
                }
                .navigationDestination(for: GalleryRoute.self) { route in
                    switch route {
                    case .weather:
                        WeatherDetail()
                            .motionTransitionDestination(
                                id: MotionTransitionID("gallery.weather"),
                                in: namespace,
                                spec: .card
                            )
                    }
                }
            }
        }
    }
}

private struct WeatherCard: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.indigo, .cyan.opacity(0.72)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            MotionMetalParticleView(
                scene: MotionParticleScene(
                    id: "gallery.snow.card",
                    preset: .snow,
                    particleCount: 180
                )
            )
            HStack {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Snow")
                        .font(.title2.bold())
                    Text("Tap to expand")
                        .foregroundStyle(.white.opacity(0.76))
                }
                Spacer()
                Text("−3°")
                    .font(.system(size: 44, weight: .semibold))
                    .monospacedDigit()
            }
            .foregroundStyle(.white)
            .padding(22)
        }
        .frame(height: 190)
        .clipShape(.rect(cornerRadius: 24))
        .overlay {
            RoundedRectangle(cornerRadius: 24)
                .stroke(.white.opacity(0.18))
        }
    }
}

private struct WeatherDetail: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.indigo, .cyan.opacity(0.58), .black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            MotionMetalParticleView(
                scene: MotionParticleScene(
                    id: "gallery.snow.detail",
                    preset: .snow,
                    particleCount: 640,
                    budget: .foregroundScene
                )
            )
            VStack(spacing: 12) {
                Image(systemName: "snowflake")
                    .font(.system(size: 58))
                Text("−3°")
                    .font(.system(size: 82, weight: .thin))
                    .monospacedDigit()
                Text("Interruptible system navigation")
                    .font(.headline)
            }
            .foregroundStyle(.white)
        }
        .navigationTitle("Weather")
    }
}
