// Article: https://raw.org/software/graphics/trackball-rotation-using-quaternions/
const std = @import("std");
const m = @import("math");

dragging: bool = false,
start: m.Vec3 = .{ .x = 0, .y = 0, .z = 1 },
base_rotation: m.Quat = .identity,
rotation: m.Quat = .identity,
// Angular velocity in camera space
spin: m.Vec3 = .zero,
previous: m.Vec3 = .zero,
width: f32,
height: f32,

const Self = @This();

pub fn begin(self: *Self, x: f32, y: f32) void {
    self.dragging = true;
    self.spin = .zero;
    self.start = self.projectToSphere(x, y);
    self.previous = self.start;
    self.base_rotation = self.rotation;
}

pub fn update(self: *Self, x: f32, y: f32, dt: f32) void {
    const current = self.projectToSphere(x, y);
    const delta = m.Quat.fromVectors(self.previous, current);
    const total_delta = m.Quat.fromVectors(self.start, current);

    // Applies rotation in `delta` coordinate space (camera-space rotation)
    self.rotation = total_delta.mul(self.base_rotation).normalize();

    if (dt > 1e-6) {
        const angle = 2.0 * std.math.acos(
            @max(-1.0, @min(1.0, delta.w)),
        );

        const sin_half = @sqrt(
            @max(0.0, 1.0 - delta.w * delta.w),
        );
        var new_spin = m.Vec3.zero;

        if (sin_half > 1e-6) {
            const axis = m.Vec3.new(
                delta.x / sin_half,
                delta.y / sin_half,
                delta.z / sin_half,
            );

            new_spin = axis.scale(angle / dt);
        }

        // Smooth velocity to avoid sudden changes from individual events.
        // self.spin = self.spin.scale(1.0 - velocity_smoothing)
        //     .add(new_spin.scale(velocity_smoothing));
        self.spin = new_spin;
    }

    self.previous = current;
}

pub fn end(self: *Self) void {
    self.dragging = false;
}

pub fn resize(self: *Self, width: f32, height: f32) void {
    self.width = width;
    self.height = height;
}

fn projectToSphere(self: *const Self, mouse_x: f32, mouse_y: f32) m.Vec3 {
    const size = @min(self.width, self.height);

    const x = (2.0 * mouse_x - self.width) / size;
    const y = (self.height - 2.0 * mouse_y) / size;

    const d2 = x * x + y * y;

    const z: f32 = if (d2 <= 0.5)
        @sqrt(1.0 - d2)
    else
        0.5 / @sqrt(d2);

    return m.Vec3.normalize(.{
        .x = x,
        .y = y,
        .z = z,
    });
}

const damping: f32 = 4.0;
const velocity_smoothing: f32 = 0.25;

pub fn integrateSpin(self: *Self, dt: f32) void {
    if (self.dragging) {
        return;
    }
    const speed = @sqrt(self.spin.dot(self.spin));

    if (speed < 1e-5) {
        self.spin = .zero;
        return;
    }

    const angle = speed * dt;
    const axis = self.spin.scale(1.0 / speed);

    const delta = m.Quat.fromAxisAngle(axis, angle);

    // Camera-space rotation
    self.rotation = delta.mul(self.rotation).normalize();

    // Exponential damping
    self.spin = self.spin.scale(@exp(-damping * dt));
}
