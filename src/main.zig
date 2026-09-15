const std = @import("std");
const linux = std.os.linux;

const types = @import("common/types.zig");
const status = @import("common/status.zig");
const ptrace = @import("trace/ptrace.zig");
const regs = @import("regs/regs.zig");
const memory_read = @import("memory/read.zig");
const memory_write = @import("memory/write.zig");
const seccomp = @import("seccomp/sigsys.zig");
const path = @import("path/prefix.zig");
const syscalls = @import("syscall/numbers.zig");
const sig = @import("signal/numbers.zig");
const fork = @import("exec/fork.zig");
const execve = @import("exec/execve.zig");

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
        if (!path.setRootfs(args[2])) {
            std.log.err("rootfs path too long", .{});
            return;
        }
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

    const pid = fork.doFork() catch |e| {
        std.log.err("fork failed: {}", .{e});
        return;
    };

    if (pid == 0) {
        _ = ptrace.call(ptrace.PTRACE_TRACEME, 0, 0, 0);
        execve.execvpZ(child_args.items[0].?, child_argv);
    }

    var st: u32 = 0;
    _ = linux.syscall4(.wait4, @intCast(pid), @intFromPtr(&st), 0, 0);

    var entering = true;
    var path_buf: [4096]u8 = undefined;
    var new_path_buf: [4096]u8 = undefined;

    while (true) {
        _ = ptrace.call(ptrace.PTRACE_SYSCALL, pid, 0, 0);
        _ = linux.syscall4(.wait4, @intCast(pid), @intFromPtr(&st), 0, 0);

        if (status.WIFEXITED(st)) break;
        if (!status.WIFSTOPPED(st)) {
            entering = !entering;
            continue;
        }

        const s = status.WSTOPSIG(st);

        if (s == sig.SIGSYS) {
            seccomp.handle(pid) catch |e| {
                std.log.warn("SIGSYS failed: {}", .{e});
            };
            continue;
        }

        if (s != sig.SIGTRAP) {
            _ = ptrace.call(
                ptrace.PTRACE_SYSCALL,
                pid,
                0,
                @intCast(@as(u32, @intCast(s))),
            );
            _ = linux.syscall4(.wait4, @intCast(pid), @intFromPtr(&st), 0, 0);
            if (status.WIFEXITED(st)) break;
            if (!status.WIFSTOPPED(st)) {
                entering = !entering;
                continue;
            }
        }

        if (entering) {
            const r = regs.get(pid) catch {
                entering = !entering;
                continue;
            };
            const nr = r.nr();
            if (syscalls.isPath(nr)) {
                const idx = syscalls.pathArgIndex(nr);
                const path_addr = r.arg(idx);
                const p = memory_read.cstring(pid, path_addr, &path_buf) catch "<read failed>";

                if (path.rootfs_len > 0 and path.shouldPrefix(p)) {
                    if (path.build(&new_path_buf, p)) |new_path| {
                        const scratch = r.sp() - 8192;
                        memory_write.cstring(pid, scratch, new_path) catch {
                            std.log.err("write failed for {s}", .{p});
                            entering = !entering;
                            continue;
                        };
                        regs.setArg(pid, idx, scratch) catch {
                            std.log.err("setregs failed for {s}", .{p});
                            entering = !entering;
                            continue;
                        };
                    }
                }
            }
        }
        entering = !entering;
    }

    std.log.info("child exited with {d}", .{status.WEXITSTATUS(st)});
}
