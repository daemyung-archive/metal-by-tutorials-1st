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
    camera.position = [0, 1, -3]
    return camera
  }()

  var models: [Prop] = []

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
    metalView.clearColor = MTLClearColor(red: 0.43, green: 0.47,
                                         blue: 0.5, alpha: 1)
    metalView.delegate = self
    mtkView(metalView, drawableSizeWillChange: metalView.bounds.size)

    // models
    let ball = Prop(name: "beachball")
    ball.position = [0, 0.35, 0]
    models.append(ball)
    let ground = Prop(name: "ground")
    ground.scale = [10, 10, 10]
    models.append(ground)

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
    camera.aspect = Float(view.bounds.width)/Float(view.bounds.height)
  }
  
  func draw(in view: MTKView) {
    guard let descriptor = view.currentRenderPassDescriptor,
      let commandBuffer = Renderer.commandQueue.makeCommandBuffer(),
      let renderEncoder =
      commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
        return
    }
    renderEncoder.setDepthStencilState(depthStencilState)
    
    uniforms.projectionMatrix = camera.projectionMatrix
    uniforms.viewMatrix = camera.viewMatrix
    
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


