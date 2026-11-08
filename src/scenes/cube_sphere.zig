const std = @import("std");
const Allocator = std.mem.Allocator;
const c = @import("c");
const utils = @import("../utils.zig");
const errify = utils.errify;
const oom = utils.oom;
const Error = utils.Error;
const App = @import("../App.zig");
const gfx = @import("../gfx.zig");
const Scene = @import("../Scene.zig");
const Camera = @import("../Camera.zig");
const m = @import("math");

vert_buf: *c.SDL_GPUBuffer,
idx_buf: *c.SDL_GPUBuffer,
quad_buf: *c.SDL_GPUBuffer,
pipeline_fill: *c.SDL_GPUGraphicsPipeline,
pipeline_line: *c.SDL_GPUGraphicsPipeline,
pipeline_points: *c.SDL_GPUGraphicsPipeline,
cube: Cube,
orientation: m.Mat4 = .identity,
spin: m.Vec3 = .zero,

const Self = @This();

const NORMALS: [6]m.Vec3 = .{
    .new(0, 0, -1), // -Z
    .new(1, 0, 0), // +X
    .new(0, -1, 0), // -Y
    .new(0, 0, 1), // +Z
    .new(-1, 0, 0), // -X
    .new(0, 1, 0), // +Y
};

fn faceAxes(face: usize) struct { n: m.Vec3, u: m.Vec3, v: m.Vec3 } {
    const n = NORMALS[face];
    // Moves the non-zero component to another slot, rotating vector 90°
    const u = n.swizzle("yzx");
    // Gets the third axis
    const v = n.cross(u);

    return .{
        .n = n,
        .u = u,
        .v = v,
    };
}

const Cube = struct {
    vertices: []const Vertex,
    indices: []const u32,
};

fn makeCube(alloc: Allocator, quads: usize) Cube {
    const side = quads + 1;
    const s: u32 = @intCast(side);
    const side2 = side * side;
    const quadsf: f32 = @floatFromInt(quads);

    var vertices = std.ArrayList(Vertex).initCapacity(alloc, side2 * 6) catch oom();
    var indices = std.ArrayList(u32).initCapacity(alloc, quads * quads * 6 * 6) catch oom();

    for (0..6) |face| {
        const axes = faceAxes(face);

        for (0..side) |y| {
            for (0..side) |x| {
                // Maps value to [-1, 1]
                const xf = (@as(f32, @floatFromInt(x)) / quadsf) * 2 - 1;
                const yf = (@as(f32, @floatFromInt(y)) / quadsf) * 2 - 1;
                // Maps value to [-0.5, 0.5]
                const cube_pos = axes.n.add(axes.u.scale(xf)).add(axes.v.scale(yf));
                const pos = cubeToSphere(cube_pos);
                vertices.appendAssumeCapacity(
                    .{ .x = pos.x, .y = pos.y, .z = pos.z, .r = xf, .g = yf, .b = @as(f32, @floatFromInt(face)) / 6, .a = 1 },
                );
            }
        }

        const vbase = face * side2;

        for (0..quads) |y| {
            for (0..quads) |x| {
                const i: u32 = @intCast(vbase + y * side + x);
                indices.appendSliceAssumeCapacity(&.{
                    i,     i + 1,     i + s,
                    i + 1, i + s + 1, i + s,
                });
            }
        }
    }

    return .{
        .vertices = vertices.toOwnedSlice(alloc) catch oom(),
        .indices = indices.toOwnedSlice(alloc) catch oom(),
    };
}

fn cubeToSphere(p: m.Vec3) m.Vec3 {
    return p.normalize();
    // const x2 = p.x * p.x;
    // const y2 = p.y * p.y;
    // const z2 = p.z * p.z;
    //
    // return m.Vec3.new(
    //     p.x * @sqrt(1.0 - (y2 + z2) / 2.0 + (y2 * z2) / 3.0),
    //     p.y * @sqrt(1.0 - (x2 + z2) / 2.0 + (x2 * z2) / 3.0),
    //     p.z * @sqrt(1.0 - (x2 + y2) / 2.0 + (x2 * y2) / 3.0),
    // );
}

const Vertex = extern struct {
    x: f32,
    y: f32,
    z: f32,
    r: f32,
    g: f32,
    b: f32,
    a: f32,
};

const CamUniform = extern struct {
    mvp: m.Mat4,
    model: m.Mat4,
};

const QuadVertex = extern struct {
    x: f32,
    y: f32,
};

const QUAD_VERTICES = [_]QuadVertex{
    .{ .x = -1, .y = -1 },
    .{ .x = 1, .y = -1 },
    .{ .x = -1, .y = 1 },

    .{ .x = -1, .y = 1 },
    .{ .x = 1, .y = -1 },
    .{ .x = 1, .y = 1 },
};

const cube_sphere_vert_buf = [_]c.SDL_GPUVertexBufferDescription{.{
    .slot = 0,
    .input_rate = c.SDL_GPU_VERTEXINPUTRATE_VERTEX,
    .pitch = @sizeOf(Vertex),
    .instance_step_rate = 0,
}};
const cube_sphere_attrs = [_]c.SDL_GPUVertexAttribute{
    .{ .buffer_slot = 0, .location = 0, .format = c.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT3, .offset = 0 },
    .{ .buffer_slot = 0, .location = 1, .format = c.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT4, .offset = 3 * @sizeOf(f32) },
};

pub fn init(alloc: Allocator, device: *c.SDL_GPUDevice, tex_format: c.SDL_GPUTextureFormat, depth_format: c.SDL_GPUTextureFormat) Error!Self {
    const pipeline_fill = try gfx.Pipeline.create(alloc, device, "cube", .{
        .tex_format = tex_format,
        .depth_format = depth_format,
        .vert_buffers = &cube_sphere_vert_buf,
        .attrs = &cube_sphere_attrs,
    });
    errdefer c.SDL_ReleaseGPUGraphicsPipeline(device, pipeline_fill);

    const pipeline_line = try gfx.Pipeline.create(alloc, device, "cube", .{
        .tex_format = tex_format,
        .depth_format = depth_format,
        .fill_mode = c.SDL_GPU_FILLMODE_LINE,
        .vert_buffers = &cube_sphere_vert_buf,
        .attrs = &cube_sphere_attrs,
    });
    errdefer c.SDL_ReleaseGPUGraphicsPipeline(device, pipeline_line);

    const pipeline_points = try gfx.Pipeline.create(alloc, device, "points", .{
        .tex_format = tex_format,
        .depth_format = depth_format,
        .enable_depth = false,
        .vert_buffers = &.{
            .{ .slot = 0, .pitch = @sizeOf(QuadVertex), .input_rate = c.SDL_GPU_VERTEXINPUTRATE_VERTEX, .instance_step_rate = 0 },
            .{ .slot = 1, .pitch = @sizeOf(Vertex), .input_rate = c.SDL_GPU_VERTEXINPUTRATE_INSTANCE, .instance_step_rate = 0 },
        },
        .attrs = &.{
            .{ .buffer_slot = 0, .location = 0, .format = c.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT2, .offset = 0 },
            // TODO: could use location 0?
            .{ .buffer_slot = 1, .location = 1, .format = c.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT3, .offset = 0 },
        },
    });
    errdefer c.SDL_ReleaseGPUGraphicsPipeline(device, pipeline_points);

    const cube = makeCube(alloc, 50);

    // Vertices
    const vert_size: u32 = @intCast(@sizeOf(Vertex) * cube.vertices.len);
    const vert_buf = try gfx.Buffer.createVertBuf(device, vert_size);
    errdefer c.SDL_ReleaseGPUBuffer(device, vert_buf);

    // Indices
    const idx_size: u32 = @intCast(@sizeOf(u32) * cube.indices.len);
    const idx_buf = try gfx.Buffer.createVertBuf(device, idx_size);
    errdefer c.SDL_ReleaseGPUBuffer(device, idx_buf);

    // Points
    const quad_size: u32 = @sizeOf(@TypeOf(QUAD_VERTICES));
    const quad_buf = try gfx.Buffer.createVertBuf(device, quad_size);
    errdefer c.SDL_ReleaseGPUBuffer(device, quad_buf);

    // Transfert
    const trans_buf = try gfx.Buffer.createTransferBuf(device, vert_size + idx_size + quad_size);
    defer c.SDL_ReleaseGPUTransferBuffer(device, trans_buf);

    // Data mapping
    const data: [*]u8 = @ptrCast(@alignCast(
        try errify(c.SDL_MapGPUTransferBuffer(device, trans_buf, false)),
    ));

    @memcpy(data[0..vert_size], @as([*]const u8, @ptrCast(cube.vertices.ptr)));
    @memcpy(data[vert_size..][0..idx_size], @as([*]const u8, @ptrCast(cube.indices.ptr)));
    @memcpy(data[vert_size + idx_size ..][0..quad_size], std.mem.sliceAsBytes(&QUAD_VERTICES));
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

    c.SDL_UploadToGPUBuffer(
        copy_pass,
        &.{ .offset = vert_size + idx_size, .transfer_buffer = trans_buf },
        &.{ .offset = 0, .size = quad_size, .buffer = quad_buf },
        false,
    );

    c.SDL_EndGPUCopyPass(copy_pass);
    try errify(c.SDL_SubmitGPUCommandBuffer(cmd));

    return .{
        .vert_buf = vert_buf,
        .idx_buf = idx_buf,
        .quad_buf = quad_buf,
        .pipeline_fill = pipeline_fill,
        .pipeline_line = pipeline_line,
        .pipeline_points = pipeline_points,
        .cube = cube,
    };
}

const sens: f32 = 0.005; // radians per pixel
const damping: f32 = 4.0; // per second; higher stops sooner

fn rotate(self: *Self, rot_axis: m.Vec3) void {
    const angle = rot_axis.length();
    if (angle < 1e-6) return;
    const r = m.Mat4.createAngleAxis(rot_axis.normalize(), angle);
    self.orientation = self.orientation.mul(r);
}

fn update(s: *anyopaque, _: *c.SDL_GPUDevice, cmd: *c.SDL_GPUCommandBuffer, cam: *const Camera, state: Scene.State) Error!void {
    const self: *Self = @ptrCast(@alignCast(s));

    if (state.dragging) {
        if (state.mouse_mvt) |d| {
            // not -x because camera is looking from +Z to -Z
            const rot_axis = m.Vec3.new(d.y, d.x, 0).scale(sens);
            self.rotate(rot_axis);
            self.spin = rot_axis.scale(1.0 / state.dt);
        } else {
            self.spin = .zero;
        }
    } else {
        self.rotate(self.spin.scale(state.dt));
        self.spin = self.spin.scale(@exp(-damping * state.dt));
    }

    const cam_uniform: CamUniform = .{
        .mvp = self.orientation.mul(cam.view).mul(cam.proj),
        .model = self.orientation,
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
    }, c.SDL_GPU_INDEXELEMENTSIZE_32BIT);

    c.SDL_DrawGPUIndexedPrimitives(render_pass, @intCast(self.cube.indices.len), 1, 0, 0, 0);

    // Draw vertex markers
    c.SDL_BindGPUGraphicsPipeline(render_pass, self.pipeline_points);

    c.SDL_BindGPUVertexBuffers(
        render_pass,
        0,
        &[_]c.SDL_GPUBufferBinding{
            .{ .buffer = self.quad_buf, .offset = 0 },
            .{ .buffer = self.vert_buf, .offset = 0 },
        },
        2,
    );

    c.SDL_DrawGPUPrimitives(render_pass, 6, @intCast(self.cube.vertices.len), 0, 0);
}

fn deinit(s: *anyopaque, alloc: Allocator, device: *c.SDL_GPUDevice) void {
    const self: *Self = @ptrCast(@alignCast(s));

    c.SDL_ReleaseGPUBuffer(device, self.vert_buf);
    c.SDL_ReleaseGPUBuffer(device, self.idx_buf);
    c.SDL_ReleaseGPUBuffer(device, self.quad_buf);
    c.SDL_ReleaseGPUGraphicsPipeline(device, self.pipeline_fill);
    c.SDL_ReleaseGPUGraphicsPipeline(device, self.pipeline_line);
    c.SDL_ReleaseGPUGraphicsPipeline(device, self.pipeline_points);

    alloc.free(self.cube.vertices);
    alloc.free(self.cube.indices);
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
