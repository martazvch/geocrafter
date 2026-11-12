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
const dvui = @import("dvui");
const Plane = @import("../geom/Plane.zig");
const Vertex = @import("../geom/vertex.zig").Vertex;
const Mesh = @import("../gfx/mesh.zig").Mesh;
const PlaneMesh = Mesh(Vertex);

alloc: Allocator,
pipelines: gfx.pipeline.Pipelines,
mesh: PlaneMesh,
uniform: Uniform,

orientation: m.Mat4 = .createAngleAxis(.unitX, m.d2r(90)),
spin: m.Vec3 = .zero,

const Self = @This();

const Uniform = extern struct {
    mvp: m.Mat4 = .zero,
};
comptime {
    std.debug.assert(@sizeOf(Uniform) % 16 == 0);
}

pub fn init(alloc: Allocator, device: *c.SDL_GPUDevice, tex_format: c.SDL_GPUTextureFormat, depth_format: c.SDL_GPUTextureFormat) Error!Self {
    var pipelines = try gfx.pipeline.Pipelines.init(alloc, device, "plane", .{
        .tex_format = tex_format,
        .depth_format = depth_format,
        .cull_mode = c.SDL_GPU_CULLMODE_NONE,
        .vert_buffers = &.{
            .{ .pitch = @sizeOf(Vertex), .slot = 0, .input_rate = c.SDL_GPU_VERTEXINPUTRATE_VERTEX, .instance_step_rate = 0 },
        },
        .attrs = &.{
            .{ .buffer_slot = 0, .location = 0, .format = c.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT3, .offset = 0 },
            .{ .buffer_slot = 0, .location = 1, .format = c.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT4, .offset = 3 * @sizeOf(f32) },
        },
    });
    errdefer pipelines.deinit(device);

    var plane = Plane.init(alloc, 1);
    defer plane.deinit(alloc);

    const cmd = try errify(c.SDL_AcquireGPUCommandBuffer(device));
    const mesh = try PlaneMesh.create(device, cmd, plane.vertices, plane.indices);
    errdefer mesh.deinit(device);
    try errify(c.SDL_SubmitGPUCommandBuffer(cmd));

    return .{
        .alloc = alloc,
        .pipelines = pipelines,
        .mesh = mesh,
        .uniform = .{},
    };
}

fn rotate(self: *Self, rot_axis: m.Vec3) void {
    const angle = rot_axis.length();
    if (angle < 1e-6) return;
    const r = m.Mat4.createAngleAxis(rot_axis.normalize(), angle);
    self.orientation = self.orientation.mul(r);
}

fn update(s: *anyopaque, _: *c.SDL_GPUDevice, _: *c.SDL_GPUCommandBuffer, cam: *const Camera, state: Scene.State) Error!void {
    const self: *Self = @ptrCast(@alignCast(s));

    self.uniform = .{
        .mvp = state.arcball.rotation.toMat4().mul(cam.view).mul(cam.proj),
    };
}

fn draw(s: *anyopaque, render_pass: *c.SDL_GPURenderPass, cmd: *c.SDL_GPUCommandBuffer, config: Scene.State) Error!void {
    const self: *Self = @ptrCast(@alignCast(s));

    if (config.wireframe) {
        c.SDL_BindGPUGraphicsPipeline(render_pass, self.pipelines.line);
    } else {
        c.SDL_BindGPUGraphicsPipeline(render_pass, self.pipelines.fill);
    }

    c.SDL_PushGPUVertexUniformData(cmd, 0, &self.uniform, @sizeOf(Uniform));

    self.mesh.draw(render_pass);
}

fn drawUi(_: *anyopaque) void {}

fn deinit(s: *anyopaque, alloc: Allocator, device: *c.SDL_GPUDevice) void {
    const self: *Self = @ptrCast(@alignCast(s));

    self.mesh.deinit(device);
    self.pipelines.deinit(device);
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
