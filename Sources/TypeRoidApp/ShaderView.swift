import AppKit
import MetalKit

/// A view that renders a liquid morph shader as a background.
@MainActor
final class LiquidShaderView: NSView {
    private var displayLink: CVDisplayLink?
    private var startTime: CFAbsoluteTime = 0
    private var metalLayer: CAMetalLayer?
    private var device: MTLDevice?
    private var commandQueue: MTLCommandQueue?
    private var pipelineState: MTLRenderPipelineState?
    private var running = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        setupMetal()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupMetal() {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        self.device = device
        self.commandQueue = device.makeCommandQueue()

        let metalLayer = CAMetalLayer()
        metalLayer.device = device
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.framebufferOnly = true
        metalLayer.frame = bounds
        self.layer = metalLayer
        self.metalLayer = metalLayer

        // Compile shader
        let shaderSource = """
        #include <metal_stdlib>
        using namespace metal;

        struct VertexOut {
            float4 position [[position]];
            float2 uv;
        };

        vertex VertexOut vertex_main(uint vid [[vertex_id]]) {
            float2 positions[] = {
                float2(-1, -1), float2(3, -1), float2(-1, 3)
            };
            VertexOut out;
            out.position = float4(positions[vid], 0, 1);
            out.uv = positions[vid] * 0.5 + 0.5;
            out.uv.y = 1.0 - out.uv.y;
            return out;
        }

        // Simplex-style noise for the liquid effect
        float hash(float2 p) {
            float3 p3 = fract(float3(p.xyx) * 0.1031);
            p3 += dot(p3, p3.yzx + 33.33);
            return fract((p3.x + p3.y) * p3.z);
        }

        float noise(float2 p) {
            float2 i = floor(p);
            float2 f = fract(p);
            f = f * f * (3.0 - 2.0 * f);
            float a = hash(i);
            float b = hash(i + float2(1, 0));
            float c = hash(i + float2(0, 1));
            float d = hash(i + float2(1, 1));
            return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
        }

        float fbm(float2 p) {
            float v = 0.0;
            float a = 0.5;
            float2 shift = float2(100.0);
            for (int i = 0; i < 5; i++) {
                v += a * noise(p);
                p = p * 2.0 + shift;
                a *= 0.5;
            }
            return v;
        }

        fragment float4 fragment_main(VertexOut in [[stage_in]],
                                       constant float &time [[buffer(0)]]) {
            float2 uv = in.uv;
            float t = time * 0.3;

            // Liquid morph: two layers of fbm noise displacing each other
            float2 q = float2(fbm(uv * 3.0 + t * 0.4),
                              fbm(uv * 3.0 + float2(1.7, 9.2) + t * 0.3));

            float2 r = float2(fbm(uv * 3.0 + q * 4.0 + float2(1.7, 9.2) + t * 0.2),
                              fbm(uv * 3.0 + q * 4.0 + float2(8.3, 2.8) + t * 0.25));

            float f = fbm(uv * 3.0 + r * 2.0);

            // Color palette: neon chartreuse (#BFFF00) on black
            float3 baseColor = float3(0.02, 0.02, 0.01); // near black
            float3 color1 = float3(0.05, 0.1, 0.0);      // dark green undertone
            float3 color2 = float3(0.15, 0.25, 0.0);     // chartreuse dark
            float3 color3 = float3(0.3, 0.5, 0.0);       // neon yellow-green accent

            float3 color = baseColor;
            color = mix(color, color1, smoothstep(0.0, 0.8, f * f));
            color = mix(color, color2, smoothstep(0.2, 0.9, q.x));
            color = mix(color, color3, smoothstep(0.3, 0.7, r.y * 0.5));

            // Subtle vignette
            float2 vc = uv - 0.5;
            float vignette = 1.0 - dot(vc, vc) * 1.2;
            color *= vignette;

            return float4(color, 1.0);
        }
        """

        do {
            let library = try device.makeLibrary(source: shaderSource, options: nil)
            let vertexFunc = library.makeFunction(name: "vertex_main")
            let fragmentFunc = library.makeFunction(name: "fragment_main")

            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = vertexFunc
            descriptor.fragmentFunction = fragmentFunc
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

            pipelineState = try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            // shader compilation failed - silently fall back to solid bg
        }

        startTime = CFAbsoluteTimeGetCurrent()
    }

    override func layout() {
        super.layout()
        metalLayer?.frame = bounds
        metalLayer?.drawableSize = CGSize(
            width: bounds.width * (window?.backingScaleFactor ?? 2),
            height: bounds.height * (window?.backingScaleFactor ?? 2)
        )
    }

    func render() {
        guard let metalLayer, let drawable = metalLayer.nextDrawable(),
              let pipelineState, let commandQueue,
              let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        let desc = MTLRenderPassDescriptor()
        desc.colorAttachments[0].texture = drawable.texture
        desc.colorAttachments[0].loadAction = .clear
        desc.colorAttachments[0].clearColor = MTLClearColorMake(0.04, 0.04, 0.06, 1)

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: desc) else { return }

        var time = Float(CFAbsoluteTimeGetCurrent() - startTime)
        encoder.setRenderPipelineState(pipelineState)
        encoder.setFragmentBytes(&time, length: MemoryLayout<Float>.size, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    private var renderTimer: Timer?

    func startRendering() {
        guard !running else { return }
        running = true
        startTime = CFAbsoluteTimeGetCurrent()

        renderTimer = Timer(timeInterval: 1.0/30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.render()
            }
        }
        RunLoop.main.add(renderTimer!, forMode: .common)
    }

    func stopRendering() {
        running = false
        renderTimer?.invalidate()
        renderTimer = nil
    }
}
