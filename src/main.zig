const std = @import("std");
const builtin = @import("builtin");
const Io = std.Io;
const c = @import("c");
const utils = @import("utils.zig");
const errify = utils.errify;
const App = @import("App.zig");
const clarg = @import("clarg");
const Arg = clarg.Arg;

const CliArgs = struct {
    scene: Arg(App.Config.SceneName.triangle) = .{ .desc = "run specific scene", .short = 's' },

    const Scene = enum {
        triangle,
        triangle_dyn,
    };
};

const sdl_log = std.log.scoped(.sdl);
var debug_alloc: std.heap.DebugAllocator(.{}) = .init;

pub fn main(init: std.process.Init) !void {
    const alloc, const is_debug = gpa: {
        break :gpa switch (builtin.mode) {
            .Debug, .ReleaseSafe => .{ debug_alloc.allocator(), true },
            .ReleaseFast, .ReleaseSmall => .{ std.heap.smp_allocator, false },
        };
    };
    defer if (is_debug) {
        std.debug.assert(debug_alloc.deinit() == .ok);
    };

    const args = try init.minimal.args.toSlice(init.arena.allocator());

    var diag: clarg.Diag = .empty;
    const parsed = clarg.parse(CliArgs, args, &diag, .{}) catch |e| {
        try diag.reportToFile(init.io, .stderr());
        return e;
    };

    if (parsed.help) {
        return clarg.helpToFile(CliArgs, init.io, .stderr());
    }

    const config: App.Config = .{
        .scene = parsed.scene,
    };

    var app = App.init(alloc, config) catch |err| switch (err) {
        error.AppError => {
            std.log.err("Interal error", .{});
            return err;
        },
        error.SdlError => {
            std.log.err("SDL error: ‘{s}'", .{c.SDL_GetError()});
            return err;
        },
    };
    defer app.deinit();

    app.run() catch |err| switch (err) {
        error.SdlError => {
            std.debug.print("SDL error: ‘{s}'", .{c.SDL_GetError()});
            return err;
        },
        else => return err,
    };
}

// const target_triple: [:0]const u8 = x: {
//     var buf: [256]u8 = undefined;
//     var fba: std.heap.FixedBufferAllocator = .init(&buf);
//     break :x (builtin.target.zigTriple(fba.allocator()) catch unreachable) ++ "";
// };
//
// const window_w = 640;
// const window_h = 480;
// var window: *c.SDL_Window = undefined;
// var renderer: *c.SDL_Renderer = undefined;
//
// var fully_initialized: bool = false;
//
// fn sdlAppInit(appstate: ?*?*anyopaque, argv: [][*:0]u8) !c.SDL_AppResult {
//     _ = appstate;
//     _ = argv;
//
//     std.log.debug("{s} {s}", .{ target_triple, @tagName(builtin.mode) });
//     const platform: [*:0]const u8 = c.SDL_GetPlatform();
//     sdl_log.debug("SDL platform: {s}", .{platform});
//     sdl_log.debug("SDL version: {d}.{d}.{d}", .{
//         c.SDL_MAJOR_VERSION,
//         c.SDL_MINOR_VERSION,
//         c.SDL_MICRO_VERSION,
//     });
//     sdl_log.debug("SDL revision: {s}", .{c.SDL_REVISION});
//
//     try errify(c.SDL_SetAppMetadata("Geocrafter", "0.0.0", "Geocrafter"));
//     try errify(c.SDL_Init(c.SDL_INIT_VIDEO | c.SDL_INIT_AUDIO));
//
//     errify(c.SDL_SetHint(c.SDL_HINT_RENDER_VSYNC, "1")) catch {};
//
//     try errify(c.SDL_CreateWindowAndRenderer("Geocrafter", window_w, window_h, 0, @ptrCast(&window), @ptrCast(&renderer)));
//     errdefer c.SDL_DestroyWindow(window);
//     errdefer c.SDL_DestroyRenderer(renderer);
//
//     fully_initialized = true;
//
//     return c.SDL_APP_CONTINUE;
// }
//
// fn sdlAppIterate(appstate: ?*anyopaque) !c.SDL_AppResult {
//     _ = appstate;
//
//     try errify(c.SDL_SetRenderDrawColor(renderer, 0x47, 0x5b, 0x8d, 0xff));
//     try errify(c.SDL_RenderClear(renderer));
//
//     return c.SDL_APP_CONTINUE;
// }
//
// fn sdlAppEvent(appstate: ?*anyopaque, event: *c.SDL_Event) !c.SDL_AppResult {
//     _ = appstate;
//
//     switch (event.type) {
//         c.SDL_EVENT_QUIT => {
//             return c.SDL_APP_SUCCESS;
//         },
//         c.SDL_EVENT_KEY_DOWN, c.SDL_EVENT_KEY_UP => {
//             const down = event.type == c.SDL_EVENT_KEY_DOWN;
//             _ = down;
//
//             switch (event.key.scancode) {
//                 else => {},
//             }
//         },
//         c.SDL_EVENT_MOUSE_BUTTON_DOWN, c.SDL_EVENT_MOUSE_BUTTON_UP => {
//             switch (event.button.button) {
//                 c.SDL_BUTTON_LEFT => {},
//                 else => {},
//             }
//         },
//         c.SDL_EVENT_MOUSE_MOTION => {},
//         else => {},
//     }
//
//     return c.SDL_APP_CONTINUE;
// }
//
// fn sdlAppQuit(appstate: ?*anyopaque, result: anyerror!c.SDL_AppResult) void {
//     _ = appstate; // autofix
//
//     _ = result catch |err| if (err == error.SdlError) {
//         sdl_log.err("{s}", .{c.SDL_GetError()});
//     };
//
//     if (fully_initialized) {
//         c.SDL_DestroyRenderer(renderer);
//         c.SDL_DestroyWindow(window);
//         fully_initialized = false;
//     }
// }
//
// pub fn main() !u8 {
//     var empty_argv: [0:null]?[*:0]u8 = .{};
//     const status: u8 = @truncate(@as(c_uint, @bitCast(c.SDL_RunApp(empty_argv.len, @ptrCast(&empty_argv), sdlMainC, null))));
//     return app_err.load() orelse status;
// }
//
// fn sdlMainC(argc: c_int, argv: ?[*:null]?[*:0]u8) callconv(.c) c_int {
//     return c.SDL_EnterAppMainCallbacks(argc, @ptrCast(argv), sdlAppInitC, sdlAppIterateC, sdlAppEventC, sdlAppQuitC);
// }
//
// fn sdlAppInitC(appstate: ?*?*anyopaque, argc: c_int, argv: ?[*:null]?[*:0]u8) callconv(.c) c.SDL_AppResult {
//     return sdlAppInit(appstate.?, @ptrCast(argv.?[0..@intCast(argc)])) catch |err| app_err.store(err);
// }
//
// fn sdlAppIterateC(appstate: ?*anyopaque) callconv(.c) c.SDL_AppResult {
//     return sdlAppIterate(appstate) catch |err| app_err.store(err);
// }
//
// fn sdlAppEventC(appstate: ?*anyopaque, event: ?*c.SDL_Event) callconv(.c) c.SDL_AppResult {
//     return sdlAppEvent(appstate, event.?) catch |err| app_err.store(err);
// }
//
// fn sdlAppQuitC(appstate: ?*anyopaque, result: c.SDL_AppResult) callconv(.c) void {
//     sdlAppQuit(appstate, app_err.load() orelse result);
// }
//
// var app_err: ErrorStore = .{};
//
// const ErrorStore = struct {
//     const status_not_stored = 0;
//     const status_storing = 1;
//     const status_stored = 2;
//
//     status: c.SDL_AtomicInt = .{ .value = status_not_stored },
//     err: anyerror = undefined,
//     trace_index: usize = undefined,
//     trace_addrs: [32]usize = undefined,
//
//     fn store(es: *ErrorStore, err: anyerror) c.SDL_AppResult {
//         if (c.SDL_CompareAndSwapAtomicInt(&es.status, status_not_stored, status_storing)) {
//             es.err = err;
//             if (@errorReturnTrace()) |src_trace| {
//                 es.trace_index = src_trace.index;
//                 const len = @min(es.trace_addrs.len, src_trace.instruction_addresses.len);
//                 @memcpy(es.trace_addrs[0..len], src_trace.instruction_addresses[0..len]);
//             }
//             _ = c.SDL_SetAtomicInt(&es.status, status_stored);
//         }
//         return c.SDL_APP_FAILURE;
//     }
//
//     fn load(es: *ErrorStore) ?anyerror {
//         if (c.SDL_GetAtomicInt(&es.status) != status_stored) return null;
//         if (@errorReturnTrace()) |dst_trace| {
//             dst_trace.index = es.trace_index;
//             const len = @min(dst_trace.instruction_addresses.len, es.trace_addrs.len);
//             @memcpy(dst_trace.instruction_addresses[0..len], es.trace_addrs[0..len]);
//         }
//         return es.err;
//     }
// };
