const std = @import("std");
const Allocator = std.mem.Allocator;
const utils = @import("../utils.zig");
const oom = utils.oom;
const vert = @import("vertex.zig");

vertices: []const vert.Vertex,
indices: []const u32,

const Self = @This();

pub fn init(alloc: Allocator, quads: usize) Self {
    std.debug.assert(quads >= 1);

    const count: u32 = @intCast(quads + 1);
    const quadsf: f32 = @floatFromInt(quads);

    var vertices = alloc.alloc(vert.Vertex, count * count) catch oom();
    var indices = alloc.alloc(u32, quads * quads * 6) catch oom();

    for (0..count) |y| {
        for (0..count) |x| {
            const xf = (@as(f32, @floatFromInt(x)) / quadsf) * 2 - 1;
            const yf = (@as(f32, @floatFromInt(y)) / quadsf) * 2 - 1;
            vertices[x + y * count] = vert.new(xf, yf, 0);
        }
    }

    var q: usize = 0;
    for (0..quads) |y| {
        for (0..quads) |x| {
            const i: u32 = @intCast(x + y * count);

            indices[q * 6 ..][0..6].* = .{
                i,     i + 1,         i + count,
                i + 1, i + count + 1, i + count,
            };
            q += 1;
        }
    }

    return .{
        .vertices = vertices,
        .indices = indices,
    };
}

pub fn deinit(self: *Self, alloc: Allocator) void {
    alloc.free(self.vertices);
    alloc.free(self.indices);
}
