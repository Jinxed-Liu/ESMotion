#if os(iOS)
import ESMotionCore
import MetalKit
import SwiftUI
import UIKit

private struct MotionTransitionMetalUniforms {
    var viewportSize: SIMD2<Float>
    var origin: SIMD2<Float>
    var size: SIMD2<Float>
    var cornerRadius: Float
    var opacity: Float
}

@MainActor
final class MotionTransitionMetalSurfaceView: MTKView, MotionTransitionRenderer {
    private let commandQueue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let textureLoader: MTKTextureLoader
    private var backdropTexture: MTLTexture?
    private var sourceTexture: MTLTexture?
    private var destinationTexture: MTLTexture?
    private var payload: MotionTransitionRenderPayload?

    private(set) var latestGPUFrameDuration: TimeInterval = 0

    var isReady: Bool {
        device != nil && window != nil
    }

    static func make(frame: CGRect) -> MotionTransitionMetalSurfaceView? {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let library = try? device.makeDefaultLibrary(bundle: .module),
              let vertex = library.makeFunction(name: "esmotionTransitionVertex"),
              let fragment = library.makeFunction(name: "esmotionTransitionFragment")
        else { return nil }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].destinationRGBBlendFactor =
            .oneMinusSourceAlpha
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        descriptor.colorAttachments[0].destinationAlphaBlendFactor =
            .oneMinusSourceAlpha
        guard let pipeline = try? device.makeRenderPipelineState(
            descriptor: descriptor
        ) else { return nil }
        return MotionTransitionMetalSurfaceView(
            frame: frame,
            device: device,
            commandQueue: queue,
            pipeline: pipeline
        )
    }

    private init(
        frame: CGRect,
        device: MTLDevice,
        commandQueue: MTLCommandQueue,
        pipeline: MTLRenderPipelineState
    ) {
        self.commandQueue = commandQueue
        self.pipeline = pipeline
        self.textureLoader = MTKTextureLoader(device: device)
        super.init(frame: frame, device: device)
        colorPixelFormat = .bgra8Unorm
        framebufferOnly = true
        isPaused = true
        enableSetNeedsDisplay = false
        autoResizeDrawable = true
        clearColor = MTLClearColorMake(0, 0, 0, 1)
        isOpaque = true
        backgroundColor = .black
        isUserInteractionEnabled = false
        isHidden = true
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func cover(with snapshot: MotionTransitionSnapshot) -> Bool {
        guard let texture = makeTexture(from: snapshot.image) else {
            return false
        }
        backdropTexture = texture
        sourceTexture = nil
        destinationTexture = nil
        payload = nil
        isHidden = false
        renderFrame(progress: 0, onlyBackdrop: true)
        return true
    }

    func prepare(_ payload: MotionTransitionRenderPayload) -> Bool {
        guard let backdrop = makeTexture(
            from: payload.session.cleanBackdropSnapshot.image
        ), let source = makeTexture(
            from: payload.session.sourceSnapshot.image
        ), let destination = makeTexture(
            from: payload.session.destinationSnapshot.image
        ) else {
            return false
        }
        backdropTexture = backdrop
        sourceTexture = source
        destinationTexture = destination
        self.payload = payload
        isHidden = false
        renderFrame(progress: payload.session.progress)
        return true
    }

    func render(progress: Double, quality: MotionQualityTier) {
        renderFrame(progress: min(max(progress, 0), 1))
    }

    func crossfadeToHost(duration: TimeInterval) {
        UIView.animate(
            withDuration: max(duration, 0),
            delay: 0,
            options: [.beginFromCurrentState, .curveEaseOut]
        ) { [weak self] in
            self?.alpha = 0
        } completion: { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.alpha = 1
                self?.clear()
            }
        }
    }

    func clear() {
        payload = nil
        backdropTexture = nil
        sourceTexture = nil
        destinationTexture = nil
        latestGPUFrameDuration = 0
        alpha = 1
        isHidden = true
    }

    private func renderFrame(
        progress: Double,
        onlyBackdrop: Bool = false
    ) {
        guard let drawable = currentDrawable,
              let pass = currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(
                descriptor: pass
              ),
              let backdropTexture else {
            return
        }
        let gpuStartedAt = ProcessInfo.processInfo.systemUptime
        encoder.setRenderPipelineState(pipeline)
        draw(
            texture: backdropTexture,
            frame: bounds,
            cornerRadius: 0,
            opacity: 1,
            encoder: encoder
        )

        if !onlyBackdrop,
           let payload,
           let sourceTexture,
           let destinationTexture {
            let geometry = MotionTransitionGeometry.resolve(
                sourceFrame: localFrame(payload.session.sourceFrame),
                destinationFrame: localFrame(payload.session.destinationFrame),
                sourceElements: [],
                destinationElements: [],
                spec: payload.spec,
                progress: progress,
                reducedMotion: payload.reducedMotion
            )
            draw(
                texture: sourceTexture,
                frame: geometry.containerFrame,
                cornerRadius: geometry.cornerRadius,
                opacity: 1,
                encoder: encoder
            )
            draw(
                texture: destinationTexture,
                frame: geometry.containerFrame,
                cornerRadius: geometry.cornerRadius,
                opacity: Double(geometry.destinationOpacity),
                encoder: encoder
            )
        }

        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.addCompletedHandler { [weak self] buffer in
            let measured = buffer.gpuEndTime > buffer.gpuStartTime
                ? buffer.gpuEndTime - buffer.gpuStartTime
                : ProcessInfo.processInfo.systemUptime - gpuStartedAt
            Task { @MainActor [weak self] in
                self?.latestGPUFrameDuration = measured
            }
        }
        commandBuffer.commit()
    }

    private func draw(
        texture: MTLTexture,
        frame: CGRect,
        cornerRadius: CGFloat,
        opacity: Double,
        encoder: MTLRenderCommandEncoder
    ) {
        var uniforms = MotionTransitionMetalUniforms(
            viewportSize: SIMD2(Float(bounds.width), Float(bounds.height)),
            origin: SIMD2(Float(frame.minX), Float(frame.minY)),
            size: SIMD2(Float(frame.width), Float(frame.height)),
            cornerRadius: Float(max(cornerRadius, 0)),
            opacity: Float(min(max(opacity, 0), 1))
        )
        encoder.setVertexBytes(
            &uniforms,
            length: MemoryLayout<MotionTransitionMetalUniforms>.stride,
            index: 0
        )
        encoder.setFragmentBytes(
            &uniforms,
            length: MemoryLayout<MotionTransitionMetalUniforms>.stride,
            index: 0
        )
        encoder.setFragmentTexture(texture, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    }

    private func makeTexture(from image: CGImage) -> MTLTexture? {
        guard let normalized = normalizedImage(image) else { return nil }
        return try? textureLoader.newTexture(
            cgImage: normalized,
            options: [
                .SRGB: false,
                .textureUsage: NSNumber(value: MTLTextureUsage.shaderRead.rawValue),
            ]
        )
    }

    private func normalizedImage(_ image: CGImage) -> CGImage? {
        guard let context = CGContext(
            data: nil,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: image.width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
                | CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        context.draw(
            image,
            in: CGRect(x: 0, y: 0, width: image.width, height: image.height)
        )
        return context.makeImage()
    }

    private func localFrame(_ windowFrame: CGRect) -> CGRect {
        guard let window else { return windowFrame }
        return convert(windowFrame, from: window)
    }
}

@MainActor
final class MotionTransitionSurfaceInstallerView: UIView {
    weak var coordinator: MotionTransitionCoordinator? {
        didSet { installIfNeeded() }
    }
    private var surface: MotionTransitionMetalSurfaceView?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        installIfNeeded()
    }

    func tearDown() {
        guard let surface else { return }
        coordinator?.detach(renderer: surface)
        surface.clear()
        surface.removeFromSuperview()
        self.surface = nil
    }

    private func installIfNeeded() {
        guard let coordinator, let window else { return }
        if let surface, surface.superview === window {
            coordinator.attach(renderer: surface)
            return
        }
        tearDown()
        guard let surface = MotionTransitionMetalSurfaceView.make(
            frame: window.bounds
        ) else {
            return
        }
        surface.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        window.addSubview(surface)
        coordinator.attach(renderer: surface)
        self.surface = surface
    }
}

struct MotionTransitionOverlayBridge: UIViewRepresentable {
    let coordinator: MotionTransitionCoordinator

    func makeUIView(context: Context) -> MotionTransitionSurfaceInstallerView {
        let view = MotionTransitionSurfaceInstallerView()
        view.coordinator = coordinator
        return view
    }

    func updateUIView(
        _ uiView: MotionTransitionSurfaceInstallerView,
        context: Context
    ) {
        uiView.coordinator = coordinator
    }

    static func dismantleUIView(
        _ uiView: MotionTransitionSurfaceInstallerView,
        coordinator: Void
    ) {
        uiView.tearDown()
    }
}

@MainActor
final class MotionTransitionRegistrationView: UIView {
    let token = UUID()
    weak var coordinator: MotionTransitionCoordinator?
    var transitionID = MotionTransitionID("")
    var role = MotionTransitionRegistrationRole.source
    var spec = MotionTransitionSpec.card
    var snapshotPolicy = MotionTransitionSnapshotPolicy.automatic
    var proxy: MotionTransitionProxy?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateRegistration()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateRegistration()
    }

    func updateRegistration() {
        guard let coordinator, let window, !bounds.isEmpty else { return }
        let frame = convert(bounds, to: window)
        let snapshotProvider: MotionTransitionSnapshotProvider?
        let backdropProvider: MotionTransitionSnapshotProvider?
        if role == .source {
            snapshotProvider = { [weak self] request in
                self?.capture(request)
            }
            backdropProvider = { [weak self] request in
                self?.captureCleanBackdrop(request)
            }
        } else {
            snapshotProvider = nil
            backdropProvider = nil
        }
        coordinator.upsertRegistration(
            MotionTransitionRegistration(
                token: token,
                id: transitionID,
                role: role,
                frame: frame,
                viewportFrame: window.bounds,
                spec: spec,
                snapshotPolicy: snapshotPolicy,
                proxy: proxy,
                snapshotProvider: snapshotProvider,
                cleanBackdropProvider: backdropProvider
            )
        )
    }

    func unregister() {
        coordinator?.removeRegistration(token: token)
    }

    private func capture(
        _ request: MotionTransitionSnapshotRequest
    ) -> MotionTransitionSnapshot? {
        captureWindow(frame: request.frame, request: request)
    }

    private func captureCleanBackdrop(
        _ request: MotionTransitionSnapshotRequest
    ) -> MotionTransitionSnapshot? {
        guard let captureView = nearestSourceContainerView else {
            return nil
        }
        let wasHidden = captureView.isHidden
        captureView.isHidden = true
        captureView.superview?.layoutIfNeeded()
        defer {
            captureView.isHidden = wasHidden
            captureView.superview?.layoutIfNeeded()
        }
        guard let captured = captureWindow(
            frame: request.frame,
            request: request
        ), let window else {
            return nil
        }
        let sourceFrame = convert(bounds, to: window).offsetBy(
            dx: -request.frame.minX,
            dy: -request.frame.minY
        )
        return patchSourceRegion(
            in: captured,
            sourceFrame: sourceFrame,
            viewportSize: request.frame.size
        )
    }

    private var nearestSourceContainerView: UIView? {
        var candidate = superview
        while let view = candidate, view !== window {
            if view.bounds.width >= bounds.width - 1,
               view.bounds.height >= bounds.height - 1,
               view.bounds.width < (window?.bounds.width ?? .greatestFiniteMagnitude) - 1 {
                return view
            }
            candidate = view.superview
        }
        return superview
    }

    private func captureWindow(
        frame: CGRect,
        request: MotionTransitionSnapshotRequest
    ) -> MotionTransitionSnapshot? {
        guard let window, frame.width > 0, frame.height > 0 else { return nil }
        let points = max(frame.width * frame.height, 1)
        let maxScale = sqrt(
            CGFloat(request.maximumByteCount) / max(points * 4, 1)
        )
        let scale = min(window.screen.scale, request.preferredScale, maxScale)
        guard scale >= 0.5 else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        format.scale = scale
        format.preferredRange = .standard
        let image = UIGraphicsImageRenderer(
            size: frame.size,
            format: format
        ).image { context in
            context.cgContext.translateBy(x: -frame.minX, y: -frame.minY)
            window.layer.render(in: context.cgContext)
        }
        guard let cgImage = image.cgImage else { return nil }
        return MotionTransitionSnapshot(image: cgImage, scale: image.scale)
    }

    private func patchSourceRegion(
        in snapshot: MotionTransitionSnapshot,
        sourceFrame: CGRect,
        viewportSize: CGSize
    ) -> MotionTransitionSnapshot? {
        let image = UIImage(
            cgImage: snapshot.image,
            scale: snapshot.scale,
            orientation: .up
        )
        let samplePoint = CGPoint(
            x: min(max(sourceFrame.midX, 0), viewportSize.width - 1),
            y: min(max(sourceFrame.maxY + 18, 0), viewportSize.height - 1)
        )
        guard let color = sampledColor(from: image, at: samplePoint) else {
            return snapshot
        }
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        format.scale = snapshot.scale
        format.preferredRange = .standard
        let patched = UIGraphicsImageRenderer(
            size: viewportSize,
            format: format
        ).image { _ in
            image.draw(in: CGRect(origin: .zero, size: viewportSize))
            color.setFill()
            UIRectFill(sourceFrame.insetBy(dx: -18, dy: -18))
        }
        guard let cgImage = patched.cgImage else { return nil }
        return MotionTransitionSnapshot(image: cgImage, scale: patched.scale)
    }

    private func sampledColor(
        from image: UIImage,
        at point: CGPoint
    ) -> UIColor? {
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        format.scale = 1
        format.preferredRange = .standard
        let sample = UIGraphicsImageRenderer(
            size: CGSize(width: 1, height: 1),
            format: format
        ).image { _ in
            image.draw(at: CGPoint(x: -point.x, y: -point.y))
        }
        guard let cgImage = sample.cgImage,
              let data = cgImage.dataProvider?.data,
              CFDataGetLength(data) >= 4,
              let bytes = CFDataGetBytePtr(data) else {
            return nil
        }
        return UIColor(
            red: CGFloat(bytes[0]) / 255,
            green: CGFloat(bytes[1]) / 255,
            blue: CGFloat(bytes[2]) / 255,
            alpha: 1
        )
    }
}

struct MotionTransitionRegistrationBridge: UIViewRepresentable {
    let coordinator: MotionTransitionCoordinator
    let id: MotionTransitionID
    let role: MotionTransitionRegistrationRole
    let spec: MotionTransitionSpec
    let snapshotPolicy: MotionTransitionSnapshotPolicy
    let proxy: MotionTransitionProxy?

    func makeUIView(context: Context) -> MotionTransitionRegistrationView {
        MotionTransitionRegistrationView()
    }

    func updateUIView(
        _ uiView: MotionTransitionRegistrationView,
        context: Context
    ) {
        uiView.coordinator = coordinator
        uiView.transitionID = id
        uiView.role = role
        uiView.spec = spec
        uiView.snapshotPolicy = snapshotPolicy
        uiView.proxy = proxy
        uiView.updateRegistration()
    }

    static func dismantleUIView(
        _ uiView: MotionTransitionRegistrationView,
        coordinator: Void
    ) {
        uiView.unregister()
    }
}

@MainActor
final class MotionTransitionEdgePanView: UIView {
    weak var coordinator: MotionTransitionCoordinator?
    var transitionID: MotionTransitionID?
    var routeMutation: MotionRouteMutation?
    var isRightToLeft = false {
        didSet { edgePan.edges = isRightToLeft ? .right : .left }
    }

    private lazy var edgePan: UIScreenEdgePanGestureRecognizer = {
        let gesture = UIScreenEdgePanGestureRecognizer(
            target: self,
            action: #selector(handleEdgePan)
        )
        return gesture
    }()
    private weak var nativePopGesture: UIGestureRecognizer?
    private var nativePopWasEnabled = true

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        addGestureRecognizer(edgePan)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            restoreNativeGesture()
        } else {
            claimEdgeGesture()
        }
    }

    override func removeFromSuperview() {
        restoreNativeGesture()
        super.removeFromSuperview()
    }

    override func gestureRecognizerShouldBegin(
        _ gestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        coordinator?.canBeginInteractiveDismiss == true
    }

    private func claimEdgeGesture() {
        guard nativePopGesture == nil,
              let navigationController = sequence(
                first: next,
                next: { $0?.next }
              )
              .compactMap({ $0 as? UIViewController })
              .first?
              .navigationController,
              let native = navigationController.interactivePopGestureRecognizer
        else {
            return
        }
        nativePopWasEnabled = native.isEnabled
        native.isEnabled = false
        nativePopGesture = native
    }

    private func restoreNativeGesture() {
        nativePopGesture?.isEnabled = nativePopWasEnabled
        nativePopGesture = nil
    }

    @objc
    private func handleEdgePan(_ gesture: UIScreenEdgePanGestureRecognizer) {
        guard let coordinator, let routeMutation else { return }
        let width = max(window?.bounds.width ?? bounds.width, 1)
        let direction: CGFloat = isRightToLeft ? -1 : 1
        let translation = max(gesture.translation(in: self).x * direction, 0)
        let velocity = max(gesture.velocity(in: self).x * direction, 0)
        let progress = min(max(translation / width, 0), 1)

        switch gesture.state {
        case .began:
            _ = coordinator.beginInteractiveDismiss(id: transitionID)
        case .changed:
            coordinator.updateInteractiveDismiss(
                progress: progress,
                velocity: velocity
            )
        case .ended:
            _ = coordinator.finishInteractiveDismiss(
                projectedProgress: progress,
                velocity: velocity,
                routeMutation: routeMutation
            )
        case .cancelled, .failed:
            _ = coordinator.finishInteractiveDismiss(
                projectedProgress: 0,
                velocity: 0,
                routeMutation: routeMutation
            )
        default:
            break
        }
    }
}

struct MotionTransitionEdgePanBridge: UIViewRepresentable {
    @Environment(\.layoutDirection) private var layoutDirection
    let coordinator: MotionTransitionCoordinator
    let transitionID: MotionTransitionID?
    let routeMutation: MotionRouteMutation

    func makeUIView(context: Context) -> MotionTransitionEdgePanView {
        MotionTransitionEdgePanView()
    }

    func updateUIView(
        _ uiView: MotionTransitionEdgePanView,
        context: Context
    ) {
        uiView.coordinator = coordinator
        uiView.transitionID = transitionID
        uiView.routeMutation = routeMutation
        uiView.isRightToLeft = layoutDirection == .rightToLeft
    }
}
#endif
