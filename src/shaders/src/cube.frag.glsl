#version 460

layout(location = 0) in vec4 v_color;
layout(location = 0) out vec4 FragColor;

layout(std140, set = 3, binding = 0) uniform UniformBlock {
    bool time;
};

void main() {
    FragColor = v_color;
}
