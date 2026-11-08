#version 460

layout(location = 0) in vec2 a_corner;
layout(location = 1) in vec3 a_position;

layout(std140, set = 1, binding = 0) uniform UniformCamera {
    mat4 mvp;
    mat4 model;
};

layout(location = 0) out vec2 v_uv;

void main() {
    v_uv = a_corner;

    // These offsets are in local sphere coordinates.
    // Replace with camera-facing basis vectors for true billboards.
    float radius = 0.005;

    // Transform sphere vertex into world space.
    vec4 world_pos = model * vec4(a_position, 1.0);

    // Project center into clip space.
    vec4 clip_pos = mvp * vec4(a_position, 1.0);

    // Offset in screen-aligned clip coordinates.
    clip_pos.xy += a_corner * radius * clip_pos.w;

    gl_Position = clip_pos;
}
