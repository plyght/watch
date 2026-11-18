//! SC-01 concept watch: parametric geometry generator.
//!
//! Units are millimetres. Z is up (the dial faces +Z), 12 o'clock is +Y and
//! the crown sits at +X. Output is a single OBJ with one named object per
//! part, so the renderer can assign a material by object name.
//!
//! This is concept geometry for renders: parts overlap instead of being
//! boolean-unioned, and functional seats (crystal, gasket, movement) are not
//! modelled yet.

const std = @import("std");

const V2 = [2]f32;
const V3 = [3]f32;
const tau: f32 = 2.0 * std.math.pi;

// ---------------------------------------------------------------- dimensions

const case_r: f32 = 20.5; // 41 mm case
const dial_z: f32 = 7.0; // top surface of the dial
const dial_r: f32 = 14.3;
const crystal_r: f32 = 15.0;
const lug_gap: f32 = 20.0; // strap width
const floor_z: f32 = -1.25;

// Emblem placement: the burst's focal point sits off-centre ("semicentric"),
// so the hands emerge from the gap between the two largest shards.
const emblem_focal_svg = V2{ 114.0, 266.0 };
const emblem_focal_mm = V2{ -7.4, -1.8 };
const emblem_scale: f32 = 0.058; // mm per SVG unit
const emblem_height: f32 = 0.6;

// The five shards of the semicentric emblem, in SVG coordinates (y down).
const shard_a = [_]V2{ .{ 115, 251.5 }, .{ 126, 248.5 }, .{ 250, 174.5 }, .{ 137, 194 }, .{ 116, 238 } };
const shard_b = [_]V2{ .{ 57, 262.5 }, .{ 87.5, 266 }, .{ 98.5, 263.5 }, .{ 64.5, 244 } };
const shard_c = [_]V2{ .{ 125.5, 265.5 }, .{ 160, 278 }, .{ 471, 256 }, .{ 147, 255.5 } };
const shard_d = [_]V2{ .{ 41, 303.5 }, .{ 65.5, 326.5 }, .{ 105.5, 290 }, .{ 105.5, 276.5 } };
const shard_e = [_]V2{ .{ 203.5, 336.5 }, .{ 129.5, 285.5 }, .{ 129.5, 294 }, .{ 168.5, 337.5 } };
const shards = [_][]const V2{ &shard_a, &shard_b, &shard_c, &shard_d, &shard_e };

// ---------------------------------------------------------------- mesh writer

const Mesh = struct {
    gpa: std.mem.Allocator,
    out: std.ArrayList(u8) = .empty,
    nv: u32 = 0,

    fn emit(m: *Mesh, comptime fmt: []const u8, args: anytype) void {
        var buf: [256]u8 = undefined;
        const s = std.fmt.bufPrint(&buf, fmt, args) catch unreachable;
        m.out.appendSlice(m.gpa, s) catch @panic("out of memory");
    }

    fn object(m: *Mesh, name: []const u8) void {
        m.emit("o {s}\n", .{name});
    }

    /// Adds a vertex and returns its 1-based OBJ index.
    fn v(m: *Mesh, p: V3) u32 {
        m.emit("v {d:.4} {d:.4} {d:.4}\n", .{ p[0], p[1], p[2] });
        m.nv += 1;
        return m.nv;
    }

    fn tri(m: *Mesh, a: u32, b: u32, c: u32) void {
        m.emit("f {d} {d} {d}\n", .{ a, b, c });
    }

    fn quad(m: *Mesh, a: u32, b: u32, c: u32, d: u32) void {
        m.emit("f {d} {d} {d} {d}\n", .{ a, b, c, d });
    }

    /// An n-gon over `count` consecutive vertices starting at `first`.
    fn ngon(m: *Mesh, first: u32, count: u32, reversed: bool) void {
        m.out.appendSlice(m.gpa, "f") catch @panic("out of memory");
        var i: u32 = 0;
        while (i < count) : (i += 1) {
            const k = if (reversed) count - 1 - i else i;
            m.emit(" {d}", .{first + k});
        }
        m.out.appendSlice(m.gpa, "\n") catch @panic("out of memory");
    }
};

// ---------------------------------------------------------------- primitives

const Axis = enum { z, x };

const Flute = struct {
    teeth: f32,
    depth: f32,
    /// Per-profile-point weight; 0 leaves the point round.
    weight: []const f32,
};

/// Revolves a closed (r, h) profile around an axis. `origin` is the point the
/// axis passes through; h runs along the axis.
fn lathe(m: *Mesh, profile: []const V2, segs: u32, axis: Axis, origin: V3, flute: ?Flute) void {
    const n: u32 = @intCast(profile.len);
    const base = m.nv + 1;
    var i: u32 = 0;
    while (i < segs) : (i += 1) {
        const t = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(segs));
        const c = @cos(t * tau);
        const s = @sin(t * tau);
        for (profile, 0..) |p, j| {
            var r = p[0];
            if (flute) |f| {
                const ph = t * f.teeth;
                const saw = @abs(2.0 * (ph - @floor(ph)) - 1.0); // 1 at tooth tip, 0 in the valley
                r -= f.depth * f.weight[j] * (1.0 - saw);
            }
            _ = m.v(switch (axis) {
                .z => .{ origin[0] + r * c, origin[1] + r * s, origin[2] + p[1] },
                .x => .{ origin[0] + p[1], origin[1] + r * c, origin[2] + r * s },
            });
        }
    }
    i = 0;
    while (i < segs) : (i += 1) {
        const inext = (i + 1) % segs;
        var j: u32 = 0;
        while (j < n) : (j += 1) {
            const jnext = (j + 1) % n;
            const r1 = profile[j][0];
            const r2 = profile[jnext][0];
            if (r1 == 0 and r2 == 0) continue; // edge lies on the axis
            const a = base + i * n + j;
            const b = base + inext * n + j;
            const c = base + inext * n + jnext;
            const d = base + i * n + jnext;
            if (r1 == 0) {
                m.tri(a, c, d);
            } else if (r2 == 0) {
                m.tri(a, b, c);
            } else {
                m.quad(a, b, c, d);
            }
        }
    }
}

/// Joins two polygons with the same vertex count and caps both ends.
fn loft(m: *Mesh, a: []const V3, b: []const V3) void {
    const n: u32 = @intCast(a.len);
    const fa = m.nv + 1;
    for (a) |p| _ = m.v(p);
    const fb = m.nv + 1;
    for (b) |p| _ = m.v(p);
    var i: u32 = 0;
    while (i < n) : (i += 1) {
        const k = (i + 1) % n;
        m.quad(fa + i, fa + k, fb + k, fb + i);
    }
    m.ngon(fa, n, true);
    m.ngon(fb, n, false);
}

/// A faceted "tent": a flat polygon at z0 rising to a smaller copy of itself,
/// pulled toward the centroid, at z0 + height.
fn tent(m: *Mesh, poly: []const V2, z0: f32, height: f32, keep: f32) void {
    var a: [16]V3 = undefined;
    var b: [16]V3 = undefined;
    var cx: f32 = 0;
    var cy: f32 = 0;
    for (poly) |p| {
        cx += p[0];
        cy += p[1];
    }
    const n: f32 = @floatFromInt(poly.len);
    cx /= n;
    cy /= n;
    for (poly, 0..) |p, i| {
        a[i] = .{ p[0], p[1], z0 };
        b[i] = .{ cx + (p[0] - cx) * keep, cy + (p[1] - cy) * keep, z0 + height };
    }
    loft(m, a[0..poly.len], b[0..poly.len]);
}

/// Rotates a point clockwise from 12 o'clock by `deg`, as a clock hand moves.
fn clock(p: V2, deg: f32) V2 {
    const a = deg * tau / 360.0;
    const c = @cos(a);
    const s = @sin(a);
    return .{ p[0] * c + p[1] * s, -p[0] * s + p[1] * c };
}

/// A kite-shaped faceted shard pointing outward along `deg`, from radius
/// `r0` (tail) to `r1` (tip), `w` wide at its shoulder.
fn kite(m: *Mesh, deg: f32, r0: f32, r1: f32, shoulder: f32, w: f32, z0: f32, height: f32) void {
    const pts = [_]V2{
        clock(.{ 0, r0 }, deg),
        clock(.{ w / 2.0, shoulder }, deg),
        clock(.{ 0, r1 }, deg),
        clock(.{ -w / 2.0, shoulder }, deg),
    };
    tent(m, &pts, z0, height, 0.35);
}

// ---------------------------------------------------------------- parts

fn caseBody(m: *Mesh) void {
    m.object("case_mid");
    lathe(m, &.{
        .{ 15.4, 0 },   .{ 18.6, 0 },   .{ 19.9, 0.9 }, .{ 20.5, 2.5 },
        .{ 20.5, 6.5 }, .{ 19.9, 8.2 }, .{ 15.4, 8.2 },
    }, 256, .z, .{ 0, 0, 0 }, null);

    m.object("case_back");
    lathe(m, &.{
        .{ 0, floor_z }, .{ 16.8, floor_z }, .{ 18.0, -0.5 }, .{ 18.0, 0.1 }, .{ 0, 0.1 },
    }, 256, .z, .{ 0, 0, 0 }, null);
}

/// "Palisade" bezel: a ring of 72 knife-edge flutes around the outer wall.
fn bezel(m: *Mesh) void {
    m.object("bezel");
    lathe(m, &.{
        .{ 19.7, 8.15 },       .{ 19.7, 9.55 },       .{ 18.3, 10.5 },      .{ crystal_r + 0.7, 10.75 },
        .{ crystal_r, 10.45 }, .{ crystal_r, 8.9 },   .{ 17.0, 8.15 },
    }, 432, .z, .{ 0, 0, 0 }, .{
        .teeth = 72,
        .depth = 0.42,
        .weight = &.{ 1, 1, 0.25, 0, 0, 0, 0 },
    });

    // Sloped inner flange between the crystal and the dial.
    m.object("rehaut");
    lathe(m, &.{
        .{ dial_r - 0.05, dial_z }, .{ crystal_r, 8.9 }, .{ crystal_r + 0.4, 8.9 }, .{ crystal_r + 0.4, dial_z },
    }, 256, .z, .{ 0, 0, 0 }, null);
}

fn crystal(m: *Mesh) void {
    m.object("crystal");
    const r = crystal_r - 0.02;
    lathe(m, &.{
        .{ 0, 8.95 }, .{ r, 8.95 }, .{ r, 10.5 }, .{ r - 0.5, 10.8 }, .{ 0, 10.8 },
    }, 256, .z, .{ 0, 0, 0 }, null);
}

fn crown(m: *Mesh) void {
    m.object("crown");
    lathe(m, &.{
        .{ 0, 19.8 }, .{ 2.3, 19.8 }, .{ 2.3, 20.9 }, .{ 3.5, 21.3 },
        .{ 3.5, 23.9 }, .{ 2.9, 24.5 }, .{ 0, 24.5 },
    }, 240, .x, .{ 0, 0, 4.3 }, .{
        .teeth = 20,
        .depth = 0.38,
        .weight = &.{ 0, 0, 0, 1, 1, 0.3, 0 },
    });
}

/// Four angular lugs. Each is a side profile whose outer face is lower than
/// its inner face, giving a sloped top facet that echoes the emblem shards.
fn lugs(m: *Mesh) void {
    m.object("lugs");
    const inner = [_]V2{ // (y, z) at the strap side
        .{ 12.0, 7.0 }, .{ 18.8, 6.6 }, .{ 24.2, 2.6 }, .{ 24.6, 0.4 }, .{ 23.2, -0.3 }, .{ 12.0, 0.1 },
    };
    const outer = [_]V2{ // (y, z) at the outside
        .{ 12.0, 4.6 }, .{ 17.2, 4.3 }, .{ 21.8, 1.9 }, .{ 22.2, 0.7 }, .{ 21.4, 0.1 }, .{ 12.0, 0.3 },
    };
    const x_in: f32 = lug_gap / 2.0 + 0.1;
    const x_out: f32 = x_in + 4.6;
    for ([_]f32{ 1, -1 }) |sx| {
        for ([_]f32{ 1, -1 }) |sy| {
            var a: [6]V3 = undefined;
            var b: [6]V3 = undefined;
            for (inner, 0..) |p, i| a[i] = .{ sx * x_in, sy * p[0], p[1] };
            for (outer, 0..) |p, i| b[i] = .{ sx * x_out, sy * p[0], p[1] };
            loft(m, &a, &b);
        }
    }
}

fn dial(m: *Mesh) void {
    m.object("dial");
    lathe(m, &.{ .{ 0, dial_z }, .{ dial_r, dial_z }, .{ dial_r, dial_z - 0.4 }, .{ 0, dial_z - 0.4 } }, 256, .z, .{ 0, 0, 0 }, null);
}

fn emblem(m: *Mesh) void {
    m.object("emblem");
    for (shards) |shard| {
        var pts: [8]V2 = undefined;
        for (shard, 0..) |p, i| {
            pts[i] = .{
                emblem_focal_mm[0] + (p[0] - emblem_focal_svg[0]) * emblem_scale,
                emblem_focal_mm[1] - (p[1] - emblem_focal_svg[1]) * emblem_scale,
            };
        }
        tent(m, pts[0..shard.len], dial_z, emblem_height, 0.45);
    }
}

/// Hour markers as small faceted shards. 3 o'clock is left out: the emblem's
/// long blade ends there and does that job.
fn markers(m: *Mesh) void {
    m.object("markers");
    var h: u32 = 0;
    while (h < 12) : (h += 1) {
        if (h == 3) continue;
        const deg = @as(f32, @floatFromInt(h)) * 30.0;
        const cardinal = h % 3 == 0;
        const r_in: f32 = if (cardinal) 11.0 else 11.7;
        const w: f32 = if (cardinal) 1.9 else 1.3;
        kite(m, deg, r_in, 13.8, 13.0, w, dial_z, 0.6);
    }
}

fn hands(m: *Mesh) void {
    const hour_deg: f32 = (10.0 + 9.0 / 60.0) * 30.0;
    const minute_deg: f32 = 9.0 * 6.0;
    const second_deg: f32 = 37.0 * 6.0;

    m.object("hand_hour");
    kite(m, hour_deg, -1.8, 7.8, 1.6, 1.9, dial_z + 0.75, 0.28);
    m.object("hand_minute");
    kite(m, minute_deg, -2.2, 12.2, 1.8, 1.5, dial_z + 1.08, 0.28);

    m.object("hand_second");
    const needle = [_]V2{
        clock(.{ -0.12, -3.4 }, second_deg), clock(.{ 0.12, -3.4 }, second_deg),
        clock(.{ 0.07, 13.0 }, second_deg),  clock(.{ -0.07, 13.0 }, second_deg),
    };
    tent(m, &needle, dial_z + 1.42, 0.1, 1.0);
    // Counterweight: a small shard on the tail of the seconds hand.
    kite(m, second_deg + 180.0, 2.0, 5.2, 4.3, 1.1, dial_z + 1.42, 0.1);

    m.object("hand_cap");
    lathe(m, &.{ .{ 0, dial_z }, .{ 0.95, dial_z }, .{ 0.95, dial_z + 1.6 }, .{ 0.7, dial_z + 1.75 }, .{ 0, dial_z + 1.75 } }, 64, .z, .{ 0, 0, 0 }, null);
}

/// Two strap halves lying flat on the surface.
fn strap(m: *Mesh) void {
    m.object("strap");
    const path = [_][3]f32{ // (y, z of centreline, thickness)
        .{ 20.6, 2.9, 3.0 }, .{ 23.2, 2.6, 3.0 }, .{ 26.5, 1.3, 2.8 }, .{ 30.0, 0.3, 2.6 },
        .{ 34.0, 0.05, 2.5 }, .{ 60.0, 0.0, 2.4 }, .{ 110.0, 0.0, 2.4 },
    };
    for ([_]f32{ 1, -1 }) |sy| {
        const base = m.nv + 1;
        for (path, 0..) |p, i| {
            const taper = @min(1.0, @as(f32, @floatFromInt(i)) / 5.0);
            const half = (lug_gap - 0.3 - 2.0 * taper) / 2.0;
            const zc = floor_z + p[2] / 2.0 + p[1];
            _ = m.v(.{ -half, sy * p[0], zc + p[2] / 2.0 });
            _ = m.v(.{ half, sy * p[0], zc + p[2] / 2.0 });
            _ = m.v(.{ half, sy * p[0], zc - p[2] / 2.0 });
            _ = m.v(.{ -half, sy * p[0], zc - p[2] / 2.0 });
        }
        var i: u32 = 0;
        while (i + 1 < path.len) : (i += 1) {
            var k: u32 = 0;
            while (k < 4) : (k += 1) {
                const knext = (k + 1) % 4;
                m.quad(base + i * 4 + k, base + i * 4 + knext, base + (i + 1) * 4 + knext, base + (i + 1) * 4 + k);
            }
        }
        m.ngon(base, 4, false);
        m.ngon(base + (@as(u32, path.len) - 1) * 4, 4, true);
    }
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    var mesh = Mesh{ .gpa = init.arena.allocator() };

    caseBody(&mesh);
    bezel(&mesh);
    lugs(&mesh);
    crown(&mesh);
    crystal(&mesh);
    dial(&mesh);
    emblem(&mesh);
    markers(&mesh);
    hands(&mesh);
    strap(&mesh);

    const cwd = std.Io.Dir.cwd();
    try cwd.createDirPath(io, "out");
    try cwd.writeFile(io, .{ .sub_path = "out/watch.obj", .data = mesh.out.items });
    std.debug.print("wrote out/watch.obj ({d} vertices)\n", .{mesh.nv});
}
