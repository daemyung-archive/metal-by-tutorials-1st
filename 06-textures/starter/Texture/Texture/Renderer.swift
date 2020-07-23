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
  var fragmentUniforms = FragmentUniforms()
  
  lazy var camera: Camera = {
    let camera = Camera()
    camera.position = [0, 1.2, -4]
    return camera
  }()

  var models: [Model] = []
  
  lazy var sunlight: Light = {
    var light = buildDefaultLight()
    light.position = [1, 2, -2]
    return light
  }()
  
  var lights: [Light] = []
  
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
                                         blue: 1.0, alpha: 1)
    metalView.delegate = self
    mtkView(metalView, drawableSizeWillChange: metalView.bounds.size)

    // models
    let house = Model(name: "lowpoly-house")
    house.position = [0, 0, 0]
    house.rotation = [0, radians(fromDegrees: 45), 0]
    models.append(house)
    

    buildDepthStencilState()
    
    // lights
    lights.append(sunlight)
    fragmentUniforms.lightCount = UInt32(lights.count)
  }
  
  func buildDefaultLight() -> Light {
    var light = Light()
    light.position = [0, 0, 0]
    light.color = [1, 1, 1]
    light.specularColor = [0.6, 0.6, 0.6]
    light.intensity = 1
    light.attenuation = float3(1, 0, 0)
    light.type = Sunlight
    return light
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
    
    fragmentUniforms.cameraPosition = camera.position
    uniforms.projectionMatrix = camera.projectionMatrix
    uniforms.viewMatrix = camera.viewMatrix
    
    renderEncoder.setFragmentBytes(&lights,
                                   length: MemoryLayout<Light>.stride * lights.count,
                                   index: Int(BufferIndexLights.rawValue))
    renderEncoder.setFragmentBytes(&fragmentUniforms,
                                   length: MemoryLayout<FragmentUniforms>.stride,
                                   index: Int(BufferIndexFragmentUniforms.rawValue))

    for model in models {
      
      // add tiling here
      
      uniforms.modelMatrix = model.modelMatrix
      uniforms.normalMatrix = float3x3(normalFrom4x4: model.modelMatrix)
      
      renderEncoder.setVertexBytes(&uniforms,
                                   length: MemoryLayout<Uniforms>.stride,
                                   index: Int(BufferIndexUniforms.rawValue))
      
      renderEncoder.setRenderPipelineState(model.pipelineState)
      renderEncoder.setVertexBuffer(model.vertexBuffer, offset: 0,
                                    index: Int(BufferIndexVertices.rawValue))
      
      for modelSubmesh in model.submeshes {

        // set the fragment texture here
        
        let submesh = modelSubmesh.submesh
        renderEncoder.drawIndexedPrimitives(type: .triangle,
                                            indexCount: submesh.indexCount,
                                            indexType: submesh.indexType,
                                            indexBuffer: submesh.indexBuffer.buffer,
                                            indexBufferOffset: submesh.indexBuffer.offset)
      }
    }
    
    renderEncoder.endEncoding()
    guard let drawable = view.currentDrawable else {
      return
    }
    commandBuffer.present(drawable)
    commandBuffer.commit()
  }
}


