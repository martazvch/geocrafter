const std = @import("std");
const Allocator = std.mem.Allocator;
const c = @import("c");
const utils = @import("../utils.zig");
const errify = utils.errify;
const Error = utils.Error;
const App = @import("../App.zig");
const gfx = @import("../gfx.zig");
const Scene = @import("../Scene.zig");
const Camera = @import("../Camera.zig");
const Triangle = @import("../geom/Triangle.zig");
const Vertex = @import("../geom/vertex.zig").Vertex;

vert_buf: *c.SDL_GPUBuffer,
pipeline: *c.SDL_GPUGraphicsPipeline,
triangle: Triangle = .{},

const Self = @This();

const Uniform = extern struct {
    float: f32,
    // 16bytes aligned
    _pad: [3]f32 = @splat(0),
};

pub fn init(alloc: Allocator, device: *c.SDL_GPUDevice, tex_format: c.SDL_GPUTextureFormat, depth_format: c.SDL_GPUTextureFormat) Error!Self {
    const triangle: Triangle = .{};

    // Vertex
    const vert_buf = try gfx.buffer.createVertBuf(device, triangle.vert_size);
    errdefer c.SDL_ReleaseGPUBuffer(device, vert_buf);

    // Transfert
    const trans_buf = try gfx.buffer.createTransferBuf(device, triangle.vert_size);
    // In this case, only used once in init
    defer c.SDL_ReleaseGPUTransferBuffer(device, trans_buf);

    // Data mapping
    const data: [*]Vertex = @ptrCast(@alignCast(
        try errify(c.SDL_MapGPUTransferBuffer(device, trans_buf, false)),
    ));
    @memcpy(data, &triangle.vertices);
    c.SDL_UnmapGPUTransferBuffer(device, trans_buf);

    const pipeline = try gfx.pipeline.create(alloc, device, "triangle", .{
        .tex_format = tex_format,
        .depth_format = depth_format,
        .vert_buffers = &[_]c.SDL_GPUVertexBufferDescription{.{
            .slot = 0,
            .input_rate = c.SDL_GPU_VERTEXINPUTRATE_VERTEX,
            .instance_step_rate = 0,
            .pitch = @sizeOf(Vertex),
        }},
        .attrs = &[_]c.SDL_GPUVertexAttribute{
            .{ .buffer_slot = 0, .location = 0, .format = c.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT3, .offset = 0 },
            .{ .buffer_slot = 0, .location = 1, .format = c.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT4, .offset = 3 * @sizeOf(f32) },
        },
    });
    errdefer c.SDL_ReleaseGPUGraphicsPipeline(device, pipeline);

    // Copy
    const cmd = try errify(c.SDL_AcquireGPUCommandBuffer(device));
    const copy_pass = c.SDL_BeginGPUCopyPass(cmd);

    const transBufLoc = c.SDL_GPUTransferBufferLocation{
        .offset = 0,
        .transfer_buffer = trans_buf,
    };

    const bufRegion = c.SDL_GPUBufferRegion{
        .offset = 0,
        .size = @sizeOf(@TypeOf(triangle.vertices)),
        .buffer = vert_buf,
    };

    c.SDL_UploadToGPUBuffer(copy_pass, &transBufLoc, &bufRegion, true);

    c.SDL_EndGPUCopyPass(copy_pass);
    try errify(c.SDL_SubmitGPUCommandBuffer(cmd));

    return .{
        .vert_buf = vert_buf,
        .pipeline = pipeline,
        .triangle = triangle,
    };
}

fn update(_: *anyopaque, _: *c.SDL_GPUDevice, cmd: *c.SDL_GPUCommandBuffer, _: *const Camera, _: Scene.State) Error!void {
    // Uniforms
    const uniform: Uniform = .{
        .float = @as(f32, (@floatFromInt(c.SDL_GetTicksNS()))) / 1e9,
    };

    c.SDL_PushGPUFragmentUniformData(cmd, 0, &uniform, @sizeOf(Uniform));
}

fn draw(s: *anyopaque, render_pass: *c.SDL_GPURenderPass, _: *c.SDL_GPUCommandBuffer, _: Scene.State) Error!void {
    const self: *Self = @ptrCast(@alignCast(s));

    c.SDL_BindGPUGraphicsPipeline(render_pass, self.pipeline);

    c.SDL_BindGPUVertexBuffers(
        render_pass,
        0,
        &[_]c.SDL_GPUBufferBinding{
            .{ .buffer = self.vert_buf, .offset = 0 },
        },
        1,
    );

    c.SDL_DrawGPUPrimitives(render_pass, 3, 1, 0, 0);
}

fn drawUi(_: *anyopaque) void {}

fn deinit(s: *anyopaque, alloc: Allocator, device: *c.SDL_GPUDevice) void {
    const self: *Self = @ptrCast(@alignCast(s));

    c.SDL_ReleaseGPUBuffer(device, self.vert_buf);
    c.SDL_ReleaseGPUGraphicsPipeline(device, self.pipeline);
    alloc.destroy(self);
}

pub fn scene(self: *Self) Scene {
    return .{
        .ptr = self,
        .vtable = &.{
            .update = update,
            .draw = draw,
            .drawUi = drawUi,
            .deinit = deinit,
        },
    };
}
