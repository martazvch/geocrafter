const m = @import("math");

view: m.Mat4,
proj: m.Mat4,

const Self = @This();
const UP = m.Vec3.unitY;

pub fn init(win_w: u32, win_h: u32) Self {
    return .{
        .view = .createLookAt(.new(0, 0, 3), .zero, UP),
        .proj = makeProj(win_w, win_h),
    };
}

pub fn resize(self: *Self, w: u32, h: u32) void {
    self.proj = makeProj(w, h);
}

fn makeProj(w: u32, h: u32) m.Mat4 {
    const aspect = @as(f32, @floatFromInt(w)) / @as(f32, @floatFromInt(h));
    return .createPerspective(m.d2r(60), aspect, 0.1, 100.0);
}
