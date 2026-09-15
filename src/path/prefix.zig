const std = @import("std");

const passthrough = [_][]const u8{
    "/proc", "/sys", "/dev", "/system", "/apex", "/vendor", "/linkerconfig",
};

pub var rootfs_buf: [512]u8 = undefined;
pub var rootfs_len: usize = 0;

pub fn rootfs() []const u8 {
    return rootfs_buf[0..rootfs_len];
}

pub fn setRootfs(path: []const u8) bool {
    if (path.len > rootfs_buf.len) return false;
    @memcpy(rootfs_buf[0..path.len], path);
    rootfs_len = path.len;
    return true;
}

pub fn shouldPrefix(path: []const u8) bool {
    if (path.len == 0 or path[0] != '/') return false;
    for (passthrough) |p| {
        if (std.mem.startsWith(u8, path, p)) {
            if (path.len == p.len or path[p.len] == '/') return false;
        }
    }
    if (rootfs_len > 0 and std.mem.startsWith(u8, path, rootfs())) return false;
    return true;
}

pub fn build(new_buf: []u8, path: []const u8) ?[]const u8 {
    if (rootfs_len + path.len + 1 > new_buf.len) return null;
    @memcpy(new_buf[0..rootfs_len], rootfs());
    @memcpy(new_buf[rootfs_len .. rootfs_len + path.len], path);
    new_buf[rootfs_len + path.len] = 0;
    return new_buf[0 .. rootfs_len + path.len];
}
