const std = @import("std");
const m = @import("math.zig");

w: f32,
x: f32,
y: f32,
z: f32,

const Self = @This();
pub const identity: Self = .{
    .w = 1,
    .x = 0,
    .y = 0,
    .z = 0,
};

pub fn mul(a: Self, b: Self) Self {
    return .{
        .w = a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z,
        .x = a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y,
        .y = a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x,
        .z = a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w,
    };
}

pub fn normalize(q: Self) Self {
    const len = @sqrt(
        q.w * q.w + q.x * q.x + q.y * q.y + q.z * q.z,
    );

    if (len < 1e-8) return .identity;

    return .{
        .w = q.w / len,
        .x = q.x / len,
        .y = q.y / len,
        .z = q.z / len,
    };
}

// Rotation taking vector a to vector b.
pub fn fromVectors(a: m.Vec3, b: m.Vec3) Self {
    const d = @max(-1.0, @min(1.0, a.dot(b)));

    if (d < -0.999999) {
        var axis = a.cross(.unitX);

        if (axis.dot(axis) < 1e-6) {
            axis = a.cross(.unitY);
        }

        axis = axis.normalize();

        return .{
            .w = 0,
            .x = axis.x,
            .y = axis.y,
            .z = axis.z,
        };
    }

    const axis = m.Vec3.cross(a, b);

    return normalize(.{
        .w = 1.0 + d,
        .x = axis.x,
        .y = axis.y,
        .z = axis.z,
    });
}

pub fn fromAxisAngle(axis: m.Vec3, angle: f32) Self {
    const half = angle * 0.5;
    const s = @sin(half);

    return .{
        .w = @cos(half),
        .x = axis.x * s,
        .y = axis.y * s,
        .z = axis.z * s,
    };
}

pub fn toMat4(q: Self) m.Mat4 {
    const nq = q.normalize();

    const w = @max(-1.0, @min(1.0, nq.w));
    const angle = 2.0 * std.math.acos(w);

    const sin_half = @sqrt(@max(0.0, 1.0 - w * w));

    const axis = if (sin_half < 1e-6)
        m.Vec3{ .x = 0, .y = 0, .z = 1 }
    else
        m.Vec3{
            .x = nq.x / sin_half,
            .y = nq.y / sin_half,
            .z = nq.z / sin_half,
        };

    return .createAngleAxis(
        m.Vec3.new(axis.x, axis.y, axis.z),
        angle,
    );
}
