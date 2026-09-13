const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    std.debug.print("[zproot] building {s}-{s}-{s} ({s})\n", .{
        @tagName(target.result.cpu.arch),
        @tagName(target.result.os.tag),
        @tagName(target.result.abi),
        @tagName(optimize),
    });

    const root_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = false,
        .pic = true,
    });

    const exe = b.addExecutable(.{
        .name = "zproot",
        .root_module = root_module,
    });
    exe.pie = true;

    b.installArtifact(exe);
}
