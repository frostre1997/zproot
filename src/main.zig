const std = @import("std");
const builtin = @import("builtin");
const linux = std.os.linux;
const arch = builtin.cpu.arch;

const PTRACE_TRACEME: u32 = 0;
const PTRACE_PEEKDATA: u32 = 2;
const PTRACE_POKEDATA: u32 = 5;
const PTRACE_GETREGS: u32 = 12;
const PTRACE_SETREGS: u32 = 13;
const PTRACE_GETSIGINFO: u32 = 0x4202;
const PTRACE_GETREGSET: u32 = 0x4204;
const PTRACE_SETREGSET: u32 = 0x4205;
const PTRACE_SYSCALL: u32 = 24;

const NT_PRSTATUS: usize = 1;
const SIGTRAP: i32 = 5;
const SIGSYS: i32 = 31;
const SIGCHLD_FLAG: u64 = 17;
const ENOSYS: u64 = @bitCast(@as(i64, 38));
const pid_t = i32;

const iovec = extern struct {
    iov_base: ?*anyopaque,
    iov_len: usize,
};

const user_pt_regs = extern struct {
    regs: [31]u64,
    sp: u64,
    pc: u64,
    pstate: u64,
};

const user_regs_struct = extern struct {
    r15: u64, r14: u64, r13: u64, r12: u64,
    rbp: u64, rbx: u64, r11: u64, r10: u64,
    r9: u64, r8: u64, rax: u64, rcx: u64,
    rdx: u64, rsi: u64, rdi: u64, orig_rax: u64,
    rip: u64, cs: u64, eflags: u64, rsp: u64,
    ss: u64, fs_base: u64, gs_base: u64,
    ds: u64, es: u64, fs: u64, gs: u64,
};

var rootfs_buf: [512]u8 = undefined;
var rootfs_len: usize = 0;

fn rootfs() []const u8 {
    return rootfs_buf[0..rootfs_len];
}

fn exitNow(code: u8) noreturn {
    _ = linux.syscall1(.exit_group, @as(usize, code));
    unreachable;
}

fn ptraceCall(request: u32, pid: pid_t, addr: usize, data: usize) usize {
    return linux.syscall4(.ptrace, request, @intCast(pid), addr, data);
}

fn syscallOk(ret: usize) bool {
    const signed: isize = @bitCast(ret);
    return signed >= 0 or signed < -4095;
}

fn ptracePoke(pid: pid_t, addr: u64, data: u64) !void {
    const ret = ptraceCall(PTRACE_POKEDATA, pid, addr, data);
    if (!syscallOk(ret)) return error.PtraceFailed;
}

const Regs = if (arch == .x86_64) struct {
    raw: user_regs_struct,
    fn nr(self: @This()) u64 {
        return self.raw.orig_rax;
    }
    fn arg(self: @This(), i: u8) u64 {
        return switch (i) {
            0 => self.raw.rdi, 1 => self.raw.rsi, 2 => self.raw.rdx,
            3 => self.raw.r10, 4 => self.raw.r8,  5 => self.raw.r9,
            else => unreachable,
        };
    }
    fn sp(self: @This()) u64 {
        return self.raw.rsp;
    }
} else if (arch == .aarch64) struct {
    raw: user_pt_regs,
    fn nr(self: @This()) u64 {
        return self.raw.regs[8];
    }
    fn arg(self: @This(), i: u8) u64 {
        return self.raw.regs[i];
    }
    fn sp(self: @This()) u64 {
        return self.raw.sp;
    }
} else @compileError("unsupported arch");

fn getRegs(pid: pid_t) !Regs {
    var regs: Regs = undefined;
    if (arch == .x86_64) {
        const ret = ptraceCall(PTRACE_GETREGS, pid, 0, @intFromPtr(&regs.raw));
        if (!syscallOk(ret)) return error.PtraceFailed;
    } else {
        var iov = iovec{
            .iov_base = @as(?*anyopaque, @ptrCast(&regs.raw)),
            .iov_len = @sizeOf(user_pt_regs),
        };
        const ret = ptraceCall(PTRACE_GETREGSET, pid, NT_PRSTATUS, @intFromPtr(&iov));
        if (!syscallOk(ret)) return error.PtraceFailed;
    }
    return regs;
}

fn setArg(pid: pid_t, i: u8, value: u64) !void {
    if (arch == .x86_64) {
        var regs: user_regs_struct = undefined;
        var ret = ptraceCall(PTRACE_GETREGS, pid, 0, @intFromPtr(&regs));
        if (!syscallOk(ret)) return error.PtraceFailed;
        switch (i) {
            0 => regs.rdi = value, 1 => regs.rsi = value, 2 => regs.rdx = value,
            3 => regs.r10 = value, 4 => regs.r8  = value, 5 => regs.r9  = value,
            else => unreachable,
        }
        ret = ptraceCall(PTRACE_SETREGS, pid, 0, @intFromPtr(&regs));
        if (!syscallOk(ret)) return error.PtraceFailed;
    } else {
        var regs: user_pt_regs = undefined;
        var iov = iovec{
            .iov_base = @as(?*anyopaque, @ptrCast(&regs)),
            .iov_len = @sizeOf(user_pt_regs),
        };
        var ret = ptraceCall(PTRACE_GETREGSET, pid, NT_PRSTATUS, @intFromPtr(&iov));
        if (!syscallOk(ret)) return error.PtraceFailed;
        regs.regs[i] = value;
        ret = ptraceCall(PTRACE_SETREGSET, pid, NT_PRSTATUS, @intFromPtr(&iov));
        if (!syscallOk(ret)) return error.PtraceFailed;
    }
}

fn processVmRead(pid: pid_t, remote_addr: u64, local_buf: []u8) !usize {
    var local_iov = iovec{
        .iov_base = @as(?*anyopaque, @ptrCast(local_buf.ptr)),
        .iov_len = local_buf.len,
    };
    var remote_iov = iovec{
        .iov_base = @as(?*anyopaque, @ptrFromInt(remote_addr)),
        .iov_len = local_buf.len,
    };
    const ret = linux.syscall6(
        .process_vm_readv,
        @intCast(pid),
        @intFromPtr(&local_iov),
        1,
        @intFromPtr(&remote_iov),
        1,
        0,
    );
    if (!syscallOk(ret)) return error.VmReadFailed;
    return ret;
}

fn ptracePeekAligned(pid: pid_t, addr: u64) !u64 {
    const aligned = addr & ~@as(u64, 7);
    const ret = ptraceCall(PTRACE_PEEKDATA, pid, aligned, 0);
    const signed: isize = @bitCast(ret);
    if (signed < 0 and signed > -4096) return error.PtraceFailed;
    return ret;
}

fn readCString(pid: pid_t, addr: u64, buf: []u8) ![]u8 {
    if (processVmRead(pid, addr, buf)) |n| {
        if (std.mem.indexOfScalar(u8, buf[0..n], 0)) |end| {
            return buf[0..end];
        }
        return error.PathTooLong;
    } else |_| {}

    const align_offset: usize = @intCast(addr & 7);
    var word_addr = addr & ~@as(u64, 7);
    var word: u64 = 0;
    var byte_in_word: usize = align_offset;
    var i: usize = 0;

    while (i < buf.len) {
        if (byte_in_word == 0) {
            word = ptracePeekAligned(pid, word_addr) catch return error.PtraceFailed;
            word_addr += 8;
        }
        const byte: u8 = @truncate(word);
        buf[i] = byte;
        if (byte == 0) return buf[0..i];
        word >>= 8;
        byte_in_word = (byte_in_word + 1) % 8;
        i += 1;
    }
    return error.PathTooLong;
}

fn writeCString(pid: pid_t, addr: u64, str: []const u8) !void {
    var word: u64 = 0;
    var i: usize = 0;
    while (i <= str.len) : (i += 1) {
        const byte: u8 = if (i < str.len) str[i] else 0;
        word |= @as(u64, byte) << @intCast((i % 8) * 8);
        if (i % 8 == 7 or i == str.len) {
            const base = addr + (i - (i % 8));
            try ptracePoke(pid, base, word);
            word = 0;
        }
    }
}

fn WIFEXITED(status: u32) bool {
    return (status & 0x7f) == 0;
}
fn WEXITSTATUS(status: u32) u8 {
    return @intCast((status >> 8) & 0xff);
}
fn WIFSTOPPED(status: u32) bool {
    return (status & 0xff) == 0x7f;
}
fn WSTOPSIG(status: u32) i32 {
    return @intCast((status >> 8) & 0xff);
}

fn readSiginfo(pid: pid_t, buf: *[128]u8) !void {
    const ret = ptraceCall(PTRACE_GETSIGINFO, pid, 0, @intFromPtr(buf));
    if (!syscallOk(ret)) return error.PtraceFailed;
}

fn skipSyscallAndReturn(pid: pid_t, ret_val: u64) !void {
    if (arch == .aarch64) {
        var regs: user_pt_regs = undefined;
        var iov = iovec{
            .iov_base = @as(?*anyopaque, @ptrCast(&regs)),
            .iov_len = @sizeOf(user_pt_regs),
        };
        var ret = ptraceCall(PTRACE_GETREGSET, pid, NT_PRSTATUS, @intFromPtr(&iov));
        if (!syscallOk(ret)) return error.PtraceFailed;
        regs.regs[0] = ret_val;
        regs.pc += 4;
        ret = ptraceCall(PTRACE_SETREGSET, pid, NT_PRSTATUS, @intFromPtr(&iov));
        if (!syscallOk(ret)) return error.PtraceFailed;
    } else {
        var regs: user_regs_struct = undefined;
        var ret = ptraceCall(PTRACE_GETREGS, pid, 0, @intFromPtr(&regs));
        if (!syscallOk(ret)) return error.PtraceFailed;
        regs.rax = ret_val;
        regs.rip += 2;
        ret = ptraceCall(PTRACE_SETREGS, pid, 0, @intFromPtr(&regs));
        if (!syscallOk(ret)) return error.PtraceFailed;
    }
}

fn handleSigsys(pid: pid_t) !void {
    var info: [128]u8 align(8) = undefined;
    try readSiginfo(pid, &info);

    const si_code = std.mem.readInt(i32, info[8..12], .little);
    if (si_code != 1) {
        std.log.warn("SIGSYS si_code={d}, suppressing", .{si_code});
        return skipSyscallAndReturn(pid, ENOSYS);
    }
    const blocked_nr = std.mem.readInt(u32, info[24..28], .little);
    std.log.warn("SIGSYS: blocked syscall {d} -> -ENOSYS", .{blocked_nr});
    try skipSyscallAndReturn(pid, ENOSYS);
}

const SYS_OPENAT: u64 = if (arch == .x86_64) 257 else 56;
const SYS_OPENAT2: u64 = 437;
const SYS_STATX: u64 = if (arch == .x86_64) 332 else 291;
const SYS_NEWFSTATAT: u64 = if (arch == .x86_64) 262 else 79;
const SYS_READLINKAT: u64 = if (arch == .x86_64) 267 else 78;
const SYS_FACCESSAT: u64 = if (arch == .x86_64) 269 else 48;
const SYS_EXECVE: u64 = if (arch == .x86_64) 59 else 221;

fn isPathSyscall(nr: u64) bool {
    return nr == SYS_OPENAT or nr == SYS_OPENAT2 or nr == SYS_STATX or
        nr == SYS_NEWFSTATAT or nr == SYS_READLINKAT or nr == SYS_FACCESSAT or
        nr == SYS_EXECVE;
}

fn pathArgIndex(nr: u64) u8 {
    if (nr == SYS_EXECVE) return 0;
    return 1;
}

const passthrough = [_][]const u8{
    "/proc", "/sys", "/dev", "/system", "/apex", "/vendor", "/linkerconfig",
};

fn shouldPrefix(path: []const u8) bool {
    if (path.len == 0 or path[0] != '/') return false;
    for (passthrough) |p| {
        if (std.mem.startsWith(u8, path, p)) {
            if (path.len == p.len or path[p.len] == '/') return false;
        }
    }
    if (rootfs_len > 0 and std.mem.startsWith(u8, path, rootfs())) return false;
    return true;
}

fn doFork() !pid_t {
    const result = if (arch == .x86_64) blk: {
        break :blk linux.syscall0(.fork);
    } else if (arch == .aarch64) blk: {
        break :blk linux.syscall5(.clone, SIGCHLD_FLAG, 0, 0, 0, 0);
    } else @compileError("unsupported arch");

    const signed: isize = @bitCast(result);
    if (signed < 0) return error.ForkFailed;
    return @intCast(signed);
}

fn execvpZ(name: [*:0]const u8, argv: [*:null]const ?[*:0]const u8) noreturn {
    const name_slice = std.mem.span(name);
    var envp_buf = [_]?[*:0]const u8{null};
    const envp: [*:null]const ?[*:0]const u8 = @ptrCast(&envp_buf);

    if (std.mem.indexOfScalar(u8, name_slice, '/') != null) {
        _ = linux.syscall3(.execve, @intFromPtr(name), @intFromPtr(argv), @intFromPtr(envp));
        exitNow(127);
    }

    const paths = [_][]const u8{ "/system/bin", "/system/xbin", "/usr/bin", "/bin" };
    var buf: [4096]u8 = undefined;
    for (paths) |dir| {
        if (dir.len + 1 + name_slice.len + 1 > buf.len) continue;
        @memcpy(buf[0..dir.len], dir);
        buf[dir.len] = '/';
        @memcpy(buf[dir.len + 1 .. dir.len + 1 + name_slice.len], name_slice);
        buf[dir.len + 1 + name_slice.len] = 0;
        _ = linux.syscall3(.execve, @intFromPtr(&buf), @intFromPtr(argv), @intFromPtr(envp));
    }
    exitNow(127);
}

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());

    if (args.len < 2) {
        std.log.err("usage: zproot [--rootfs <path>] <program> [args...]", .{});
        return;
    }

    var start_idx: usize = 1;
    if (std.mem.eql(u8, args[1], "--rootfs")) {
        if (args.len < 4) {
            std.log.err("--rootfs requires a path and a program", .{});
            return;
        }
        const r = args[2];
        if (r.len > rootfs_buf.len) {
            std.log.err("rootfs path too long", .{});
            return;
        }
        @memcpy(rootfs_buf[0..r.len], r);
        rootfs_len = r.len;
        start_idx = 3;
    }

    var argv_arena = std.heap.ArenaAllocator.init(init.gpa);
    defer argv_arena.deinit();
    const aa = argv_arena.allocator();

    var child_args: std.ArrayList(?[*:0]const u8) = .empty;
    defer child_args.deinit(init.gpa);

    for (args[start_idx..]) |arg| {
        const z = try aa.dupeZ(u8, arg);
        try child_args.append(init.gpa, z.ptr);
    }
    try child_args.append(init.gpa, null);

    const child_argv: [*:null]const ?[*:0]const u8 =
        @ptrCast(child_args.items.ptr);

    const pid = doFork() catch |e| {
        std.log.err("fork failed: {}", .{e});
        return;
    };

    if (pid == 0) {
        _ = ptraceCall(PTRACE_TRACEME, 0, 0, 0);
        execvpZ(child_args.items[0].?, child_argv);
    }

    var status: u32 = 0;
    _ = linux.syscall4(.wait4, @intCast(pid), @intFromPtr(&status), 0, 0);

    var entering = true;
    var path_buf: [4096]u8 = undefined;
    var new_path_buf: [4096]u8 = undefined;

    while (true) {
        _ = ptraceCall(PTRACE_SYSCALL, pid, 0, 0);
        _ = linux.syscall4(.wait4, @intCast(pid), @intFromPtr(&status), 0, 0);

        if (WIFEXITED(status)) break;
        if (!WIFSTOPPED(status)) {
            entering = !entering;
            continue;
        }

        const sig = WSTOPSIG(status);

        if (sig == SIGSYS) {
            handleSigsys(pid) catch |e| {
                std.log.warn("SIGSYS failed: {}", .{e});
            };
            continue;
        }

        if (sig != SIGTRAP) {
            _ = ptraceCall(
                PTRACE_SYSCALL,
                pid,
                0,
                @intCast(@as(u32, @intCast(sig))),
            );
            _ = linux.syscall4(.wait4, @intCast(pid), @intFromPtr(&status), 0, 0);
            if (WIFEXITED(status)) break;
            if (!WIFSTOPPED(status)) {
                entering = !entering;
                continue;
            }
        }

        if (entering) {
            const regs = getRegs(pid) catch {
                entering = !entering;
                continue;
            };
            const nr = regs.nr();
            if (isPathSyscall(nr)) {
                const idx = pathArgIndex(nr);
                const path_addr = regs.arg(idx);
                const path = readCString(pid, path_addr, &path_buf) catch "<read failed>";

                if (rootfs_len > 0 and shouldPrefix(path)) {
                    if (rootfs_len + path.len + 1 <= new_path_buf.len) {
                        @memcpy(new_path_buf[0..rootfs_len], rootfs());
                        @memcpy(new_path_buf[rootfs_len .. rootfs_len + path.len], path);
                        new_path_buf[rootfs_len + path.len] = 0;
                        const new_path = new_path_buf[0 .. rootfs_len + path.len];

                        const scratch = regs.sp() - 8192;
                        writeCString(pid, scratch, new_path) catch {
                            std.log.err("write failed for {s}", .{path});
                            entering = !entering;
                            continue;
                        };
                        setArg(pid, idx, scratch) catch {
                            std.log.err("setregs failed for {s}", .{path});
                            entering = !entering;
                            continue;
                        };
                    }
                }
            }
        }
        entering = !entering;
    }

    std.log.info("child exited with {d}", .{WEXITSTATUS(status)});
}
