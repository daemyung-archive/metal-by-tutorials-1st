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

class GLTFAsset {
  
  public var buffers = [MTLBuffer]()
  public var nodes = [CharacterNode]()
  public var skins = [Skin]()
  public var animations = [AnimationClip]()
  public var scenes = [GLTFScene]()
  
  private var glTFJSON: [String: Any]!
  private var buffersData = [Data]()
  private var bufferViews = [GLTFBufferView]()
  private var accessors = [GLTFAccessor]()
  private var meshes = [GLTFMesh]()
  private var gltfAnimations = [GLTFAnimation]()
  private var materials = [[String :Any]]()
  private var textures = [[String: Any]]()
  private var images = [[String: Any]]()
  private var samplers = [[String: Any]]()
  private var vertexCount: Int = 0
  
  var hasNormal = false
  var hasTangent = false
  var hasJoints = false
  var hasWeights = false
  var hasBitangent = false
  var hasColor = false
  
  private var animatedModel: Character!
  
  private var nodeToIndex: [Int: CharacterNode] = [:]
  
  init(filename: String) {
    let url = Bundle.main.url(forResource: filename, withExtension: "gltf")!
    let assetData = try! Data(contentsOf: url)
    glTFJSON = try! JSONSerialization.jsonObject(with: assetData, options: []) as! [String: Any]
    
    loadBuffers(url: url)
    loadBufferViews()
    loadAccessors()
    loadMaterials()
    loadTextures()
    loadImages()
    loadSamplers()
    loadMeshes()
    loadSkins()
    loadNodes()
    loadAnimations()
    loadScenes()
    
    // revisit the data to clean it up
    generateNodes()
    generateSkeleton()
    generateAnimations()
    generateMesh()
    
    // wrap up asset for external use
    finalizeAsset()
    
    print("\(filename) imported")
  }
  
  // collect mesh nodes for each scene
  private func finalizeAsset() {
    for scene in scenes {
      for node in scene.nodes {
        scene.meshNodes = flatten(root: node, children: { $0.children } ).filter( {
          $0.mesh != nil
        })
      }
    }
  }
  
  // flatten hierarchy into an array
  // thank you Stackoverflow
  // https://codereview.stackexchange.com/a/86915
  private func flatten<GLTFNode>(root: GLTFNode, children: (GLTFNode) -> [GLTFNode]) -> [GLTFNode] {
    return [root] + children(root).flatMap( {
      flatten(root: $0, children: children)
    } )
  }
  
  // create joint matrix palette
  // and load inverseBindPose
  private func generateSkeleton() {
    for skin in skins {
      guard let accessor = skin.inverseBindMatricesAccessor else { continue }
      let count = accessor.count
      assert(count == skin.jointNodes.count)
      let bufferView = accessor.bufferView!
      let end = bufferView.byteLength + bufferView.byteOffset
      let buffer = buffersData[bufferView.bufferIndex].subdata(in: bufferView.byteOffset..<end)
      
      skin.jointMatrixPalette = [simd_float4x4](repeatElement(float4x4.identity(), count: count))
      buffer.withUnsafeBytes { (bytes: UnsafePointer<float4x4>)->Void in
        var pointer = bytes
        for i in 0..<count {
          skin.jointMatrixPalette[i] = pointer.pointee
          pointer = pointer.advanced(by: 1)
          skin.jointNodes[i].inverseBindTransform = skin.jointMatrixPalette[i]
        }
      }
    }
  }
  
  private func generateMesh() {
    for mesh in meshes {
      for gltfSubmesh in mesh.gltfSubmeshes {
        hasJoints = false
        hasNormal = false
        hasTangent = false
        hasWeights = false
        let vertexDescriptor = createVertexDescriptor(submesh: gltfSubmesh)
        let mtkVertexDescriptor = MTKMetalVertexDescriptorFromModelIO(vertexDescriptor)!
        gltfSubmesh.pipelineState = createPipelineState(vertexDescriptor: mtkVertexDescriptor)
        
        let indexAccessor = gltfSubmesh.indexAccessor!
        let bufferView = indexAccessor.bufferView!
        let indexCount = indexAccessor.count
        let indexBuffer = buffers[bufferView.bufferIndex]
        let indexBufferOffset = bufferView.byteOffset + indexAccessor.offset
        
        gltfSubmesh.indexCount = indexCount
        gltfSubmesh.indexBuffer = indexBuffer
        gltfSubmesh.indexBufferOffset = indexBufferOffset
        
        for attribute in gltfSubmesh.accessorsForAttribute {
          guard let key = GLTFAttribute(rawValue: attribute.key) else {
            continue
          }
          let index = key.bufferIndex()
          let accessor = attribute.value
          let bufferView = accessor.bufferView!
          let bufferIndex = bufferView.bufferIndex
          let offset = accessor.offset + bufferView.byteOffset
          
          var attrib = Attributes()
          attrib.name = attribute.key
          attrib.index = index
          attrib.bufferIndex = bufferIndex
          attrib.offset = offset
          gltfSubmesh.attributes.append(attrib)
        }
        let submesh = Character.CharacterSubmesh(pipelineState: gltfSubmesh.pipelineState!, material: gltfSubmesh.material)
        submesh.attributes = gltfSubmesh.attributes
        submesh.indexCount = gltfSubmesh.indexCount
        submesh.indexBuffer = gltfSubmesh.indexBuffer
        submesh.indexBufferOffset = gltfSubmesh.indexBufferOffset
        submesh.indexType = gltfSubmesh.indexType
        mesh.submeshes.append(submesh)
      }
    }
  }
  
  private func createVertexDescriptor(submesh: GLTFSubmesh) -> MDLVertexDescriptor {
    let layouts = NSMutableArray(capacity: 8)
    for _ in 0..<8 {
      layouts.add(MDLVertexBufferLayout(stride: 0))
    }
    let vertexDescriptor = GLTFMakeVertexDescriptor()
    for accessorAttribute in submesh.accessorsForAttribute {
      let accessor = accessorAttribute.value
      var attributeName = "Untitled"
      var layoutIndex = 0
      guard let key = GLTFAttribute(rawValue: accessorAttribute.key) else {
        print("WARNING! - Attribute: \(accessorAttribute.key) not supported")
        continue
      }
      switch key {
      case .position:
        attributeName = MDLVertexAttributePosition
        vertexCount = accessor.count
      case .normal:
        attributeName = MDLVertexAttributeNormal
        hasNormal = true
      case .texCoord:
        attributeName = MDLVertexAttributeTextureCoordinate
      case .joints:
        attributeName = MDLVertexAttributeJointIndices
        hasJoints = true
      case .weights:
        attributeName = MDLVertexAttributeJointWeights
        hasWeights = true
      case .tangent:
        attributeName = MDLVertexAttributeTangent
        hasTangent = true
      case .bitangent:
        attributeName = MDLVertexAttributeBitangent
        hasBitangent = true
      case .color:
        attributeName = MDLVertexAttributeColor
        hasColor = true
      }
      layoutIndex = key.bufferIndex()
      
      let bufferView = accessor.bufferView!
      let format: MDLVertexFormat = GLTFGetVertexFormat(componentType: accessor.componentType, type: accessor.type)
      // the accessor and bufferView offsets are picked up during rendering,
      // as all layouts start from 0
      let offset = 0
      let attribute = MDLVertexAttribute(name: attributeName,
                                         format: format,
                                         offset: offset,
                                         bufferIndex: layoutIndex)
      vertexDescriptor.addOrReplaceAttribute(attribute)
      
      // update the layout
      var stride = bufferView.byteStride
      if stride <= 0 {
        stride = GLTFStrideOf(vertexFormat: format)
      }
      layouts[layoutIndex] = MDLVertexBufferLayout(stride: stride);
    }
    vertexDescriptor.layouts  = layouts
    return vertexDescriptor
  }
  
  // load buffers into MTLBuffers
  // buffers contain the data that is used for the geometry
  // of 3D models, animations and skinning
  private func loadBuffers(url: URL) {
    guard let buffersMap = glTFJSON["buffers"] as? [[String: Any]] else { return }
    buffersData.reserveCapacity(buffersMap.count)
    for properties in buffersMap {
      let byteLength = properties["byteLength"] as! Int
      let uri = properties["uri"]! as! String
      if uri.hasPrefix("data:application/octet-stream;base64") {
        fatalError("base64 encoding currently not supported")
      } else if uri.count > 0 {
        let fileURL = url.deletingLastPathComponent().appendingPathComponent(uri)
        print(fileURL)
        let data: Data
        do {
          data = try Data(contentsOf: fileURL)
        } catch let error {
          fatalError(error.localizedDescription)
        }
        let buffer = Renderer.device.makeBuffer(length: byteLength, options: [])!
        
        data.withUnsafeBytes { (uint8Ptr: UnsafePointer<UInt8>) in
          let pointer = UnsafeRawPointer(uint8Ptr)
          memcpy(buffer.contents(), pointer, byteLength)
        }
        buffers.append(buffer)
        buffersData.append(data)
      }
    }
  }
  
  // load bufferViews
  // the bufferViews add structural information to buffer data
  private func loadBufferViews() {
    guard let bufferViewsMap = glTFJSON["bufferViews"] as? [[String: Any]] else { return }
    bufferViews.reserveCapacity(bufferViewsMap.count)
    for (index, properties) in bufferViewsMap.enumerated() {
      let bufferView = GLTFBufferView()
      bufferView.bufferIndex = properties["buffer"] as? Int ?? 0
      bufferView.byteLength = properties["byteLength"] as? Int ?? 0
      bufferView.byteStride = properties["byteStride"] as? Int ?? 0
      bufferView.byteOffset = properties["byteOffset"] as? Int ?? 0
      bufferView.target = properties["target"] as? Int ?? 0
      bufferView.bufferViewIndex = index
      bufferViews.append(bufferView)
    }
  }
  
  // load accessors
  // the accessors define the exact type and layout of the data
  private func loadAccessors() {
    guard let accessorsMap = glTFJSON["accessors"] as? [[String: Any]] else { return }
    accessors.reserveCapacity(accessorsMap.count)
    for (index, properties) in accessorsMap.enumerated() {
      var accessor = GLTFAccessor()
      accessor.componentType = properties["componentType"] as? Int ?? 0
      accessor.type = properties["type"] as? String ?? "invalid"
      accessor.offset = properties["byteOffset"] as? Int ?? 0
      accessor.count = properties["count"] as? Int ?? 0
      let bufferViewIndex = properties["bufferView"] as? Int ?? 0
      if (bufferViewIndex < bufferViews.count) {
        accessor.bufferView = bufferViews[bufferViewIndex]
      }
      let minValues = properties["min"] as? [Float] ?? [Float]()
      for value in minValues {
        accessor.valueRange.minValues.append(value)
      }
      let maxValues = properties["max"] as? [Float] ?? [Float]()
      for value in maxValues {
        accessor.valueRange.maxValues.append(value)
      }
      accessor.accessorIndex = index
      accessors.append(accessor)
    }
  }
  
  private func loadMaterials() {
    guard let materialsMap = glTFJSON["materials"] as? [[String: Any]] else { return }
    materials = materialsMap
  }
  
  private func loadTextures() {
    guard let texturesMap = glTFJSON["textures"] as? [[String: Any]] else { return }
    textures = texturesMap
  }
  
  private func loadImages() {
    guard let imagesMap = glTFJSON["images"] as? [[String: Any]] else { return }
    images = imagesMap
  }
  
  private func loadSamplers() {
    guard let samplersMap = glTFJSON["samplers"] as? [[String: Any]] else { return }
    samplers = samplersMap
  }
  
  private func getImage(dictionary: [String: Any]) -> String? {
    if let texCoord = dictionary["texCoord"] as? Int {
      if texCoord != 0 {
        fatalError("only texCoord 0 is currently supported")
      }
    }
    if let index = dictionary["index"] as? Int {
      let textureDictionary = textures[index]
      if let imageIndex = textureDictionary["source"] as? Int {
        let imageDictionary = images[imageIndex]
        if let imageName = imageDictionary["uri"] as? String {
          print("Image name: \(imageName)")
          return imageName
        }
      }
    }
    return nil
  }
  
  private func createMaterial(index: Int) -> MDLMaterial {
    let material = MDLMaterial()
    let materialDictionary = materials[index]
    for property in materialDictionary {
      if property.key == "occlusionTexture" {
        var materialProperty: MDLMaterialProperty?
        if let dictionary = property.value as? [String: Any] {
          if let imageName = getImage(dictionary: dictionary) {
            materialProperty = MDLMaterialProperty(name: property.key, semantic: .ambientOcclusion, string: imageName)
          }
          if let strength = dictionary["strength"] as? Float {
            materialProperty = MDLMaterialProperty(name: "occlusionStrength", semantic: .ambientOcclusionScale, float: strength)
          }
        }
        if let materialProperty = materialProperty {
          material.setProperty(materialProperty)
        }
      }
      if property.key == "normalTexture" {
        var materialProperty: MDLMaterialProperty?
        if let dictionary = property.value as? [String: Any] {
          if let imageName = getImage(dictionary: dictionary) {
            materialProperty = MDLMaterialProperty(name: property.key, semantic: .tangentSpaceNormal, string: imageName)
          }
          if let scale = dictionary["scale"] as? Float {
            materialProperty = MDLMaterialProperty(name: "normalScale", semantic: .userDefined, float: scale)
          }
        }
        if let materialProperty = materialProperty {
          material.setProperty(materialProperty)
        }
      }
      if property.key == "pbrMetallicRoughness" {
        guard let properties = property.value as? [String: Any] else {
          continue
        }
        for property in properties {
          var materialProperty: MDLMaterialProperty?
          switch property.key {
          case "baseColorFactor":
            if let value = property.value as? [Float] {
              let color = float4(array: value)
              materialProperty = MDLMaterialProperty(name: property.key, semantic: .baseColor, float3: [color.x, color.y, color.z])
            } else if let value = property.value as? [Double] {
              let color = float4(array: value)
              materialProperty = MDLMaterialProperty(name: property.key, semantic: .baseColor, float3: [color.x, color.y, color.z])
            }
          case "metallicFactor":
            if let value = property.value as? Float {
              materialProperty = MDLMaterialProperty(name: property.key, semantic: .metallic, float: value)
            }
          case "roughnessFactor":
            if let value = property.value as? Float {
              materialProperty = MDLMaterialProperty(name: property.key, semantic: .roughness, float: value)
            }
          case "emissiveFactor":
            if let value = property.value as? Float {
              materialProperty = MDLMaterialProperty(name: property.key, semantic: .emission, float: value)
            }
          case "baseColorTexture":
            if let dictionary = property.value as? [String: Any] {
              if let imageName = getImage(dictionary: dictionary) {
                materialProperty = MDLMaterialProperty(name: property.key, semantic: .baseColor, string: imageName)
              }
            }
          case "metallicRoughnessTexture":
            if let dictionary = property.value as? [String: Any] {
              if let imageName = getImage(dictionary: dictionary) {
                materialProperty = MDLMaterialProperty(name: property.key, semantic: .userDefined, string: imageName)
              }
            }
          case "emissiveTexture":
            if let dictionary = property.value as? [String: Any] {
              if let imageName = getImage(dictionary: dictionary) {
                materialProperty = MDLMaterialProperty(name: property.key, semantic: .emission, string: imageName)
              }
            }
          default: break
          }
          if let materialProperty = materialProperty {
            material.setProperty(materialProperty)
          }
        }
      }
    }
    return material
  }
  
  // load meshes
  // refer to geometry data
  // has attributes eg POSITION, NORMAL with accessor indices
  // also has material
  // primitives are submeshes
  private func loadMeshes() {
    guard let meshesMap = glTFJSON["meshes"] as? [[String: Any]] else { return }
    meshes.reserveCapacity(meshesMap.count)
    for properties in meshesMap {
      let mesh = GLTFMesh()
      mesh.name = properties["name"] as? String ?? "untitled"
      mesh.extensions = properties["extensions"]
      mesh.extras = properties["extras"]
      let primitives = properties["primitives"] as? [Any] ?? [Any]()
      for primitive in primitives {
        guard let primitive = primitive as? [String: Any] else { continue }
        let submesh = GLTFSubmesh()
        
        let attributes = primitive["attributes"] as? [String: Any] ?? [String: Any]()
        var attributeAccessors = [String: GLTFAccessor]()
        for attribute in attributes {
          let attributeName = attribute.key
          let accessorIndex = attribute.value as? Int ?? 0
          guard accessorIndex < accessors.count else { continue }
          let accessor = accessors[accessorIndex]
          attributeAccessors[attributeName] = accessor
        }
        submesh.accessorsForAttribute = attributeAccessors
        
        // Create material
        if let materialIndex = primitive["material"] as? Int {
          submesh.material = createMaterial(index: materialIndex)
        }
        
        if let indexAccessorIndex = primitive["indices"] as? Int {
          submesh.indexAccessor = accessors[indexAccessorIndex]
          if let mode = primitive["mode"] as? Int {
            switch mode {
            case 0:
              submesh.primitiveType = .points
            case 1:
              submesh.primitiveType = .lines
            case 3:
              fatalError("line strips are not supported in Metal")
            case 4:
              submesh.primitiveType = .triangles
            case 5:
              submesh.primitiveType = .triangleStrips
            default:
              fatalError("Unsupported submesh Primitive Type")
            }
          }
        } else {
          fatalError("Currently only indexed glTF models are supported")
        }
        mesh.gltfSubmeshes.append(submesh)
      }
      meshes.append(mesh)
    }
  }
  
  // load skins
  private func loadSkins() {
    guard let skinsMap = glTFJSON["skins"] as? [[String: Any]] else { return }
    skins.reserveCapacity(skinsMap.count)
    for (index, properties) in skinsMap.enumerated() {
      let skin = Skin()
      skin.skinIndex = index
      // Skin is temporarily not a GLTFObject
      //      skin.name = properties["name"] as? String ?? "untitled"
      let accessorIndex = properties["inverseBindMatrices"] as! Int
      skin.inverseBindMatricesAccessor = accessors[accessorIndex]
      skin.jointNodeIndices = properties["joints"] as? [Int] ?? [Int]()
      skin.skeletonRootNodeIndex = properties["skeleton"] as? Int ?? 0
      skins.append(skin)
    }
  }
  
  // load nodes
  // needs skins and meshes loaded
  private func loadNodes() {
    guard let nodesMap = glTFJSON["nodes"] as? [[String: Any]] else { return }
    nodes.reserveCapacity(nodesMap.count)
    for (index, properties) in nodesMap.enumerated() {
      let node = CharacterNode()
      node.nodeIndex = index
      if properties["camera"] != nil {
        fatalError("cameras are not yet supported")
        continue
      }
      
      node.name = properties["name"] as? String ?? "untitled"
      
      // Currently for convenience CharacterNode is not a GLTFObject
      //      node.extras = properties["extras"]
      //      node.extensions = properties["extensions"]
      
      node.jointName = properties["jointName"] as? String
      node.childIndices = properties["children"] as? [Int] ?? [Int]()
      if let rotationArray = properties["rotation"] as? [Float] {
        node.rotationQuaternion = simd_quatf(array: rotationArray)
      }
      if let scaleArray = properties["scale"] as? [Float] {
        node.scale = float3(array: scaleArray)
      }
      if let translationArray = properties["translation"] as? [Float] {
        node.translation = float3(array: translationArray)
      }
      if let matrixArray = properties["matrix"] as? [Float] {
        node.matrix = float4x4(array: matrixArray)
      }
      if let meshIndex = properties["mesh"] as? Int {
        node.mesh = meshes[meshIndex]
      }
      if let skinIndex = properties["skin"] as? Int {
        node.skin = skins[skinIndex]
      }
      nodes.append(node)
    }
  }
  
  // load animations
  // needs nodes loaded
  private func loadAnimations() {
    guard let animationsMap = glTFJSON["animations"] as? [[String: Any]] else { return }
    gltfAnimations.reserveCapacity(animationsMap.count)
    for properties in animationsMap {
      let animation = GLTFAnimation()
      animation.name = properties["name"] as? String ?? "untitled"
      let samplersMap = properties["samplers"] as? [Any] ?? [Any]()
      for samplerMap in samplersMap {
        guard let samplerMap = samplerMap as? [String: Any] else { continue }
        var sampler = GLTFSampler()
        if let inputIndex = samplerMap["input"] as? Int {
          sampler.input = accessors[inputIndex]
          sampler.inputAccessorIndex = inputIndex
        }
        sampler.interpolation = samplerMap["interpolation"] as? String ?? "untitled"
        if let outputIndex = samplerMap["output"] as? Int {
          sampler.output = accessors[outputIndex]
          sampler.outputAccessorIndex = outputIndex
        }
        animation.samplers.append(sampler)
      }
      let channelsMap = properties["channels"] as? [Any] ?? [Any]()
      for channelMap in channelsMap {
        guard let channelMap = channelMap as? [String: Any] else { continue }
        var channel = GLTFChannel()
        let targets = channelMap["target"] as? [String: Any] ?? [String: Any]()
        if let targetNodeIndex = targets["node"] as? Int {
          channel.targetNode = nodes[targetNodeIndex]
          channel.targetPath = targets["path"] as? String ?? "untitled"
        }
        if let samplerIndex = channelMap["sampler"] as? Int {
          channel.sampler = animation.samplers[samplerIndex]
        }
        animation.channels.append(channel)
        
      }
      gltfAnimations.append(animation)
    }
  }
  
  private func loadScenes() {
    guard let scenesMap = glTFJSON["scenes"] as? [[String: Any]] else { return }
    scenes.reserveCapacity(scenesMap.count)
    for properties in scenesMap {
      let scene = GLTFScene()
      scene.name = properties["name"] as? String ?? "untitled"
      scene.extensions = properties["extensions"]
      scene.extras = properties["extras"]
      if let sceneNodes = properties["nodes"] as? [Int] {
        for nodeIndex in sceneNodes {
          scene.nodes.append(nodes[nodeIndex])
        }
      }
      scenes.append(scene)
    }
  }
  
  /// Iterate through Skins and Nodes to make
  /// sure they are all cross-checked with actual
  /// objects and not indices
  private func generateNodes() {
    for skin in skins {
      for index in skin.jointNodeIndices {
        skin.jointNodes.append(nodes[index])
      }
      skin.skeletonRootNode = nodes[skin.skeletonRootNodeIndex]
    }
    
    for node in nodes {
      
      nodeToIndex[node.nodeIndex] = node
      
      for index in node.childIndices {
        let childNode = nodes[index]
        childNode.parent = node
        node.children.append(childNode)
      }
    }
  }
  
  // generate key times and values from loaded animations
  private func generateAnimations() {
    for gltfAnimation in gltfAnimations {
      var animationClip = AnimationClip()
      animationClip.name = gltfAnimation.name
      for channel in gltfAnimation.channels {
        guard let sampler = channel.sampler,
          let nodeIndex = channel.targetNode?.nodeIndex,
          let inputAccessor = sampler.input,
          let inputBufferView = inputAccessor.bufferView,
          let outputAccessor = sampler.output,
          let outputBufferView = outputAccessor.bufferView,
          let targetPath = channel.targetPath
          else { continue }
        
        // load in key times through sampler input
        let inputStart = inputAccessor.offset + inputBufferView.byteOffset
        let inputEnd = inputStart + inputBufferView.byteLength
        let inputData = buffersData[inputBufferView.bufferIndex].subdata(in: inputStart..<inputEnd)
        let keyTimes = inputData.withUnsafeBytes {
          Array(UnsafeBufferPointer<Float>(start: $0, count: inputAccessor.count))
        }
        if let last = keyTimes.last {
          if last > animationClip.duration {
            animationClip.duration = last
          }
        }
        // load in translation and rotation values through sampler output
        let outputStart = outputAccessor.offset + outputBufferView.byteOffset
        var outputEnd = outputStart + outputBufferView.byteLength
        if outputBufferView.byteStride != 0 {
          outputEnd = outputStart + (outputAccessor.count*outputBufferView.byteStride)
        }
        let outputData = buffersData[outputBufferView.bufferIndex].subdata(in: outputStart..<outputEnd)
        
        var float3Values = [simd_float3]()
        var quaternionValues = [simd_quatf]()
        
        if outputAccessor.type == "VEC3" {
          outputData.withUnsafeBytes { (bytes: UnsafePointer<Float>)->Void in
            var pointer = bytes
            for _ in stride(from: 0, through:outputAccessor.count*3-1, by: 3) {
              var value = float3(0)
              value.x = pointer.pointee
              pointer = pointer.advanced(by: 1)
              value.y = pointer.pointee
              pointer = pointer.advanced(by: 1)
              value.z = pointer.pointee
              pointer = pointer.advanced(by: 1)
              float3Values.append(value)
            }
          }
        } else if outputAccessor.type == "VEC4" && targetPath == "rotation" {   // quaterions
          quaternionValues = outputData.withUnsafeBytes {
            Array(UnsafeBufferPointer<simd_quatf>(start: $0, count: outputAccessor.count))
          }
        }
        
        // add the keyTimes and
        // key values to the animation
        // for the correct node
        
        let animation = animationClip.nodeAnimations[nodeIndex] ?? Animation()
        switch targetPath {
          
        case "translation" where outputAccessor.type == "VEC3":
          for (index, keyTime) in keyTimes.enumerated() {
            let keyframe = Keyframe(time: keyTime, value: float3Values[index])
            animation.translations.append(keyframe)
          }
        case "rotation" where outputAccessor.type == "VEC4":
          for (index, keyTime) in keyTimes.enumerated() {
            let keyframe = KeyQuaternion(time: keyTime, value: quaternionValues[index])
            animation.rotations.append(keyframe)
          }
        case "scale":
          // Scale is not yet implemented
          break
        default:
          print("unknown key values type: \(targetPath): \(outputAccessor.type)")
          break
        }
        animationClip.nodeAnimations[nodeIndex] = animation
        animationClip.nodeAnimations[nodeIndex]?.node = nodeToIndex[nodeIndex]
      }
      animations.append(animationClip)
    }
  }
}

extension GLTFAsset {
  
  private func buildFunctionConstants() -> MTLFunctionConstantValues {
    let functionConstants = MTLFunctionConstantValues()
    functionConstants.setConstantValue(&hasNormal, type: .bool, index: Int(Normal.rawValue))
    functionConstants.setConstantValue(&hasTangent, type: .bool, index: Int(Tangent.rawValue))
    return functionConstants
  }
  
  func createPipelineState(vertexDescriptor: MTLVertexDescriptor) -> MTLRenderPipelineState{
    let functionConstants = buildFunctionConstants()
    let pipelineState: MTLRenderPipelineState
    do {
      let library = Renderer.device.makeDefaultLibrary()
      let vertexFunction = try library?.makeFunction(name: "character_vertex_main", constantValues: functionConstants)
      let fragmentFunction =  library?.makeFunction(name: "character_fragment_main")
      let descriptor = MTLRenderPipelineDescriptor()
      descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
      descriptor.vertexFunction = vertexFunction
      descriptor.fragmentFunction = fragmentFunction
      descriptor.vertexDescriptor = vertexDescriptor
      descriptor.depthAttachmentPixelFormat = .depth32Float
      try pipelineState = Renderer.device.makeRenderPipelineState(descriptor: descriptor)
    } catch let error {
      fatalError(error.localizedDescription)
    }
    return pipelineState
  }
}


/* This code owes much to Warren Moore's GLTFKit at
 https://github.com/warrenm/GLTFKit
 
 Used under license:
 Copyright (c) 2017 Warren Moore. All rights reserved.
 
 Permission to use, copy, modify, and distribute this software for any
 purpose with or without fee is hereby granted, provided that the above
 copyright notice and this permission notice appear in all copies.
 
 THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 */
