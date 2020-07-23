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
    camera.position = [0, 1, -3]
    return camera
  }()

  var models: [Model] = []
  lazy var lights: [Light] = {
    return lighting()
  }()

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
    metalView.clearColor = MTLClearColor(red: 0.93, green: 0.97,
                                         blue: 1, alpha: 1)
    metalView.delegate = self
    mtkView(metalView, drawableSizeWillChange: metalView.bounds.size)

    // models
    let model = Model(name: "chest")
    model.position = [0, 0, 0]
    models.append(model)
    
    buildDepthStencilState()
    
    lights = lighting()
    fragmentUniforms.lightCount = UInt32(lights.count)
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

    for model in models {
      fragmentUniforms.tiling = model.tiling
      renderEncoder.setFragmentSamplerState(model.samplerState, index: 0)

      renderEncoder.setFragmentBytes(&fragmentUniforms,
                                     length: MemoryLayout<FragmentUniforms>.stride,
                                     index: Int(BufferIndexFragmentUniforms.rawValue))

      uniforms.modelMatrix = model.modelMatrix
      uniforms.normalMatrix = float3x3(normalFrom4x4: model.modelMatrix)
      
      renderEncoder.setVertexBytes(&uniforms,
                                   length: MemoryLayout<Uniforms>.stride,
                                   index: Int(BufferIndexUniforms.rawValue))
      
      
      
      // render multiple buffers
      // replace the following line
      // this line only sends the MTLBuffer containing position, normal and UV
      for (index, vertexBuffer) in model.mesh.vertexBuffers.enumerated() {
        renderEncoder.setVertexBuffer(vertexBuffer.buffer,
                                      offset: 0, index: index)
      }

      for modelSubmesh in model.submeshes {
        renderEncoder.setRenderPipelineState(modelSubmesh.pipelineState)
        renderEncoder.setFragmentTexture(modelSubmesh.textures.baseColor,
                                         index: Int(BaseColorTexture.rawValue))
        renderEncoder.setFragmentTexture(modelSubmesh.textures.normal,
                                         index: Int(NormalTexture.rawValue))
        renderEncoder.setFragmentTexture(modelSubmesh.textures.roughness,
                                         index: 2)


        // set the materials here
        var material = modelSubmesh.material
        renderEncoder.setFragmentBytes(&material,
                                       length: MemoryLayout<Material>.stride,
                                       index: Int(BufferIndexMaterials.rawValue))

        
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


