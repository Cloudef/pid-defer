const std = @import("std");
const waitpid = @import("common.zig").waitpid;
const sigact = @import("common.zig").sigact;

fn killChildren(ttid: std.posix.pid_t, signal: u8) !usize {
    const max_path = std.fmt.comptimePrint("/proc/self/task/{}/children", .{std.math.maxInt(@TypeOf(ttid))});
    var proc_path = std.BoundedArray(u8, max_path.len){};
    try proc_path.writer().print("/proc/self/task/{}/children", .{ttid});
    var file = try std.fs.openFileAbsolute(proc_path.constSlice(), .{ .mode = .read_only });
    defer file.close();
    var reader = file.reader();
    var nchild: usize = 0;
    while (try reader.readUntilDelimiterOrEof(proc_path.slice(), ' ')) |buf| {
        const pid = try std.fmt.parseInt(std.posix.pid_t, buf, 10);
        std.posix.kill(pid, signal) catch {};
        nchild += 1;
    }
    return nchild;
}

fn cleanupChildren() !void {
    const ttid = std.os.linux.gettid();
    var signal: u8 = std.posix.SIG.TERM;
    again: {
        // TODO: custom timeout
        for (1..5) |_| {
            if (try killChildren(ttid, signal) == 0) {
                // we are done
                return;
            }
            if (signal == std.posix.SIG.KILL) {
                // give up
                return;
            }
            std.time.sleep(1e+9);
        }
        signal = std.posix.SIG.KILL;
        break :again;
    }
}

fn signalHandler(signal: c_int) anyerror!void {
    cleanupChildren() catch unreachable;
    std.posix.exit(@truncate(@as(c_uint, @bitCast(signal))));
}

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const args = try std.process.argsAlloc(allocator);
    defer allocator.free(args);
    if (args.len < 2) {
        std.log.warn("usage: reaper cmd [args]", .{});
        return error.InvalidUsage;
    }

    {
        const signals = .{ std.posix.SIG.TERM, std.posix.SIG.INT, std.posix.SIG.QUIT, std.posix.SIG.HUP };
        var act = sigact(signalHandler);
        inline for (signals) |sig| try std.posix.sigaction(sig, &act, null);
    }

    _ = try std.posix.prctl(.SET_CHILD_SUBREAPER, .{1});
    var chld = std.process.Child.init(args[1..], allocator);
    _ = try chld.spawn();
    defer cleanupChildren() catch unreachable;

    while (true) switch (waitpid(-1, true)) {
        .noop, .alive, .exited => {},
        .nopid => break,
    };
}
