#version 460

layout(location = 0) in vec2 a_corner;
layout(location = 1) in vec3 a_position;

layout(std140, set = 1, binding = 0) uniform UniformCamera {
    mat4 mvp;
    mat4 model;
    // x = aspect (width / height)
    // y = marker radius in NDC height units (pixel radius = y * height / 2)
    // z = depth bias in NDC depth units
    vec4 marker;
};

layout(location = 0) out vec2 v_uv;

void main() {
    v_uv = a_corner;

    // Center of the marker in clip space.
    vec4 clip = mvp * vec4(a_position, 1.0);

    // Offset in NDC, so multiply by w to survive the perspective divide:
    // the marker keeps the same size in pixels at any distance.
    // NDC x spans the width and NDC y the height, so x is divided by the aspect
    // to get the same pixel size on both axes: a circle instead of an ellipse.
    vec2 offset = a_corner * marker.y * vec2(1.0 / marker.x, 1.0);
    // clip.xy += offset * clip.w;
    clip.xy += offset;

    // The quad has the depth of its center, but the sphere surface tilts around it:
    // without a bias one side of the marker loses the depth test.
    // Smaller z is nearer (non-reversed depth, compare LESS).
    clip.z -= marker.z * clip.w;

    gl_Position = clip;
}
