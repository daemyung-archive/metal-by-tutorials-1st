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

#include <metal_stdlib>
using namespace metal;

#import "Common.h"

struct VertexIn {
  float4 position [[ attribute(Position) ]];
  float3 normal [[ attribute(Normal) ]];
  float2 uv [[ attribute(UV) ]];
  float3 tangent [[ attribute(Tangent) ]];
  float3 bitangent [[ attribute(Bitangent) ]];
  float4 color [[ attribute(Color) ]];
  ushort4 joints [[ attribute(Joints) ]];
  float4 weights [[ attribute(Weights) ]];
};

struct VertexOut {
  float4 position [[ position ]];
  float3 worldNormal;
};

vertex VertexOut character_vertex_main(const VertexIn vertexIn [[ stage_in ]],
                                       constant float4x4 *jointMatrices [[ buffer(21) ]],
                                       constant Uniforms &uniforms [[ buffer(BufferIndexUniforms) ]])
{
  VertexOut out;
  float4x4 modelMatrix = uniforms.projectionMatrix * uniforms.viewMatrix * uniforms.modelMatrix;

  // skinning code
  float4 weights = vertexIn.weights;
  ushort4 joints = vertexIn.joints;
  float4x4 skinMatrix =
  weights.x * jointMatrices[joints.x] +
  weights.y * jointMatrices[joints.y] +
  weights.z * jointMatrices[joints.z] +
  weights.w * jointMatrices[joints.w];

  out.position = modelMatrix * skinMatrix * vertexIn.position;
  out.worldNormal = uniforms.normalMatrix *
                    (skinMatrix * float4(vertexIn.normal, 1)).xyz;
  
  return out;
}

fragment float4 character_fragment_main(VertexOut in [[ stage_in ]],
                              constant Material &material [[ buffer(BufferIndexMaterials) ]]) {
  float4 color;
  float3 normalDirection = normalize(in.worldNormal);
  float3 lightPosition = float3(1, 2, -2);
  float3 lightDirection = normalize(lightPosition);
  float nDotl = max(0.001, saturate(dot(normalDirection, lightDirection)));
  float3 diffuseColor = material.baseColor + pow(material.baseColor * nDotl,  3);
  color = float4(diffuseColor, 1);
  return color;
}

