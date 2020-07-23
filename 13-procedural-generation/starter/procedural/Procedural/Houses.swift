//
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

class Houses: Node {
  var props: [Prop] = []
  
  override init() {
    
    super.init()
    props.append(Prop(name: "houseGround1",
                      vertexFunctionName: "vertex_house",
                      fragmentFunctionName: "fragment_house"))
  }
  
}

extension Houses: Renderable {
  func render(renderEncoder: MTLRenderCommandEncoder, uniforms vertex: Uniforms, fragmentUniforms fragment: FragmentUniforms) {
    for prop in props {
      var uniforms = vertex
      var fragmentUniforms = fragment
      uniforms.modelMatrix = modelMatrix * prop.modelMatrix
      uniforms.normalMatrix = float3x3(normalFrom4x4: modelMatrix * prop.modelMatrix)
      
      renderEncoder.setVertexBuffer(prop.instanceBuffer, offset: 0,
                                    index: Int(BufferIndexInstances.rawValue))
      renderEncoder.setFragmentSamplerState(prop.samplerState, index: 0)
      renderEncoder.setVertexBytes(&uniforms,
                                   length: MemoryLayout<Uniforms>.stride,
                                   index: Int(BufferIndexUniforms.rawValue))
      renderEncoder.setFragmentBytes(&fragmentUniforms,
                                     length: MemoryLayout<FragmentUniforms>.stride,
                                     index: Int(BufferIndexFragmentUniforms.rawValue))
      
      for (index, vertexBuffer) in prop.mesh.vertexBuffers.enumerated() {
        renderEncoder.setVertexBuffer(vertexBuffer.buffer,
                                      offset: 0, index: index)
      }
      
      var tiling = 1
      renderEncoder.setFragmentBytes(&tiling, length: MemoryLayout<UInt32>.stride, index: 22)
      for modelSubmesh in prop.submeshes {
        renderEncoder.setRenderPipelineState(modelSubmesh.pipelineState)
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
                                            instanceCount:  prop.instanceCount)
      }
    }
  }
}
