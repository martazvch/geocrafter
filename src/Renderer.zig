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
color_format: c.SDL_GPUTextureFormat,
depth_tex: ?*c.SDL_GPUTexture = null,
depth_w: u32 = 0,
depth_h: u32 = 0,

const Self = @This();
pub const DEPTH_FORMAT = c.SDL_GPU_TEXTUREFORMAT_D32_FLOAT;

pub const Frame = struct {
    cmd: *c.SDL_GPUCommandBuffer,
    swapchain: ?*c.SDL_GPUTexture,
    width: u32,
    height: u32,
    resized: bool,
};

pub fn init(window: *c.SDL_Window) Error!Self {
    const formats = c.SDL_GPU_SHADERFORMAT_SPIRV | c.SDL_GPU_SHADERFORMAT_DXIL | c.SDL_GPU_SHADERFORMAT_MSL;
    // null lets SDL to handle automatically for us
    const device = try errify(c.SDL_CreateGPUDevice(formats, builtin.mode == .debug, null));
    errdefer c.SDL_DestroyGPUDevice(device);

    try errify(c.SDL_ClaimWindowForGPUDevice(device, window));

    return .{
        .device = device,
        .window = window,
        .color_format = c.SDL_GetGPUSwapchainTextureFormat(device, window),
    };
}

/// Call before destroying anything that owns GPU resources
pub fn waitIdle(self: *Self) void {
    _ = c.SDL_WaitForGPUIdle(self.device);
}

/// Call after scene and Ui have been destroyed
pub fn deinit(self: *Self) void {
    if (self.depth_tex) |tex| {
        c.SDL_ReleaseGPUTexture(self.device, tex);
    }

    c.SDL_ReleaseWindowFromGPUDevice(self.device, self.window);
    c.SDL_DestroyGPUDevice(self.device);
}

/// Acquires the command buffer and the swapchain texture.
pub fn beginFrame(self: *Self) Error!Frame {
    const cmd = try errify(c.SDL_AcquireGPUCommandBuffer(self.device));

    var swapchain: ?*c.SDL_GPUTexture = null;
    var width: u32, var height: u32 = .{ 0, 0 };
    const acquired = c.SDL_WaitAndAcquireGPUSwapchainTexture(cmd, self.window, &swapchain, &width, &height);

    // Cancelling is only legal before a swapchain texture was acquired.
    if (!acquired) _ = c.SDL_CancelGPUCommandBuffer(cmd);
    try errify(acquired);

    // From here on the command buffer must be submitted, even on error.
    errdefer _ = c.SDL_SubmitGPUCommandBuffer(cmd);

    var resized = false;
    if (swapchain != null) {
        resized = try self.ensureDepth(width, height);
    }

    return .{
        .cmd = cmd,
        .swapchain = swapchain,
        .width = width,
        .height = height,
        .resized = resized,
    };
}

/// Submits the command buffer, which also presents the swapchain texture.
pub fn endFrame(_: *Self, frame: Frame) Error!void {
    try errify(c.SDL_SubmitGPUCommandBuffer(frame.cmd));
}

/// Scene preparation (copy/compute passes) followed by the main render pass
/// Must be called with no pass open and before the ui draws
pub fn renderScene(
    self: *Self,
    frame: Frame,
    scene: *Scene,
    cam: *Camera,
    state: Scene.State,
) Error!void {
    const tex = frame.swapchain orelse return;

    // Scene update before any pass
    try scene.update(self.device, frame.cmd, cam, state);

    var target = std.mem.zeroes(c.SDL_GPUColorTargetInfo);
    target.texture = tex;
    target.clear_color = .{ .r = 0.02, .g = 0.02, .b = 0.05, .a = 1.0 };
    target.load_op = c.SDL_GPU_LOADOP_CLEAR;
    target.store_op = c.SDL_GPU_STOREOP_STORE;

    var depth = std.mem.zeroes(c.SDL_GPUDepthStencilTargetInfo);
    depth.texture = self.depth_tex.?;
    // matches compare_op = LESS, with 1 being the far plane in the 0..1 range
    depth.clear_depth = 1.0;
    depth.load_op = c.SDL_GPU_LOADOP_CLEAR;
    depth.store_op = c.SDL_GPU_STOREOP_DONT_CARE;
    depth.stencil_load_op = c.SDL_GPU_LOADOP_DONT_CARE;
    depth.stencil_store_op = c.SDL_GPU_STOREOP_DONT_CARE;
    depth.cycle = true;

    const pass = try errify(c.SDL_BeginGPURenderPass(frame.cmd, &target, 1, &depth));
    // defer to ensure end of pass even if scene draw fails
    defer c.SDL_EndGPURenderPass(pass);
    try scene.draw(pass, frame.cmd, state);
}

fn ensureDepth(self: *Self, w: u32, h: u32) Error!bool {
    if (self.depth_w == w and self.depth_h == h) {
        return false;
    }

    if (self.depth_tex) |old| {
        c.SDL_ReleaseGPUTexture(self.device, old);
    }

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

    return true;
}
