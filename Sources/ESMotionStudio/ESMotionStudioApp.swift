import ESMotion
import Observation
import SwiftUI

@main
struct ESMotionStudioApp: App {
    @State private var project = StudioProject()

    var body: some Scene {
        WindowGroup("ESMotion Studio") {
            StudioRootView(project: project)
                .frame(minWidth: 1_080, minHeight: 680)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Motion Project") {
                    project.reset()
                }
                .keyboardShortcut("n")
            }
        }
    }
}

@MainActor
@Observable
private final class StudioProject {
    var document = MotionDocument(
        name: "Untitled Motion",
        layers: [
            MotionLayer(name: "Card", kind: .shape),
            MotionLayer(name: "Title", kind: .text),
        ]
    )
    var selectedLayerID: UUID?
    var playhead: Double = 0
    var isPlaying = false

    func reset() {
        document = MotionDocument(name: "Untitled Motion")
        selectedLayerID = nil
        playhead = 0
        isPlaying = false
    }
}

private struct StudioRootView: View {
    @Bindable var project: StudioProject

    var body: some View {
        NavigationSplitView {
            StudioSidebar(project: project)
                .navigationSplitViewColumnWidth(min: 210, ideal: 250)
        } content: {
            StudioCanvas(project: project)
                .navigationSplitViewColumnWidth(min: 520, ideal: 720)
        } detail: {
            StudioInspector(project: project)
                .navigationSplitViewColumnWidth(min: 250, ideal: 290)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            StudioTimeline(project: project)
        }
    }
}

private struct StudioSidebar: View {
    @Bindable var project: StudioProject

    var body: some View {
        List(selection: $project.selectedLayerID) {
            Section("Layers") {
                ForEach(project.document.layers) { layer in
                    Label(
                        layer.name,
                        systemImage: symbol(for: layer.kind)
                    )
                    .tag(layer.id)
                }
            }

            Section("States") {
                ForEach(project.document.states) { state in
                    Label(state.name, systemImage: "point.3.connected.trianglepath.dotted")
                }
            }
        }
        .navigationTitle(project.document.name)
    }

    private func symbol(for kind: MotionLayerKind) -> String {
        switch kind {
        case .shape:
            "square.on.circle"
        case .text:
            "textformat"
        case .image:
            "photo"
        case .lottie:
            "sparkles.rectangle.stack"
        case .precomposition:
            "square.stack.3d.up"
        case .particle:
            "aqi.medium"
        }
    }
}

private struct StudioCanvas: View {
    @Bindable var project: StudioProject

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color(nsColor: .windowBackgroundColor)

                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .fill(.black)
                    .overlay {
                        ZStack {
                            LinearGradient(
                                colors: [
                                    Color.indigo.opacity(0.8),
                                    Color.cyan.opacity(0.42),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            VStack(spacing: 14) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 44, weight: .medium))
                                Text("ESMotion")
                                    .font(.largeTitle.bold())
                                Text("Interactive motion canvas")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .clipShape(.rect(cornerRadius: 34))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 34)
                            .stroke(.white.opacity(0.16))
                    }
                    .aspectRatio(
                        project.document.canvas.width
                            / project.document.canvas.height,
                        contentMode: .fit
                    )
                    .frame(
                        maxWidth: min(proxy.size.width - 96, 430),
                        maxHeight: proxy.size.height - 76
                    )
                    .shadow(color: .black.opacity(0.28), radius: 30, y: 16)
            }
        }
        .navigationTitle("Canvas")
        .toolbar {
            ToolbarItemGroup {
                Button {
                    project.isPlaying.toggle()
                } label: {
                    Label(
                        project.isPlaying ? "Pause" : "Play",
                        systemImage: project.isPlaying ? "pause.fill" : "play.fill"
                    )
                }
                Button {
                    project.playhead = 0
                    project.isPlaying = false
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
            }
        }
    }
}

private struct StudioInspector: View {
    @Bindable var project: StudioProject

    var body: some View {
        Form {
            Section("Canvas") {
                LabeledContent("Width") {
                    Text(project.document.canvas.width, format: .number)
                }
                LabeledContent("Height") {
                    Text(project.document.canvas.height, format: .number)
                }
                LabeledContent("Frame Rate") {
                    Text(project.document.canvas.frameRate, format: .number)
                }
            }

            if let selectedLayer {
                Section("Selection") {
                    LabeledContent("Name", value: selectedLayer.name)
                    LabeledContent(
                        "Type",
                        value: selectedLayer.kind.rawValue.capitalized
                    )
                    LabeledContent("Opacity") {
                        Text(
                            selectedLayer.transform.opacity,
                            format: .percent
                        )
                    }
                }
            }

            Section("Performance Budget") {
                Label("120 Hz interaction lane", systemImage: "gauge.with.dots.needle.67percent")
                Label("Shared display coordinator", systemImage: "rectangle.3.group")
                Label("Reduce Motion fallback", systemImage: "accessibility")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Inspector")
    }

    private var selectedLayer: MotionLayer? {
        project.document.layers.first {
            $0.id == project.selectedLayerID
        }
    }
}

private struct StudioTimeline: View {
    @Bindable var project: StudioProject

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Timeline")
                    .font(.headline)
                Spacer()
                Text(project.playhead, format: .number.precision(.fractionLength(2)))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: $project.playhead, in: 0 ... 1)
        }
        .padding(14)
        .background(.bar)
        .overlay(alignment: .top) {
            Divider()
        }
    }
}
