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
class Skybox {
  let skybox: MTKMesh
  var skyboxTexture: MTLTexture?
  let pipelineState: MTLRenderPipelineState
  let depthStencilState: MTLDepthStencilState?
  
  struct SkySettings {
    var turbidity: Float = 1.0
    var sunElevation: Float = 0.77
    var upperAtmosphereScattering: Float = 0.93
    var groundAlbedo: Float = 0.1
  }
  var skySettings = SkySettings()
  
  var skyboxDiffuse: MTLTexture?
  var BRDFlut: MTLTexture?
  
  init(skyboxTextureName: String?) {
    let allocator = MTKMeshBufferAllocator(device: Renderer.device)
    let cube = MDLMesh(boxWithExtent: [1,1,1], segments: [1, 1, 1],
                       inwardNormals: true, geometryType: .triangles,
                       allocator: allocator)
    do {
      skybox = try MTKMesh(mesh: cube,
                           device: Renderer.device)
 
    } catch {
           fatalError("failed to create skybox mesh")
    }
    pipelineState =
      Skybox.buildPipelineState(vertexDescriptor: cube.vertexDescriptor)
    depthStencilState = Skybox.buildDepthStencilState()
    if skyboxTextureName == nil {
      skyboxTexture = loadGeneratedSkyboxTexture(dimensions: [256, 256])
      skyboxDiffuse = skyboxTexture
    } else { do {
      skyboxTexture = try Skybox.loadCubeTexture(imageName: skyboxTextureName!)
      let irradiance = "irradiance-" + skyboxTextureName! + ".png"
      skyboxDiffuse = try Skybox.loadCubeTexture(imageName: irradiance)
    } catch let error {
      fatalError(error.localizedDescription)
      }
    }
    BRDFlut = Renderer.buildBRDF()
  }
  
  func update(renderEncoder: MTLRenderCommandEncoder) {
    renderEncoder.setFragmentTexture(skyboxTexture,
                                     index: Int(BufferIndexSkybox.rawValue))
    renderEncoder.setFragmentTexture(skyboxDiffuse,
                                     index: Int(BufferIndexSkyboxDiffuse.rawValue))
    renderEncoder.setFragmentTexture(BRDFlut,
                                     index: Int(BufferIndexBRDFLut.rawValue))
  }
  
  func render(renderEncoder: MTLRenderCommandEncoder, uniforms: Uniforms) {
    renderEncoder.pushDebugGroup("Skybox")

    renderEncoder.setRenderPipelineState(pipelineState)
     renderEncoder.setDepthStencilState(depthStencilState)
    renderEncoder.setVertexBuffer(skybox.vertexBuffers[0].buffer,
                                  offset: 0, index: 0)
    var viewMatrix = uniforms.viewMatrix
    viewMatrix.columns.3 = [0, 0, 0, 1]
    var viewProjectionMatrix = uniforms.projectionMatrix * viewMatrix
    renderEncoder.setVertexBytes(&viewProjectionMatrix,
                                 length: MemoryLayout<float4x4>.stride,
                                 index: 1)
    renderEncoder.setFragmentTexture(skyboxTexture,
                                     index: Int(BufferIndexSkybox.rawValue))
    let submesh = skybox.submeshes[0]
    renderEncoder.drawIndexedPrimitives(type: .triangle,
                                        indexCount: submesh.indexCount,
                                        indexType: submesh.indexType,
                                        indexBuffer: submesh.indexBuffer.buffer,
                                        indexBufferOffset: 0)
  }
  
  func loadGeneratedSkyboxTexture(dimensions: int2) -> MTLTexture? {
    var texture: MTLTexture?
    let skyTexture = MDLSkyCubeTexture(name: "sky",
                                       channelEncoding: .uInt8,
                                       textureDimensions: dimensions,
                                       turbidity: skySettings.turbidity,
                                       sunElevation: skySettings.sunElevation,
                                       upperAtmosphereScattering: skySettings.upperAtmosphereScattering,
                                       groundAlbedo: skySettings.groundAlbedo)
    do {
      let textureLoader = MTKTextureLoader(device: Renderer.device)
      texture = try textureLoader.newTexture(texture: skyTexture, options:
        nil)
//      let irradiance = MDLTexture.irradianceTextureCube(with: skyTexture,
//                                                        name: nil, dimensions: [64, 64],
//                                                        roughness: 0.6)
//      skyboxDiffuse = try textureLoader.newTexture(texture: irradiance, options: nil)
    } catch let error {
      print(error.localizedDescription)
    }
    return texture
  }
  
  private static func
    buildPipelineState(vertexDescriptor: MDLVertexDescriptor)
    -> MTLRenderPipelineState {
      var pipelineState: MTLRenderPipelineState
      let descriptor = MTLRenderPipelineDescriptor()
      descriptor.colorAttachments[0].pixelFormat = Renderer.colorPixelFormat
      descriptor.depthAttachmentPixelFormat = .depth32Float
      descriptor.vertexFunction =
        Renderer.library?.makeFunction(name: "vertexSkybox")
      descriptor.fragmentFunction =
        Renderer.library?.makeFunction(name: "fragmentSkybox")
      descriptor.vertexDescriptor =
        MTKMetalVertexDescriptorFromModelIO(vertexDescriptor)
      do {
        pipelineState = try
          Renderer.device.makeRenderPipelineState(descriptor: descriptor)
      } catch let error {
        fatalError(error.localizedDescription)
      }
      return pipelineState
  }
  
  private static func buildDepthStencilState() -> MTLDepthStencilState? {
    let descriptor = MTLDepthStencilDescriptor()
    descriptor.depthCompareFunction = .lessEqual
    descriptor.isDepthWriteEnabled = true
    return Renderer.device.makeDepthStencilState(descriptor: descriptor)
  }
}

extension Skybox: Texturable {}
