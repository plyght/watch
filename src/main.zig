//! Diver watch with the semicentric emblem cut through the dial.
//! Parametric geometry generator: writes out/watch.obj.
//!
//! Units are millimetres. Z is up (the dial faces +Z), 12 o'clock is +Y and
//! the crown sits at +X. Each part is a named OBJ object so the renderer can
//! assign materials by name. Objects named `cut_*` are cutters: the renderer
//! subtracts them from the dial.
//!
//! This is render geometry: parts overlap instead of being unioned, and the
//! functional seats (gaskets, movement holder, threads) are not modelled.

const std = @import("std");

const V2 = [2]f32;
const V3 = [3]f32;
const tau: f32 = 2.0 * std.math.pi;

// ---------------------------------------------------------------- dimensions

const case_r: f32 = 20.0; // 40 mm case
const case_top: f32 = 7.0; // top of the mid-case, where the bezel sits
const lug_gap: f32 = 20.0;
const lug_tip_y: f32 = 24.5; // 49 mm lug to lug
const floor_z: f32 = -0.3;

const dial_r: f32 = 14.6;
const dial_z: f32 = 7.4; // top surface of the dial
const dial_thickness: f32 = 0.6;
const crystal_r: f32 = 15.5;

// The emblem, in its native SVG coordinates (y down), centred on the dial.
const emblem_centre = V2{ 256.0, 256.0 };
const emblem_scale: f32 = dial_r * 1.8 / 430.0;
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

/// Revolves a closed (r, h) profile around an axis through `origin`.
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
                const saw = @abs(2.0 * (ph - @floor(ph)) - 1.0);
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

/// A flat polygon at z0 rising by `height` to a copy of itself scaled toward
/// its centroid by `keep` (1.0 gives straight walls).
fn prism(m: *Mesh, poly: []const V2, z0: f32, height: f32, keep: f32) void {
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

/// Extrudes a (y, z) profile along X from x0 to x1.
fn extrudeX(m: *Mesh, profile: []const V2, x0: f32, x1: f32, sy: f32) void {
    var a: [16]V3 = undefined;
    var b: [16]V3 = undefined;
    for (profile, 0..) |p, i| {
        a[i] = .{ x0, sy * p[0], p[1] };
        b[i] = .{ x1, sy * p[0], p[1] };
    }
    loft(m, a[0..profile.len], b[0..profile.len]);
}

/// Rotates a point clockwise from 12 o'clock by `deg`, as a clock hand moves.
fn clock(p: V2, deg: f32) V2 {
    const a = deg * tau / 360.0;
    const c = @cos(a);
    const s = @sin(a);
    return .{ p[0] * c + p[1] * s, -p[0] * s + p[1] * c };
}

fn clockAll(comptime n: usize, pts: [n]V2, deg: f32) [n]V2 {
    var out: [n]V2 = undefined;
    for (pts, 0..) |p, i| out[i] = clock(p, deg);
    return out;
}

// ---------------------------------------------------------------- case

/// How far the top of the case has dropped at distance |y| from the centre:
/// flat over the dial, curving down along the lugs.
fn lugDrop(y: f32) f32 {
    const start: f32 = 11.0;
    const ay = @abs(y);
    if (ay <= start) return 0;
    const t = (ay - start) / (lug_tip_y - start);
    return 4.3 * std.math.pow(f32, t, 1.7);
}

/// Crown guards: the case swells gently outward around the crown at 3 o'clock.
fn crownSwell(p: V2) f32 {
    const reach: f32 = 6.5;
    if (p[0] < 0 or @abs(p[1]) >= reach) return 0;
    const c = @cos(p[1] / reach * tau / 4.0);
    return 1.9 * c * c;
}

/// Top-view outline of the case with its four lugs, counter-clockwise.
fn caseOutline(buf: []V2) usize {
    // One quadrant, from 12 o'clock round to 3 o'clock.
    var q: [64]V2 = undefined;
    var n: usize = 0;
    const x_in: f32 = lug_gap / 2.0 + 0.1;
    const a_in = std.math.asin(x_in / case_r);
    const a_out: f32 = 62.0 * tau / 360.0;
    var i: usize = 0;
    while (i < 8) : (i += 1) { // arc between the lugs
        const a = a_in * @as(f32, @floatFromInt(i)) / 8.0;
        q[n] = .{ case_r * @sin(a), case_r * @cos(a) };
        n += 1;
    }
    q[n] = .{ x_in, case_r * @cos(a_in) };
    q[n + 1] = .{ x_in, lug_tip_y - 0.7 };
    q[n + 2] = .{ x_in + 0.5, lug_tip_y };
    q[n + 3] = .{ x_in + 2.4, lug_tip_y };
    n += 4;
    // Outer edge of the lug sweeping back into the case.
    const p0 = V2{ x_in + 3.2, lug_tip_y - 0.6 };
    const p1 = V2{ 15.6, 16.5 };
    const p2 = V2{ case_r * @sin(a_out), case_r * @cos(a_out) };
    i = 0;
    while (i < 12) : (i += 1) {
        const t = @as(f32, @floatFromInt(i)) / 12.0;
        const u = 1.0 - t;
        q[n] = .{ u * u * p0[0] + 2 * u * t * p1[0] + t * t * p2[0], u * u * p0[1] + 2 * u * t * p1[1] + t * t * p2[1] };
        n += 1;
    }
    i = 0;
    while (i < 20) : (i += 1) { // arc down to 3 o'clock
        const a = a_out + (tau / 4.0 - a_out) * @as(f32, @floatFromInt(i)) / 20.0;
        q[n] = .{ case_r * @sin(a), case_r * @cos(a) };
        n += 1;
    }
    // Mirror the quadrant round the case. Clockwise order here; reversed below.
    var total: usize = 0;
    for (q[0..n]) |p| {
        buf[total] = p;
        total += 1;
    }
    buf[total] = .{ case_r, 0 };
    total += 1;
    i = n;
    while (i > 1) : (i -= 1) {
        buf[total] = .{ q[i - 1][0], -q[i - 1][1] };
        total += 1;
    }
    for (q[0..n]) |p| {
        buf[total] = .{ -p[0], -p[1] };
        total += 1;
    }
    buf[total] = .{ -case_r, 0 };
    total += 1;
    i = n;
    while (i > 1) : (i -= 1) {
        buf[total] = .{ -q[i - 1][0], q[i - 1][1] };
        total += 1;
    }
    for (buf[0..total]) |*p| p[0] += crownSwell(p.*);
    std.mem.reverse(V2, buf[0..total]);
    return total;
}

/// Moves every outline point inward along its averaged edge normal.
fn inset(src: []const V2, dst: []V2, amount: f32) void {
    const n = src.len;
    for (src, 0..) |p, i| {
        const a = src[(i + n - 1) % n];
        const b = src[(i + 1) % n];
        var nx = -(b[1] - a[1]);
        var ny = b[0] - a[0];
        const len = @sqrt(nx * nx + ny * ny);
        nx /= len;
        ny /= len;
        dst[i] = .{ p[0] + nx * amount, p[1] + ny * amount };
    }
}

fn caseBody(m: *Mesh) void {
    m.object("case_mid");
    var outline: [256]V2 = undefined;
    const n = caseOutline(&outline);
    var chamfer: [256]V2 = undefined;
    inset(outline[0..n], chamfer[0..n], 0.75);
    const count: u32 = @intCast(n);

    // Five rings: bottom chamfer, wall bottom, wall top, top chamfer, and an
    // inner ring under the bezel that closes the top.
    const first = m.nv + 1;
    for (chamfer[0..n]) |p| _ = m.v(.{ p[0], p[1], 0 });
    for (outline[0..n]) |p| _ = m.v(.{ p[0], p[1], 0.8 });
    for (outline[0..n]) |p| _ = m.v(.{ p[0], p[1], case_top - lugDrop(p[1]) - 0.75 });
    for (chamfer[0..n]) |p| _ = m.v(.{ p[0], p[1], case_top - lugDrop(p[1]) });
    for (outline[0..n]) |p| {
        const r = @sqrt(p[0] * p[0] + p[1] * p[1]);
        const k = @min(1.0, 18.0 / r);
        _ = m.v(.{ p[0] * k, p[1] * k, case_top });
    }
    var ring: u32 = 0;
    while (ring < 4) : (ring += 1) {
        var i: u32 = 0;
        while (i < count) : (i += 1) {
            const k = (i + 1) % count;
            m.quad(first + ring * count + i, first + ring * count + k, first + (ring + 1) * count + k, first + (ring + 1) * count + i);
        }
    }
    m.ngon(first, count, true);

    m.object("case_back");
    lathe(m, &.{ .{ 0, floor_z }, .{ 16.5, floor_z }, .{ 17.6, 0.05 }, .{ 0, 0.05 } }, 192, .z, .{ 0, 0, 0 }, null);
}

fn crown(m: *Mesh) void {
    m.object("crown");
    lathe(m, &.{
        .{ 0, 20.0 },   .{ 2.2, 20.0 }, .{ 2.2, 22.5 }, .{ 3.3, 22.9 },
        .{ 3.3, 25.6 }, .{ 2.8, 26.1 }, .{ 0, 26.1 },
    }, 240, .x, .{ -1.2, 0, 3.5 }, .{
        .teeth = 24,
        .depth = 0.32,
        .weight = &.{ 0, 0, 0, 1, 1, 0.3, 0 },
    });
}

fn bezel(m: *Mesh) void {
    // Rotating bezel with a coin edge.
    m.object("bezel");
    lathe(m, &.{
        .{ 20.35, 7.05 },    .{ 20.35, 9.1 }, .{ 19.6, 9.85 },  .{ 19.15, 9.85 },
        .{ 19.15, 9.5 },     .{ 16.0, 9.5 },  .{ 16.0, 10.05 }, .{ crystal_r, 10.05 },
        .{ crystal_r, 8.9 }, .{ 17.5, 7.05 },
    }, 720, .z, .{ 0, 0, 0 }, .{
        .teeth = 120,
        .depth = 0.3,
        .weight = &.{ 1, 1, 0.4, 0, 0, 0, 0, 0, 0, 0 },
    });

    // Black insert sitting in the bezel's channel.
    m.object("insert");
    lathe(m, &.{ .{ 16.02, 9.4 }, .{ 19.13, 9.4 }, .{ 19.13, 9.82 }, .{ 16.02, 9.98 } }, 256, .z, .{ 0, 0, 0 }, null);

    // Luminous triangle at 12 on the insert.
    m.object("insert_pip");
    prism(m, &.{ .{ -1.25, 18.75 }, .{ 0, 16.5 }, .{ 1.25, 18.75 } }, 9.8, 0.2, 0.95);

    // Sloped flange between the crystal and the dial.
    m.object("rehaut");
    lathe(m, &.{
        .{ dial_r - 0.05, dial_z }, .{ crystal_r, 8.9 }, .{ crystal_r + 0.4, 8.9 }, .{ crystal_r + 0.4, dial_z },
    }, 256, .z, .{ 0, 0, 0 }, null);

    m.object("crystal");
    const r = crystal_r - 0.02;
    lathe(m, &.{ .{ 0, 8.95 }, .{ r, 8.95 }, .{ r, 10.15 }, .{ r - 0.35, 10.4 }, .{ 0, 10.4 } }, 256, .z, .{ 0, 0, 0 }, null);
}

// ---------------------------------------------------------------- dial

fn emblemPoint(p: V2) V2 {
    return .{ (p[0] - emblem_centre[0]) * emblem_scale, -(p[1] - emblem_centre[1]) * emblem_scale };
}

fn dial(m: *Mesh) void {
    m.object("dial");
    lathe(m, &.{
        .{ 0, dial_z }, .{ dial_r, dial_z }, .{ dial_r, dial_z - dial_thickness }, .{ 0, dial_z - dial_thickness },
    }, 256, .z, .{ 0, 0, 0 }, null);

    // One cutter per shard, passing right through the dial plate.
    m.object("cut_emblem");
    for (shards) |shard| {
        var pts: [8]V2 = undefined;
        for (shard, 0..) |p, i| pts[i] = emblemPoint(p);
        prism(m, pts[0..shard.len], dial_z - dial_thickness - 0.3, dial_thickness + 0.6, 1.0);
    }

    // Printed minute track.
    m.object("print");
    var i: u32 = 0;
    while (i < 60) : (i += 1) {
        if (i % 5 == 0) continue;
        const deg = @as(f32, @floatFromInt(i)) * 6.0;
        const tick = clockAll(4, .{ .{ -0.06, 13.6 }, .{ 0.06, 13.6 }, .{ 0.06, 14.3 }, .{ -0.06, 14.3 } }, deg);
        prism(m, &tick, dial_z, 0.012, 1.0);
    }
}

/// Applied hour markers shaped like shards of the emblem: a polished steel
/// surround filled with lume. 3 and 9 are left out because the emblem reaches
/// the edge there.
fn markers(m: *Mesh) void {
    var h: u32 = 0;
    while (h < 12) : (h += 1) {
        if (h == 3 or h == 9) continue;
        const deg = @as(f32, @floatFromInt(h)) * 30.0;
        const inner: f32 = if (h == 0) 9.6 else if (h == 6) 10.2 else 11.0;
        const w: f32 = if (h == 0) 1.7 else 0.95;
        const outline = clockAll(4, .{ .{ -w, 13.7 }, .{ w, 13.7 }, .{ w * 0.35, inner }, .{ -w * 0.45, inner + 0.9 } }, deg);
        m.object("marker_steel");
        prism(m, &outline, dial_z, 0.4, 0.97);
        m.object("marker_lume");
        prism(m, &outline, dial_z + 0.38, 0.1, 0.66);
    }
}

/// Fine polished lines running on from each shard's tip to the edge of the
/// dial, as if the dial had cracked outward from the emblem.
fn fractures(m: *Mesh) void {
    m.object("fracture");
    const focal = emblemPoint(.{ 114.0, 266.0 });
    for (shards) |shard| {
        var best: f32 = 0;
        var tip = V2{ 0, 0 };
        for (shard) |sp| {
            const p = emblemPoint(sp);
            const d = (p[0] - focal[0]) * (p[0] - focal[0]) + (p[1] - focal[1]) * (p[1] - focal[1]);
            if (d > best) {
                best = d;
                tip = p;
            }
        }
        const len = @sqrt(best);
        const dx = (tip[0] - focal[0]) / len;
        const dy = (tip[1] - focal[1]) / len;
        // Walk outward from the tip until the line reaches the minute track.
        var reach: f32 = 0;
        while (reach < 40.0) : (reach += 0.05) {
            const x = tip[0] + dx * reach;
            const y = tip[1] + dy * reach;
            if (x * x + y * y > 13.4 * 13.4) break;
        }
        if (reach < 0.3) continue;
        const hw: f32 = 0.045;
        prism(m, &.{
            .{ tip[0] - dy * hw, tip[1] + dx * hw },
            .{ tip[0] + dy * hw, tip[1] - dx * hw },
            .{ tip[0] + dx * reach + dy * hw, tip[1] + dy * reach - dx * hw },
            .{ tip[0] + dx * reach - dy * hw, tip[1] + dy * reach + dx * hw },
        }, dial_z, 0.015, 1.0);
    }
}

fn swordHand(m: *Mesh, deg: f32, len: f32, w: f32, z: f32) void {
    m.object("hand_steel");
    const body = clockAll(5, .{
        .{ -0.28 * w, -1.9 }, .{ 0.28 * w, -1.9 }, .{ 0.5 * w, 0.22 * len }, .{ 0, len }, .{ -0.5 * w, 0.22 * len },
    }, deg);
    prism(m, &body, z, 0.2, 0.96);
    m.object("hand_lume");
    const fill = clockAll(5, .{
        .{ -0.16 * w, 0.14 * len }, .{ 0.16 * w, 0.14 * len }, .{ 0.3 * w, 0.26 * len }, .{ 0, 0.86 * len }, .{ -0.3 * w, 0.26 * len },
    }, deg);
    prism(m, &fill, z + 0.19, 0.04, 1.0);
}

fn hands(m: *Mesh) void {
    const hour_deg: f32 = (10.0 + 9.0 / 60.0) * 30.0;
    const minute_deg: f32 = 9.0 * 6.0;
    const second_deg: f32 = 36.0 * 6.0;

    swordHand(m, hour_deg, 7.6, 2.3, dial_z + 0.7);
    swordHand(m, minute_deg, 12.2, 1.8, dial_z + 1.0);

    m.object("hand_accent");
    const needle = clockAll(4, .{ .{ -0.11, -3.4 }, .{ 0.11, -3.4 }, .{ 0.06, 13.2 }, .{ -0.06, 13.2 } }, second_deg);
    prism(m, &needle, dial_z + 1.3, 0.1, 1.0);
    const dot = clock(.{ 0, 9.0 }, second_deg);
    lathe(m, &.{ .{ 0, 0 }, .{ 0.62, 0 }, .{ 0.62, 0.1 }, .{ 0, 0.1 } }, 32, .z, .{ dot[0], dot[1], dial_z + 1.3 }, null);
    m.object("hand_lume");
    lathe(m, &.{ .{ 0, 0 }, .{ 0.42, 0 }, .{ 0.42, 0.03 }, .{ 0, 0.03 } }, 32, .z, .{ dot[0], dot[1], dial_z + 1.4 }, null);

    m.object("hand_steel");
    lathe(m, &.{ .{ 0, dial_z - 0.5 }, .{ 0.9, dial_z - 0.5 }, .{ 0.9, dial_z + 1.45 }, .{ 0.7, dial_z + 1.6 }, .{ 0, dial_z + 1.6 } }, 64, .z, .{ 0, 0, 0 }, null);
}

// ---------------------------------------------------------------- movement

fn gear(m: *Mesh, name: []const u8, c: V2, r: f32, teeth: u32, z0: f32) void {
    m.object(name);
    lathe(m, &.{ .{ r * 0.74, 0 }, .{ r, 0 }, .{ r, 0.3 }, .{ r * 0.74, 0.3 } }, teeth * 6, .z, .{ c[0], c[1], z0 }, .{
        .teeth = @floatFromInt(teeth),
        .depth = r * 0.1,
        .weight = &.{ 0, 1, 1, 0 },
    });
    lathe(m, &.{ .{ 0, 0 }, .{ r * 0.24, 0 }, .{ r * 0.24, 0.34 }, .{ 0, 0.34 } }, 32, .z, .{ c[0], c[1], z0 }, null);
    var i: u32 = 0;
    while (i < 5) : (i += 1) {
        const deg = 72.0 * @as(f32, @floatFromInt(i));
        var spoke = clockAll(4, .{ .{ -r * 0.07, 0 }, .{ r * 0.07, 0 }, .{ r * 0.07, r * 0.8 }, .{ -r * 0.07, r * 0.8 } }, deg);
        for (&spoke) |*p| p.* = .{ p[0] + c[0], p[1] + c[1] };
        prism(m, &spoke, z0, 0.3, 1.0);
    }
    m.object("mov_ruby");
    lathe(m, &.{ .{ 0, 0 }, .{ r * 0.1, 0 }, .{ r * 0.1, 0.4 }, .{ 0, 0.4 } }, 24, .z, .{ c[0], c[1], z0 }, null);
}

/// A simplified mechanism under the dial: enough to read as gears and jewels
/// through the emblem windows. Not a real calibre.
fn movement(m: *Mesh) void {
    const top: f32 = dial_z - dial_thickness - 0.45;
    m.object("mov_plate");
    lathe(m, &.{ .{ 0, top - 1.0 }, .{ dial_r + 0.3, top - 1.0 }, .{ dial_r + 0.3, top }, .{ 0, top } }, 128, .z, .{ 0, 0, 0 }, null);

    gear(m, "mov_bright", .{ -7.4, 3.2 }, 5.2, 40, top + 0.02);
    gear(m, "mov_steel", .{ -10.2, -3.0 }, 3.4, 26, top + 0.28);
    gear(m, "mov_bright", .{ -1.6, -3.6 }, 4.0, 30, top + 0.02);
    gear(m, "mov_steel", .{ 4.6, 0.6 }, 3.6, 28, top + 0.28);
    gear(m, "mov_bright", .{ 10.2, -0.6 }, 2.6, 20, top + 0.02);
    gear(m, "mov_steel", .{ -3.6, 4.6 }, 2.4, 18, top + 0.3);
}

// ---------------------------------------------------------------- bracelet

/// Three-link bracelet lying flat on the surface on both sides of the case.
fn bracelet(m: *Mesh) void {
    const link_h: f32 = 3.0;
    const zc: f32 = floor_z + 0.1 + link_h / 2.0;
    const pitch: f32 = 5.0;
    // Rounded link cross-section in (y, z), centred on the link.
    const a: f32 = pitch / 2.0 - 0.12;
    const b: f32 = link_h / 2.0;
    const c: f32 = 0.9;
    const section = [_]V2{
        .{ -a, -b + c }, .{ -a + c, -b }, .{ a - c, -b }, .{ a, -b + c },
        .{ a, b - c },   .{ a - c, b },   .{ -a + c, b }, .{ -a, b - c },
    };

    for ([_]f32{ 1, -1 }) |sy| {
        // End link filling the gap between the lugs.
        m.object("bracelet");
        extrudeX(m, &.{ .{ 16.0, 0.2 }, .{ 21.4, 0.2 }, .{ 22.0, 0.9 }, .{ 22.0, 2.6 }, .{ 20.2, 4.0 }, .{ 16.0, 6.4 } }, -9.85, 9.85, sy);

        var row: u32 = 0;
        while (row < 12) : (row += 1) {
            const y = 24.6 + pitch * @as(f32, @floatFromInt(row));
            const taper = @min(1.0, @as(f32, @floatFromInt(row)) / 6.0);
            const half = 9.9 - 1.0 * taper;
            const mid = half * 0.42;
            var outer: [8]V2 = undefined;
            var inner: [8]V2 = undefined;
            for (section, 0..) |p, i| {
                outer[i] = .{ y + p[0], zc + p[1] };
                inner[i] = .{ y + pitch / 2.0 + p[0], zc + p[1] };
            }
            m.object("bracelet");
            extrudeX(m, &outer, -half, -mid - 0.08, sy);
            extrudeX(m, &outer, mid + 0.08, half, sy);
            m.object("bracelet_mid");
            extrudeX(m, &inner, -mid, mid, sy);
        }
    }
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    var mesh = Mesh{ .gpa = init.arena.allocator() };

    caseBody(&mesh);
    crown(&mesh);
    bezel(&mesh);
    movement(&mesh);
    dial(&mesh);
    markers(&mesh);
    fractures(&mesh);
    hands(&mesh);
    bracelet(&mesh);

    const cwd = std.Io.Dir.cwd();
    try cwd.createDirPath(io, "out");
    try cwd.writeFile(io, .{ .sub_path = "out/watch.obj", .data = mesh.out.items });
    std.debug.print("wrote out/watch.obj ({d} vertices)\n", .{mesh.nv});
}
