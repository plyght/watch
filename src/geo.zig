//! Shared mesh writer, primitives and emblem data for the watch generators.
//!
//! Units are millimetres. Z is up (the dial faces +Z), 12 o'clock is +Y and
//! the crown sits at +X.

const std = @import("std");

pub const V2 = [2]f32;
pub const V3 = [3]f32;
pub const tau: f32 = 2.0 * std.math.pi;
// The emblem, in its native SVG coordinates (y down), centred on the dial.
/// Middle of the emblem's bounding box and its focal point, in SVG units.
pub const emblem_box_centre = V2{ 256.0, 256.0 };
pub const emblem_focal = V2{ 114.0, 266.0 };

/// Maps an emblem point (SVG units, y down) to millimetres (y up), with
/// `origin` (SVG units) landing at (0, 0) and `scale` mm per SVG unit.
pub fn emblemPoint(p: V2, origin: V2, scale: f32) V2 {
    return .{ (p[0] - origin[0]) * scale, -(p[1] - origin[1]) * scale };
}
pub const shard_a = [_]V2{ .{ 115, 251.5 }, .{ 126, 248.5 }, .{ 250, 174.5 }, .{ 137, 194 }, .{ 116, 238 } };
pub const shard_b = [_]V2{ .{ 57, 262.5 }, .{ 87.5, 266 }, .{ 98.5, 263.5 }, .{ 64.5, 244 } };
pub const shard_c = [_]V2{ .{ 125.5, 265.5 }, .{ 160, 278 }, .{ 471, 256 }, .{ 147, 255.5 } };
pub const shard_d = [_]V2{ .{ 41, 303.5 }, .{ 65.5, 326.5 }, .{ 105.5, 290 }, .{ 105.5, 276.5 } };
pub const shard_e = [_]V2{ .{ 203.5, 336.5 }, .{ 129.5, 285.5 }, .{ 129.5, 294 }, .{ 168.5, 337.5 } };
pub const shards = [_][]const V2{ &shard_a, &shard_b, &shard_c, &shard_d, &shard_e };
// ---------------------------------------------------------------- mesh writer

pub const Mesh = struct {
    gpa: std.mem.Allocator,
    out: std.ArrayList(u8) = .empty,
    nv: u32 = 0,

    pub fn emit(m: *Mesh, comptime fmt: []const u8, args: anytype) void {
        var buf: [256]u8 = undefined;
        const s = std.fmt.bufPrint(&buf, fmt, args) catch unreachable;
        m.out.appendSlice(m.gpa, s) catch @panic("out of memory");
    }

    pub fn object(m: *Mesh, name: []const u8) void {
        m.emit("o {s}\n", .{name});
    }

    /// Adds a vertex and returns its 1-based OBJ index.
    pub fn v(m: *Mesh, p: V3) u32 {
        m.emit("v {d:.4} {d:.4} {d:.4}\n", .{ p[0], p[1], p[2] });
        m.nv += 1;
        return m.nv;
    }

    pub fn tri(m: *Mesh, a: u32, b: u32, c: u32) void {
        m.emit("f {d} {d} {d}\n", .{ a, b, c });
    }

    pub fn quad(m: *Mesh, a: u32, b: u32, c: u32, d: u32) void {
        m.emit("f {d} {d} {d} {d}\n", .{ a, b, c, d });
    }

    /// An n-gon over `count` consecutive vertices starting at `first`.
    pub fn ngon(m: *Mesh, first: u32, count: u32, reversed: bool) void {
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

pub const Axis = enum { z, x };

pub const Flute = struct {
    teeth: f32,
    depth: f32,
    /// Per-profile-point weight; 0 leaves the point round.
    weight: []const f32,
};

/// Revolves a closed (r, h) profile around an axis through `origin`.
pub fn lathe(m: *Mesh, profile: []const V2, segs: u32, axis: Axis, origin: V3, flute: ?Flute) void {
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
pub fn loft(m: *Mesh, a: []const V3, b: []const V3) void {
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
pub fn prism(m: *Mesh, poly: []const V2, z0: f32, height: f32, keep: f32) void {
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
pub fn extrudeX(m: *Mesh, profile: []const V2, x0: f32, x1: f32, sy: f32) void {
    var a: [16]V3 = undefined;
    var b: [16]V3 = undefined;
    for (profile, 0..) |p, i| {
        a[i] = .{ x0, sy * p[0], p[1] };
        b[i] = .{ x1, sy * p[0], p[1] };
    }
    loft(m, a[0..profile.len], b[0..profile.len]);
}

/// Rotates a point clockwise from 12 o'clock by `deg`, as a clock hand moves.
pub fn clock(p: V2, deg: f32) V2 {
    const a = deg * tau / 360.0;
    const c = @cos(a);
    const s = @sin(a);
    return .{ p[0] * c + p[1] * s, -p[0] * s + p[1] * c };
}

pub fn clockAll(comptime n: usize, pts: [n]V2, deg: f32) [n]V2 {
    var out: [n]V2 = undefined;
    for (pts, 0..) |p, i| out[i] = clock(p, deg);
    return out;
}

/// Moves every outline point inward along its averaged edge normal.
pub fn inset(src: []const V2, dst: []V2, amount: f32) void {
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


// ---------------------------------------------------------------- bracelets

/// A wrist cross-section in the Y-Z plane, as a superellipse
/// |y/half_width|^n + |(z - centre_z)/half_depth|^n = 1 through the strap's
/// centreline.
pub const Wrist = struct {
    half_width: f32,
    half_depth: f32,
    centre_z: f32,
    n: f32 = 2.6,
};

/// The centreline of a strap on the +Y side of the case, by arc length from
/// where it leaves the end link. Flat on a table without a wrist; otherwise it
/// blends onto the wrist curve over the first `blend` mm and follows it round
/// to the bottom of the wrist (y = 0).
pub const Band = struct {
    start: V2,
    wrist: ?Wrist,
    blend: f32 = 9.0,
    offset: V2 = .{ 0, 0 },
    theta0: f32 = 0,
    table: [1025]f32 = undefined, // arc length at evenly spaced angles
    total: f32 = 75.0,

    pub const Pose = struct { p: V2, t: V2 };

    pub fn init(start: V2, wrist: ?Wrist) Band {
        var b = Band{ .start = start, .wrist = wrist };
        const w = wrist orelse return b;
        const ratio = @min(start[0] / w.half_width, 0.999);
        b.theta0 = std.math.acos(std.math.pow(f32, ratio, w.n / 2.0));
        const p0 = b.curve(b.theta0);
        b.offset = .{ start[0] - p0[0], start[1] - p0[1] };
        b.table[0] = 0;
        var prev = p0;
        for (1..b.table.len) |i| {
            const p = b.curve(b.angle(@as(f32, @floatFromInt(i)) / 1024.0));
            b.table[i] = b.table[i - 1] + @sqrt((p[0] - prev[0]) * (p[0] - prev[0]) + (p[1] - prev[1]) * (p[1] - prev[1]));
            prev = p;
        }
        b.total = b.table[b.table.len - 1];
        return b;
    }

    fn angle(b: Band, f: f32) f32 {
        return b.theta0 + f * (-tau / 4.0 - b.theta0);
    }

    fn spow(x: f32, e: f32) f32 {
        return std.math.sign(x) * std.math.pow(f32, @abs(x), e);
    }

    fn curve(b: Band, theta: f32) V2 {
        const w = b.wrist.?;
        return .{ w.half_width * spow(@cos(theta), 2.0 / w.n), w.centre_z + w.half_depth * spow(@sin(theta), 2.0 / w.n) };
    }

    fn point(b: Band, s: f32) V2 {
        if (b.wrist == null) return .{ b.start[0] + s, b.start[1] };
        const sc = std.math.clamp(s, 0, b.total);
        var lo: usize = 0;
        var hi: usize = b.table.len - 1;
        while (hi - lo > 1) {
            const mid = (lo + hi) / 2;
            if (b.table[mid] < sc) lo = mid else hi = mid;
        }
        const span = b.table[hi] - b.table[lo];
        const f = (@as(f32, @floatFromInt(lo)) + if (span > 0) (sc - b.table[lo]) / span else 0) / 1024.0;
        const p = b.curve(b.angle(f));
        const k = std.math.clamp(1.0 - s / b.blend, 0, 1);
        const fade = k * k * (3.0 - 2.0 * k);
        return .{ p[0] + b.offset[0] * fade, p[1] + b.offset[1] * fade };
    }

    pub fn at(b: Band, s: f32) Pose {
        const p = b.point(s);
        const q = b.point(s + 0.05);
        const r = b.point(s - 0.05);
        var t = V2{ q[0] - r[0], q[1] - r[1] };
        const len = @sqrt(t[0] * t[0] + t[1] * t[1]);
        t = .{ t[0] / len, t[1] / len };
        return .{ .p = p, .t = t };
    }

    /// A point at arc length `s` plus `w` along the outward normal (up, for a
    /// flat band), in (y, z).
    pub fn place(b: Band, s: f32, w: f32) V2 {
        const pose = b.at(s);
        return .{ pose.p[0] - pose.t[1] * w, pose.p[1] + pose.t[0] * w };
    }
};

/// Sweeps a closed cross-section along a band from s0 to s1, bending with it.
/// `section` is in (x, w): x across the strap, w along the band's normal.
/// `sy` = 1 for the 12 o'clock side, -1 to mirror to the 6 o'clock side.
pub fn sweep(m: *Mesh, band: Band, s0: f32, s1: f32, section: []const V2, sy: f32) void {
    const n: u32 = @intCast(section.len);
    const steps: u32 = @max(2, @as(u32, @intFromFloat(@ceil((s1 - s0) / 0.5))));
    const first = m.nv + 1;
    var i: u32 = 0;
    while (i <= steps) : (i += 1) {
        const s = s0 + (s1 - s0) * @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(steps));
        for (section) |q| {
            const yz = band.place(s, q[1]);
            _ = m.v(.{ q[0], sy * yz[0], yz[1] });
        }
    }
    i = 0;
    while (i < steps) : (i += 1) {
        var j: u32 = 0;
        while (j < n) : (j += 1) {
            const k = (j + 1) % n;
            const a = first + i * n + j;
            const b = first + i * n + k;
            const c = first + (i + 1) * n + k;
            const d = first + (i + 1) * n + j;
            if (sy > 0) m.quad(a, b, c, d) else m.quad(a, d, c, b);
        }
    }
    m.ngon(first, n, sy > 0);
    m.ngon(first + steps * n, n, sy < 0);
}

/// A rounded-rectangle cross-section for sweep(): `half` across, `h` tall
/// (from w = 0 to w = h), corners cut by `r`.
pub fn roundedSection(buf: *[8]V2, x0: f32, x1: f32, w0: f32, w1: f32, r: f32) []const V2 {
    buf.* = .{
        .{ x0, w0 + r }, .{ x0 + r, w0 }, .{ x1 - r, w0 }, .{ x1, w0 + r },
        .{ x1, w1 - r }, .{ x1 - r, w1 }, .{ x0 + r, w1 }, .{ x0, w1 - r },
    };
    return buf[0..];
}

// ---------------------------------------------------------------- engraved surfaces

/// A slab whose top surface is a displaced grid. `ctx.top(u, v)` gives the
/// top point for u, v in [0, 1]; `ctx.bottom(u, v)` the matching point on the
/// underside; `ctx.keep(u, v)` false punches a hole (cells are dropped, so
/// hole edges are stepped at the grid pitch: cover them with a rim).
/// With `solid` the underside is a full grid too and the border gets walls
/// (watertight, for printing); without it only the top surface is emitted,
/// which is all a render needs when the edges are hidden under other parts.
pub fn slab(m: *Mesh, nx: u32, ny: u32, solid: bool, ctx: anytype) void {
    const row = nx + 1;
    const top0 = m.nv + 1;
    var j: u32 = 0;
    while (j <= ny) : (j += 1) {
        var i: u32 = 0;
        while (i <= nx) : (i += 1) {
            _ = m.v(ctx.top(@as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(nx)), @as(f32, @floatFromInt(j)) / @as(f32, @floatFromInt(ny))));
        }
    }
    j = 0;
    while (j < ny) : (j += 1) {
        var i: u32 = 0;
        while (i < nx) : (i += 1) {
            const u = (@as(f32, @floatFromInt(i)) + 0.5) / @as(f32, @floatFromInt(nx));
            const v = (@as(f32, @floatFromInt(j)) + 0.5) / @as(f32, @floatFromInt(ny));
            if (!ctx.keep(u, v)) continue;
            const a = j * row + i;
            m.quad(top0 + a, top0 + a + 1, top0 + a + row + 1, top0 + a + row);
        }
    }

    // Walk the outer border once, top and bottom, and join them with walls.
    var border: [4096][2]u32 = undefined; // grid (i, j) of each border point
    var n: usize = 0;
    var i: u32 = 0;
    while (i < nx) : (i += 1) { border[n] = .{ i, 0 }; n += 1; }
    j = 0;
    while (j < ny) : (j += 1) { border[n] = .{ nx, j }; n += 1; }
    i = nx;
    while (i > 0) : (i -= 1) { border[n] = .{ i, ny }; n += 1; }
    j = ny;
    while (j > 0) : (j -= 1) { border[n] = .{ 0, j }; n += 1; }

    if (solid) {
        const bot0 = m.nv + 1;
        j = 0;
        while (j <= ny) : (j += 1) {
            i = 0;
            while (i <= nx) : (i += 1) {
                _ = m.v(ctx.bottom(@as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(nx)), @as(f32, @floatFromInt(j)) / @as(f32, @floatFromInt(ny))));
            }
        }
        j = 0;
        while (j < ny) : (j += 1) {
            i = 0;
            while (i < nx) : (i += 1) {
                const u = (@as(f32, @floatFromInt(i)) + 0.5) / @as(f32, @floatFromInt(nx));
                const v = (@as(f32, @floatFromInt(j)) + 0.5) / @as(f32, @floatFromInt(ny));
                if (!ctx.keep(u, v)) continue;
                const a = j * row + i;
                m.quad(bot0 + a, bot0 + a + row, bot0 + a + row + 1, bot0 + a + 1);
            }
        }
        for (0..n) |k| {
            const p = border[k];
            const q = border[(k + 1) % n];
            m.quad(top0 + p[1] * row + p[0], bot0 + p[1] * row + p[0], bot0 + q[1] * row + q[0], top0 + q[1] * row + q[0]);
        }
    }
}
