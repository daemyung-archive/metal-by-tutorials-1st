#include <metal_stdlib>
using namespace metal;

struct VertexOut {
  float4 position [[ position ]];
  float point_size [[ point_size ]];
};

// 1
vertex VertexOut vertex_main(constant float3 *vertices [[ buffer(0) ]],
                             constant float4x4 &matrix [[ buffer(1) ]],
                             uint id [[ vertex_id ]])
{
  // 3
  VertexOut vertex_out;
  vertex_out.position = matrix * float4(vertices[id], 1);
// 4
  vertex_out.point_size = 20.0;
  return vertex_out;
}

fragment float4 fragment_main(constant float4 &color [[ buffer(0) ]])
{
  return color;
}
