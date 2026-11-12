const std = @import("std");
const c = @import("c");
const utils = @import("../utils.zig");
const errify = utils.errify;
const Error = utils.Error;
const gfx = @import("../gfx.zig");

pub fn Mesh(V: type) type {
    return struct {
        const Self = @This();

        vertex: *c.SDL_GPUBuffer,
        index: *c.SDL_GPUBuffer,
        vertex_count: u32,
        index_count: u32,

        pub fn create(
            device: *c.SDL_GPUDevice,
            cmd: *c.SDL_GPUCommandBuffer,
            vertices: []const V,
            indices: []const u32,
        ) Error!Self {
            const vertex = try gfx.buffer.createVertBuf(device, @intCast(@sizeOf(V) * vertices.len));
            errdefer c.SDL_ReleaseGPUBuffer(device, vertex);

            // Same helper as before for the index buffer: if it only sets VERTEX usage,
            // give it VERTEX | INDEX (Vulkan validation layers will complain otherwise).
            const index = try gfx.buffer.createIndexBuf(device, @intCast(@sizeOf(u32) * indices.len));
            errdefer c.SDL_ReleaseGPUBuffer(device, index);

            try upload(device, cmd, &.{
                .{ .dst = vertex, .bytes = std.mem.sliceAsBytes(vertices) },
                .{ .dst = index, .bytes = std.mem.sliceAsBytes(indices) },
            });

            return .{
                .vertex = vertex,
                .index = index,
                .vertex_count = @intCast(vertices.len),
                .index_count = @intCast(indices.len),
            };
        }

        pub fn deinit(self: Self, device: *c.SDL_GPUDevice) void {
            c.SDL_ReleaseGPUBuffer(device, self.vertex);
            c.SDL_ReleaseGPUBuffer(device, self.index);
        }

        /// Binds the mesh (vertex slot 0) and draws it with the pipeline already bound
        pub fn draw(self: Self, pass: *c.SDL_GPURenderPass) void {
            c.SDL_BindGPUVertexBuffers(
                pass,
                0,
                &[_]c.SDL_GPUBufferBinding{.{ .buffer = self.vertex, .offset = 0 }},
                1,
            );
            c.SDL_BindGPUIndexBuffer(pass, &.{ .buffer = self.index, .offset = 0 }, c.SDL_GPU_INDEXELEMENTSIZE_32BIT);
            c.SDL_DrawGPUIndexedPrimitives(pass, self.index_count, 1, 0, 0, 0);
        }
    };
}

pub const Upload = struct {
    dst: *c.SDL_GPUBuffer,
    bytes: []const u8,
};

/// The CPU data is copied into the transfer buffer immediately, so it can be freed after this call
/// `cmd` must not be inside a render pass
pub fn upload(device: *c.SDL_GPUDevice, cmd: *c.SDL_GPUCommandBuffer, uploads: []const Upload) Error!void {
    var total: u32 = 0;
    for (uploads) |u| total += @intCast(u.bytes.len);

    const trans = try gfx.buffer.createTransferBuf(device, total);
    defer c.SDL_ReleaseGPUTransferBuffer(device, trans);

    const data: [*]u8 = @ptrCast(@alignCast(
        try errify(c.SDL_MapGPUTransferBuffer(device, trans, false)),
    ));

    var offset: usize = 0;
    for (uploads) |u| {
        @memcpy(data[offset..][0..u.bytes.len], u.bytes);
        offset += u.bytes.len;
    }
    c.SDL_UnmapGPUTransferBuffer(device, trans);

    const copy_pass = c.SDL_BeginGPUCopyPass(cmd);
    defer c.SDL_EndGPUCopyPass(copy_pass);

    offset = 0;
    for (uploads) |u| {
        const size: u32 = @intCast(u.bytes.len);
        c.SDL_UploadToGPUBuffer(
            copy_pass,
            &.{ .transfer_buffer = trans, .offset = @intCast(offset) },
            &.{ .buffer = u.dst, .offset = 0, .size = size },
            false,
        );
        offset += u.bytes.len;
    }
}
