pub const Vertex = extern struct {
    x: f32,
    y: f32,
    z: f32,
    r: f32,
    g: f32,
    b: f32,
    a: f32,
};
const R = 162.0 / 255.0;
const G = 164.0 / 255.0;
const B = 164.0 / 255.0;

pub fn new(x: f32, y: f32, z: f32) Vertex {
    return .{ .x = x, .y = y, .z = z, .r = R, .g = G, .b = B, .a = 1 };
}
