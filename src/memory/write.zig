const types = @import("../common/types.zig");
const ptrace = @import("../trace/ptrace.zig");

fn poke(pid: types.pid_t, addr: u64, data: u64) !void {
    const ret = ptrace.call(ptrace.PTRACE_POKEDATA, pid, addr, data);
    if (!ptrace.ok(ret)) return error.PtraceFailed;
}

pub fn cstring(pid: types.pid_t, addr: u64, str: []const u8) !void {
    var word: u64 = 0;
    var i: usize = 0;
    while (i <= str.len) : (i += 1) {
        const byte: u8 = if (i < str.len) str[i] else 0;
        word |= @as(u64, byte) << @intCast((i % 8) * 8);
        if (i % 8 == 7 or i == str.len) {
            const base = addr + (i - (i % 8));
            try poke(pid, base, word);
            word = 0;
        }
    }
}
