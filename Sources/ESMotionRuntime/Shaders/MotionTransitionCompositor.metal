#include <metal_stdlib>
using namespace metal;

struct MotionTransitionUniforms {
    float2 viewportSize;
    float2 origin;
    float2 size;
    float cornerRadius;
    float opacity;
};

struct MotionTransitionVertexOut {
    float4 position [[position]];
    float2 uv;
    float2 localPosition;
};

vertex MotionTransitionVertexOut esmotionTransitionVertex(
    uint vertexID [[vertex_id]],
    constant MotionTransitionUniforms &uniforms [[buffer(0)]]
) {
    constexpr float2 corners[4] = {
        float2(0.0, 0.0),
        float2(1.0, 0.0),
        float2(0.0, 1.0),
        float2(1.0, 1.0)
    };
    float2 uv = corners[vertexID];
    float2 point = uniforms.origin + uv * uniforms.size;
    float2 clip = float2(
        point.x / uniforms.viewportSize.x * 2.0 - 1.0,
        1.0 - point.y / uniforms.viewportSize.y * 2.0
    );
    MotionTransitionVertexOut output;
    output.position = float4(clip, 0.0, 1.0);
    output.uv = uv;
    output.localPosition = uv * uniforms.size;
    return output;
}

fragment half4 esmotionTransitionFragment(
    MotionTransitionVertexOut input [[stage_in]],
    constant MotionTransitionUniforms &uniforms [[buffer(0)]],
    texture2d<half> image [[texture(0)]]
) {
    constexpr sampler textureSampler(
        mag_filter::linear,
        min_filter::linear,
        mip_filter::none,
        address::clamp_to_edge
    );
    float2 halfSize = uniforms.size * 0.5;
    float radius = min(
        uniforms.cornerRadius,
        min(halfSize.x, halfSize.y)
    );
    float2 q = abs(input.localPosition - halfSize)
        - (halfSize - float2(radius));
    float distance = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
    float coverage = 1.0 - smoothstep(-0.75, 0.75, distance);
    half4 color = image.sample(textureSampler, input.uv);
    color.a *= half(uniforms.opacity * coverage);
    return color;
}
