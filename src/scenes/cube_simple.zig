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
const Cube = @import("../geom/Cube.zig");
const m = @import("math");
const Vertex = @import("../geom/vertex.zig").Vertex;

vert_buf: *c.SDL_GPUBuffer,
idx_buf: *c.SDL_GPUBuffer,
pipeline_fill: *c.SDL_GPUGraphicsPipeline,
pipeline_line: *c.SDL_GPUGraphicsPipeline,
cube: Cube = .{},

const Self = @This();

const CamUniform = extern struct {
    mvp: m.Mat4,
    model: m.Mat4,
};

pub fn init(alloc: Allocator, device: *c.SDL_GPUDevice, tex_format: c.SDL_GPUTextureFormat, depth_format: c.SDL_GPUTextureFormat) Error!Self {
    const pipeline_fill = try gfx.pipeline.create(alloc, device, "cube", .{
        .tex_format = tex_format,
        .depth_format = depth_format,
        .vert_buffers = &[_]c.SDL_GPUVertexBufferDescription{.{
            .slot = 0,
            .input_rate = c.SDL_GPU_VERTEXINPUTRATE_VERTEX,
            .pitch = @sizeOf(Vertex),
            .instance_step_rate = 0,
        }},
        .attrs = &[_]c.SDL_GPUVertexAttribute{
            .{ .buffer_slot = 0, .location = 0, .format = c.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT3, .offset = 0 },
            .{ .buffer_slot = 0, .location = 1, .format = c.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT4, .offset = 3 * @sizeOf(f32) },
        },
    });
    errdefer c.SDL_ReleaseGPUGraphicsPipeline(device, pipeline_fill);

    const pipeline_line = try gfx.pipeline.create(alloc, device, "cube", .{
        .tex_format = tex_format,
        .depth_format = depth_format,
        .fill_mode = c.SDL_GPU_FILLMODE_LINE,
        .vert_buffers = &[_]c.SDL_GPUVertexBufferDescription{.{
            .slot = 0,
            .input_rate = c.SDL_GPU_VERTEXINPUTRATE_VERTEX,
            .pitch = @sizeOf(Vertex),
            .instance_step_rate = 0,
        }},
        .attrs = &[_]c.SDL_GPUVertexAttribute{
            .{ .buffer_slot = 0, .location = 0, .format = c.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT3, .offset = 0 },
            .{ .buffer_slot = 0, .location = 1, .format = c.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT4, .offset = 3 * @sizeOf(f32) },
        },
    });
    errdefer c.SDL_ReleaseGPUGraphicsPipeline(device, pipeline_line);

    const cube: Cube = .{};
    // Vertices
    const vert_buf = try gfx.buffer.createVertBuf(device, cube.vert_size);
    errdefer c.SDL_ReleaseGPUBuffer(device, vert_buf);

    // Indices
    const idx_buf = try gfx.buffer.createVertBuf(device, cube.idx_size);
    errdefer c.SDL_ReleaseGPUBuffer(device, idx_buf);

    // Transfert
    const trans_buf = try gfx.buffer.createTransferBuf(device, cube.vert_size + cube.idx_size);
    defer c.SDL_ReleaseGPUTransferBuffer(device, trans_buf);

    // Data mapping
    const data: [*]u8 = @ptrCast(@alignCast(
        try errify(c.SDL_MapGPUTransferBuffer(device, trans_buf, false)),
    ));
    @memcpy(data[0..cube.vert_size], std.mem.asBytes(&cube.vertices));
    @memcpy(data[cube.vert_size..][0..cube.idx_size], std.mem.asBytes(&cube.indices));
    c.SDL_UnmapGPUTransferBuffer(device, trans_buf);

    // Copy
    const cmd = try errify(c.SDL_AcquireGPUCommandBuffer(device));
    const copy_pass = c.SDL_BeginGPUCopyPass(cmd);

    c.SDL_UploadToGPUBuffer(
        copy_pass,
        &.{ .offset = 0, .transfer_buffer = trans_buf },
        &.{ .offset = 0, .size = cube.vert_size, .buffer = vert_buf },
        false,
    );

    c.SDL_UploadToGPUBuffer(
        copy_pass,
        &.{ .offset = cube.vert_size, .transfer_buffer = trans_buf },
        &.{ .offset = 0, .size = cube.idx_size, .buffer = idx_buf },
        false,
    );

    c.SDL_EndGPUCopyPass(copy_pass);
    try errify(c.SDL_SubmitGPUCommandBuffer(cmd));

    return .{
        .vert_buf = vert_buf,
        .idx_buf = idx_buf,
        .pipeline_fill = pipeline_fill,
        .pipeline_line = pipeline_line,
        .cube = cube,
    };
}

fn update(_: *anyopaque, _: *c.SDL_GPUDevice, cmd: *c.SDL_GPUCommandBuffer, cam: *const Camera, _: Scene.State) Error!void {
    const model: m.Mat4 = .createAngleAxis(.unitY, @as(f32, (@floatFromInt(c.SDL_GetTicksNS()))) / 1e9);
    const cam_uniform: CamUniform = .{
        .mvp = model.mul(cam.view).mul(cam.proj),
        .model = model,
    };

    c.SDL_PushGPUFragmentUniformData(cmd, 0, &cam_uniform, @sizeOf(CamUniform));
}

fn draw(s: *anyopaque, render_pass: *c.SDL_GPURenderPass, _: *c.SDL_GPUCommandBuffer, config: Scene.State) Error!void {
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

    c.SDL_DrawGPUIndexedPrimitives(render_pass, self.cube.indices.len, 1, 0, 0, 0);
}

fn drawUi(_: *anyopaque) void {}

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
            .drawUi = drawUi,
            .deinit = deinit,
        },
    };
}
