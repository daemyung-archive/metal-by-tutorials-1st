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

class Prop: Node {
  
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
  
  private var transforms: [Transform]
  let instanceCount: Int
  var instanceBuffer: MTLBuffer
  
  init(name: String,
       vertexFunctionName: String = "vertex_main",
       fragmentFunctionName: String = "fragment_IBL",
       instanceCount: Int = 1) {
    let assetURL = Bundle.main.url(forResource: name, withExtension: "obj")!
    let allocator = MTKMeshBufferAllocator(device: Renderer.device)
    let asset = MDLAsset(url: assetURL,
                         vertexDescriptor: Prop.defaultVertexDescriptor,
                         bufferAllocator: allocator)
    let mdlMesh = asset.object(at: 0) as! MDLMesh
    
    // add tangent and bitangent here
    mdlMesh.addTangentBasis(forTextureCoordinateAttributeNamed:
      MDLVertexAttributeTextureCoordinate,
                            tangentAttributeNamed: MDLVertexAttributeTangent,
                            bitangentAttributeNamed:
      MDLVertexAttributeBitangent)
    
    Prop.defaultVertexDescriptor = mdlMesh.vertexDescriptor
    let mesh = try! MTKMesh(mesh: mdlMesh, device: Renderer.device)
    self.mesh = mesh
    vertexBuffer = mesh.vertexBuffers[0].buffer
    submeshes = mdlMesh.submeshes?.enumerated().compactMap {index, submesh in
      (submesh as? MDLSubmesh).map {
        Submesh(submesh: mesh.submeshes[index], mdlSubmesh: $0,
                vertexFunctionName: vertexFunctionName,
                fragmentFunctionName: fragmentFunctionName)
      }
      }
      ?? []
    
    samplerState = Prop.buildSamplerState()
    
    self.instanceCount = instanceCount
    transforms = Prop.buildTransforms(instanceCount: instanceCount)
    instanceBuffer = Prop.buildInstanceBuffer(transforms: transforms)
    
    super.init()
    self.name = name
    self.boundingBox = mdlMesh.boundingBox
  }
  
  func updateBuffer(instance: Int, transform: Transform) {
    transforms[instance] = transform
    var pointer =
      instanceBuffer.contents().bindMemory(to: Instances.self,
                                           capacity: transforms.count)
    pointer = pointer.advanced(by: instance)
    pointer.pointee.modelMatrix = transforms[instance].modelMatrix
    pointer.pointee.normalMatrix = transforms[instance].normalMatrix
  }
  
  static func buildInstanceBuffer(transforms: [Transform]) -> MTLBuffer {
    // 1
    let instances = transforms.map {
      Instances(modelMatrix: $0.modelMatrix,
                normalMatrix: float3x3(normalFrom4x4: $0.modelMatrix))
    }
    // 2
    guard let instanceBuffer =
      Renderer.device.makeBuffer(bytes: instances,
                                 length: MemoryLayout<Instances>.stride * instances.count,
                                 options: []) else {
                                  fatalError("Failed to create instance buffer")
    }
    return instanceBuffer
  }
  
  static func buildTransforms(instanceCount: Int) -> [Transform] {
    return [Transform](repeatElement(Transform(), count: instanceCount))
  }
  
  func set(color: float3) {
    guard submeshes.count > 0 else { return }
    submeshes[0].material.baseColor = color
  }
  
  private static func buildSamplerState() -> MTLSamplerState? {
    let descriptor = MTLSamplerDescriptor()
    descriptor.sAddressMode = .repeat
    descriptor.tAddressMode = .repeat
    descriptor.mipFilter = .linear
    descriptor.magFilter = .linear
    descriptor.maxAnisotropy = 8
    
    let samplerState =
      Renderer.device.makeSamplerState(descriptor: descriptor)
    return samplerState
  }
  
}

extension Prop: Renderable {
  func render(renderEncoder: MTLRenderCommandEncoder, uniforms vertex: Uniforms,
              fragmentUniforms fragment: FragmentUniforms) {
    var uniforms = vertex
    var fragmentUniforms = fragment
    uniforms.modelMatrix = worldTransform
    uniforms.normalMatrix = float3x3(normalFrom4x4: modelMatrix)
    fragmentUniforms.tiling = tiling
    
    renderEncoder.setVertexBuffer(instanceBuffer, offset: 0,
                                  index: Int(BufferIndexInstances.rawValue))
    
    renderEncoder.setFragmentSamplerState(samplerState, index: 0)
    renderEncoder.setVertexBytes(&uniforms,
                                 length: MemoryLayout<Uniforms>.stride,
                                 index: Int(BufferIndexUniforms.rawValue))
    renderEncoder.setFragmentBytes(&fragmentUniforms,
                                   length: MemoryLayout<FragmentUniforms>.stride,
                                   index: Int(BufferIndexFragmentUniforms.rawValue))
    
    for (index, vertexBuffer) in mesh.vertexBuffers.enumerated() {
      renderEncoder.setVertexBuffer(vertexBuffer.buffer,
                                    offset: 0, index: index)
    }
    
    renderEncoder.setFragmentBytes(&tiling, length: MemoryLayout<UInt32>.stride, index: 22)
    
    
    for modelSubmesh in submeshes {
      renderEncoder.setRenderPipelineState(modelSubmesh.pipelineState)
      renderEncoder.setFragmentTexture(modelSubmesh.textures.baseColor,
                                       index: Int(BaseColorTexture.rawValue))
      renderEncoder.setFragmentTexture(modelSubmesh.textures.normal,
                                       index: Int(NormalTexture.rawValue))
      renderEncoder.setFragmentTexture(modelSubmesh.textures.roughness,
                                       index: 2)
      renderEncoder.setFragmentTexture(modelSubmesh.textures.metallic,
                                       index: Int(MetallicTexture.rawValue))
      renderEncoder.setFragmentTexture(modelSubmesh.textures.ao,
                                       index: Int(AOTexture.rawValue))
      var material = modelSubmesh.material
      renderEncoder.setFragmentBytes(&material,
                                     length: MemoryLayout<Material>.stride,
                                     index: Int(BufferIndexMaterials.rawValue))
      guard let submesh = modelSubmesh.submesh else { continue }
      renderEncoder.drawIndexedPrimitives(type: .triangle,
                                          indexCount: submesh.indexCount,
                                          indexType: submesh.indexType,
                                          indexBuffer: submesh.indexBuffer.buffer,
                                          indexBufferOffset: submesh.indexBuffer.offset,
                                          instanceCount:  instanceCount)
    }
  }
}