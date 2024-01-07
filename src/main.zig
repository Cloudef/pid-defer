const std = @import("std");

var CHILD: ?std.process.Child = null;

fn signalHandler(signal: c_int) anyerror!void {
    if (CHILD) |*chld| {
        CHILD = null;
        _ = chld.kill() catch {};
    }
    if (signal == std.os.SIG.HUP) {
        std.os.exit(@truncate(@as(c_uint, @bitCast(signal))));
    }
}

fn sigact(comptime handler: fn (c_int) anyerror!void) std.os.Sigaction {
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
        .mask = std.os.empty_sigset,
        .flags = 0,
    };
}

fn waitpid(pid: std.process.Child.Id) !std.process.Child.Id {
    var status: u32 = undefined;
    const ret = @as(std.process.Child.Id, @truncate(@as(isize, @bitCast(std.os.system.waitpid(pid, &status, std.os.system.W.NOHANG)))));
    if (ret == -1) return error.WaitPidFailed;
    return ret;
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
    CHILD = chld;
    _ = try chld.spawn();
    defer {
        if (CHILD) |_| {
            CHILD = null;
            _ = chld.kill() catch {};
        }
    }

    const child_fd: std.os.pid_t = @bitCast(@as(u32, @truncate(std.os.linux.pidfd_open(chld.id, 0))));
    if (child_fd == -1) return error.PidfdOpenFailed;

    const efd = try std.os.epoll_create1(std.os.linux.EPOLL.CLOEXEC);
    const fds = .{ ppid_fd, child_fd };
    const pids = .{ ppid, chld.id };
    inline for (fds, pids) |fd, pid| {
        var ev: std.os.linux.epoll_event = .{ .events = std.os.linux.EPOLL.IN, .data = .{ .fd = pid } };
        try std.os.epoll_ctl(efd, std.os.linux.EPOLL.CTL_ADD, fd, &ev);
    }

    var events: [2]std.os.linux.epoll_event = undefined;
    var nevents: usize = 0;
    while (nevents == 0) {
        nevents = std.os.linux.epoll_pwait(efd, events[0..], events.len, 0, null);
        for (events[0..nevents]) |ev| {
            if (try waitpid(ev.data.fd) == ev.data.fd) {
                // process closed
                return;
            }
        }
    }
}
