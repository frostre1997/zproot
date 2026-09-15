const builtin = @import("builtin");
const arch = builtin.cpu.arch;

pub const SYS_OPENAT: u64 = if (arch == .x86_64) 257 else 56;
pub const SYS_OPENAT2: u64 = 437;
pub const SYS_STATX: u64 = if (arch == .x86_64) 332 else 291;
pub const SYS_NEWFSTATAT: u64 = if (arch == .x86_64) 262 else 79;
pub const SYS_READLINKAT: u64 = if (arch == .x86_64) 267 else 78;
pub const SYS_FACCESSAT: u64 = if (arch == .x86_64) 269 else 48;
pub const SYS_EXECVE: u64 = if (arch == .x86_64) 59 else 221;

pub fn isPath(nr: u64) bool {
    return nr == SYS_OPENAT or nr == SYS_OPENAT2 or nr == SYS_STATX or
        nr == SYS_NEWFSTATAT or nr == SYS_READLINKAT or nr == SYS_FACCESSAT or
        nr == SYS_EXECVE;
}

pub fn pathArgIndex(nr: u64) u8 {
    if (nr == SYS_EXECVE) return 0;
    return 1;
}
