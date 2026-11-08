const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const c = @import("c");
const dvui = @import("dvui");
const SDLBackend = @import("sdl3gpu-backend");
const utils = @import("utils.zig");
const Error = utils.UiError;
const oom = utils.oom;

io: Io,
win: dvui.Window,
backend: SDLBackend,

const Self = @This();
const log = std.log.scoped(.ui);

pub fn create(io: Io, alloc: Allocator, window: *c.SDL_Window, device: *c.SDL_GPUDevice) Error!*Self {
    const self = alloc.create(Self) catch utils.oom();
    errdefer alloc.destroy(self);

    self.io = io;
    self.backend = SDLBackend.init(io, @ptrCast(window), @ptrCast(device), alloc);
    errdefer self.backend.deinit();

    self.win = dvui.Window.init(@src(), alloc, self.backend.backend(), .{}) catch |e| {
        log.err("Self init failed: {s}", .{@errorName(e)});
        return error.UiInit;
    };

    return self;
}

pub fn destroy(self: *Self, alloc: Allocator) void {
    self.win.deinit();
    self.backend.deinit();
    alloc.destroy(self);
}

pub fn beginFrame(self: *Self, cmd: *c.SDL_GPUCommandBuffer, swapchain: *c.SDL_GPUTexture) Error!void {
    self.backend.cmd = @ptrCast(cmd);
    self.backend.swapchain_texture = @ptrCast(swapchain);

    const now = std.Io.Clock.boot.now(self.io);

    self.win.begin(now.nanoseconds) catch |e| {
        log.err("Ui begin frame failed: {s}", .{@errorName(e)});
        return error.UiFrame;
    };
}

/// Returns true if dvui consumed the event
pub fn handleEvent(self: *Self, ev: c.SDL_Event) bool {
    const dvui_ev: *const SDLBackend.c.SDL_Event = @ptrCast(&ev);

    return self.backend.addEvent(&self.win, dvui_ev.*) catch |e| {
        log.warn("Ui handle event failed: {s}", .{@errorName(e)});
        return false;
    };
}

/// Draws the ui on top of the swapchain texture
/// Call after passes are closed and before submitting the command buffer
pub fn endFrame(self: *Self) Error!void {
    _ = self.win.end(.{ .manage_backend = false }) catch |e| {
        log.err("Ui end frame failed: {s}", .{@errorName(e)});
        return error.UiFrame;
    };

    if (self.win.cursorRequestedFloating()) |cursor| {
        // cursor is over a dvui window: dvui decides
        self.backend.setCursor(cursor);
    } else {
        // the app owns the cursor here (the dvui example uses .bad as a marker)
        self.backend.setCursor(.arrow);
    }
    self.backend.textInputRect(self.win.textInputRequested());
    self.backend.renderPresent();

    self.backend.cmd = null;
    self.backend.swapchain_texture = null;
}
