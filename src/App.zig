const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const c = @import("c");
const m = @import("math");
const utils = @import("utils.zig");
const errify = utils.errify;
const Error = utils.Error;
const Renderer = @import("Renderer.zig");
const Camera = @import("Camera.zig");
const Scene = @import("Scene.zig");

ctx: Context,
window: *c.SDL_Window,
renderer: Renderer,
camera: Camera,
running: bool = true,
ui_wants_mouse: bool = false,

const Self = @This();

pub const INIT_WIN_WIDTH = 1280;
pub const INIT_WIN_HEIGHT = 720;

pub const Config = struct {
    scene: SceneName,

    pub const SceneName = enum {
        triangle,
        triangle_dyn,
        cube,
        cube_sphere,
    };
};

pub const Context = struct {
    alloc: Allocator,
    scene_state: Scene.State,
};

pub fn init(alloc: Allocator, config: Config) Error!Self {
    try errify(c.SDL_Init(c.SDL_INIT_VIDEO | c.SDL_INIT_AUDIO));

    const ctx: Context = .{
        .alloc = alloc,
        .scene_state = .{},
    };

    const window = try errify(c.SDL_CreateWindow(
        "Geocrafter",
        INIT_WIN_WIDTH,
        INIT_WIN_HEIGHT,
        c.SDL_WINDOW_RESIZABLE,
    ));
    errdefer c.SDL_DestroyWindow(window);

    const renderer = try Renderer.init(window, config, &ctx);

    return .{
        .ctx = ctx,
        .window = window,
        .renderer = renderer,
        .camera = .init(INIT_WIN_WIDTH, INIT_WIN_HEIGHT),
    };
}

pub fn deinit(self: *Self) void {
    self.renderer.deinit(self.ctx);
    c.SDL_DestroyWindow(self.window);
}

pub fn run(self: *Self) Error!void {
    var frames: usize = 0;
    var last_time = c.SDL_GetTicksNS();

    while (self.running) {
        const cur_time = c.SDL_GetTicksNS();
        const dt = cur_time - last_time;

        if (builtin.mode == .debug) {
            frames += 1;
            if (dt >= 1_000_000) {
                var buf: [100]u8 = undefined;
                const written = std.fmt.bufPrintSentinel(&buf, "Geocrafter - FPS {}", .{frames}, 0) catch utils.oom();
                try errify(c.SDL_SetWindowTitle(self.window, written));
                last_time = cur_time;
                frames = 0;
            }
        }

        try self.frame(@floatCast(@as(f64, @floatFromInt(dt)) / 1e9));
    }
}

fn handleEvents(self: *Self) void {
    var event: c.SDL_Event = undefined;
    while (c.SDL_PollEvent(&event)) {
        // First: ImGui_ImplSDL3_ProcessEvent(&event)
        switch (event.type) {
            c.SDL_EVENT_QUIT => self.running = false,
            c.SDL_EVENT_MOUSE_MOTION => {
                if (event.button.button == c.SDL_BUTTON_MIDDLE) {
                    self.ctx.scene_state.dragging = true;
                }

                if ((event.motion.state & c.SDL_BUTTON_MMASK) != 0) {
                    const mvt = m.Vec2.new(event.motion.xrel, event.motion.yrel);
                    const state = &self.ctx.scene_state;
                    state.mouse_mvt = if (state.mouse_mvt) |d| d.add(mvt) else mvt;
                }
            },
            c.SDL_EVENT_MOUSE_BUTTON_UP => {
                if (event.button.button == c.SDL_BUTTON_MIDDLE) {
                    self.ctx.scene_state.dragging = false;
                }
            },
            c.SDL_EVENT_KEY_DOWN => switch (event.key.key) {
                c.SDLK_Q, c.SDLK_ESCAPE => self.running = false,
                c.SDLK_W => self.ctx.scene_state.wireframe = !self.ctx.scene_state.wireframe,
                else => {},
            },
            c.SDL_EVENT_MOUSE_WHEEL => {
                self.camera.zoom(event.wheel.y);
                // if (!self.ui_wants_mouse) self.camera.zoom(ev.wheel.y, self.planet.params.radius);
            },
            else => {},
        }
    }
}

fn drawUi(self: *Self) void {
    // ImGui panels live in their own file. They only mutate params and set flags:
    //
    //   if (zgui.sliderFloat("Amplitude", .{ .v = &p.amplitude, .min = 0, .max = 0.3 }))
    //       self.planet.dirty.heightmap = true;
    //
    // self.ui_wants_mouse = imgui_io.WantCaptureMouse;
    _ = self;
}

pub fn frame(self: *Self, dt: f32) Error!void {
    self.ctx.scene_state.dt = dt;
    self.ctx.scene_state.mouse_mvt = null;
    self.handleEvents();
    self.drawUi();
    // if (self.planet.dirty.any()) self.planet.regenerate(&self.renderer);
    try self.renderer.drawFrame(&self.camera, self.ctx);
}
