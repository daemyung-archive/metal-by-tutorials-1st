/**
 * Copyright (c) 2018 Razeware LLC
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * Notwithstanding the foregoing, you may not use, copy, modify, merge, publish,
 * distribute, sublicense, create a derivative work, and/or sell copies of the
 * Software in any work that is designed, intended, or marketed for pedagogical or
 * instructional purposes related to programming, coding, application development,
 * or information technology.  Permission for such use, copying, modification,
 * merger, publication, distribution, sublicensing, creation of derivative works,
 * or sale is expressly withheld.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */

import MetalKit

class Renderer: NSObject {
  
  static var device: MTLDevice!
  static var commandQueue: MTLCommandQueue!
  static var colorPixelFormat: MTLPixelFormat!
  static var library: MTLLibrary?
  var depthStencilState: MTLDepthStencilState!
  
  var uniforms = Uniforms()

  lazy var camera: Camera = {
    let camera = Camera()
    camera.position = [0, 1.2, -4]
    return camera
  }()
  
  lazy var lights: [Light] = {
    return lighting()
  }()

  var models: [Renderable] = []

  init(metalView: MTKView) {
    guard let device = MTLCreateSystemDefaultDevice() else {
      fatalError("GPU not available")
    }
    metalView.depthStencilPixelFormat = .depth32Float
    metalView.device = device
    Renderer.device = device
    Renderer.commandQueue = device.makeCommandQueue()!
    Renderer.colorPixelFormat = metalView.colorPixelFormat
    Renderer.library = device.makeDefaultLibrary()
    
    super.init()
    metalView.clearColor = MTLClearColor(red: 0.7, green: 0.9,
                                         blue: 1, alpha: 1)
    metalView.delegate = self
    mtkView(metalView, drawableSizeWillChange: metalView.bounds.size)

    // models
    let ground = Prop(name: "large-plane")
    ground.tiling = 32
    models.append(ground)
    let car = Prop(name: "racing-car")
    car.rotation = [0, radians(fromDegrees: 90), 0]
    car.position = [-0.8, 0, 0]
    models.append(car)
    let skeleton = Character(name: "skeleton")
    skeleton.position = [1.6, 0, 0]
    skeleton.rotation.y = .pi
    skeleton.runAnimation(name: "Armature_idle")
    skeleton.pauseAnimation()
    models.append(skeleton)
    
    buildDepthStencilState()
  }
  
  func buildDepthStencilState() {
    let descriptor = MTLDepthStencilDescriptor()
    descriptor.depthCompareFunction = .less
    descriptor.isDepthWriteEnabled = true
    depthStencilState =
      Renderer.device.makeDepthStencilState(descriptor: descriptor)
  }
}

extension Renderer: MTKViewDelegate {
  func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
    camera.aspect = Float(view.bounds.width) / Float(view.bounds.height)
  }
  
  func update(deltaTime: Float) {
    for model in models  {
      guard let node = model as? Node else { continue }
      node.update(deltaTime: deltaTime)
    }
  }

  func draw(in view: MTKView) {
    guard let descriptor = view.currentRenderPassDescriptor,
      let commandBuffer = Renderer.commandQueue.makeCommandBuffer(),
      let renderEncoder =
      commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
        return
    }
    let deltaTime = 1 / Float(view.preferredFramesPerSecond)
    update(deltaTime: deltaTime)

    renderEncoder.setDepthStencilState(depthStencilState)
    
    uniforms.projectionMatrix = camera.projectionMatrix
    uniforms.viewMatrix = camera.viewMatrix
    var fragmentUniforms = FragmentUniforms()
    fragmentUniforms.cameraPosition = camera.position
    fragmentUniforms.lightCount = UInt32(lights.count)

    renderEncoder.setFragmentBytes(&fragmentUniforms,
                                   length: MemoryLayout<FragmentUniforms>.stride,
                                   index: Int(BufferIndexFragmentUniforms.rawValue))

    renderEncoder.setFragmentBytes(&lights,
                                   length: MemoryLayout<Light>.stride * lights.count,
                                   index: Int(BufferIndexLights.rawValue))

    for model in models {
      renderEncoder.pushDebugGroup(model.name)
      model.render(renderEncoder: renderEncoder, uniforms: uniforms)
      renderEncoder.popDebugGroup()
    }
    
    renderEncoder.endEncoding()
    guard let drawable = view.currentDrawable else {
      return
    }
    commandBuffer.present(drawable)
    commandBuffer.commit()
  }
}


