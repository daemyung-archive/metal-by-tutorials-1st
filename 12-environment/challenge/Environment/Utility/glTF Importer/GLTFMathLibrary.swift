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

import Foundation
import simd

extension float4x4 {
  init(array: [Float]) {
    guard array.count == 16 else {
      fatalError("presented array has \(array.count) elements - a float4x4 needs 16 elements")
    }
    self = matrix_identity_float4x4
    columns = (
      float4( array[0],  array[1],  array[2],  array[3]),
      float4( array[4],  array[5],  array[6],  array[7]),
      float4( array[8],  array[9],  array[10], array[11]),
      float4( array[12],  array[13],  array[14],  array[15])
    )
  }
}

extension float3 {
  init(array: [Float]) {
    guard array.count == 3 else {
      fatalError("float3 array has \(array.count) elements - a float3 needs 3 elements")
    }
    self = float3(array[0], array[1], array[2])
  }
}

extension float4 {
  init(array: [Float]) {
    guard array.count == 4 else {
      fatalError("float4 array has \(array.count) elements - a float4 needs 4 elements")
    }
    self = float4(array[0], array[1], array[2], array[3])
  }
  
  init(array: [Double]) {
    guard array.count == 4 else {
      fatalError("float4 array has \(array.count) elements - a float4 needs 4 elements")
    }
    self = float4(Float(array[0]), Float(array[1]), Float(array[2]), Float(array[3]))
  }
  
}

extension simd_quatf {
  init(array: [Float]) {
    guard array.count == 4 else {
      fatalError("quaternion array has \(array.count) elements - a quaternion needs 4 Floats")
    }
    self = simd_quatf(ix: array[0], iy: array[1], iz: array[2], r: array[3])
  }
}

