const v = @import("vertex.zig");

vertices: [24]v.Vertex = VERTICES,
vert_size: usize = @sizeOf(@TypeOf(VERTICES)),
indices: [36]u16 = INDICES,
idx_size: usize = @sizeOf(@TypeOf(INDICES)),

const VERTICES = [24]v.Vertex{
    // +Z
    v.new(-0.5, -0.5, 0.5),  v.new(0.5, -0.5, 0.5),
    v.new(0.5, 0.5, 0.5),    v.new(-0.5, 0.5, 0.5),
    // -Z
    v.new(0.5, -0.5, -0.5),  v.new(-0.5, -0.5, -0.5),
    v.new(-0.5, 0.5, -0.5),  v.new(0.5, 0.5, -0.5),
    // +X
    v.new(0.5, -0.5, 0.5),   v.new(0.5, -0.5, -0.5),
    v.new(0.5, 0.5, -0.5),   v.new(0.5, 0.5, 0.5),
    // -X
    v.new(-0.5, -0.5, -0.5), v.new(-0.5, -0.5, 0.5),
    v.new(-0.5, 0.5, 0.5),   v.new(-0.5, 0.5, -0.5),
    // +Y
    v.new(-0.5, 0.5, 0.5),   v.new(0.5, 0.5, 0.5),
    v.new(0.5, 0.5, -0.5),   v.new(-0.5, 0.5, -0.5),
    // -Y
    v.new(-0.5, -0.5, -0.5), v.new(0.5, -0.5, -0.5),
    v.new(0.5, -0.5, 0.5),   v.new(-0.5, -0.5, 0.5),
};

const INDICES = [36]u16{
    0, 1, 2, 0, 2, 3, // +Z
    4, 5, 6, 4, 6, 7, // -Z
    8, 9, 10, 8, 10, 11, // +X
    12, 13, 14, 12, 14, 15, // -X
    16, 17, 18, 16, 18, 19, // +Y
    20, 21, 22, 20, 22, 23, // -Y
};
