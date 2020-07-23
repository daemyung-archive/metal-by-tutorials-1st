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
import MetalPerformanceShaders

class Terrain: Node {
  static let maxTessellation: Int = {
    #if os(macOS)
    return 64
    #else
    return 16
    #endif
  } ()
  
  let patches = (horizontal: 4, vertical: 4)
  var patchCount: Int {
    return patches.horizontal * patches.vertical
  }

  var edgeFactors: [Float] = [4]
  var insideFactors: [Float] = [4]
  var controlPointsBuffer: MTLBuffer?

  lazy var tessellationFactorsBuffer: MTLBuffer? = {
    let count = patchCount * (4 + 2)
    let size = count * MemoryLayout<Float>.size / 2
    return Renderer.device.makeBuffer(length: size,
                                      options: .storageModePrivate)
  }()
  let tessellationPipelineState: MTLComputePipelineState
  let renderPipelineState: MTLRenderPipelineState

  let heightMap: MTLTexture?
  let terrainColor: MTLTexture?
  
  var tiling: Float = 1

  var terrainUniforms = TerrainUniforms()
  
  init(patchCount: (horizontal: Int, vertical: Int),
       terrainSize: float2,
       heightScale: Float,
       heightTexture: String,
       colorTexture: String) {
    
    do {
      heightMap = try Terrain.loadTexture(imageName: heightTexture)
      terrainColor = try Terrain.loadTexture(imageName: colorTexture)
    } catch {
        fatalError(error.localizedDescription)
    }
    tessellationPipelineState = Terrain.buildComputePipelineState()
    let controlPoints = Terrain.createControlPoints(patches: patches,
                                            size: (width: terrainSize.x,
                                                   height: terrainSize.y))
    controlPointsBuffer = Renderer.device.makeBuffer(bytes: controlPoints,
                                                     length: MemoryLayout<float3>.stride * controlPoints.count)
    renderPipelineState = Terrain.buildRenderPipelineState()
    super.init()
    name = "Terrain"
    terrainUniforms.height = heightScale
    terrainUniforms.size = terrainSize
    terrainUniforms.maxTessellation = UInt32(Terrain.maxTessellation)
  }
  
  static func buildRenderPipelineState() -> MTLRenderPipelineState {
    let descriptor = MTLRenderPipelineDescriptor()
    descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
    descriptor.depthAttachmentPixelFormat = .depth32Float
    
    let vertexFunction = Renderer.library?.makeFunction(name: "terrain_vertex")
    let fragmentFunction = Renderer.library?.makeFunction(name: "terrain_fragment")
    descriptor.vertexFunction = vertexFunction
    descriptor.fragmentFunction = fragmentFunction
    
    let vertexDescriptor = MTLVertexDescriptor()
    vertexDescriptor.attributes[0].format = .float3
    vertexDescriptor.attributes[0].offset = 0
    vertexDescriptor.attributes[0].bufferIndex = 0
    
    vertexDescriptor.layouts[0].stepFunction = .perPatchControlPoint
    vertexDescriptor.layouts[0].stride = MemoryLayout<float3>.stride
    descriptor.vertexDescriptor = vertexDescriptor
    
    descriptor.tessellationFactorStepFunction = .perPatch
    descriptor.maxTessellationFactor = Terrain.maxTessellation
    descriptor.tessellationPartitionMode = .pow2
    
    return try! Renderer.device.makeRenderPipelineState(descriptor: descriptor)
  }

  static func buildComputePipelineState() -> MTLComputePipelineState {
    guard let kernelFunction =
      Renderer.library?.makeFunction(name: "terrain_kernel") else {
        fatalError("Tessellation shader function not found")
    }
    return try!
      Renderer.device.makeComputePipelineState(function: kernelFunction)
  }
  
  static func heightToSlope(source: MTLTexture) -> MTLTexture {
    let descriptor =
      MTLTextureDescriptor.texture2DDescriptor(pixelFormat:
        source.pixelFormat,
                                               width: source.width,
                                               height: source.height,
                                               mipmapped: false)
    descriptor.usage = [.shaderWrite, .shaderRead]
    guard let destination = Renderer.device.makeTexture(descriptor: descriptor),
      let commandBuffer = Renderer.commandQueue.makeCommandBuffer()
      else {
        fatalError()
    }
    let shader = MPSImageSobel(device: Renderer.device)
    shader.encode(commandBuffer: commandBuffer,
                  sourceTexture: source,
                  destinationTexture: destination)
    commandBuffer.commit()
    return destination
  }

  static func createControlPoints(patches: (horizontal: Int, vertical: Int),
                           size: (width: Float, height: Float)) -> [float3] {
    
    var points: [float3] = []
    // per patch width and height
    let width = 1 / Float(patches.horizontal)
    let height = 1 / Float(patches.vertical)
    
    for j in 0..<patches.vertical {
      let row = Float(j)
      for i in 0..<patches.horizontal {
        let column = Float(i)
        let left = width * column
        let bottom = height * row
        let right = width * column + width
        let top = height * row + height
        
        points.append([left, 0, top])
        points.append([right, 0, top])
        points.append([right, 0, bottom])
        points.append([left, 0, bottom])
      }
    }
    // size and convert to Metal coordinates
    // eg. 6 across would be -3 to + 3
    points = points.map {
      [$0.x * size.width - size.width / 2,
       0,
       $0.z * size.height - size.height / 2]
    }
    return points
  }
  
  func update(viewMatrix: float4x4) {
    guard let computeEncoder = Renderer.commandBuffer?.makeComputeCommandEncoder() else {
      fatalError()
    }
    computeEncoder.setComputePipelineState(tessellationPipelineState)
    computeEncoder.setBytes(&edgeFactors,
                            length: MemoryLayout<Float>.size * edgeFactors.count,
                            index: 0)
    computeEncoder.setBytes(&insideFactors,
                            length: MemoryLayout<Float>.size * insideFactors.count,
                            index: 1)
    computeEncoder.setBuffer(tessellationFactorsBuffer, offset: 0, index: 2)
    var cameraPosition = viewMatrix.columns.3
    computeEncoder.setBytes(&cameraPosition,
                            length: MemoryLayout<float4>.stride,
                            index: 3)
    var matrix = modelMatrix
    computeEncoder.setBytes(&matrix,
                            length: MemoryLayout<float4x4>.stride,
                            index: 4)
    computeEncoder.setBuffer(controlPointsBuffer, offset: 0, index: 5)
    computeEncoder.setBytes(&terrainUniforms,
                            length: MemoryLayout<TerrainUniforms>.stride,
                            index: 6)
    
    let width = min(patchCount,
                    tessellationPipelineState.threadExecutionWidth)
    computeEncoder.dispatchThreadgroups(MTLSizeMake(patchCount, 1, 1),
                                        threadsPerThreadgroup: MTLSizeMake(width, 1, 1))
    computeEncoder.endEncoding()

  }

}

extension Terrain: Texturable {}


extension Terrain: Renderable {
  
  
  func render(renderEncoder: MTLRenderCommandEncoder, uniforms: Uniforms, fragmentUniforms: FragmentUniforms) {
    var mvp = uniforms.projectionMatrix * uniforms.viewMatrix * modelMatrix
    renderEncoder.setVertexBytes(&mvp, length: MemoryLayout<float4x4>.stride, index: 1)
    renderEncoder.setRenderPipelineState(renderPipelineState)
    renderEncoder.setVertexBuffer(controlPointsBuffer, offset: 0, index: 0)
    renderEncoder.setTessellationFactorBuffer(tessellationFactorsBuffer,
                                              offset: 0,
                                              instanceStride: 0)
    
    renderEncoder.setVertexTexture(heightMap, index: 0)
    renderEncoder.setVertexBytes(&terrainUniforms,
                                 length: MemoryLayout<TerrainUniforms>.stride, index: 6)
    renderEncoder.setFragmentTexture(terrainColor, index: 1)
    renderEncoder.setFragmentBytes(&tiling, length: MemoryLayout<Float>.stride, index: 1)
    // draw
    renderEncoder.drawPatches(numberOfPatchControlPoints: 4,
                              patchStart: 0, patchCount: patchCount,
                              patchIndexBuffer: nil,
                              patchIndexBufferOffset: 0,
                              instanceCount: 1, baseInstance: 0)
    

  }
}
