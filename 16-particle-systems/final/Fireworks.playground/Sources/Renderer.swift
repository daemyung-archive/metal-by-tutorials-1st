import MetalKit

public class Renderer: NSObject, MTKViewDelegate {
  
  public let device: MTLDevice!
  let commandQueue: MTLCommandQueue!
  
  let particleCount = 10000
  let maxEmitters = 8
  var emitters: [Emitter] = []
  let life: Float = 256
  var timer: Float = 0
  
  let pipelineState: MTLComputePipelineState!
  let particlePipelineState: MTLComputePipelineState!
  
  override public init() {
    let initialized = Renderer.initializeMetal()
    device = initialized?.device
    commandQueue = initialized?.commandQueue
    pipelineState = initialized?.pipelineState
    particlePipelineState = initialized?.particlePipelineState
    super.init()
  }
  
  private static func initializeMetal() -> (
    device: MTLDevice, commandQueue: MTLCommandQueue,
    pipelineState: MTLComputePipelineState,
    particlePipelineState: MTLComputePipelineState)?  {
      guard let device = MTLCreateSystemDefaultDevice(),
        let commandQueue = device.makeCommandQueue(),
        let path = Bundle.main.path(forResource: "Shaders",
                                    ofType: "metal") else { return nil }
      
      let pipelineState: MTLComputePipelineState
      let particlePipelineState: MTLComputePipelineState
      do {
        let input = try String(contentsOfFile: path,
                               encoding: String.Encoding.utf8)
        let library = try device.makeLibrary(source: input, options: nil)
        guard let function = library.makeFunction(name: "compute"),
          let particleFunction = library.makeFunction(name: "particleKernel") else { return nil }
        pipelineState = try device.makeComputePipelineState(function: function)
        particlePipelineState = try
          device.makeComputePipelineState(function: particleFunction)
      }
      catch {
        print(error.localizedDescription)
        return nil
      }
      return (
        device, commandQueue,
        pipelineState: pipelineState, particlePipelineState:
        particlePipelineState)
  }
  
  func makeRenderCommandEncoder(_ commandBuffer: MTLCommandBuffer, _ texture: MTLTexture) -> MTLRenderCommandEncoder {
    let descriptor = MTLRenderPassDescriptor()
    let color = MTLClearColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)
    descriptor.colorAttachments[0].texture = texture
    descriptor.colorAttachments[0].clearColor = color
    descriptor.colorAttachments[0].loadAction = .clear
    guard let renderCommandEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
      fatalError("Cannot create a render command encoder.")
    }
    return renderCommandEncoder
  }
  
  func update(size: CGSize) {
    timer += 1
    if timer >= 50 {
      timer = 0
      if emitters.count > maxEmitters {
        emitters.removeFirst()
      }
      let emitter = Emitter(particleCount: particleCount,
                            size: size, life: life,
                            device: device)
      emitters.append(emitter)
    }
  }
  
  public func draw(in view: MTKView) {
    guard let commandBuffer = commandQueue.makeCommandBuffer(),
      let drawable = view.currentDrawable else {
        return
    }
    update(size: view.drawableSize)
    
    // first command encoder
    guard let computeEncoder = commandBuffer.makeComputeCommandEncoder()
      else { return }
    computeEncoder.setComputePipelineState(pipelineState)
    computeEncoder.setTexture(drawable.texture, index: 0)
    var width = pipelineState.threadExecutionWidth
    var height = pipelineState.maxTotalThreadsPerThreadgroup / width
    let threadsPerThreadgroup = MTLSizeMake(width, height, 1)
    width = Int(view.drawableSize.width)
    height = Int(view.drawableSize.height)
    var threadsPerGrid = MTLSizeMake(width, height, 1)
    computeEncoder.dispatchThreads(threadsPerGrid,
                                   threadsPerThreadgroup: threadsPerThreadgroup)
    computeEncoder.endEncoding()
    
    // second command encoder
    guard let particleEncoder = commandBuffer.makeComputeCommandEncoder()
      else { return }
    particleEncoder.setComputePipelineState(particlePipelineState)
    particleEncoder.setTexture(drawable.texture, index: 0)
    threadsPerGrid = MTLSizeMake(particleCount, 1, 1)
    for emitter in emitters {
      let particleBuffer = emitter.particleBuffer
      particleEncoder.setBuffer(particleBuffer, offset: 0, index: 0)
      particleEncoder.dispatchThreads(threadsPerGrid,
                                      threadsPerThreadgroup: threadsPerThreadgroup)
    }
    particleEncoder.endEncoding()
    
    commandBuffer.present(drawable)
    commandBuffer.commit()
  }
  
  public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
}
