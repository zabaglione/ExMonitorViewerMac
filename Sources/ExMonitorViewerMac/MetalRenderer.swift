import AppKit
import MetalKit
import CoreVideo

enum RendererError: Error { case unavailable }

final class MetalRenderer: NSObject, MTKViewDelegate {
    let frames: LatestFrame
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private var cache: CVMetalTextureCache!
    private let inFlight = DispatchSemaphore(value: 3)

    init(view: MTKView, frames: LatestFrame) throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue(),
              let shaderURL = Bundle.main.url(forResource: "Shaders", withExtension: "metal") else {
            throw RendererError.unavailable
        }
        let source = try String(contentsOf: shaderURL, encoding: .utf8)
        let library = try device.makeLibrary(source: source, options: nil)
        self.frames = frames
        self.queue = queue
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "viewerVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "viewerFragment")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        super.init()
        guard CVMetalTextureCacheCreate(nil, nil, device, nil, &cache) == kCVReturnSuccess else {
            throw RendererError.unavailable
        }
        view.device = device
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        view.framebufferOnly = true
        (view.layer as? CAMetalLayer)?.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        view.isPaused = true
        view.delegate = self
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard inFlight.wait(timeout: .now()) == .success else { return }
        guard let pass = view.currentRenderPassDescriptor, let drawable = view.currentDrawable,
              let command = queue.makeCommandBuffer(), let encoder = command.makeRenderCommandEncoder(descriptor: pass) else {
            inFlight.signal(); return
        }
        var retainedBuffer: CVPixelBuffer?
        var retainedTexture: CVMetalTexture?
        if let buffer = frames.get() {
            let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
            var cvTexture: CVMetalTexture?
            if CVMetalTextureCacheCreateTextureFromImage(nil, cache, buffer, nil, .bgra8Unorm,
                                                         width, height, 0, &cvTexture) == kCVReturnSuccess,
               let cvTexture, let texture = CVMetalTextureGetTexture(cvTexture) {
                retainedBuffer = buffer; retainedTexture = cvTexture
                let rect = ViewGeometry.aspectFit(source: CGSize(width: width, height: height),
                                                  destination: CGRect(origin: .zero, size: view.drawableSize))
                encoder.setViewport(MTLViewport(originX: rect.minX, originY: rect.minY,
                                                 width: rect.width, height: rect.height, znear: 0, zfar: 1))
                encoder.setRenderPipelineState(pipeline)
                encoder.setFragmentTexture(texture, index: 0)
                encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            }
        }
        encoder.endEncoding()
        let semaphore = inFlight
        command.addCompletedHandler { _ in
            withExtendedLifetime((retainedBuffer, retainedTexture)) {}
            semaphore.signal()
        }
        command.present(drawable)
        command.commit()
    }
}
