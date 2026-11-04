const c = @import("c");
const utils = @import("../utils.zig");
const errify = utils.errify;
const Error = utils.Error;

pub fn createVertBuf(device: *c.SDL_GPUDevice, size: u32) Error!*c.SDL_GPUBuffer {
    return errify(c.SDL_CreateGPUBuffer(device, &c.SDL_GPUBufferCreateInfo{
        .size = size,
        .usage = c.SDL_GPU_BUFFERUSAGE_VERTEX,
        .props = 0,
    }));
}

pub fn createIndexBuf(device: *c.SDL_GPUDevice, size: u32) Error!*c.SDL_GPUBuffer {
    return errify(c.SDL_CreateGPUBuffer(device, &.{
        .size = size,
        .usage = c.SDL_GPU_BUFFERUSAGE_INDEX,
        .props = 0,
    }));
}

pub fn createTransferBuf(device: *c.SDL_GPUDevice, size: u32) Error!*c.SDL_GPUTransferBuffer {
    return errify(c.SDL_CreateGPUTransferBuffer(device, &.{
        .size = size,
        .usage = c.SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD,
        .props = 0,
    }));
}
