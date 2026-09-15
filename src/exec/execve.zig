const std = @import("std");
const linux = std.os.linux;

fn exitNow(code: u8) noreturn {
    _ = linux.syscall1(.exit_group, @as(usize, code));
    unreachable;
}

pub fn execvpZ(name: [*:0]const u8, argv: [*:null]const ?[*:0]const u8) noreturn {
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
