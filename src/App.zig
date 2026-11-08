const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const c = @import("c");
const m = @import("math");
const utils = @import("utils.zig");
const errify = utils.errify;
const Error = utils.Error;
const Renderer = @import("Renderer.zig");
const Camera = @import("Camera.zig");
const Scene = @import("Scene.zig");
const scenes = @import("scenes.zig");
const Ui = @import("Ui.zig");

io: Io,
alloc: Allocator,
window: *c.SDL_Window,
renderer: Renderer,
ui: *Ui,
scene: Scene,
scene_state: Scene.State = .{},
camera: Camera,
running: bool = true,

const Self = @This();

pub const INIT_WIN_WIDTH = 1280;
pub const INIT_WIN_HEIGHT = 720;

pub const Config = struct {
    scene: scenes.Name,
};

pub fn init(io: Io, alloc: Allocator, config: Config) Error!Self {
    try errify(c.SDL_Init(c.SDL_INIT_VIDEO | c.SDL_INIT_AUDIO));

    const window = try errify(c.SDL_CreateWindow(
        "Geocrafter",
        INIT_WIN_WIDTH,
        INIT_WIN_HEIGHT,
        c.SDL_WINDOW_RESIZABLE,
    ));
    errdefer c.SDL_DestroyWindow(window);

    const renderer = try Renderer.init(window);

    var scene = try scenes.create(alloc, config.scene, renderer.device, renderer.color_format, Renderer.DEPTH_FORMAT);
    errdefer scene.deinit(alloc, renderer.device);

    const ui = try Ui.create(io, alloc, window, renderer.device);
    errdefer ui.destroy(alloc);

    return .{
        .io = io,
        .alloc = alloc,
        .window = window,
        .renderer = renderer,
        .ui = ui,
        .scene = scene,
        .camera = .init(INIT_WIN_WIDTH, INIT_WIN_HEIGHT),
    };
}

pub fn deinit(self: *Self) void {
    self.renderer.waitIdle();
    self.ui.destroy(self.alloc);
    self.scene.deinit(self.alloc, self.renderer.device);
    self.renderer.deinit();
    c.SDL_DestroyWindow(self.window);
}

pub fn run(self: *Self) Error!void {
    var acc: u64 = 0;
    var frames: u32 = 0;
    var last = c.SDL_GetTicksNS();

    while (self.running) {
        const now = c.SDL_GetTicksNS();
        const dt = now - last;
        last = now;

        if (builtin.mode == .debug) {
            acc += dt;
            frames += 1;

            if (acc >= std.time.ns_per_s) {
                var buf: [64]u8 = undefined;
                const written = std.fmt.bufPrintSentinel(&buf, "Geocrafter - FPS {}", .{frames}, 0) catch utils.oom();
                try errify(c.SDL_SetWindowTitle(self.window, written));

                acc = 0;
                frames = 0;
            }
        }

        try self.frame(@floatCast(@as(f64, @floatFromInt(dt)) / 1e9));
    }
}

pub fn frame(self: *Self, dt: f32) Error!void {
    self.scene_state.dt = dt;
    self.scene_state.mouse_mvt = null;

    const f = try self.renderer.beginFrame();
    if (f.resized) {
        self.camera.resize(f.width, f.height);
    }

    // Minimized window: no swapchain texture, so no drawing and no dvui frame
    // but events must still be processed (restore, quit...)
    const swapchain = f.swapchain orelse {
        self.handleEvents(false);
        try self.renderer.endFrame(f);
        return;
    };

    try self.ui.beginFrame(f.cmd, swapchain);
    self.handleEvents(true);

    try self.renderer.renderScene(f, &self.scene, &self.camera, self.scene_state);

    try self.ui.endFrame();
    try self.renderer.endFrame(f);
}

fn handleEvents(self: *Self, ui_active: bool) void {
    var ev: c.SDL_Event = undefined;
    while (c.SDL_PollEvent(&ev)) {
        // Always handled by the app, never offered to dvui.
        if (ev.type == c.SDL_EVENT_QUIT) {
            self.running = false;
            continue;
        }

        // A button release must always reach app, even if dvui consumes it too
        // otherwise a drag could get stuck for example
        if (ev.type == c.SDL_EVENT_MOUSE_BUTTON_UP and ev.button.button == c.SDL_BUTTON_MIDDLE) {
            self.scene_state.dragging = false;
        }

        // dvui first, it returns true when the event belongs to a floating window
        if (ui_active and self.ui.handleEvent(ev)) {
            continue;
        }

        switch (ev.type) {
            c.SDL_EVENT_MOUSE_BUTTON_DOWN => {
                if (ev.button.button == c.SDL_BUTTON_MIDDLE) {
                    self.scene_state.dragging = true;
                }
            },
            c.SDL_EVENT_MOUSE_MOTION => {
                if ((ev.motion.state & c.SDL_BUTTON_MMASK) != 0) {
                    const mvt = m.Vec2.new(ev.motion.xrel, ev.motion.yrel);
                    const state = &self.scene_state;
                    state.mouse_mvt = if (state.mouse_mvt) |d| d.add(mvt) else mvt;
                }
            },
            c.SDL_EVENT_MOUSE_WHEEL => self.camera.zoom(ev.wheel.y),
            c.SDL_EVENT_KEY_DOWN => switch (ev.key.key) {
                c.SDLK_Q, c.SDLK_ESCAPE => self.running = false,
                c.SDLK_W => self.scene_state.wireframe = !self.scene_state.wireframe,
                else => {},
            },
            else => {},
        }
    }
}
