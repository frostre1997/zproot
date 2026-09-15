const std = @import("std");
const linux = std.os.linux;
const types = @import("../common/types.zig");

pub const PTRACE_TRACEME: u32 = 0;
pub const PTRACE_PEEKDATA: u32 = 2;
pub const PTRACE_POKEDATA: u32 = 5;
pub const PTRACE_GETREGS: u32 = 12;
pub const PTRACE_SETREGS: u32 = 13;
pub const PTRACE_GETSIGINFO: u32 = 0x4202;
pub const PTRACE_GETREGSET: u32 = 0x4204;
pub const PTRACE_SETREGSET: u32 = 0x4205;
pub const PTRACE_SYSCALL: u32 = 24;

pub fn call(request: u32, pid: types.pid_t, addr: usize, data: usize) usize {
    return linux.syscall4(.ptrace, request, @intCast(pid), addr, data);
}

pub fn ok(ret: usize) bool {
    const signed: isize = @bitCast(ret);
    return signed >= 0 or signed < -4095;
}
