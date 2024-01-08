const std = @import("std");
const waitpid = @import("common.zig").waitpid;
const sigact = @import("common.zig").sigact;

var CHILD: ?std.process.Child.Id = null;

fn cleanupChild() void {
    if (CHILD) |chld| {
        CHILD = null;
        const signals = .{ std.os.SIG.TERM, std.os.SIG.KILL };
        inline for (signals) |sig| {
            std.os.kill(chld, sig) catch return;
            // TODO: custom timeout
            for (1..5) |_| {
                if (waitpid(chld, false) == .nopid) return;
                std.time.sleep(1e+9);
            }
        }
    }
}

fn signalHandler(signal: c_int) anyerror!void {
    cleanupChild();
    std.os.exit(@truncate(@as(c_uint, @bitCast(signal))));
}

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

    {
        const signals = .{std.os.SIG.TERM, std.os.SIG.INT, std.os.SIG.QUIT, std.os.SIG.HUP};
        var act = sigact(signalHandler);
        inline for (signals) |sig| try std.os.sigaction(sig, &act, null);
    }

    var chld = std.process.Child.init(args[2..], allocator);
    _ = try chld.spawn();
    CHILD = chld.id;
    defer cleanupChild();

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
