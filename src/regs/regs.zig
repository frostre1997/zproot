const builtin = @import("builtin");
const arch = builtin.cpu.arch;
const types = @import("../common/types.zig");
const ptrace = @import("../trace/ptrace.zig");
const sig = @import("../signal/numbers.zig");

pub const Regs = if (arch == .x86_64) struct {
    raw: types.user_regs_struct,

    pub fn nr(self: @This()) u64 {
        return self.raw.orig_rax;
    }

    pub fn arg(self: @This(), i: u8) u64 {
        return switch (i) {
            0 => self.raw.rdi,
            1 => self.raw.rsi,
            2 => self.raw.rdx,
            3 => self.raw.r10,
            4 => self.raw.r8,
            5 => self.raw.r9,
            else => unreachable,
        };
    }

    pub fn sp(self: @This()) u64 {
        return self.raw.rsp;
    }
} else if (arch == .aarch64) struct {
    raw: types.user_pt_regs,

    pub fn nr(self: @This()) u64 {
        return self.raw.regs[8];
    }

    pub fn arg(self: @This(), i: u8) u64 {
        return self.raw.regs[i];
    }

    pub fn sp(self: @This()) u64 {
        return self.raw.sp;
    }
} else @compileError("unsupported arch");

pub fn get(pid: types.pid_t) !Regs {
    var regs: Regs = undefined;
    if (arch == .x86_64) {
        const ret = ptrace.call(ptrace.PTRACE_GETREGS, pid, 0, @intFromPtr(&regs.raw));
        if (!ptrace.ok(ret)) return error.PtraceFailed;
    } else {
        var iov = types.iovec{
            .iov_base = @as(?*anyopaque, @ptrCast(&regs.raw)),
            .iov_len = @sizeOf(types.user_pt_regs),
        };
        const ret = ptrace.call(ptrace.PTRACE_GETREGSET, pid, sig.NT_PRSTATUS, @intFromPtr(&iov));
        if (!ptrace.ok(ret)) return error.PtraceFailed;
    }
    return regs;
}

pub fn setArg(pid: types.pid_t, i: u8, value: u64) !void {
    if (arch == .x86_64) {
        var regs: types.user_regs_struct = undefined;
        var ret = ptrace.call(ptrace.PTRACE_GETREGS, pid, 0, @intFromPtr(&regs));
        if (!ptrace.ok(ret)) return error.PtraceFailed;
        switch (i) {
            0 => regs.rdi = value,
            1 => regs.rsi = value,
            2 => regs.rdx = value,
            3 => regs.r10 = value,
            4 => regs.r8 = value,
            5 => regs.r9 = value,
            else => unreachable,
        }
        ret = ptrace.call(ptrace.PTRACE_SETREGS, pid, 0, @intFromPtr(&regs));
        if (!ptrace.ok(ret)) return error.PtraceFailed;
    } else {
        var regs: types.user_pt_regs = undefined;
        var iov = types.iovec{
            .iov_base = @as(?*anyopaque, @ptrCast(&regs)),
            .iov_len = @sizeOf(types.user_pt_regs),
        };
        var ret = ptrace.call(ptrace.PTRACE_GETREGSET, pid, sig.NT_PRSTATUS, @intFromPtr(&iov));
        if (!ptrace.ok(ret)) return error.PtraceFailed;
        regs.regs[i] = value;
        ret = ptrace.call(ptrace.PTRACE_SETREGSET, pid, sig.NT_PRSTATUS, @intFromPtr(&iov));
        if (!ptrace.ok(ret)) return error.PtraceFailed;
    }
}
