const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const main_exe = b.addExecutable(.{
        .name = "local-daemon",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(main_exe);
    const main_run = b.addRunArtifact(main_exe);
    if (b.args) |args| main_run.addArgs(args);
    const run = b.step("run", "Run");
    run.dependOn(&main_run.step);
}
