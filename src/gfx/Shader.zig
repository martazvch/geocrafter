const std = @import("std");
const Allocator = std.mem.Allocator;
const builtin = @import("builtin");
const c = @import("c");
const utils = @import("../utils.zig");
const errify = utils.errify;
const Error = utils.Error;

vert: *c.SDL_GPUShader,
frag: *c.SDL_GPUShader,

const Self = @This();

pub const format = switch (builtin.os.tag) {
    .linux => c.SDL_GPU_SHADERFORMAT_SPIRV,
    .macos => c.SDL_GPU_SHADERFORMAT_MSL,
    .windows => c.SDL_GPU_SHADERFORMAT_DXIL,
    else => |os| @compileError("unsupported OS: " ++ os),
};

const extension = switch (builtin.os.tag) {
    .linux => "spv",
    .macos => "msl",
    .windows => "dxil",
    else => @compileError("OS not supported"),
};

pub fn init(device: *c.SDL_GPUDevice, alloc: Allocator, comptime name: []const u8) Error!Self {
    return .{
        .vert = try createShader(device, alloc, name, .vert),
        .frag = try createShader(device, alloc, name, .frag),
    };
}

pub fn deinit(self: *Self, device: *c.SDL_GPUDevice) void {
    c.SDL_ReleaseGPUShader(device, self.vert);
    c.SDL_ReleaseGPUShader(device, self.frag);
}

const Stage = enum {
    vert,
    frag,
};
const ShaderInfo = struct {
    samplers: u32,
    storage_textures: u32,
    storage_buffers: u32,
    uniform_buffers: u32,
    inputs: []const Layout,
    outputs: []const Layout,

    const Layout = struct {
        name: []const u8,
        type: []const u8,
        location: u32,
    };
};

fn createShader(device: *c.SDL_GPUDevice, alloc: Allocator, comptime name: []const u8, comptime stage: Stage) Error!*c.SDL_GPUShader {
    const code_path = comptime getPath(name, extension, stage);
    const code = @embedFile(code_path);

    const json_path = comptime getPath(name, "json", stage);
    const json = @embedFile(json_path);

    const info = std.json.parseFromSlice(
        ShaderInfo,
        alloc,
        json,
        .{ .allocate = .alloc_if_needed },
    ) catch {
        std.log.err("Invalid vertex shader metadata", .{});
        return error.AppError;
    };
    defer info.deinit();

    var shader_info: c.SDL_GPUShaderCreateInfo = .{
        .code = code,
        .code_size = code.len,
        // Metal specific entrypoint
        .entrypoint = if (builtin.os.tag == .macos) "main0" else "main",
        .format = format,
        .stage = if (stage == .vert) c.SDL_GPU_SHADERSTAGE_VERTEX else c.SDL_GPU_SHADERSTAGE_FRAGMENT,
        .num_samplers = info.value.samplers,
        .num_storage_buffers = info.value.storage_buffers,
        .num_storage_textures = info.value.storage_textures,
        .num_uniform_buffers = info.value.uniform_buffers,
        .props = 0,
    };

    return errify(c.SDL_CreateGPUShader(device, &shader_info));
}

fn getPath(comptime name: []const u8, comptime ext: []const u8, comptime stage: Stage) []const u8 {
    return "../shaders/" ++ ext ++ "/" ++ name ++ "." ++ @tagName(stage) ++ "." ++ ext;
}
