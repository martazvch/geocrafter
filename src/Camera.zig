const m = @import("math");

pos: m.Vec3,
view: m.Mat4,
proj: m.Mat4,

const Self = @This();
const UP = m.Vec3.unitY;
const INIT_POS: m.Vec3 = .new(0, 0, 3);

pub fn init(win_w: u32, win_h: u32) Self {
    return .{
        .pos = INIT_POS,
        .view = .createLookAt(INIT_POS, .zero, UP),
        .proj = makeProj(win_w, win_h),
    };
}

pub fn zoom(self: *Self, delta: f32) void {
    // Multiplying by 0.1 makes it logarithmic, and * distance slows down when we get close
    self.pos.z = @max(0.1, self.pos.z - delta * self.pos.z * 0.1);
    self.view = .createLookAt(self.pos, .zero, UP);
}

pub fn resize(self: *Self, w: u32, h: u32) void {
    self.proj = makeProj(w, h);
}

fn makeProj(w: u32, h: u32) m.Mat4 {
    const aspect = @as(f32, @floatFromInt(w)) / @as(f32, @floatFromInt(h));
    return .createPerspective(m.d2r(60), aspect, 0.1, 100.0);
}
