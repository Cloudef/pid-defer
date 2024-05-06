const std = @import("std");
const waitpid = @import("common.zig").waitpid;

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const args = try std.process.argsAlloc(allocator);
    defer allocator.free(args);
    if (args.len < 1) {
        std.log.warn("usage: waitpid PID", .{});
        return error.InvalidUsage;
    }

    const pid = try std.fmt.parseInt(std.posix.pid_t, args[1], 10);
    const pid_fd: std.posix.pid_t = @bitCast(@as(u32, @truncate(std.os.linux.pidfd_open(pid, 0))));
    if (pid_fd == -1) return error.PidfdOpenFailed;
    defer std.posix.close(pid_fd);

    const efd = try std.posix.epoll_create1(std.os.linux.EPOLL.CLOEXEC);
    defer std.posix.close(efd);
    var iev: std.os.linux.epoll_event = .{ .events = std.os.linux.EPOLL.IN, .data = .{ .fd = pid } };
    try std.posix.epoll_ctl(efd, std.os.linux.EPOLL.CTL_ADD, pid_fd, &iev);

    var events: [1]std.os.linux.epoll_event = undefined;
    var nevents: usize = 0;
    while (nevents == 0) {
        nevents = std.os.linux.epoll_pwait(efd, events[0..], events.len, 0, null);
        for (events[0..nevents]) |ev| {
            switch (waitpid(ev.data.fd, false)) {
                .noop, .alive => {},
                .exited, .nopid => return,
            }
        }
    }
}
