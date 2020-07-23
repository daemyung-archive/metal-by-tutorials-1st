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
  
  enum Rules {
    // gap between houses
    static let minGap: Float = 0.3
    static let maxGap: Float = 1.0
    
    // number of obj files for each type
    static let numberOfGroundFloors = 4
    static let numberOfUpperFloors = 4
    static let numberOfRoofs = 2
    
    // maximum houses
    static let maxHouses: Int = 5
    
    // maximum number of floors in a single house
    static let maxFloors: Int = 6
  }
  
  var floorsRoof: Set<Int> = []
  var remainingHouses: Set<Int> = []
  var housefloors: [[Int]] = []
  
  struct Floor {
    var propIndex: Int = 0
    var transform = Transform()
  }
  var floors: [Floor] = []
  var props: [Prop] = []
  
  override init() {
    
    super.init()
    props = loadobjs()
    let numberOfHouses = 5
    for _ in 0..<numberOfHouses {
      let random = Int.random(in: 0..<Rules.numberOfGroundFloors)
      housefloors.append([random])
      let lastIndex = housefloors.count - 1
      remainingHouses.insert(lastIndex)
    }
    
    while remainingHouses.count > 0 {
      for i in 0..<housefloors.count {
        // 1
        if remainingHouses.contains(i) {
          let offset = Rules.numberOfGroundFloors
          let upperBound =
            offset + Rules.numberOfUpperFloors + Rules.numberOfRoofs
          let random = Int.random(in: offset..<upperBound)
          housefloors[i].append(random)
          
          // 2
          if floorsRoof.contains(random) ||
            housefloors[i].count >= Rules.maxFloors ||
            Int.random(in: 0...3) == 0 {
            // 3
            remainingHouses.remove(i)
          }
        }
      }
    }
    // 4
    var width: Float = 0
    var height: Float = 0
    var depth: Float = 0
    for house in housefloors {
      var houseHeight: Float = 0
      
      // add inner for loop here to process all the floors
      for floor in house {
        var transform = Transform()
        transform.position.x = width
        transform.position.y = houseHeight
        floors.append(Floor(propIndex: floor, transform: transform))
        houseHeight += props[floor].size.y
      }
      
      let prop = props[house[0]]
      width += prop.size.x
      height = max(houseHeight, height)
      depth = max(prop.size.z, depth)
      boundingBox.maxBounds = [width, height, depth]
      width += Float.random(in: Rules.minGap...Rules.maxGap)
    }
    
  }
 
  func loadobjs() -> [Prop] {
    var props: [Prop] = []
    func loadHouse(name: String) {
      props.append(Prop(name: name,
                        vertexFunctionName: "vertex_house",
                        fragmentFunctionName: "fragment_house"))
    }
    for i in 1...Rules.numberOfGroundFloors {
      loadHouse(name: String(format: "houseGround%d", i))
    }
    for i in 1...Rules.numberOfUpperFloors {
      loadHouse(name: String(format: "houseFloor%d", i))
    }
    for i in 1...Rules.numberOfRoofs {
      loadHouse(name: String(format: "houseRoof%d", i))
      floorsRoof.insert(props.count-1)
    }
    return props
  }
}

extension Houses: Renderable {
  func render(renderEncoder: MTLRenderCommandEncoder, uniforms vertex: Uniforms, fragmentUniforms fragment: FragmentUniforms) {
    for floor in floors {
      let prop = props[floor.propIndex]
      var uniforms = vertex
      var fragmentUniforms = fragment
      uniforms.modelMatrix = modelMatrix * floor.transform.modelMatrix
      uniforms.normalMatrix =
        float3x3(normalFrom4x4: modelMatrix * floor.transform.modelMatrix)
      
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
