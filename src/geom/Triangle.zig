const vert = @import("vertex.zig");

vertices: [3]vert.Vertex = VERTICES,
vert_size: usize = @sizeOf(@TypeOf(VERTICES)),

const VERTICES = [_]vert.Vertex{
    vert.new(0, 0.5, 0),
    vert.new(-0.5, -0.5, 0),
    vert.new(0.5, -0.5, 0),
};
