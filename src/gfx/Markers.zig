// Screen-space markers (discs) drawn once per instance, as instanced quads
//   vertex buffer slot 0 (per vertex)   : the 6 quad corners, owned here
//   vertex buffer slot 1 (per instance) : any buffer whose elements start with a position,
//                                         for example the vertex buffer of a mesh
const std = @import("std");
const Allocator = std.mem.Allocator;
const c = @import("c");
const utils = @import("../utils.zig");
const Error = utils.Error;
const gfx = @import("../gfx.zig");
const upload = @import("mesh.zig").upload;

const Self = @This();

const Corner = extern struct { x: f32, y: f32 };

const CORNERS = [_]Corner{
    .{ .x = -1, .y = -1 },
    .{ .x = 1, .y = -1 },
    .{ .x = -1, .y = 1 },

    .{ .x = -1, .y = 1 },
    .{ .x = 1, .y = -1 },
    .{ .x = 1, .y = 1 },
};

pipeline: *c.SDL_GPUGraphicsPipeline,
quad: *c.SDL_GPUBuffer,

/// `Instance` is the element type of the instance buffer and `pos_offset` the byte offset of
/// its position (3 floats) inside it. Records the quad upload on `cmd`.
pub fn init(
    alloc: Allocator,
    device: *c.SDL_GPUDevice,
    cmd: *c.SDL_GPUCommandBuffer,
    tex_format: c.SDL_GPUTextureFormat,
    depth_format: c.SDL_GPUTextureFormat,
    comptime Instance: type,
    comptime pos_offset: u32,
) Error!Self {
    const pipeline = try gfx.pipeline.create(alloc, device, "points", .{
        .tex_format = tex_format,
        .depth_format = depth_format,
        .enable_depth_write = false,
        .vert_buffers = &.{
            .{ .slot = 0, .pitch = @sizeOf(Corner), .input_rate = c.SDL_GPU_VERTEXINPUTRATE_VERTEX, .instance_step_rate = 0 },
            .{ .slot = 1, .pitch = @sizeOf(Instance), .input_rate = c.SDL_GPU_VERTEXINPUTRATE_INSTANCE, .instance_step_rate = 0 },
        },
        .attrs = &.{
            .{ .buffer_slot = 0, .location = 0, .format = c.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT2, .offset = 0 },
            .{ .buffer_slot = 1, .location = 1, .format = c.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT3, .offset = pos_offset },
        },
    });
    errdefer c.SDL_ReleaseGPUGraphicsPipeline(device, pipeline);

    const quad = try gfx.buffer.createVertBuf(device, @sizeOf(@TypeOf(CORNERS)));
    errdefer c.SDL_ReleaseGPUBuffer(device, quad);

    try upload(device, cmd, &.{
        .{ .dst = quad, .bytes = std.mem.sliceAsBytes(&CORNERS) },
    });

    return .{ .pipeline = pipeline, .quad = quad };
}

pub fn deinit(self: Self, device: *c.SDL_GPUDevice) void {
    c.SDL_ReleaseGPUGraphicsPipeline(device, self.pipeline);
    c.SDL_ReleaseGPUBuffer(device, self.quad);
}

/// Inside the render pass. The vertex uniforms (slot 0) must already be pushed
pub fn draw(self: Self, pass: *c.SDL_GPURenderPass, instances: *c.SDL_GPUBuffer, count: u32) void {
    c.SDL_BindGPUGraphicsPipeline(pass, self.pipeline);
    c.SDL_BindGPUVertexBuffers(
        pass,
        0,
        &[_]c.SDL_GPUBufferBinding{
            .{ .buffer = self.quad, .offset = 0 },
            .{ .buffer = instances, .offset = 0 },
        },
        2,
    );
    c.SDL_DrawGPUPrimitives(pass, CORNERS.len, count, 0, 0);
}
