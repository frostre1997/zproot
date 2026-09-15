const std = @import("std");
const builtin = @import("builtin");
const arch = builtin.cpu.arch;
const types = @import("../common/types.zig");
const ptrace = @import("../trace/ptrace.zig");
const sig = @import("../signal/numbers.zig");

fn readSiginfo(pid: types.pid_t, buf: *[128]u8) !void {
    const ret = ptrace.call(ptrace.PTRACE_GETSIGINFO, pid, 0, @intFromPtr(buf));
    if (!ptrace.ok(ret)) return error.PtraceFailed;
}

fn skipAndReturn(pid: types.pid_t, ret_val: u64) !void {
    if (arch == .aarch64) {
        var regs: types.user_pt_regs = undefined;
        var iov = types.iovec{
            .iov_base = @as(?*anyopaque, @ptrCast(&regs)),
            .iov_len = @sizeOf(types.user_pt_regs),
        };
        var ret = ptrace.call(ptrace.PTRACE_GETREGSET, pid, sig.NT_PRSTATUS, @intFromPtr(&iov));
        if (!ptrace.ok(ret)) return error.PtraceFailed;
        regs.regs[0] = ret_val;
        regs.pc += 4;
        ret = ptrace.call(ptrace.PTRACE_SETREGSET, pid, sig.NT_PRSTATUS, @intFromPtr(&iov));
        if (!ptrace.ok(ret)) return error.PtraceFailed;
    } else {
        var regs: types.user_regs_struct = undefined;
        var ret = ptrace.call(ptrace.PTRACE_GETREGS, pid, 0, @intFromPtr(&regs));
        if (!ptrace.ok(ret)) return error.PtraceFailed;
        regs.rax = ret_val;
        regs.rip += 2;
        ret = ptrace.call(ptrace.PTRACE_SETREGS, pid, 0, @intFromPtr(&regs));
        if (!ptrace.ok(ret)) return error.PtraceFailed;
    }
}

pub fn handle(pid: types.pid_t) !void {
    var info: [128]u8 align(8) = undefined;
    try readSiginfo(pid, &info);

    const si_code = std.mem.readInt(i32, info[8..12], .little);
    if (si_code != 1) {
        std.log.warn("SIGSYS si_code={d}, suppressing", .{si_code});
        return skipAndReturn(pid, sig.ENOSYS);
    }
    const blocked_nr = std.mem.readInt(u32, info[24..28], .little);
    std.log.warn("SIGSYS: blocked syscall {d} -> -ENOSYS", .{blocked_nr});
    try skipAndReturn(pid, sig.ENOSYS);
}
