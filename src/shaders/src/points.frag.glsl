#version 460

layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 out_color;

void main() {
    if (dot(v_uv, v_uv) > 1.0) {
        discard;
    }

    out_color = vec4(1.0, 0.15, 0.05, 1.0);
    out_color = vec4(1.0, 0.0, 0.0, 1.0);
}
