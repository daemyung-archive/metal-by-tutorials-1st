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
    vertexDescriptor.attributes[Int(Position.rawValue)] =
                  MDLVertexAttribute(name: MDLVertexAttributePosition,
                  format: .float3,
                  offset: 0, bufferIndex: 0)
    vertexDescriptor.attributes[Int(Normal.rawValue)] =
                  MDLVertexAttribute(name: MDLVertexAttributeNormal,
                  format: .float3,
                  offset: 12, bufferIndex: 0)
    vertexDescriptor.attributes[Int(UV.rawValue)] =
      MDLVertexAttribute(name: MDLVertexAttributeTextureCoordinate,
                         format: .float2,
                         offset: 24, bufferIndex: 0)
    
    vertexDescriptor.layouts[0] = MDLVertexBufferLayout(stride: 32)
    return vertexDescriptor
  }()
  
  let vertexBuffer: MTLBuffer
  let mesh: MTKMesh
  let submeshes: [Submesh]
  let samplerState: MTLSamplerState?

  var tiling: UInt32 = 1

  init(name: String) {
    let assetURL = Bundle.main.url(forResource: name, withExtension: "obj")!
    let allocator = MTKMeshBufferAllocator(device: Renderer.device)
    let asset = MDLAsset(url: assetURL, vertexDescriptor: Model.defaultVertexDescriptor,
                         bufferAllocator: allocator)
    let mdlMesh = asset.object(at: 0) as! MDLMesh
    
    // add tangent and bitangent here
    mdlMesh.addTangentBasis(forTextureCoordinateAttributeNamed:
      MDLVertexAttributeTextureCoordinate,
                            tangentAttributeNamed: MDLVertexAttributeTangent,
                            bitangentAttributeNamed:
      MDLVertexAttributeBitangent)
    Model.defaultVertexDescriptor = mdlMesh.vertexDescriptor

    let mesh = try! MTKMesh(mesh: mdlMesh, device: Renderer.device)
    self.mesh = mesh
    vertexBuffer = mesh.vertexBuffers[0].buffer
    submeshes = mdlMesh.submeshes?.enumerated().compactMap {index, submesh in
      (submesh as? MDLSubmesh).map {
        Submesh(submesh: mesh.submeshes[index],
                mdlSubmesh: $0)
      }
      }
      ?? []

    samplerState = Model.buildSamplerState()
    super.init()
    
  }
  
  private static func buildSamplerState() -> MTLSamplerState? {
    let descriptor = MTLSamplerDescriptor()
    descriptor.sAddressMode = .repeat
    descriptor.tAddressMode = .repeat
    descriptor.mipFilter = .linear
    descriptor.maxAnisotropy = 8

    let samplerState =
      Renderer.device.makeSamplerState(descriptor: descriptor)
    return samplerState
  }
}


