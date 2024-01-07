const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const Tool = struct {
        name: []const u8,
        file: []const u8,
    };
    const tools: []const Tool = &.{
        .{ .name = "local-daemon", .file = "src/main.zig" },
        .{ .name = "waitpid", .file = "src/waitpid.zig" },
    };

    inline for (tools) |tool| {
        const main_exe = b.addExecutable(.{
            .name = tool.name,
            .root_source_file = .{ .path = tool.file },
            .target = target,
            .optimize = optimize,
        });
        b.installArtifact(main_exe);
        const main_run = b.addRunArtifact(main_exe);
        if (b.args) |args| main_run.addArgs(args);
        const run = b.step(
            std.fmt.comptimePrint("run-{s}", .{tool.name}),
            std.fmt.comptimePrint("Run {s}", .{tool.name})
        );
        run.dependOn(&main_run.step);
    }
}
