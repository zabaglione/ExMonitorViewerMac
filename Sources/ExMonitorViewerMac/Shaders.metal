#include <metal_stdlib>
using namespace metal;
struct VertexOut { float4 position [[position]]; float2 uv; };
vertex VertexOut viewerVertex(uint id [[vertex_id]]) {
    const float2 positions[] = {float2(-1,-1),float2(1,-1),float2(-1,1),float2(1,1)};
    const float2 uv[] = {float2(0,1),float2(1,1),float2(0,0),float2(1,0)};
    return {float4(positions[id],0,1),uv[id]};
}
fragment float4 viewerFragment(VertexOut in [[stage_in]], texture2d<float> image [[texture(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    return float4(image.sample(s,in.uv).rgb,1);
}
