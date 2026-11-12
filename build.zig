const std = @import("std");
const translate_c = @import("translate_c");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const sdl_dep = b.dependency("sdl", .{
        .target = target,
        .optimize = optimize,
        //.preferred_linkage = .static,
        //.strip = null,
        //.sanitize_c = null,
        //.pic = null,
        //.lto = null,
        //.emscripten_pthreads = false,
        //.system_include_path = null,
        //.system_framework_path = null,
        //.library_path = null,
    });
    const sdl_lib = sdl_dep.artifact("SDL3");

    const zlm_dep = b.dependency("zlm", .{
        .target = target,
        .optimize = optimize,
    });

    const clarg_dep = b.dependency("clarg", .{
        .target = target,
        .optimize = optimize,
    });

    const dvui_dep = b.dependency("dvui", .{
        .target = target,
        .optimize = optimize,
        .backend = .sdl3gpu,
    });

    const math_mod = b.createModule(.{
        .root_source_file = b.path("src/math.zig"),
        .target = target,
        .optimize = optimize,
    });
    math_mod.addImport("zlm", zlm_dep.module("zlm"));

    const mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "math", .module = math_mod },
            .{ .name = "clarg", .module = clarg_dep.module("clarg") },
            .{ .name = "dvui", .module = dvui_dep.module("dvui_sdl3gpu") },
            .{ .name = "sdl3gpu-backend", .module = dvui_dep.module("sdl3gpu") },
        },
    });
    mod.linkLibrary(sdl_lib);

    const exe = b.addExecutable(.{
        .name = "geocrafter",
        .root_module = mod,
    });

    const translate_c_dep = b.dependency("translate_c", .{});
    const translator: translate_c.Translator = .init(translate_c_dep, .{
        .c_source_file = b.addWriteFiles().add("c.h",
            \\#define SDL_DISABLE_OLD_NAMES
            \\#include <SDL3/SDL.h>
            \\#include <SDL3/SDL_revision.h>
            \\#define SDL_MAIN_HANDLED
            \\#include <SDL3/SDL_main.h>
        ),
        .target = target,
        .optimize = optimize,
    });
    translator.linkLibrary(sdl_lib);
    mod.addImport("c", translator.mod);

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());
    run_cmd.addPassthruArgs();
}
