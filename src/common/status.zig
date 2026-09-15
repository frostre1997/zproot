pub fn WIFEXITED(status: u32) bool {
    return (status & 0x7f) == 0;
}

pub fn WEXITSTATUS(status: u32) u8 {
    return @intCast((status >> 8) & 0xff);
}

pub fn WIFSTOPPED(status: u32) bool {
    return (status & 0xff) == 0x7f;
}

pub fn WSTOPSIG(status: u32) i32 {
    return @intCast((status >> 8) & 0xff);
}
