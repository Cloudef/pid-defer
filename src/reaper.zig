const std = @import("std");
const waitpid = @import("common.zig").waitpid;
const sigact = @import("common.zig").sigact;

fn killChildren(ttid: std.os.pid_t, signal: u8) !usize {
    const max_path = std.fmt.comptimePrint("/proc/self/task/{}/children", .{std.math.maxInt(@TypeOf(ttid))});
    var proc_path = std.BoundedArray(u8, max_path.len){};
    try proc_path.writer().print("/proc/self/task/{}/children", .{ttid});
    var file = try std.fs.openFileAbsolute(proc_path.constSlice(), .{.mode = .read_only});
    defer file.close();
    var reader = file.reader();
    var nchild: usize = 0;
    while (try reader.readUntilDelimiterOrEof(proc_path.slice(), ' ')) |buf| {
        const pid = try std.fmt.parseInt(std.os.pid_t, buf, 10);
        std.os.kill(pid, signal) catch {};
        nchild += 1;
    }
    return nchild;
}

fn cleanupChildren() !void {
    const ttid = std.os.linux.gettid();
    var signal: u8 = std.os.SIG.TERM;
    again: {
        // TODO: custom timeout
        for (1..5) |_| {
            if (try killChildren(ttid, signal) == 0) {
                // we are done
                return;
            }
            if (signal == std.os.SIG.KILL) {
                // give up
                return;
            }
            std.time.sleep(1e+9);
        }
        signal = std.os.SIG.KILL;
        break :again;
    }
}

fn signalHandler(signal: c_int) anyerror!void {
    cleanupChildren() catch unreachable;
    std.os.exit(@truncate(@as(c_uint, @bitCast(signal))));
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
        const signals = .{std.os.SIG.TERM, std.os.SIG.INT, std.os.SIG.QUIT, std.os.SIG.HUP};
        var act = sigact(signalHandler);
        inline for (signals) |sig| try std.os.sigaction(sig, &act, null);
    }

    _ = try std.os.prctl(.SET_CHILD_SUBREAPER, .{1});
    var chld = std.process.Child.init(args[1..], allocator);
    _ = try chld.spawn();
    defer cleanupChildren() catch unreachable;

    while (true) switch (waitpid(-1, true)) {
        .noop, .alive, .exited => {},
        .nopid => break,
    };
}
