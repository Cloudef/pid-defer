const std = @import("std");

pub fn waitpid(pid: std.process.Child.Id) bool {
    var status: u32 = undefined;
    const ret = std.os.system.waitpid(pid, &status, std.os.system.W.NOHANG);
    switch (std.os.errno(ret)) {
        .SUCCESS => {},
        .CHILD => return true,
        else => {},
    }
    const rpid: std.process.Child.Id = @truncate(@as(isize, @bitCast(ret)));
    if (rpid != pid) return false;
    return std.os.linux.W.IFSIGNALED(status) or std.os.linux.W.IFEXITED(status);
}
