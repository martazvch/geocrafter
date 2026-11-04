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
const m = @import("math");

vert_buf: *c.SDL_GPUBuffer,
idx_buf: *c.SDL_GPUBuffer,
pipeline_fill: *c.SDL_GPUGraphicsPipeline,
pipeline_line: *c.SDL_GPUGraphicsPipeline,

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

fn v(x: f32, y: f32, z: f32, r: f32, g: f32, b: f32) Vertex {
    return .{ .x = x, .y = y, .z = z, .r = r, .g = g, .b = b, .a = 1 };
}

const vertices = [24]Vertex{
    // +Z (front), red
    v(-0.5, -0.5, 0.5, 1, 0, 0),  v(0.5, -0.5, 0.5, 1, 0, 0),
    v(0.5, 0.5, 0.5, 1, 0, 0),    v(-0.5, 0.5, 0.5, 1, 0, 0),
    // -Z (back), green
    v(0.5, -0.5, -0.5, 0, 1, 0),  v(-0.5, -0.5, -0.5, 0, 1, 0),
    v(-0.5, 0.5, -0.5, 0, 1, 0),  v(0.5, 0.5, -0.5, 0, 1, 0),
    // +X (right), blue
    v(0.5, -0.5, 0.5, 0, 0, 1),   v(0.5, -0.5, -0.5, 0, 0, 1),
    v(0.5, 0.5, -0.5, 0, 0, 1),   v(0.5, 0.5, 0.5, 0, 0, 1),
    // -X (left), yellow
    v(-0.5, -0.5, -0.5, 1, 1, 0), v(-0.5, -0.5, 0.5, 1, 1, 0),
    v(-0.5, 0.5, 0.5, 1, 1, 0),   v(-0.5, 0.5, -0.5, 1, 1, 0),
    // +Y (top), magenta
    v(-0.5, 0.5, 0.5, 1, 0, 1),   v(0.5, 0.5, 0.5, 1, 0, 1),
    v(0.5, 0.5, -0.5, 1, 0, 1),   v(-0.5, 0.5, -0.5, 1, 0, 1),
    // -Y (bottom), cyan
    v(-0.5, -0.5, -0.5, 0, 1, 1), v(0.5, -0.5, -0.5, 0, 1, 1),
    v(0.5, -0.5, 0.5, 0, 1, 1),   v(-0.5, -0.5, 0.5, 0, 1, 1),
};
const vert_size = @sizeOf(@TypeOf(vertices));

const indices = [36]u16{
    0, 1, 2, 0, 2, 3, // +Z
    4, 5, 6, 4, 6, 7, // -Z
    8, 9, 10, 8, 10, 11, // +X
    12, 13, 14, 12, 14, 15, // -X
    16, 17, 18, 16, 18, 19, // +Y
    20, 21, 22, 20, 22, 23, // -Y
};
const idx_size = @sizeOf(@TypeOf(indices));

const CamUniform = extern struct {
    mvp: m.Mat4,
    model: m.Mat4,
};

pub fn init(alloc: Allocator, device: *c.SDL_GPUDevice, tex_format: c.SDL_GPUTextureFormat, depth_format: c.SDL_GPUTextureFormat) Error!*Self {
    const pipeline_fill = try gfx.Pipeline.create(alloc, device, "cube", .{
        .vertex_pitch = @sizeOf(Vertex),
        .tex_format = tex_format,
        .depth_format = depth_format,
        .attrs = &[_]c.SDL_GPUVertexAttribute{
            .{ .buffer_slot = 0, .location = 0, .format = c.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT3, .offset = 0 },
            .{ .buffer_slot = 0, .location = 1, .format = c.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT4, .offset = 3 * @sizeOf(f32) },
        },
    });
    errdefer c.SDL_ReleaseGPUGraphicsPipeline(device, pipeline_fill);

    const pipeline_line = try gfx.Pipeline.create(alloc, device, "cube", .{
        .vertex_pitch = @sizeOf(Vertex),
        .tex_format = tex_format,
        .depth_format = depth_format,
        .fill_mode = c.SDL_GPU_FILLMODE_LINE,
        .attrs = &[_]c.SDL_GPUVertexAttribute{
            .{ .buffer_slot = 0, .location = 0, .format = c.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT3, .offset = 0 },
            .{ .buffer_slot = 0, .location = 1, .format = c.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT4, .offset = 3 * @sizeOf(f32) },
        },
    });
    errdefer c.SDL_ReleaseGPUGraphicsPipeline(device, pipeline_line);

    // Vertices
    const vert_buf = try gfx.Buffer.createVertBuf(device, vert_size);
    errdefer c.SDL_ReleaseGPUBuffer(device, vert_buf);

    // Indices
    const idx_buf = try gfx.Buffer.createVertBuf(device, idx_size);
    errdefer c.SDL_ReleaseGPUBuffer(device, idx_buf);

    // Transfert
    const trans_buf = try gfx.Buffer.createTransferBuf(device, vert_size + idx_size);
    defer c.SDL_ReleaseGPUTransferBuffer(device, trans_buf);

    // Data mapping
    const data: [*]u8 = @ptrCast(@alignCast(
        try errify(c.SDL_MapGPUTransferBuffer(device, trans_buf, false)),
    ));
    @memcpy(data[0..vert_size], std.mem.asBytes(&vertices));
    @memcpy(data[vert_size..][0..idx_size], std.mem.asBytes(&indices));
    c.SDL_UnmapGPUTransferBuffer(device, trans_buf);

    // Copy
    const cmd = try errify(c.SDL_AcquireGPUCommandBuffer(device));
    const copy_pass = c.SDL_BeginGPUCopyPass(cmd);

    c.SDL_UploadToGPUBuffer(
        copy_pass,
        &.{ .offset = 0, .transfer_buffer = trans_buf },
        &.{ .offset = 0, .size = vert_size, .buffer = vert_buf },
        false,
    );

    c.SDL_UploadToGPUBuffer(
        copy_pass,
        &.{ .offset = vert_size, .transfer_buffer = trans_buf },
        &.{ .offset = 0, .size = idx_size, .buffer = idx_buf },
        false,
    );

    c.SDL_EndGPUCopyPass(copy_pass);
    try errify(c.SDL_SubmitGPUCommandBuffer(cmd));

    const self = alloc.create(Self) catch unreachable;
    self.* = .{
        .vert_buf = vert_buf,
        .idx_buf = idx_buf,
        .pipeline_fill = pipeline_fill,
        .pipeline_line = pipeline_line,
    };

    return self;
}

fn update(_: *anyopaque, _: *c.SDL_GPUDevice, cmd: *c.SDL_GPUCommandBuffer, cam: *const Camera, _: Scene.State) Error!void {
    const model: m.Mat4 = .createAngleAxis(.unitY, @as(f32, (@floatFromInt(c.SDL_GetTicksNS()))) / 1e9);
    const cam_uniform: CamUniform = .{
        .mvp = model.mul(cam.view).mul(cam.proj),
        .model = model,
    };

    c.SDL_PushGPUFragmentUniformData(cmd, 0, &cam_uniform, @sizeOf(CamUniform));
}

fn draw(s: *anyopaque, render_pass: *c.SDL_GPURenderPass, config: Scene.State) Error!void {
    const self: *Self = @ptrCast(@alignCast(s));

    if (config.wireframe) {
        c.SDL_BindGPUGraphicsPipeline(render_pass, self.pipeline_line);
    } else {
        c.SDL_BindGPUGraphicsPipeline(render_pass, self.pipeline_fill);
    }

    c.SDL_BindGPUVertexBuffers(
        render_pass,
        0,
        &[_]c.SDL_GPUBufferBinding{
            .{ .buffer = self.vert_buf, .offset = 0 },
        },
        1,
    );

    c.SDL_BindGPUIndexBuffer(render_pass, &.{
        .buffer = self.idx_buf,
        .offset = 0,
    }, c.SDL_GPU_INDEXELEMENTSIZE_16BIT);

    c.SDL_DrawGPUIndexedPrimitives(render_pass, indices.len, 1, 0, 0, 0);
}

fn deinit(s: *anyopaque, alloc: Allocator, device: *c.SDL_GPUDevice) void {
    const self: *Self = @ptrCast(@alignCast(s));

    c.SDL_ReleaseGPUBuffer(device, self.vert_buf);
    c.SDL_ReleaseGPUBuffer(device, self.idx_buf);
    c.SDL_ReleaseGPUGraphicsPipeline(device, self.pipeline_fill);
    c.SDL_ReleaseGPUGraphicsPipeline(device, self.pipeline_line);
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
