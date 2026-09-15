const std = @import("std");
const builtin = @import("builtin");
const linux = std.os.linux;
const arch = builtin.cpu.arch;
const types = @import("../common/types.zig");
const sig = @import("../signal/numbers.zig");

pub fn doFork() !types.pid_t {
    const result = if (arch == .x86_64) blk: {
        break :blk linux.syscall0(.fork);
    } else if (arch == .aarch64) blk: {
        break :blk linux.syscall5(.clone, sig.SIGCHLD_FLAG, 0, 0, 0, 0);
    } else @compileError("unsupported arch");

    const signed: isize = @bitCast(result);
    if (signed < 0) return error.ForkFailed;
    return @intCast(signed);
}
