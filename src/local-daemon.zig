const std = @import("std");
const waitpid = @import("common.zig").waitpid;

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const args = try std.process.argsAlloc(allocator);
    defer allocator.free(args);
    if (args.len < 2) {
        std.log.warn("usage: local-daemon PPID cmd [args]", .{});
        return error.InvalidUsage;
    }

    if (try std.os.fork() > 0) {
        // parent process
        return;
    }

    const ppid = try std.fmt.parseInt(std.os.pid_t, args[1], 10);
    const ppid_fd: std.os.pid_t = @bitCast(@as(u32, @truncate(std.os.linux.pidfd_open(ppid, 0))));
    if (ppid_fd == -1) return error.PidfdOpenFailed;
    defer std.os.close(ppid_fd);

    if (std.os.errno(std.os.linux.syscall2(.setpgid, @bitCast(@as(isize, std.os.linux.getpid())), 0)) != .SUCCESS) {
        return error.SetpgidFailed;
    }

    var chld = std.process.Child.init(args[2..], allocator);
    _ = try chld.spawn();
    defer std.os.kill(0, std.os.SIG.TERM) catch {};

    const child_fd: std.os.pid_t = @bitCast(@as(u32, @truncate(std.os.linux.pidfd_open(chld.id, 0))));
    if (child_fd == -1) return error.PidfdOpenFailed;
    defer std.os.close(child_fd);

    const efd = try std.os.epoll_create1(std.os.linux.EPOLL.CLOEXEC);
    defer std.os.close(efd);

    const fds = .{ ppid_fd, child_fd };
    const pids = .{ ppid, chld.id };
    inline for (fds, pids) |fd, pid| {
        var ev: std.os.linux.epoll_event = .{ .events = std.os.linux.EPOLL.IN, .data = .{ .fd = pid } };
        try std.os.epoll_ctl(efd, std.os.linux.EPOLL.CTL_ADD, fd, &ev);
    }

    var events: [2]std.os.linux.epoll_event = undefined;
    var nevents: usize = 0;
    while (true) {
        nevents = std.os.linux.epoll_pwait(efd, events[0..], events.len, -1, null);
        for (events[0..nevents]) |ev| {
            switch (waitpid(ev.data.fd, false)) {
                .noop, .alive => {},
                .exited, .nopid => return,
            }
        }
    }
}
