//! The "chamber" family, two watches on one case and bracelet:
//!
//!   study:  a study of the reference revolver-cylinder watch (aged gunmetal,
//!           rope bezel, scroll-engraved dial with six chamber windows over a
//!           silver hour ring, a brass cartridge head in the sixth chamber,
//!           scroll-engraved bracelet plaques).
//!   impact: the semicentric take, same build and materials: a twisted
//!           faceted bezel, a dial fractured from an off-centre impact point
//!           with the emblem bursting out of it in gold, and fracture-engraved
//!           bracelet plaques.
//!
//! Engraving is real displaced geometry, so it would print or cast as-is.

const std = @import("std");
const geo = @import("geo.zig");
const patterns = @import("patterns.zig");
const pgm = @import("pgm.zig");

const V2 = geo.V2;
const V3 = geo.V3;
const tau = geo.tau;
const Mesh = geo.Mesh;
const lathe = geo.lathe;
const loft = geo.loft;
const prism = geo.prism;
const extrudeX = geo.extrudeX;
const clock = geo.clock;
const clockAll = geo.clockAll;

pub const Variant = enum { study, impact };

// ---------------------------------------------------------------- dimensions

const case_r: f32 = 21.0; // 42 mm
const mid_top: f32 = 5.8; // top of the mid-case
// Measured from the reference photo against its 43 mm case (see design/measure.md).
const band_half: f32 = 10.35; // bracelet half-width at the case (20.7 mm)
const lug_inner: f32 = 10.45; // slim horn lugs flank the bracelet
const lug_outer: f32 = 13.6;
const lug_tip: f32 = 22.9;
const plaque_half: f32 = 4.75; // engraved centre column (9.5 mm)
const floor_z: f32 = -0.3;

const bezel_R: f32 = 19.7; // centre of the rope's tube
const bezel_r: f32 = 1.75; // tube radius
const bezel_z: f32 = mid_top + 1.5;

const crystal_r: f32 = 17.9;
const dial_r: f32 = 18.0;
const dial_z: f32 = 6.6; // dial ground; relief rises above it
const relief: f32 = 0.35;
const dial_under: f32 = 0.4;

// The cylinder artwork is scaled in from the photo's proportions so it sits
// clear of the bezel with a black margin all round (client's call).
const art: f32 = 0.92;
const chamber_ring: f32 = 12.0 * art;
const chamber_hole: f32 = 4.3 * art;
const bullet_pos = V2{ 0, -11.25 * art };
const bullet_hole: f32 = 4.0 * art;
const bullet_rim: f32 = 4.45 * art;
const silver_inner: f32 = 9.6 * art;

// The reference photo reads about 1:38:03.
const hour_deg: f32 = (1.0 + 38.0 / 60.0) * 30.0;
const minute_deg: f32 = 38.0 * 6.0;
const second_deg: f32 = 3.0 * 6.0;

// ---------------------------------------------------------------- case

fn caseBody(m: *Mesh, variant: Variant) void {
    m.object("antique");
    caseSolid(m);

    // Seat under the bezel, and the flange that holds the crystal.
    lathe(m, &.{ .{ 17.9, mid_top - 0.05 }, .{ 20.9, mid_top - 0.05 }, .{ 20.9, mid_top + 0.35 }, .{ 17.9, mid_top + 0.35 } }, 256, .z, .{ 0, 0, 0 }, null);
    lathe(m, &.{ .{ 17.9, 7.7 }, .{ 18.4, 7.7 }, .{ 18.4, 8.55 }, .{ 17.9, 8.55 } }, 256, .z, .{ 0, 0, 0 }, null);
    // Black flange ring at the dial edge; the black ground between it and
    // the cylinder's lobes is the padding round the cylinder.
    m.object("rehaut");
    lathe(m, &.{
        .{ 17.55, dial_z - 0.1 }, .{ 17.55, dial_z + relief + 0.12 }, .{ 17.62, dial_z + relief + 0.18 },
        .{ 17.9, 7.45 },          .{ 18.1, 7.5 },                      .{ 18.1, dial_z - 0.1 },
    }, 256, .z, .{ 0, 0, 0 }, null);

    m.object("case_back");
    lathe(m, &.{ .{ 0, floor_z }, .{ 17.5, floor_z }, .{ 18.6, 0.05 }, .{ 0, 0.05 } }, 192, .z, .{ 0, 0, 0 }, null);

    // Big fluted crown, like a cylinder pin.
    m.object("antique");
    lathe(m, &.{
        .{ 0, 20.4 }, .{ 1.6, 20.4 }, .{ 1.6, 20.9 }, .{ 3.5, 21.0 }, .{ 3.65, 21.3 }, .{ 3.65, 24.5 }, .{ 3.3, 24.9 }, .{ 0, 24.9 },
    }, 360, .x, .{ 0, 0, 2.9 }, .{
        .teeth = 12,
        .depth = 0.55,
        .weight = &.{ 0, 0, 0, 0.7, 1, 1, 0.4, 0 },
    });
    if (variant == .impact) {
        m.object("gold");
        lathe(m, &.{ .{ 0, 24.85 }, .{ 2.3, 24.85 }, .{ 2.3, 25.0 }, .{ 2.1, 25.1 }, .{ 0, 25.1 } }, 64, .x, .{ 0, 0, 2.9 }, null);
    }

    m.object("crystal");
    lathe(m, &.{
        .{ 0, 7.75 }, .{ crystal_r, 7.75 }, .{ crystal_r, 8.4 }, .{ crystal_r - 0.3, 8.6 }, .{ 0, 8.6 },
    }, 256, .z, .{ 0, 0, 0 }, null);
}

// ---------------------------------------------------------------- case shape
//
// The mid-case and its four lugs are one solid, like the machined original:
// a single top-view outline (case circle, lug faces and the tangent fillets
// between them) swept with one vertical profile, so every surface flows into
// the next with no seams.

const fillet_in: f32 = 0.9; // between the case and a lug's inner face
const taper_r: f32 = 60.0; // the lug's outer face: one concave arc from the tip into the case
const lug_outer_tip: f32 = 12.9; // outer face at the tip (lugs taper toward the bracelet)
const tip_round: f32 = 0.7; // lug tip corners, in plan
const edge_round: f32 = 0.8; // the rounded top edge all the way round

fn arc(buf: []V2, n: *usize, c: V2, r: f32, a0: f32, a1: f32, steps: u32) void {
    var i: u32 = 1;
    while (i <= steps) : (i += 1) {
        const a = a0 + (a1 - a0) * @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(steps));
        buf[n.*] = .{ c[0] + r * @cos(a), c[1] + r * @sin(a) };
        n.* += 1;
    }
}

/// One quadrant of the outline, clockwise from 12 o'clock to 3 o'clock.
fn quadrant(q: []V2) usize {
    const R = case_r;
    var n: usize = 0;
    // Inner fillet: tangent to the lug's inner face and externally to the case.
    const ci = V2{ lug_inner - fillet_in, @sqrt((R + fillet_in) * (R + fillet_in) - (lug_inner - fillet_in) * (lug_inner - fillet_in)) };
    const ti = V2{ ci[0] * R / (R + fillet_in), ci[1] * R / (R + fillet_in) };
    // Outer face: the arc of radius taper_r through the tip corner T that
    // touches the case circle tangentially. Its centre C is taper_r from T
    // and R + taper_r from the origin (circle-circle intersection).
    const t = V2{ lug_outer_tip, lug_tip - tip_round };
    const d = @sqrt(t[0] * t[0] + t[1] * t[1]);
    const r1 = R + taper_r;
    const along = (d * d + r1 * r1 - taper_r * taper_r) / (2.0 * d);
    const h = @sqrt(r1 * r1 - along * along);
    const co = V2{ t[0] * along / d + h * t[1] / d, t[1] * along / d - h * t[0] / d };
    const to = V2{ co[0] * R / r1, co[1] * R / r1 };

    // Case circle from 12 o'clock to the inner fillet.
    const a_ti = std.math.atan2(ti[0], ti[1]);
    var i: u32 = 0;
    while (i < 24) : (i += 1) {
        const a = a_ti * @as(f32, @floatFromInt(i)) / 24.0;
        q[n] = .{ R * @sin(a), R * @cos(a) };
        n += 1;
    }
    q[n] = ti;
    n += 1;
    arc(q, &n, ci, fillet_in, std.math.atan2(ti[1] - ci[1], ti[0] - ci[0]), 0, 10);
    // Up the inner face, round the tip, down the outer face.
    q[n] = .{ lug_inner, lug_tip - tip_round };
    n += 1;
    arc(q, &n, .{ lug_inner + tip_round, lug_tip - tip_round }, tip_round, std.math.pi, std.math.pi / 2.0, 6);
    q[n] = .{ lug_outer_tip - tip_round, lug_tip };
    n += 1;
    arc(q, &n, .{ lug_outer_tip - tip_round, lug_tip - tip_round }, tip_round, std.math.pi / 2.0, 0, 6);
    // Down the tapering outer face into the case.
    arc(q, &n, co, taper_r, std.math.atan2(t[1] - co[1], t[0] - co[0]), std.math.atan2(to[1] - co[1], to[0] - co[0]), 40);
    // Case circle on to 3 o'clock.
    const a_to = std.math.atan2(to[0], to[1]);
    i = 1;
    while (i < 28) : (i += 1) {
        const a = a_to + (tau / 4.0 - a_to) * @as(f32, @floatFromInt(i)) / 28.0;
        q[n] = .{ R * @sin(a), R * @cos(a) };
        n += 1;
    }
    return n;
}

/// The whole outline, counter-clockwise, mirrored from one quadrant.
fn caseOutline(buf: []V2) usize {
    var q: [256]V2 = undefined;
    const n = quadrant(&q);
    var total: usize = 0;
    for (q[0..n]) |p| {
        buf[total] = p;
        total += 1;
    }
    buf[total] = .{ case_r, 0 };
    total += 1;
    var i: usize = n;
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
    std.mem.reverse(V2, buf[0..total]);
    return total;
}

/// Height of the case top at a point of the outline: flat over the case,
/// sloping down along each lug toward its tip.
fn caseTop(p: V2) f32 {
    const along = std.math.clamp((@abs(p[1]) - 17.6) / (lug_tip - 17.6), 0, 1);
    const on_lug = std.math.clamp((@abs(p[0]) - (lug_inner - 1.3)) / 1.2, 0, 1);
    return mid_top - 1.5 * along * on_lug;
}

fn caseSolid(m: *Mesh) void {
    var outline: [1024]V2 = undefined;
    const n = caseOutline(&outline);
    const count: u32 = @intCast(n);
    var ring: [1024]V2 = undefined;
    const first = m.nv + 1;

    // Bottom chamfer, then the straight wall.
    geo.inset(outline[0..n], ring[0..n], 0.45);
    for (ring[0..n]) |p| _ = m.v(.{ p[0], p[1], 0 });
    for (outline[0..n]) |p| _ = m.v(.{ p[0], p[1], 0.5 });
    // Rounded top edge: a quarter circle of radius edge_round.
    const steps: u32 = 5;
    var k: u32 = 0;
    while (k <= steps) : (k += 1) {
        const th = (tau / 4.0) * @as(f32, @floatFromInt(k)) / @as(f32, @floatFromInt(steps));
        geo.inset(outline[0..n], ring[0..n], edge_round * (1.0 - @cos(th)));
        for (ring[0..n], outline[0..n]) |p, o| _ = m.v(.{ p[0], p[1], caseTop(o) - edge_round * (1.0 - @sin(th)) });
    }
    // Top surface running in under the bezel. Over the lugs it runs straight
    // back along the lug (so the lug top is one clean slope); elsewhere it
    // runs radially in.
    for (outline[0..n]) |p| {
        const r = @sqrt(p[0] * p[0] + p[1] * p[1]);
        if (@abs(p[0]) < 16.5 and @abs(p[1]) > 15.5) {
            const x = p[0];
            _ = m.v(.{ x, std.math.sign(p[1]) * @sqrt(17.9 * 17.9 - x * x), mid_top });
        } else {
            const s = @min(1.0, 17.9 / r);
            _ = m.v(.{ p[0] * s, p[1] * s, mid_top });
        }
    }
    const rings: u32 = 2 + steps + 1 + 1;
    var r: u32 = 0;
    while (r + 1 < rings) : (r += 1) {
        var i: u32 = 0;
        while (i < count) : (i += 1) {
            const j = (i + 1) % count;
            m.quad(first + r * count + i, first + r * count + j, first + (r + 1) * count + j, first + (r + 1) * count + i);
        }
    }
    m.ngon(first, count, true);
}

/// A torus whose tube cross-section is given in polar form by `radius(phi, psi)`.
fn torus(m: *Mesh, nphi: u32, npsi: u32, ctx: anytype) void {
    const first = m.nv + 1;
    var i: u32 = 0;
    while (i < nphi) : (i += 1) {
        const phi = tau * @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(nphi));
        var j: u32 = 0;
        while (j < npsi) : (j += 1) {
            const p = ctx.point(phi, j);
            const ring = bezel_R + p[0];
            _ = m.v(.{ ring * @cos(phi), ring * @sin(phi), bezel_z + p[1] });
        }
    }
    i = 0;
    while (i < nphi) : (i += 1) {
        const inext = (i + 1) % nphi;
        var j: u32 = 0;
        while (j < npsi) : (j += 1) {
            const jnext = (j + 1) % npsi;
            m.quad(first + i * npsi + j, first + inext * npsi + j, first + inext * npsi + jnext, first + i * npsi + jnext);
        }
    }
}

/// Three-strand rope: 88 rounded strands around the ring, separated by
/// narrow deep grooves. Returns (radial, vertical) offsets in the tube.
const Rope = struct {
    const npsi: u32 = 40;
    fn point(_: Rope, phi: f32, j: u32) V2 {
        const psi = tau * @as(f32, @floatFromInt(j)) / @as(f32, @floatFromInt(npsi));
        const lobe = @sqrt(@abs(@cos(1.5 * psi - 44.0 * phi)));
        const r = bezel_r * (0.76 + 0.24 * lobe);
        return .{ r * @cos(psi), r * @sin(psi) };
    }
};

/// A hexagonal bar twisted round the ring: sharp helical facets, the rope
/// reworked in the emblem's angular language.
const TwistedHex = struct {
    const per_side: u32 = 5;
    const npsi: u32 = 6 * per_side;
    fn point(_: TwistedHex, phi: f32, j: u32) V2 {
        const twist = phi * 28.0 / 6.0; // the hexagon turns 60 degrees 28 times round the ring
        const side = j / per_side;
        const f = @as(f32, @floatFromInt(j % per_side)) / @as(f32, @floatFromInt(per_side));
        const a0 = twist + tau * @as(f32, @floatFromInt(side)) / 6.0;
        const a1 = a0 + tau / 6.0;
        const r = bezel_r * 1.04;
        const c0 = V2{ r * @cos(a0), r * @sin(a0) };
        const c1 = V2{ r * @cos(a1), r * @sin(a1) };
        return .{ c0[0] + (c1[0] - c0[0]) * f, c0[1] + (c1[1] - c0[1]) * f };
    }
};

fn bezel(m: *Mesh, variant: Variant) void {
    m.object("antique_bezel");
    switch (variant) {
        .study => torus(m, 88 * 14, Rope.npsi, Rope{}),
        .impact => torus(m, 28 * 30, TwistedHex.npsi, TwistedHex{}),
    }
}

// ---------------------------------------------------------------- dial

fn chamberCentre(i: u32) V2 {
    return clock(.{ 0, chamber_ring }, 60.0 * @as(f32, @floatFromInt(i)));
}

const DialSlab = struct {
    map: patterns.Heightmap,
    variant: Variant,
    hole_centre: V2,
    hole_r: f32,

    fn xy(u: f32, v: f32) V2 {
        return .{ (2.0 * u - 1.0) * dial_r, (1.0 - 2.0 * v) * dial_r };
    }
    pub fn top(s: DialSlab, u: f32, v: f32) V3 {
        const p = xy(u, v);
        const k: f32 = if (s.variant == .study) art else 1.0;
        return .{ p[0], p[1], dial_z + relief * s.map.sample(0.5 + (u - 0.5) / k, 0.5 + (v - 0.5) / k) };
    }
    pub fn bottom(_: DialSlab, u: f32, v: f32) V3 {
        const p = xy(u, v);
        return .{ p[0], p[1], dial_z - dial_under };
    }
    pub fn keep(s: DialSlab, u: f32, v: f32) bool {
        const p = xy(u, v);
        if (p[0] * p[0] + p[1] * p[1] > dial_r * dial_r) return false;
        switch (s.variant) {
            .study => {
                for (0..6) |i| {
                    const c = if (i == 3) bullet_pos else chamberCentre(@intCast(i));
                    const r = if (i == 3) bullet_hole else chamber_hole;
                    const dx = p[0] - c[0];
                    const dy = p[1] - c[1];
                    if (dx * dx + dy * dy < r * r) return false;
                }
            },
            .impact => {
                const dx = p[0] - s.hole_centre[0];
                const dy = p[1] - s.hole_centre[1];
                if (dx * dx + dy * dy < s.hole_r * s.hole_r) return false;
            },
        }
        return true;
    }
};

/// A polished collar round a hole in the dial, hiding the stepped grid edge.
fn collar(m: *Mesh, c: V2, r: f32, width: f32, top: f32) void {
    lathe(m, &.{
        .{ r - 0.02, dial_z - dial_under }, .{ r + width, dial_z - dial_under }, .{ r + width, top - 0.05 },
        .{ r + width - 0.08, top },         .{ r + 0.06, top },                  .{ r - 0.02, top - 0.08 },
    }, 128, .z, .{ c[0], c[1], 0 }, null);
}

fn studyDial(m: *Mesh, gpa: std.mem.Allocator, io: std.Io) !void {
    // Relief lifted from the reference photo itself (tools/extract_reference.py):
    // the scalloped barrel plate, chamber rings and filigree over black ground.
    const map = try pgm.load(gpa, io, "assets/reference/derived/dial-height.pgm");

    m.object("dial_plate");
    geo.slab(m, 900, 900, false, DialSlab{ .map = map, .variant = .study, .hole_centre = .{ 0, 0 }, .hole_r = 0 });

    // Thin bore walls hiding the stepped hole edges.
    m.object("antique");
    for (0..6) |i| {
        if (i == 3) continue;
        collar(m, chamberCentre(@intCast(i)), chamber_hole, 0.1, dial_z + relief * 0.95);
    }

    // The hour ring seen through the chambers: silver outside, black inside.
    m.object("silver_disc");
    lathe(m, &.{ .{ silver_inner, 5.9 }, .{ 17.4, 5.9 }, .{ 17.4, 6.15 }, .{ silver_inner, 6.15 } }, 256, .z, .{ 0, 0, 0 }, null);
    m.object("black_disc");
    lathe(m, &.{ .{ 0, 5.85 }, .{ silver_inner + 0.02, 5.85 }, .{ silver_inner + 0.02, 6.1 }, .{ 0, 6.1 } }, 128, .z, .{ 0, 0, 0 }, null);
    m.object("print");
    for (0..6) |i| {
        if (i == 3) continue;
        const deg = 60.0 * @as(f32, @floatFromInt(i));
        prism(m, &clockAll(4, .{ .{ -0.15, 11.3 * art }, .{ 0.15, 11.3 * art }, .{ 0.15, 13.6 * art }, .{ -0.15, 13.6 * art } }, deg), 6.15, 0.02, 1.0);
    }

    // Small polished batons at 3 and 9, between the chambers.
    m.object("polished");
    for ([_]f32{ 90, 270 }) |deg| {
        prism(m, &clockAll(4, .{ .{ -0.22, 11.7 * art }, .{ 0.22, 11.7 * art }, .{ 0.22, 14.0 * art }, .{ -0.22, 14.0 * art } }, deg), dial_z + relief - 0.05, 0.3, 0.9);
    }

    // Brass cartridge head sitting in the sixth chamber, with its own collar.
    m.object("antique");
    collar(m, bullet_pos, bullet_rim + 0.02, 0.35, dial_z + relief + 0.05);
    m.object("brass");
    lathe(m, &.{
        .{ 0, 5.0 },                   .{ bullet_hole - 0.05, 5.0 },  .{ bullet_hole - 0.05, dial_z - 0.1 }, .{ bullet_rim, dial_z - 0.05 },
        .{ bullet_rim, dial_z + 0.5 }, .{ bullet_rim - 0.18, dial_z + 0.62 }, .{ 1.75, dial_z + 0.62 }, .{ 1.75, dial_z + 0.56 }, .{ 0, dial_z + 0.56 },
    }, 192, .z, .{ bullet_pos[0], bullet_pos[1], 0 }, null);
    m.object("primer");
    lathe(m, &.{ .{ 0, dial_z + 0.5 }, .{ 1.6, dial_z + 0.5 }, .{ 1.6, dial_z + 0.6 }, .{ 1.4, dial_z + 0.64 }, .{ 0, dial_z + 0.64 } }, 96, .z, .{ bullet_pos[0], bullet_pos[1], 0 }, null);
}

fn impactDial(m: *Mesh, gpa: std.mem.Allocator) !void {
    // The emblem's focal point is the impact, off-centre toward 8 o'clock.
    const focal_mm = V2{ -5.6, -2.6 };
    const scale: f32 = 0.046;
    const impact_uv = [2]f32{ (focal_mm[0] / dial_r + 1.0) / 2.0, (1.0 - focal_mm[1] / dial_r) / 2.0 };
    const map = try patterns.cracks(gpa, 1024, 1024, impact_uv, 11);
    const hole_r: f32 = 1.55;

    m.object("engraved");
    geo.slab(m, 640, 640, false, DialSlab{ .map = map, .variant = .impact, .hole_centre = focal_mm, .hole_r = hole_r });

    // Gold emblem bursting out of the impact.
    m.object("gold");
    for (geo.shards) |shard| {
        var pts: [8]V2 = undefined;
        for (shard, 0..) |p, i| {
            const q = geo.emblemPoint(p, geo.emblem_focal, scale);
            pts[i] = .{ q[0] + focal_mm[0], q[1] + focal_mm[1] };
        }
        prism(m, pts[0..shard.len], dial_z + relief - 0.05, 0.5, 0.88);
    }
    collar(m, focal_mm, hole_r, 0.35, dial_z + relief + 0.2);

    // Through the hole: the balance wheel, beating.
    m.object("mov_plate");
    lathe(m, &.{ .{ 0, 4.9 }, .{ 3.2, 4.9 }, .{ 3.2, 5.3 }, .{ 0, 5.3 } }, 64, .z, .{ focal_mm[0], focal_mm[1], 0 }, null);
    m.object("mov_steel");
    lathe(m, &.{ .{ 1.05, 5.75 }, .{ 1.35, 5.75 }, .{ 1.35, 5.95 }, .{ 1.05, 5.95 } }, 64, .z, .{ focal_mm[0], focal_mm[1], 0 }, null);
    for (0..3) |k| {
        const arm = clockAll(4, .{ .{ -0.07, 0 }, .{ 0.07, 0 }, .{ 0.07, 1.2 }, .{ -0.07, 1.2 } }, 120.0 * @as(f32, @floatFromInt(k)) + 20.0);
        var moved: [4]V2 = undefined;
        for (arm, 0..) |p, i| moved[i] = .{ p[0] + focal_mm[0], p[1] + focal_mm[1] };
        prism(m, &moved, 5.8, 0.1, 1.0);
    }
    m.object("mov_ruby");
    lathe(m, &.{ .{ 0, 5.6 }, .{ 0.22, 5.6 }, .{ 0.22, 6.0 }, .{ 0, 6.0 } }, 24, .z, .{ focal_mm[0], focal_mm[1], 0 }, null);

    // Brushed silver chapter ring with polished shard markers.
    m.object("silver_disc");
    lathe(m, &.{ .{ 15.0, dial_z }, .{ 17.5, dial_z }, .{ 17.5, dial_z + 0.32 }, .{ 15.0, dial_z + 0.32 } }, 256, .z, .{ 0, 0, 0 }, null);
    m.object("print_dark");
    var i: u32 = 0;
    while (i < 60) : (i += 1) {
        const deg = 6.0 * @as(f32, @floatFromInt(i));
        const long: f32 = if (i % 5 == 0) 1.1 else 0.55;
        const w: f32 = if (i % 5 == 0) 0.11 else 0.06;
        prism(m, &clockAll(4, .{ .{ -w, 17.0 - long }, .{ w, 17.0 - long }, .{ w, 17.0 }, .{ -w, 17.0 } }, deg), dial_z + 0.32, 0.015, 1.0);
    }
    m.object("polished");
    var h: u32 = 0;
    while (h < 12) : (h += 1) {
        const deg = 30.0 * @as(f32, @floatFromInt(h));
        const w: f32 = if (h == 0) 1.4 else 0.75;
        const inner: f32 = if (h == 0) 11.4 else 12.2;
        prism(m, &clockAll(4, .{ .{ -w, 14.6 }, .{ w, 14.6 }, .{ w * 0.3, inner }, .{ -w * 0.4, inner + 0.7 } }, deg), dial_z + relief - 0.05, 0.4, 0.94);
    }
}

// ---------------------------------------------------------------- hands

/// Straight sword hand: a dark steel frame round a full-length lume plot,
/// with a short tail.
fn swordHand(m: *Mesh, deg: f32, len: f32, w: f32, z: f32) void {
    m.object("hand_frame");
    prism(m, &clockAll(6, .{
        .{ -0.32 * w, -2.0 }, .{ 0.32 * w, -2.0 }, .{ 0.5 * w, 1.4 }, .{ 0.5 * w, len - 0.9 * w }, .{ 0, len }, .{ -0.5 * w, len - 0.9 * w },
    }, deg), z, 0.2, 0.97);
    m.object("hand_lume");
    prism(m, &clockAll(5, .{
        .{ -0.36 * w, 2.0 }, .{ 0.36 * w, 2.0 }, .{ 0.36 * w, len - 1.0 * w }, .{ 0, len - 0.35 * w }, .{ -0.36 * w, len - 1.0 * w },
    }, deg), z + 0.19, 0.04, 1.0);
}

fn bladeHand(m: *Mesh, deg: f32, len: f32, w: f32, z: f32) void {
    m.object("hand_steel");
    prism(m, &clockAll(5, .{
        .{ -0.28 * w, -1.9 }, .{ 0.28 * w, -1.9 }, .{ 0.5 * w, 0.22 * len }, .{ 0, len }, .{ -0.5 * w, 0.22 * len },
    }, deg), z, 0.2, 0.96);
    m.object("hand_lume");
    prism(m, &clockAll(5, .{
        .{ -0.16 * w, 0.14 * len }, .{ 0.16 * w, 0.14 * len }, .{ 0.3 * w, 0.26 * len }, .{ 0, 0.86 * len }, .{ -0.3 * w, 0.26 * len },
    }, deg), z + 0.19, 0.04, 1.0);
}

fn hands(m: *Mesh, variant: Variant) void {
    const z0 = dial_z + relief + 0.25;
    switch (variant) {
        .study => {
            swordHand(m, hour_deg, 8.4, 1.8, z0);
            swordHand(m, minute_deg, 13.4, 1.6, z0 + 0.3);
            m.object("hand_frame");
            prism(m, &clockAll(4, .{ .{ -0.07, -3.0 }, .{ 0.07, -3.0 }, .{ 0.04, 12.5 }, .{ -0.04, 12.5 } }, second_deg), z0 + 0.62, 0.08, 1.0);
        },
        .impact => {
            bladeHand(m, hour_deg, 8.4, 2.1, z0 + 0.25);
            bladeHand(m, minute_deg, 13.6, 1.6, z0 + 0.55);
        },
    }
    m.object("hand_steel");
    lathe(m, &.{ .{ 0, dial_z }, .{ 0.85, dial_z }, .{ 0.85, z0 + 0.85 }, .{ 0.65, z0 + 1.0 }, .{ 0, z0 + 1.0 } }, 64, .z, .{ 0, 0, 0 }, null);
}

// ---------------------------------------------------------------- bracelet

const link_h: f32 = 3.2;
const pitch: f32 = 7.0;

/// One engraved centre plaque bent along the band.
const Plaque = struct {
    band: geo.Band,
    map: patterns.Heightmap,
    s0: f32,
    s1: f32,
    half: f32,
    sy: f32,

    fn at(p: Plaque, u: f32, v: f32, w: f32) V3 {
        const yz = p.band.place(p.s0 + (p.s1 - p.s0) * v, w);
        return .{ (2.0 * u - 1.0) * p.half, p.sy * yz[0], yz[1] };
    }
    pub fn top(p: Plaque, u: f32, v: f32) V3 {
        // Edges roll off so the plaque reads as a domed, cast link.
        const eu = @min(u, 1.0 - u) * 2.0;
        const ev = @min(v, 1.0 - v) * 2.0;
        const edge = @min(1.0, @min(eu * 6.0, ev * 5.0));
        const dome = @sqrt(@max(0.0, 1.0 - (1.0 - edge) * (1.0 - edge)));
        const h = link_h / 2.0 - 0.75 + 0.55 * dome + 0.2 * p.map.sample(u, v) * edge;
        return p.at(u, v, h);
    }
    pub fn bottom(p: Plaque, u: f32, v: f32) V3 {
        return p.at(u, v, -link_h / 2.0);
    }
    pub fn keep(_: Plaque, _: f32, _: f32) bool {
        return true;
    }
};

fn bracelet(m: *Mesh, gpa: std.mem.Allocator, io: std.Io, variant: Variant, wrist: ?geo.Wrist) !void {
    const band = geo.Band.init(.{ 21.3, floor_z + 0.1 + link_h / 2.0 }, wrist);
    const rows: u32 = if (wrist != null) @intFromFloat(@floor((band.total - 4.0) / pitch)) else 9;
    var buf: [8]V2 = undefined;

    // A few engraving variations, cycled down the bracelet.
    var maps: [3]patterns.Heightmap = undefined;
    for (&maps, 0..) |*map, k| {
        map.* = switch (variant) {
            // The reference's own engraved plaques, lifted from the photo.
            .study => try pgm.load(gpa, io, switch (k) {
                0 => "assets/reference/derived/plaque-1.pgm",
                1 => "assets/reference/derived/plaque-2.pgm",
                else => "assets/reference/derived/plaque-3.pgm",
            }),
            .impact => try patterns.cracks(gpa, 512, 290, .{ 0.15 + 0.35 * @as(f32, @floatFromInt(k)), if (k % 2 == 0) -0.25 else 1.25 }, 201 + k),
        };
    }

    for ([_]f32{ 1, -1 }) |sy| {
        // Solid end link between the lugs.
        m.object("antique");
        extrudeX(m, &.{ .{ 15.5, 0.0 }, .{ 21.0, 0.0 }, .{ 21.3, 0.4 }, .{ 21.3, 3.1 }, .{ 20.8, 3.7 }, .{ 18.5, 4.6 }, .{ 15.5, 5.0 } }, -lug_inner + 0.05, lug_inner - 0.05, sy);

        var row: u32 = 0;
        while (row < rows) : (row += 1) {
            const s = pitch * @as(f32, @floatFromInt(row));
            const taper = @min(1.0, @as(f32, @floatFromInt(row)) / 5.0);
            const half = band_half - 1.0 * taper;
            const mid = plaque_half - 0.25 * taper;
            m.object("antique");
            geo.sweep(m, band, s + 0.12, s + pitch - 0.12, geo.roundedSection(&buf, -half, -mid - 0.1, -link_h / 2.0, link_h / 2.0, 0.6), sy);
            geo.sweep(m, band, s + 0.12, s + pitch - 0.12, geo.roundedSection(&buf, mid + 0.1, half, -link_h / 2.0, link_h / 2.0, 0.6), sy);
            // Short plain centre bar, then the engraved plaque.
            geo.sweep(m, band, s + 0.12, s + 1.4, geo.roundedSection(&buf, -mid, mid, -link_h / 2.0 + 0.1, link_h / 2.0 - 0.2, 0.45), sy);
            m.object("engraved");
            geo.slab(m, 200, 90, false, Plaque{ .band = band, .map = maps[row % maps.len], .s0 = s + 1.55, .s1 = s + pitch - 0.12, .half = mid - 0.05, .sy = sy });
        }
        if (wrist != null) {
            m.object("antique");
            geo.sweep(m, band, band.total - 14.0, band.total, geo.roundedSection(&buf, -9.0, 9.0, -link_h / 2.0, link_h / 2.0 + 0.4, 0.9), sy);
        }
    }
}

// ---------------------------------------------------------------- build

pub fn build(m: *Mesh, gpa: std.mem.Allocator, io: std.Io, variant: Variant, wrist: ?geo.Wrist) !void {
    caseBody(m, variant);
    bezel(m, variant);
    switch (variant) {
        .study => try studyDial(m, gpa, io),
        .impact => try impactDial(m, gpa),
    }
    hands(m, variant);
    try bracelet(m, gpa, io, variant, wrist);
}
