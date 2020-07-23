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

class Character: Node {
  
  let buffers: [MTLBuffer]
  let meshNodes: [CharacterNode]
  let animations: [AnimationClip]
  let nodes: [CharacterNode]
  var currentTime: Float = 0
  var currentAnimation: AnimationClip?
  var currentAnimationPlaying: Bool = false

  class CharacterSubmesh: Submesh {
    var attributes: [Attributes] = []
    var indexCount: Int = 0
    var indexBuffer: MTLBuffer?
    var indexBufferOffset: Int = 0
    var indexType: MTLIndexType = .uint16
  }
  
  var debugBoundingBox: DebugBoundingBox?
  override var boundingBox: MDLAxisAlignedBoundingBox {
    didSet {
      debugBoundingBox = DebugBoundingBox(boundingBox: boundingBox)
    }
  }
  
  init(name: String) {
    let asset = GLTFAsset(filename: name)
    buffers = asset.buffers
    animations = asset.animations
    guard asset.scenes.count > 0 else {
      fatalError("glTF file has no scene")
    }
    meshNodes = asset.scenes[0].meshNodes
    nodes = asset.scenes[0].nodes

    super.init()
    
    self.name = name
  }
  
  override func update(deltaTime: Float) {
    guard let animation = currentAnimation,
      currentAnimationPlaying == true else {
        return
    }
    currentTime += deltaTime
    let time = fmod(currentTime, animation.duration)
    for nodeAnimation in animation.nodeAnimations {
      let speed = animation.speed
      let animation = nodeAnimation.value
      animation.speed = speed
      guard let node = animation.node else { continue }
      if let translation = animation.getTranslation(time: time) {
        node.translation = translation
      }
      if let rotationQuaternion = animation.getRotation(time: time) {
        node.rotationQuaternion = rotationQuaternion
      }
    }
  }
}

// MARK:- Animation Control
extension Character {
  
  func calculateJoints(node: CharacterNode, time: Float) {
    if let nodeAnimation = animations[0].nodeAnimations[node.nodeIndex] {
      if let translation = nodeAnimation.getTranslation(time: time) {
        node.translation = translation
      }
      if let rotationQuaternion = nodeAnimation.getRotation(time: time) {
        node.rotationQuaternion = rotationQuaternion
      }
    }
    for child in node.children {
      calculateJoints(node: child, time: time)
    }
  }

  func runAnimation(clip animationClip: AnimationClip? = nil) {
    var clip = animationClip
    if clip == nil {
      guard animations.count > 0 else { return }
      clip = animations[0]
    } else {
      clip = animationClip
    }
    currentAnimation = clip
    currentTime = 0
    currentAnimationPlaying = true
    // immediately update the initial pose
    update(deltaTime: 0)
  }
  
  func runAnimation(name: String) {
    guard let clip = (animations.filter {
      $0.name == name
    }).first else {
      return
    }
    runAnimation(clip: clip)
  }
  
  func pauseAnimation() {
    currentAnimationPlaying = false
  }
  
  func resumeAnimation() {
    currentAnimationPlaying = true
  }
  
  func stopAnimation() {
    currentAnimation = nil
    currentAnimationPlaying = false
  }
}

// MARK:- Rendering
extension Character: Renderable {
  func render(renderEncoder: MTLRenderCommandEncoder, uniforms vertex: Uniforms) {
    for node in meshNodes {
      guard let mesh = node.mesh else { continue }
      
      if let skin = node.skin {
        for (i, jointNode) in skin.jointNodes.enumerated() {
          skin.jointMatrixPalette[i] = node.globalTransform.inverse *
            jointNode.globalTransform *
            jointNode.inverseBindTransform
        }
        let length = MemoryLayout<float4x4>.stride *
          skin.jointMatrixPalette.count
        let buffer =
          Renderer.device.makeBuffer(bytes: &skin.jointMatrixPalette,
                                     length: length, options: [])
        renderEncoder.setVertexBuffer(buffer, offset: 0, index: 21)
      }

      var uniforms = vertex
      uniforms.modelMatrix = worldTransform
      uniforms.normalMatrix = float3x3(normalFrom4x4: modelMatrix)
      renderEncoder.setVertexBytes(&uniforms,
                                   length: MemoryLayout<Uniforms>.stride,
                                   index: Int(BufferIndexUniforms.rawValue))
      
      for submesh in mesh.submeshes {
        renderEncoder.setRenderPipelineState(submesh.pipelineState)
        var material = submesh.material
        renderEncoder.setFragmentBytes(&material,
                                       length: MemoryLayout<Material>.stride,
                                       index: Int(BufferIndexMaterials.rawValue))
        for attribute in submesh.attributes {
          renderEncoder.setVertexBuffer(buffers[attribute.bufferIndex],
                                        offset: attribute.offset,
                                        index: attribute.index)
        }

        renderEncoder.drawIndexedPrimitives(type: .triangle,
                                            indexCount: submesh.indexCount,
                                            indexType: submesh.indexType,
                                            indexBuffer: submesh.indexBuffer!,
                                            indexBufferOffset: submesh.indexBufferOffset)
      }
      if debugRenderBoundingBox {
        debugBoundingBox?.render(renderEncoder: renderEncoder, uniforms: uniforms)
      }
    }
  }
}

