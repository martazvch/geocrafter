const std = @import("std");
const Allocator = std.mem.Allocator;
const c = @import("c");
const utils = @import("utils.zig");
const Error = utils.Error;
const oom = utils.oom;
const Scene = @import("Scene.zig");

pub const Name = enum {
    triangle,
    triangle_dyn,
    cube,
    cube_sphere,
    plane_noise,
};

pub fn create(
    alloc: Allocator,
    name: Name,
    device: *c.SDL_GPUDevice,
    color_format: c.SDL_GPUTextureFormat,
    depth_format: c.SDL_GPUTextureFormat,
) Error!Scene {
    return switch (name) {
        .triangle => make(@import("scenes/triangle_simple.zig"), alloc, device, color_format, depth_format),
        .triangle_dyn => make(@import("scenes/triangle_dyn.zig"), alloc, device, color_format, depth_format),
        .cube => make(@import("scenes/cube_simple.zig"), alloc, device, color_format, depth_format),
        .cube_sphere => make(@import("scenes/cube_sphere.zig"), alloc, device, color_format, depth_format),
        .plane_noise => make(@import("scenes/plane_noise.zig"), alloc, device, color_format, depth_format),
    };
}

fn make(
    M: type,
    alloc: Allocator,
    device: *c.SDL_GPUDevice,
    color_format: c.SDL_GPUTextureFormat,
    depth_format: c.SDL_GPUTextureFormat,
) Error!Scene {
    const T = Created(M);
    const scene = alloc.create(T) catch oom();
    errdefer alloc.destroy(scene);

    scene.* = try M.init(alloc, device, color_format, depth_format);

    return scene.scene();
}

fn Created(T: type) type {
    if (!@hasDecl(T, "init")) {
        @compileError("Scene must define an init function");
    }

    const R = @typeInfo(@TypeOf(T.init)).@"fn".return_type.?;

    return switch (@typeInfo(R)) {
        .error_union => |eu| eu.payload,
        else => R,
    };
}
