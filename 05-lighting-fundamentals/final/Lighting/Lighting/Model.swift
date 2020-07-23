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

class Model: Node {
  
  static var defaultVertexDescriptor: MDLVertexDescriptor = {
    let vertexDescriptor = MDLVertexDescriptor()
    vertexDescriptor.attributes[0] = MDLVertexAttribute(name: MDLVertexAttributePosition,
                                                        format: .float3,
                                                        offset: 0, bufferIndex: 0)
    // add the normal attribute here
    vertexDescriptor.attributes[1] = MDLVertexAttribute(name: MDLVertexAttributeNormal,
                                                        format: .float3,
                                                        offset: 12, bufferIndex: 0)
    vertexDescriptor.layouts[0] = MDLVertexBufferLayout(stride: 24)
    return vertexDescriptor
  }()
  
  let vertexBuffer: MTLBuffer
  let pipelineState: MTLRenderPipelineState
  let mesh: MTKMesh
  let submeshes: [Submesh]

  init(name: String) {
    let assetURL = Bundle.main.url(forResource: name, withExtension: "obj")!
    let allocator = MTKMeshBufferAllocator(device: Renderer.device)
    let asset = MDLAsset(url: assetURL, vertexDescriptor: Model.defaultVertexDescriptor,
                         bufferAllocator: allocator)
    let mdlMesh = asset.object(at: 0) as! MDLMesh
    
    let mesh = try! MTKMesh(mesh: mdlMesh, device: Renderer.device)
    self.mesh = mesh
    vertexBuffer = mesh.vertexBuffers[0].buffer

    submeshes = mdlMesh.submeshes?.enumerated().compactMap {index, submesh in
      (submesh as? MDLSubmesh).map {
        Submesh(submesh: mesh.submeshes[index],
                mdlSubmesh: $0)
      }
      } ?? []

    pipelineState = Model.buildPipelineState(vertexDescriptor: mdlMesh.vertexDescriptor)
    super.init()
  }
  
  private static func buildPipelineState(vertexDescriptor: MDLVertexDescriptor) -> MTLRenderPipelineState {
    let library = Renderer.library
    let vertexFunction = library?.makeFunction(name: "vertex_main")
    let fragmentFunction = library?.makeFunction(name: "fragment_main")

    var pipelineState: MTLRenderPipelineState
    let pipelineDescriptor = MTLRenderPipelineDescriptor()
    pipelineDescriptor.vertexFunction = vertexFunction
    pipelineDescriptor.fragmentFunction = fragmentFunction
    pipelineDescriptor.vertexDescriptor = MTKMetalVertexDescriptorFromModelIO(vertexDescriptor)
    pipelineDescriptor.colorAttachments[0].pixelFormat = Renderer.colorPixelFormat
    pipelineDescriptor.depthAttachmentPixelFormat = .depth32Float
    do {
      pipelineState = try Renderer.device.makeRenderPipelineState(descriptor: pipelineDescriptor)
    } catch let error {
      fatalError(error.localizedDescription)
    }
    return pipelineState
  }
}


