const std = @import("std");

pub const WaitPidResult = union(enum) {
    // no state change
    noop: void,
    // given child with the pid does not exist or all children are dead
    nopid: void,
    // child has exited cleanly
    exited: std.process.Child.Id,
    // child still alive
    alive: std.process.Child.Id,
};

pub fn waitpid(pid: std.process.Child.Id, blocking: bool) WaitPidResult {
    while (true) {
        var status: u32 = undefined;
        const ret = std.posix.system.waitpid(pid, &status, if (blocking) 0 else std.posix.W.NOHANG);
        switch (std.posix.errno(ret)) {
            .SUCCESS => {},
            .CHILD => return .nopid,
            .INTR => continue,
            .INVAL => unreachable,
            else => {},
        }
        const rpid: std.process.Child.Id = @truncate(@as(isize, @bitCast(ret)));
        if (rpid != 0) {
            if (std.os.linux.W.IFSIGNALED(status) or std.os.linux.W.IFEXITED(status)) {
                return .{ .exited = rpid };
            }
            return .{ .alive = rpid };
        }
        break;
    }
    return .noop;
}

pub fn sigact(comptime handler: fn (c_int) anyerror!void) std.posix.Sigaction {
    const wrapper = struct {
        fn fun(sig: c_int) callconv(.C) void {
            handler(sig) catch |err| {
                std.log.err("error from signal handler: {}", .{err});
                @panic("cannot continue");
            };
        }
    };
    return .{
        .handler = .{ .handler = wrapper.fun },
        .mask = std.posix.empty_sigset,
        .flags = 0,
    };
}
