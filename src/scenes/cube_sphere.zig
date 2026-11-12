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
const Cube = @import("../geom/CubeSphere.zig");
const Mesh = @import("../gfx/Mesh.zig").Mesh;
const Markers = @import("../gfx/Markers.zig");
const Vertex = @import("../geom/vertex.zig").Vertex;

alloc: Allocator,
pipeline_fill: *c.SDL_GPUGraphicsPipeline,
pipeline_line: *c.SDL_GPUGraphicsPipeline,
markers: Markers,
mesh: CubeMesh,
orientation: m.Mat4 = .identity,
spin: m.Vec3 = .zero,
uniforms: Uniform = .{},

// UI
dirty: bool = false,
better_spacing: bool = false,
show_points: bool = false,
cube_sphere_quads: usize = QUADS_PER_FACE,

const Self = @This();
const CubeMesh = Mesh(Vertex);
const QUADS_PER_FACE = 50;

const Uniform = extern struct {
    mvp: m.Mat4 = .zero,
    model: m.Mat4 = .zero,
    /// x = aspect, y = marker radius (NDC), z = depth bias
    marker: [4]f32 = @splat(0),
};
comptime {
    std.debug.assert(@sizeOf(Uniform) % 16 == 0);
}

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

fn buildMesh(
    alloc: Allocator,
    device: *c.SDL_GPUDevice,
    cmd: *c.SDL_GPUCommandBuffer,
    quads: usize,
    better_spacing: bool,
) Error!CubeMesh {
    var cube = Cube.init(alloc, quads, better_spacing);
    defer cube.deinit(alloc);
    return CubeMesh.create(device, cmd, cube.vertices, cube.indices);
}

fn rebuildMesh(self: *Self, device: *c.SDL_GPUDevice, cmd: *c.SDL_GPUCommandBuffer) Error!void {
    const new_mesh = try buildMesh(self.alloc, device, cmd, self.cube_sphere_quads, self.better_spacing);
    self.mesh.deinit(device);
    self.mesh = new_mesh;
}

pub fn init(alloc: Allocator, device: *c.SDL_GPUDevice, tex_format: c.SDL_GPUTextureFormat, depth_format: c.SDL_GPUTextureFormat) Error!Self {
    const pipeline_fill = try gfx.pipeline.create(alloc, device, "cube", .{
        .tex_format = tex_format,
        .depth_format = depth_format,
        .vert_buffers = &cube_sphere_vert_buf,
        .attrs = &cube_sphere_attrs,
    });
    errdefer c.SDL_ReleaseGPUGraphicsPipeline(device, pipeline_fill);

    const pipeline_line = try gfx.pipeline.create(alloc, device, "cube", .{
        .tex_format = tex_format,
        .depth_format = depth_format,
        .fill_mode = c.SDL_GPU_FILLMODE_LINE,
        .vert_buffers = &cube_sphere_vert_buf,
        .attrs = &cube_sphere_attrs,
        .cull_mode = c.SDL_GPU_CULLMODE_NONE,
    });
    errdefer c.SDL_ReleaseGPUGraphicsPipeline(device, pipeline_line);

    // Copy
    const cmd = try errify(c.SDL_AcquireGPUCommandBuffer(device));

    const markers = try Markers.init(alloc, device, cmd, tex_format, depth_format, Vertex, @offsetOf(Vertex, "x"));
    errdefer markers.deinit(device);

    const mesh = try buildMesh(alloc, device, cmd, QUADS_PER_FACE, false);
    errdefer mesh.deinit(device);

    try errify(c.SDL_SubmitGPUCommandBuffer(cmd));

    return .{
        .alloc = alloc,
        .pipeline_fill = pipeline_fill,
        .pipeline_line = pipeline_line,
        .markers = markers,
        .mesh = mesh,
    };
}

fn update(s: *anyopaque, device: *c.SDL_GPUDevice, cmd: *c.SDL_GPUCommandBuffer, cam: *const Camera, state: Scene.State) Error!void {
    const self: *Self = @ptrCast(@alignCast(s));

    if (self.dirty) {
        self.dirty = false;
        try self.rebuildMesh(device, cmd);
    }

    self.uniforms = .{
        .mvp = state.arcball.rotation.toMat4().mul(cam.view).mul(cam.proj),
        .model = self.orientation,
        .marker = .{ cam.aspect, 0.008, 0.0005, 0 },
    };
}

fn draw(s: *anyopaque, render_pass: *c.SDL_GPURenderPass, cmd: *c.SDL_GPUCommandBuffer, config: Scene.State) Error!void {
    const self: *Self = @ptrCast(@alignCast(s));

    if (config.wireframe) {
        c.SDL_BindGPUGraphicsPipeline(render_pass, self.pipeline_line);
    } else {
        c.SDL_BindGPUGraphicsPipeline(render_pass, self.pipeline_fill);
    }

    c.SDL_PushGPUVertexUniformData(cmd, 0, &self.uniforms, @sizeOf(Uniform));
    self.mesh.draw(render_pass);

    // Binds its own pipeline
    if (self.show_points) {
        self.markers.draw(render_pass, self.mesh.vertex, self.mesh.vertex_count);
    }
}

fn drawUi(s: *anyopaque) void {
    const self: *Self = @ptrCast(@alignCast(s));

    var float = dvui.floatingWindow(@src(), .{}, .{ .max_size_content = .{ .w = 400, .h = 400 } });
    defer float.deinit();

    float.dragAreaSet(dvui.windowHeader(.{ .title = "Floating Window" }));

    var scroll = dvui.scrollArea(@src(), .{}, .{ .expand = .both });
    defer scroll.deinit();

    if (dvui.checkbox(@src(), &self.better_spacing, "better spacing", .{})) {
        self.dirty = true;
    }

    if (dvui.checkbox(@src(), &self.show_points, "show points", .{})) {}
}

fn deinit(s: *anyopaque, alloc: Allocator, device: *c.SDL_GPUDevice) void {
    const self: *Self = @ptrCast(@alignCast(s));

    self.mesh.deinit(device);
    self.markers.deinit(device);
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
