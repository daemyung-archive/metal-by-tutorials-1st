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

import simd

let π = Float.pi

public func radians(fromDegrees degrees: Float) -> Float {
  return (degrees / 180) * π
}

public func degrees(fromRadians radians: Float) -> Float {
  return (radians / π) * 180
}

extension Float {
  var radiansToDegrees: Float {
    return (self / π) * 180
  }
  var degreesToRadians: Float {
    return (self / 180) * π
  }
}

extension float4x4 {
  public init(translation: float3) {
    self = matrix_identity_float4x4
    columns.3.x = translation.x
    columns.3.y = translation.y
    columns.3.z = translation.z
  }
  
  public init(scaling: float3) {
    self = matrix_identity_float4x4
    columns.0.x = scaling.x
    columns.1.y = scaling.y
    columns.2.z = scaling.z
  }
  
  public init(scaling: Float) {
    self = matrix_identity_float4x4
    columns.3.w = 1 / scaling
  }
  
  public init(rotationX angle: Float) {
    self = matrix_identity_float4x4
    columns.1.y = cos(angle)
    columns.1.z = sin(angle)
    columns.2.y = -sin(angle)
    columns.2.z = cos(angle)
  }
  
  public init(rotationY angle: Float) {
    self = matrix_identity_float4x4
    columns.0.x = cos(angle)
    columns.0.z = -sin(angle)
    columns.2.x = sin(angle)
    columns.2.z = cos(angle)
  }
  
  public init(rotationZ angle: Float) {
    self = matrix_identity_float4x4
    columns.0.x = cos(angle)
    columns.0.y = sin(angle)
    columns.1.x = -sin(angle)
    columns.1.y = cos(angle)
  }
  
  public init(rotation angle: float3) {
    let rotationX = float4x4(rotationX: angle.x)
    let rotationY = float4x4(rotationY: angle.y)
    let rotationZ = float4x4(rotationZ: angle.z)
    self = rotationX * rotationY * rotationZ
  }
  
  public static func identity() -> float4x4 {
    let matrix:float4x4 = matrix_identity_float4x4
    return matrix
  }
  
  public func upperLeft() -> float3x3 {
    var matrix = matrix_identity_float3x3
    matrix.columns.0 = [columns.0.x, columns.0.y, columns.0.z]
    matrix.columns.1 = [columns.1.x, columns.1.y, columns.1.z]
    matrix.columns.2 = [columns.2.x, columns.2.y, columns.2.z]
    return matrix
  }
  
  public init(projectionFov fov: Float, near: Float, far: Float, aspect: Float) {
    let y = 1 / tan(fov * 0.5)
    let x = y / aspect
    let z = far / (near - far)
    self.init(columns: (
        float4( x,  0,  0,  0),
        float4( 0,  y,  0,  0),
        float4( 0,  0,  z, -1),
        float4( 0,  0,  z * near,  0)
    ))
  }
  
  // left-handed LookAt
  public init(eye: float3, center: float3, up: float3) {
    let z = normalize(eye - center)
    let x = normalize(cross(up, z))
    let y = cross(z, x)
    let w = float3(dot(x, -eye), dot(y, -eye), dot(z, -eye))
    
    let X = float4(x.x, y.x, z.x, 0)
    let Y = float4(x.y, y.y, z.y, 0)
    let Z = float4(x.z, y.z, z.z, 0)
    let W = float4(w.x, w.y, x.z, 1)
    self.init(columns: (X, Y, Z, W))
  }

}
