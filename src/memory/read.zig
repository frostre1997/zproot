const std = @import("std");
const linux = std.os.linux;
const types = @import("../common/types.zig");
const ptrace = @import("../trace/ptrace.zig");

fn processVm(pid: types.pid_t, remote_addr: u64, local_buf: []u8) !usize {
    var local_iov = types.iovec{
        .iov_base = @as(?*anyopaque, @ptrCast(local_buf.ptr)),
        .iov_len = local_buf.len,
    };
    var remote_iov = types.iovec{
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
    if (!ptrace.ok(ret)) return error.VmReadFailed;
    return ret;
}

fn peekAligned(pid: types.pid_t, addr: u64) !u64 {
    const aligned = addr & ~@as(u64, 7);
    const ret = ptrace.call(ptrace.PTRACE_PEEKDATA, pid, aligned, 0);
    const signed: isize = @bitCast(ret);
    if (signed < 0 and signed > -4096) return error.PtraceFailed;
    return ret;
}

pub fn cstring(pid: types.pid_t, addr: u64, buf: []u8) ![]u8 {
    if (processVm(pid, addr, buf)) |n| {
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
            word = peekAligned(pid, word_addr) catch return error.PtraceFailed;
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
