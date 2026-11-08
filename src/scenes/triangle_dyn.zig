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

vert_buf: *c.SDL_GPUBuffer,
trans_buf: *c.SDL_GPUTransferBuffer,
pipeline: *c.SDL_GPUGraphicsPipeline,

const Self = @This();

const Vertex = extern struct {
    x: f32,
    y: f32,
    z: f32,
    r: f32,
    g: f32,
    b: f32,
    a: f32,
};
var vertices = [_]Vertex{
    .{ .x = 0, .y = 0.5, .z = 0, .r = 1, .g = 0, .b = 0, .a = 1 },
    .{ .x = -0.5, .y = -0.5, .z = 0, .r = 1, .g = 1, .b = 0, .a = 1 },
    .{ .x = 0.5, .y = -0.5, .z = 0, .r = 1, .g = 0, .b = 1, .a = 1 },
};
const vert_size = @sizeOf(@TypeOf(vertices));

const Uniform = extern struct {
    float: f32,
    // 16bytes aligned
    _pad: [3]f32 = @splat(0),
};

pub fn init(alloc: Allocator, device: *c.SDL_GPUDevice, tex_format: c.SDL_GPUTextureFormat, depth_format: c.SDL_GPUTextureFormat) Error!Self {
    // Vertex
    const vert_buf = try gfx.Buffer.createVertBuf(device, vert_size);
    errdefer c.SDL_ReleaseGPUBuffer(device, vert_buf);

    // Transfert
    const trans_buf = try gfx.Buffer.createTransferBuf(device, vert_size);
    // In this case, only used once in init
    errdefer c.SDL_ReleaseGPUTransferBuffer(device, trans_buf);

    // Pipeline
    const pipeline = try gfx.Pipeline.create(alloc, device, "triangle", .{
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

    return .{
        .vert_buf = vert_buf,
        .trans_buf = trans_buf,
        .pipeline = pipeline,
    };
}

fn update(s: *anyopaque, device: *c.SDL_GPUDevice, cmd: *c.SDL_GPUCommandBuffer, _: *const Camera, _: Scene.State) Error!void {
    const self: *Self = @ptrCast(@alignCast(s));

    const uniform: Uniform = .{
        .float = @as(f32, (@floatFromInt(c.SDL_GetTicksNS()))) / 1e9,
    };

    // Uniforms
    c.SDL_PushGPUFragmentUniformData(cmd, 0, &uniform, @sizeOf(Uniform));

    // Copy
    const copy_pass = c.SDL_BeginGPUCopyPass(cmd);

    vertices[0].x += 0.001;

    // Data mapping
    const data: [*]u8 = @ptrCast(@alignCast(
        try errify(c.SDL_MapGPUTransferBuffer(device, self.trans_buf, false)),
    ));
    @memcpy(data, std.mem.asBytes(&vertices));
    c.SDL_UnmapGPUTransferBuffer(device, self.trans_buf);

    const trans_buf_lococ = c.SDL_GPUTransferBufferLocation{
        .offset = 0,
        .transfer_buffer = self.trans_buf,
    };

    const buf_region = c.SDL_GPUBufferRegion{
        .offset = 0,
        .size = @sizeOf(@TypeOf(vertices)),
        .buffer = self.vert_buf,
    };

    c.SDL_UploadToGPUBuffer(copy_pass, &trans_buf_lococ, &buf_region, true);

    c.SDL_EndGPUCopyPass(copy_pass);
}

fn draw(s: *anyopaque, render_pass: *c.SDL_GPURenderPass, _: Scene.State) Error!void {
    const self: *Self = @ptrCast(@alignCast(s));

    // Draw
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

fn deinit(s: *anyopaque, alloc: Allocator, device: *c.SDL_GPUDevice) void {
    const self: *Self = @ptrCast(@alignCast(s));

    c.SDL_ReleaseGPUBuffer(device, self.vert_buf);
    c.SDL_ReleaseGPUTransferBuffer(device, self.trans_buf);
    c.SDL_ReleaseGPUGraphicsPipeline(device, self.pipeline);
    alloc.destroy(self);
}

pub fn scene(self: *Self) Scene {
    return .{
        .ptr = self,
        .vtable = &.{
            .update = update,
            .draw = draw,
            .deinit = deinit,
        },
    };
}
