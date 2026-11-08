const Allocator = @import("std").mem.Allocator;
const c = @import("c");
const App = @import("App.zig");
const Error = @import("utils.zig").Error;
const Camera = @import("Camera.zig");
const m = @import("math");

ptr: *anyopaque,
vtable: *const VTable,

const Self = @This();
pub const VTable = struct {
    update: *const fn (*anyopaque, *c.SDL_GPUDevice, *c.SDL_GPUCommandBuffer, *const Camera, State) Error!void,
    draw: *const fn (*anyopaque, *c.SDL_GPURenderPass, State) Error!void,
    deinit: *const fn (*anyopaque, Allocator, *c.SDL_GPUDevice) void,
};

pub const State = struct {
    dt: f32 = 0,
    wireframe: bool = false,
    mouse_mvt: ?m.Vec2 = null,
    dragging: bool = false,
};

pub fn update(self: *Self, device: *c.SDL_GPUDevice, cmd: *c.SDL_GPUCommandBuffer, cam: *const Camera, state: State) Error!void {
    try self.vtable.update(self.ptr, device, cmd, cam, state);
}

pub fn draw(self: *Self, renderPass: *c.SDL_GPURenderPass, config: State) Error!void {
    try self.vtable.draw(self.ptr, renderPass, config);
}

pub fn deinit(self: *Self, alloc: Allocator, device: *c.SDL_GPUDevice) void {
    self.vtable.deinit(self.ptr, alloc, device);
}
