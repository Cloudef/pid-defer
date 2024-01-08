const std = @import("std");

pub const WaitPidResult = union (enum) {
    // no state change
    noop: void,
    // given child with the pid does not exist or all children are dead
    nopid: void,
    // child has exited cleanly
    exited: std.process.Child.Id,
};

pub fn waitpid(pid: std.process.Child.Id, blocking: bool) WaitPidResult {
    again: {
        var status: u32 = undefined;
        const ret = std.os.system.waitpid(pid, &status, if (blocking) 0 else std.os.system.W.NOHANG);
        switch (std.os.errno(ret)) {
            .SUCCESS => {},
            .CHILD => return .nopid,
            .INTR => break :again,
            .INVAL => unreachable,
            else => {},
        }
        const rpid: std.process.Child.Id = @truncate(@as(isize, @bitCast(ret)));
        if (rpid != 0 and (std.os.linux.W.IFSIGNALED(status) or std.os.linux.W.IFEXITED(status))) {
            return .{ .exited = rpid };
        }
    }
    return .noop;
}
