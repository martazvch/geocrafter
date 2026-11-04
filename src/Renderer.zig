const std = @import("std");
const builtin = @import("builtin");
const c = @import("c");
const utils = @import("utils.zig");
const errify = utils.errify;
const Error = utils.Error;
const App = @import("App.zig");
const Scene = @import("Scene.zig");
const Camera = @import("Camera.zig");

device: *c.SDL_GPUDevice,
window: *c.SDL_Window,
scene: Scene,
depth_tex: *c.SDL_GPUTexture,
depth_w: u32 = 0,
depth_h: u32 = 0,

const Self = @This();
pub const DEPTH_FORMAT = c.SDL_GPU_TEXTUREFORMAT_D32_FLOAT;

pub fn init(window: *c.SDL_Window, config: App.Config, ctx: *const App.Context) Error!Self {
    const formats = c.SDL_GPU_SHADERFORMAT_SPIRV | c.SDL_GPU_SHADERFORMAT_DXIL | c.SDL_GPU_SHADERFORMAT_MSL;
    // null lets SDL to handle automatically for us
    const device = try errify(c.SDL_CreateGPUDevice(formats, builtin.mode == .debug, null));
    errdefer c.SDL_DestroyGPUDevice(device);

    try errify(c.SDL_ClaimWindowForGPUDevice(device, window));
    const tex_format = c.SDL_GetGPUSwapchainTextureFormat(device, window);

    const scene = scene: switch (config.scene) {
        .triangle => {
            var tri = try @import("scenes/triangle.zig").init(ctx.alloc, device, tex_format, DEPTH_FORMAT);
            break :scene tri.scene();
        },
        .triangle_dyn => {
            var tri = try @import("scenes/triangle_dyn.zig").init(ctx.alloc, device, tex_format, DEPTH_FORMAT);
            break :scene tri.scene();
        },
        .cube => {
            var tri = try @import("scenes/cube.zig").init(ctx.alloc, device, tex_format, DEPTH_FORMAT);
            break :scene tri.scene();
        },
    };

    const depth_tex = try errify(c.SDL_CreateGPUTexture(device, &.{
        .type = c.SDL_GPU_TEXTURETYPE_2D,
        .format = DEPTH_FORMAT,
        .usage = c.SDL_GPU_TEXTUREUSAGE_DEPTH_STENCIL_TARGET,
        .width = App.INIT_WIN_WIDTH,
        .height = App.INIT_WIN_HEIGHT,
        .layer_count_or_depth = 1,
        .num_levels = 1,
        .sample_count = c.SDL_GPU_SAMPLECOUNT_1,
        .props = 0,
    }));

    return .{
        .device = device,
        .window = window,
        .scene = scene,
        .depth_tex = depth_tex,
    };
}

pub fn deinit(self: *Self, ctx: App.Context) void {
    _ = c.SDL_WaitForGPUIdle(self.device);
    self.scene.deinit(ctx.alloc, self.device);
    c.SDL_ReleaseGPUTexture(self.device, self.depth_tex);
    c.SDL_ReleaseWindowFromGPUDevice(self.device, self.window);
    c.SDL_DestroyGPUDevice(self.device);
}

pub fn drawFrame(self: *Self, cam: *Camera, ctx: App.Context) Error!void {
    const cmd = try errify(c.SDL_AcquireGPUCommandBuffer(self.device));

    var swapchain: ?*c.SDL_GPUTexture = null;
    var width: u32, var height: u32 = .{ 0, 0 };
    try errify(c.SDL_WaitAndAcquireGPUSwapchainTexture(cmd, self.window, &swapchain, &width, &height));

    if (swapchain) |tex| {
        try self.ensureDepth(width, height, cam);

        var target = std.mem.zeroes(c.SDL_GPUColorTargetInfo);
        target.texture = tex;
        target.clear_color = .{ .r = 0.02, .g = 0.02, .b = 0.05, .a = 1.0 };
        target.load_op = c.SDL_GPU_LOADOP_CLEAR;
        target.store_op = c.SDL_GPU_STOREOP_STORE;

        try self.scene.update(self.device, cmd, cam);

        var depth = std.mem.zeroes(c.SDL_GPUDepthStencilTargetInfo);
        depth.texture = self.depth_tex;
        // matches compare_op = LESS, with 1 being the far plane in the 0..1 range
        depth.clear_depth = 1.0;
        depth.load_op = c.SDL_GPU_LOADOP_CLEAR;
        depth.store_op = c.SDL_GPU_STOREOP_DONT_CARE;
        depth.stencil_load_op = c.SDL_GPU_LOADOP_DONT_CARE;
        depth.stencil_store_op = c.SDL_GPU_STOREOP_DONT_CARE;
        depth.cycle = true;

        const pass = try errify(c.SDL_BeginGPURenderPass(cmd, &target, 1, &depth));
        try self.scene.draw(pass, ctx.draw_config);
        c.SDL_EndGPURenderPass(pass);
    }

    // Submit even if swapchain texture is null
    try errify(c.SDL_SubmitGPUCommandBuffer(cmd));
}

fn ensureDepth(self: *Self, w: u32, h: u32, cam: *Camera) Error!void {
    if (self.depth_w == w and self.depth_h == h) return;

    cam.resize(w, h);
    // Created before first call to this function
    c.SDL_ReleaseGPUTexture(self.device, self.depth_tex);

    self.depth_tex = try errify(c.SDL_CreateGPUTexture(self.device, &.{
        .type = c.SDL_GPU_TEXTURETYPE_2D,
        .format = DEPTH_FORMAT,
        .usage = c.SDL_GPU_TEXTUREUSAGE_DEPTH_STENCIL_TARGET,
        .width = w,
        .height = h,
        .layer_count_or_depth = 1,
        .num_levels = 1,
        .sample_count = c.SDL_GPU_SAMPLECOUNT_1,
        .props = 0,
    }));
    self.depth_w = w;
    self.depth_h = h;
}
