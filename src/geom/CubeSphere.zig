const std = @import("std");
const Allocator = std.mem.Allocator;
const m = @import("math");
const utils = @import("../utils.zig");
const oom = utils.oom;
const vert = @import("vertex.zig");

vertices: []const vert.Vertex,
indices: []const u32,

const Self = @This();

const NORMALS: [6]m.Vec3 = .{
    .new(0, 0, -1), // -Z
    .new(1, 0, 0), // +X
    .new(0, -1, 0), // -Y
    .new(0, 0, 1), // +Z
    .new(-1, 0, 0), // -X
    .new(0, 1, 0), // +Y
};

fn faceAxes(face: usize) struct { n: m.Vec3, u: m.Vec3, v: m.Vec3 } {
    const n = NORMALS[face];
    // Moves the non-zero component to another slot, rotating vector 90°
    const u = n.swizzle("yzx");
    // Gets the third axis
    const v = n.cross(u);

    return .{
        .n = n,
        .u = u,
        .v = v,
    };
}

pub fn init(alloc: Allocator, quads: usize, better_spacing: bool) Self {
    const side = quads + 1;
    const s: u32 = @intCast(side);
    const side2 = side * side;
    const quadsf: f32 = @floatFromInt(quads);

    var vertices = std.ArrayList(vert.Vertex).initCapacity(alloc, side2 * 6) catch oom();
    var indices = std.ArrayList(u32).initCapacity(alloc, quads * quads * 6 * 6) catch oom();

    for (0..6) |face| {
        const axes = faceAxes(face);

        for (0..side) |y| {
            for (0..side) |x| {
                // Maps value to [-1, 1]
                const xf = (@as(f32, @floatFromInt(x)) / quadsf) * 2 - 1;
                const yf = (@as(f32, @floatFromInt(y)) / quadsf) * 2 - 1;
                // Maps value to [-0.5, 0.5]
                const cube_pos = axes.n.add(axes.u.scale(xf)).add(axes.v.scale(yf));
                const pos = cubeToSphere(cube_pos, better_spacing);
                vertices.appendAssumeCapacity(vert.new(pos.x, pos.y, pos.z));
            }
        }

        const vbase = face * side2;

        for (0..quads) |y| {
            for (0..quads) |x| {
                const i: u32 = @intCast(vbase + y * side + x);
                indices.appendSliceAssumeCapacity(&.{
                    i,     i + 1,     i + s,
                    i + 1, i + s + 1, i + s,
                });
            }
        }
    }

    return .{
        .vertices = vertices.toOwnedSlice(alloc) catch oom(),
        .indices = indices.toOwnedSlice(alloc) catch oom(),
    };
}

pub fn deinit(self: *Self, alloc: Allocator) void {
    alloc.free(self.vertices);
    alloc.free(self.indices);
}

fn cubeToSphere(p: m.Vec3, better_spacing: bool) m.Vec3 {
    if (better_spacing) {
        const x2 = p.x * p.x;
        const y2 = p.y * p.y;
        const z2 = p.z * p.z;

        return m.Vec3.new(
            p.x * @sqrt(1.0 - (y2 + z2) / 2.0 + (y2 * z2) / 3.0),
            p.y * @sqrt(1.0 - (x2 + z2) / 2.0 + (x2 * z2) / 3.0),
            p.z * @sqrt(1.0 - (x2 + y2) / 2.0 + (x2 * y2) / 3.0),
        );
    }

    return p.normalize();
}
