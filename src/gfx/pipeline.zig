const std = @import("std");
const Allocator = std.mem.Allocator;
const c = @import("c");
const utils = @import("../utils.zig");
const errify = utils.errify;
const Error = utils.Error;
const Shader = @import("Shader.zig");

pub const Desc = struct {
    attrs: []const c.SDL_GPUVertexAttribute,
    vert_buffers: []const c.SDL_GPUVertexBufferDescription,
    tex_format: c.SDL_GPUTextureFormat,
    depth_format: c.SDL_GPUTextureFormat,
    fill_mode: c.SDL_GPUFillMode = c.SDL_GPU_FILLMODE_FILL,
    cull_mode: c.SDL_GPUCullMode = c.SDL_GPU_CULLMODE_NONE,
    enable_depth: bool = true,
};

pub fn create(
    alloc: Allocator,
    device: *c.SDL_GPUDevice,
    comptime shader_name: []const u8,
    desc: Desc,
) Error!*c.SDL_GPUGraphicsPipeline {
    var shader = try Shader.init(device, alloc, shader_name);
    defer shader.deinit(device);

    var color_target = std.mem.zeroes(c.SDL_GPUColorTargetDescription);
    color_target.format = desc.tex_format;
    color_target.blend_state = std.mem.zeroes(c.SDL_GPUColorTargetBlendState);

    var info = std.mem.zeroes(c.SDL_GPUGraphicsPipelineCreateInfo);
    info.vertex_shader = shader.vert;
    info.fragment_shader = shader.frag;
    info.primitive_type = c.SDL_GPU_PRIMITIVETYPE_TRIANGLELIST;

    info.vertex_input_state = .{
        .vertex_buffer_descriptions = desc.vert_buffers.ptr,
        .num_vertex_buffers = @intCast(desc.vert_buffers.len),
        .vertex_attributes = desc.attrs.ptr,
        .num_vertex_attributes = @intCast(desc.attrs.len),
    };

    var target_info = std.mem.zeroes(c.SDL_GPUGraphicsPipelineTargetInfo);
    target_info.num_color_targets = 1;
    target_info.color_target_descriptions = &color_target;
    target_info.has_depth_stencil_target = desc.enable_depth;
    target_info.depth_stencil_format = desc.depth_format;
    info.target_info = target_info;

    var depth_state = std.mem.zeroes(c.SDL_GPUDepthStencilState);
    depth_state.enable_depth_test = desc.enable_depth;
    depth_state.enable_depth_write = desc.enable_depth;
    depth_state.compare_op = c.SDL_GPU_COMPAREOP_LESS;
    info.depth_stencil_state = depth_state;

    var raster_state = std.mem.zeroes(c.struct_SDL_GPURasterizerState);
    raster_state.fill_mode = desc.fill_mode;
    raster_state.cull_mode = desc.cull_mode;
    raster_state.front_face = c.SDL_GPU_FRONTFACE_COUNTER_CLOCKWISE;
    info.rasterizer_state = raster_state;

    var multisample_state = std.mem.zeroes(c.struct_SDL_GPUMultisampleState);
    multisample_state.sample_count = c.SDL_GPU_SAMPLECOUNT_1;
    info.multisample_state = multisample_state;

    return errify(c.SDL_CreateGPUGraphicsPipeline(device, &info));
}
