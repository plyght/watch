//! Renders previews of every engraving pattern in patterns.zig to out/patterns/*.pgm
//! (binary P5, 8-bit): the raw heightmap and a lit "metal" shading of it.
//!
//!     zig run -O ReleaseFast src/patterns_preview.zig

const std = @import("std");
const patterns = @import("patterns.zig");
const Heightmap = patterns.Heightmap;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.arena.allocator();
    const cwd = std.Io.Dir.cwd();
    try cwd.createDirPath(io, "out/patterns");

    const Job = struct { name: []const u8, relief: f32 };
    var maps: std.ArrayList(struct { job: Job, hm: Heightmap }) = .empty;

    {
        const t0 = std.Io.Clock.awake.now(io);
        const hm = try patterns.scrollwork(gpa, 512, 256, 1);
        report(io, "scrollwork 512x256 seed 1", t0);
        try maps.append(gpa, .{ .job = .{ .name = "scroll_plaque_s1", .relief = 6 }, .hm = hm });
    }
    {
        const t0 = std.Io.Clock.awake.now(io);
        const hm = try patterns.scrollwork(gpa, 512, 256, 7);
        report(io, "scrollwork 512x256 seed 7", t0);
        try maps.append(gpa, .{ .job = .{ .name = "scroll_plaque_s7", .relief = 6 }, .hm = hm });
    }
    {
        const t0 = std.Io.Clock.awake.now(io);
        const hm = try patterns.scrollwork(gpa, 1024, 1024, 3);
        report(io, "scrollwork 1024x1024 seed 3", t0);
        try maps.append(gpa, .{ .job = .{ .name = "scroll_square_s3", .relief = 7 }, .hm = hm });
    }
    {
        // Revolver-cylinder style: six chamber windows on a ring plus a centre arbor.
        var clear: [7][3]f32 = undefined;
        for (0..6) |i| {
            const a = std.math.tau * @as(f32, @floatFromInt(i)) / 6.0 - std.math.pi / 2.0;
            clear[i] = .{ 0.56 * @cos(a), 0.56 * @sin(a), 0.17 };
        }
        clear[6] = .{ 0, 0, 0.08 };
        const t0 = std.Io.Clock.awake.now(io);
        const hm = try patterns.scrollRadial(gpa, 1024, 6, &clear, 11);
        report(io, "scrollRadial 1024 folds 6 (7 clear)", t0);
        try maps.append(gpa, .{ .job = .{ .name = "scroll_dial_6", .relief = 7 }, .hm = hm });
    }
    {
        const t0 = std.Io.Clock.awake.now(io);
        const hm = try patterns.scrollRadial(gpa, 1024, 4, &.{}, 5);
        report(io, "scrollRadial 1024 folds 4 (no clear)", t0);
        try maps.append(gpa, .{ .job = .{ .name = "scroll_dial_4", .relief = 7 }, .hm = hm });
    }
    {
        const t0 = std.Io.Clock.awake.now(io);
        const hm = try patterns.cracks(gpa, 1024, 1024, .{ 0.42, 0.38 }, 2);
        report(io, "cracks 1024 centre-ish", t0);
        try maps.append(gpa, .{ .job = .{ .name = "cracks_square", .relief = 5 }, .hm = hm });
    }
    {
        const t0 = std.Io.Clock.awake.now(io);
        const hm = try patterns.cracks(gpa, 512, 256, .{ -0.15, 0.3 }, 9);
        report(io, "cracks 512x256 impact outside", t0);
        try maps.append(gpa, .{ .job = .{ .name = "cracks_plaque", .relief = 4 }, .hm = hm });
    }

    for (maps.items) |m| {
        const hm = m.hm;
        var raw: std.ArrayList(u8) = .empty;
        var lit: std.ArrayList(u8) = .empty;
        try header(gpa, &raw, hm.w, hm.h);
        try header(gpa, &lit, hm.w, hm.h);
        for (0..hm.h) |y| {
            for (0..hm.w) |x| {
                const v = std.math.clamp(hm.at(x, y), 0, 1);
                try raw.append(gpa, @intFromFloat(v * 255.0 + 0.5));
                try lit.append(gpa, shade(hm, x, y, m.job.relief));
            }
        }
        const p1 = try std.fmt.allocPrint(gpa, "out/patterns/{s}.pgm", .{m.job.name});
        const p2 = try std.fmt.allocPrint(gpa, "out/patterns/{s}_lit.pgm", .{m.job.name});
        try cwd.writeFile(io, .{ .sub_path = p1, .data = raw.items });
        try cwd.writeFile(io, .{ .sub_path = p2, .data = lit.items });
        std.debug.print("wrote {s} and {s}\n", .{ p1, p2 });
    }

    // Sampling sanity check.
    const hm = maps.items[0].hm;
    std.debug.print("sample(0.5,0.5)={d:.3} sample(-1,2)={d:.3}\n", .{ hm.sample(0.5, 0.5), hm.sample(-1, 2) });
}

fn report(io: std.Io, what: []const u8, t0: std.Io.Timestamp) void {
    const t1 = std.Io.Clock.awake.now(io);
    const ms = @divTrunc(t0.durationTo(t1).nanoseconds, std.time.ns_per_ms);
    std.debug.print("{s}: {d} ms\n", .{ what, ms });
}

fn header(gpa: std.mem.Allocator, buf: *std.ArrayList(u8), w: usize, h: usize) !void {
    const s = try std.fmt.allocPrint(gpa, "P5\n{d} {d}\n255\n", .{ w, h });
    try buf.appendSlice(gpa, s);
}

/// Polished-metal look: dark environment with a key light from the upper left, strong
/// specular, so raised polished relief reads bright against the ground.
fn shade(hm: Heightmap, x: usize, y: usize, relief: f32) u8 {
    const xl = if (x > 0) x - 1 else x;
    const xr = if (x + 1 < hm.w) x + 1 else x;
    const yu = if (y > 0) y - 1 else y;
    const yd = if (y + 1 < hm.h) y + 1 else y;
    const dx = (hm.at(xr, y) - hm.at(xl, y)) * relief / @as(f32, @floatFromInt(xr - xl));
    const dy = (hm.at(x, yd) - hm.at(x, yu)) * relief / @as(f32, @floatFromInt(yd - yu));
    var n = [3]f32{ -dx, -dy, 1 };
    const nl = @sqrt(n[0] * n[0] + n[1] * n[1] + n[2] * n[2]);
    for (&n) |*c| c.* /= nl;
    const l = norm(.{ -0.5, -0.6, 0.62 });
    const v = [3]f32{ 0, 0, 1 };
    const hv = norm(.{ l[0] + v[0], l[1] + v[1], l[2] + v[2] });
    const ndl = @max(0, n[0] * l[0] + n[1] * l[1] + n[2] * l[2]);
    const ndh = @max(0, n[0] * hv[0] + n[1] * hv[1] + n[2] * hv[2]);
    const spec = std.math.pow(f32, ndh, 40);
    const height = hm.at(x, y);
    const ao = 0.35 + 0.65 * std.math.clamp(height * 1.4, 0, 1);
    const c = (0.12 + 0.5 * ndl) * ao + 0.6 * spec;
    return @intFromFloat(std.math.clamp(c, 0, 1) * 255.0);
}

fn norm(v: [3]f32) [3]f32 {
    const l = @sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]);
    return .{ v[0] / l, v[1] / l, v[2] / l };
}
