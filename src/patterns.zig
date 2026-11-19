//! Procedural engraving heightmaps for watch parts.
//!
//! * `scrollwork`   – raised acanthus scrollwork filling a rectangle.
//! * `scrollRadial` – the same scroll language with dihedral symmetry for a round dial,
//!                    flowing around circular "clear" windows framed by raised rims.
//! * `cracks`       – a bullet-impact spider-web fracture with tilted facets and V-grooves.
//!
//! Heights are 0..1 (0 = ground / deepest, 1 = top of relief). All maps are row-major.
//!
//! How the scrolls are made: every stroke is a polyline of samples (position, half-width,
//! heading). Scrolls follow a clothoid lead-in that runs into a logarithmic spiral (radius of
//! curvature shrinking exponentially with turning angle), so they curl inward; their width
//! tapers toward the eye. Strokes "grow" from each other: every accepted scroll spawns
//! counter-curling child scrolls and acanthus leaf barbs from its outer flank, and smaller
//! sprigs into its bay. An occupancy grid (each stroke stamped dilated by a gap) keeps strokes
//! from merging. When the growth front stalls, a distance transform of the free space finds the
//! biggest holes and new scrolls / leaves are branched toward them from the nearest stroke.
//! Finally the strokes are rasterised as rounded ridges with max-blending.

const std = @import("std");
const Allocator = std.mem.Allocator;

const tau: f32 = 2.0 * std.math.pi;

pub const Heightmap = struct {
    w: usize,
    h: usize,
    data: []f32, // row-major, values 0..1 (0 = background/deepest, 1 = top of relief)

    /// Bilinear sample; u,v in [0,1] (u across width, v down height); clamps outside.
    pub fn sample(self: Heightmap, u: f32, v: f32) f32 {
        const wm: f32 = @floatFromInt(self.w - 1);
        const hm: f32 = @floatFromInt(self.h - 1);
        const fx = std.math.clamp(u, 0.0, 1.0) * wm;
        const fy = std.math.clamp(v, 0.0, 1.0) * hm;
        const x0: usize = @intFromFloat(@floor(fx));
        const y0: usize = @intFromFloat(@floor(fy));
        const x1 = @min(x0 + 1, self.w - 1);
        const y1 = @min(y0 + 1, self.h - 1);
        const tx = fx - @as(f32, @floatFromInt(x0));
        const ty = fy - @as(f32, @floatFromInt(y0));
        const a = self.data[y0 * self.w + x0];
        const b = self.data[y0 * self.w + x1];
        const c = self.data[y1 * self.w + x0];
        const d = self.data[y1 * self.w + x1];
        return (a * (1 - tx) + b * tx) * (1 - ty) + (c * (1 - tx) + d * tx) * ty;
    }

    /// Value at an integer pixel.
    pub fn at(self: Heightmap, x: usize, y: usize) f32 {
        return self.data[y * self.w + x];
    }

    pub fn deinit(self: Heightmap, gpa: Allocator) void {
        gpa.free(self.data);
    }
};

/// Extra knobs for the scroll generators. The required API functions use the defaults.
pub const ScrollOptions = struct {
    /// Height of the punched/stippled ground texture between strokes (0 disables it).
    stipple: f32 = 0.035,
    /// Multiplies the size of the main scrolls (and with it stroke widths and gaps).
    scale: f32 = 1.0,
    /// Multiplies the ground gap kept between neighbouring strokes.
    gap: f32 = 1.0,
    /// Depth of the engraver's shading cuts on top of strokes (0 disables them).
    shading: f32 = 0.22,
};

/// Raised acanthus-style scrollwork filling a w×h rectangle (aspect = w/h), like hand-engraved
/// scrolls on vintage firearms / western bracelets: C- and S-scrolls built from tapering
/// spiral strokes that curl inward, with leaf barbs/sprigs branching off, densely but not
/// uniformly filling the area. Deterministic for a given seed.
pub fn scrollwork(gpa: Allocator, w: usize, h: usize, seed: u64) !Heightmap {
    return scrollworkOpts(gpa, w, h, seed, .{});
}

pub fn scrollworkOpts(gpa: Allocator, w: usize, h: usize, seed: u64, opts: ScrollOptions) !Heightmap {
    const fw: f32 = @floatFromInt(w);
    const fh: f32 = @floatFromInt(h);
    const short = @min(fw, fh);
    const B = 0.3 * short * opts.scale;

    var g = try Grower.init(gpa, w, h, seed, B, opts);
    defer g.deinit();
    g.dom = .{ .radial = false, .w = fw, .h = fh, .margin = g.gap * 0.8, .gap_half = g.gap * 0.5 };
    g.addImage(.{ 1, 0, 0, 1 });

    // Seed: one or more big S-scrolls along the long axis.
    const long = @max(fw, fh);
    const horizontal = fw >= fh;
    const n_s: usize = @max(1, @as(usize, @intFromFloat(@round(long / short / 2.0))));
    const rng = g.rng();
    for (0..n_s) |i| {
        const fi: f32 = @floatFromInt(i);
        const fnum: f32 = @floatFromInt(n_s);
        const along = (fi + 0.5) / fnum * long + (rng.float(f32) - 0.5) * 0.12 * long / fnum;
        const across = short * (0.5 + (rng.float(f32) - 0.5) * 0.1);
        const cx = if (horizontal) along else across;
        const cy = if (horizontal) across else along;
        var head: f32 = if (horizontal) 0 else tau / 4.0;
        head += (rng.float(f32) - 0.5) * 0.5;
        const curl: f32 = if (rng.boolean()) 1 else -1;
        const r0 = B * (0.95 + 0.15 * rng.float(f32));
        const first = g.trySeedScroll(cx, cy, head, curl, r0, g.w_main, 0);
        _ = g.trySeedScroll(cx, cy, head + tau / 2.0, curl, r0, g.w_main, first orelse 0);
    }
    try g.grow();
    return g.render(null);
}

/// Same scroll language arranged with `folds`-fold rotational + mirror (dihedral) symmetry
/// around the centre of a square map, for a round dial. The square maps to [-1,1]²; only the
/// disc of radius 1 matters. `clear` lists circles (cx, cy, r in the same [-1,1] units) that
/// must be left at height 0 except for a raised rim ring hugging each circle (rim width ≈ 0.025),
/// because chamber windows get cut there; scrolls should flow around and frame those circles.
pub fn scrollRadial(gpa: Allocator, size: usize, folds: u32, clear: []const [3]f32, seed: u64) !Heightmap {
    return scrollRadialOpts(gpa, size, folds, clear, seed, .{});
}

pub const rim_width: f32 = 0.025;

pub fn scrollRadialOpts(gpa: Allocator, size: usize, folds_in: u32, clear: []const [3]f32, seed: u64, opts: ScrollOptions) !Heightmap {
    const folds: u32 = std.math.clamp(folds_in, 1, 16);
    const fs: f32 = @floatFromInt(size);
    const half = fs * 0.5;
    const B = 0.075 * fs * opts.scale;
    var g = try Grower.init(gpa, size, size, seed, B, opts);
    defer g.deinit();

    const ff: f32 = @floatFromInt(folds);
    const phi0: f32 = -tau / 4.0; // 12 o'clock (y grows downward)
    const phi1: f32 = phi0 + tau / (2.0 * ff);
    g.dom = .{
        .radial = true,
        .w = fs,
        .h = fs,
        .margin = 0,
        .cx = half,
        .cy = half,
        .rmax = half * 0.975,
        .rmin = half * 0.03,
        .n1 = .{ -@sin(phi0), @cos(phi0) },
        .n2 = .{ @sin(phi1), -@cos(phi1) },
        .gap_half = g.gap * 0.5,
    };
    // Dihedral images: rotations, and rotations composed with the mirror across phi0.
    const c2 = @cos(2 * phi0);
    const s2 = @sin(2 * phi0);
    for (0..folds) |k| {
        const a = tau * @as(f32, @floatFromInt(k)) / ff;
        const ca = @cos(a);
        const sa = @sin(a);
        g.addImage(.{ ca, -sa, sa, ca });
        // R * S
        g.addImage(.{ ca * c2 - sa * s2, ca * s2 + sa * c2, sa * c2 + ca * s2, sa * s2 - ca * c2 });
    }

    // Frames: raised rims around the clear circles. Their occupancy is stamped under every
    // symmetry image so that the (symmetric) strokes avoid every window.
    for (clear) |c| {
        const ccx = half + c[0] * half;
        const ccy = half + c[1] * half;
        const rr = c[2] * half;
        const rim_half = rim_width * half * 0.5;
        try g.addRim(ccx, ccy, rr + rim_half, rim_half);
    }
    try g.seedWalls();
    try g.grow();
    return g.render(clear);
}

// ---------------------------------------------------------------------------------------------
// Scroll growth engine
// ---------------------------------------------------------------------------------------------

const Sample = struct {
    x: f32,
    y: f32,
    r: f32, // half-width
    th: f32, // heading
    s: f32, // arc length from stroke start
    sid: u32 = 0,
};

const Kind = enum(u8) { frame, scroll, leaf };

const Stroke = struct {
    start: u32,
    len: u32,
    kind: Kind,
    curl: f32,
    top: f32,
    r0: f32,
    depth: u8,
    parent: u32 = 0,
    spine: bool = false,
};

const Cand = struct {
    prio: f32,
    kind: Kind,
    x: f32,
    y: f32,
    head: f32,
    curl: f32,
    size: f32, // R0 for scrolls, length for leaves
    w0: f32,
    parent: u32,
    ignore_len: f32,
    depth: u8,
    wall_ignore: f32 = 0,
};

const Domain = struct {
    radial: bool,
    w: f32,
    h: f32,
    margin: f32,
    cx: f32 = 0,
    cy: f32 = 0,
    rmax: f32 = 0,
    rmin: f32 = 0,
    n1: [2]f32 = .{ 0, 0 },
    n2: [2]f32 = .{ 0, 0 },
    gap_half: f32,

    /// Inside the fundamental wedge (walls with no margin); always true for rectangles.
    fn inWedge(d: *const Domain, x: f32, y: f32) bool {
        if (!d.radial) return true;
        const px = x - d.cx;
        const py = y - d.cy;
        return px * d.n1[0] + py * d.n1[1] >= 0 and px * d.n2[0] + py * d.n2[1] >= 0;
    }

    fn wallDist(d: *const Domain, x: f32, y: f32) f32 {
        if (!d.radial) return 1e9;
        const px = x - d.cx;
        const py = y - d.cy;
        return @min(px * d.n1[0] + py * d.n1[1], px * d.n2[0] + py * d.n2[1]);
    }

    /// Radial bounds only (ignores the mirror walls).
    fn okRadial(d: *const Domain, x: f32, y: f32, r: f32) bool {
        if (!d.radial) return d.ok(x, y, r);
        const px = x - d.cx;
        const py = y - d.cy;
        const rho = @sqrt(px * px + py * py);
        return rho + r <= d.rmax and rho >= d.rmin + r;
    }

    fn ok(d: *const Domain, x: f32, y: f32, r: f32) bool {
        if (!d.radial) {
            return x - r >= d.margin and y - r >= d.margin and x + r <= d.w - d.margin and y + r <= d.h - d.margin;
        }
        const px = x - d.cx;
        const py = y - d.cy;
        const rho = @sqrt(px * px + py * py);
        if (rho + r > d.rmax) return false;
        if (rho < d.rmin + r) return false;
        const m = r + d.gap_half;
        if (px * d.n1[0] + py * d.n1[1] < m) return false;
        if (px * d.n2[0] + py * d.n2[1] < m) return false;
        return true;
    }
};

const id_empty: u32 = 0;
const id_wall: u32 = 1;
const id_first: u32 = 2;

const bucket_size: f32 = 24.0;

const Grower = struct {
    gpa: Allocator,
    W: usize,
    H: usize,
    prng: std.Random.DefaultPrng,
    opts: ScrollOptions,
    B: f32,
    w_main: f32,
    w_min: f32,
    gap: f32,
    dom: Domain = undefined,
    imgs: [32][4]f32 = undefined,
    n_img: usize = 0,
    wall_ignore: f32 = 0,

    occ: []u32,
    tried: []u8,
    dt: []f32,
    samples: std.ArrayList(Sample) = .empty,
    strokes: std.ArrayList(Stroke) = .empty,
    path: std.ArrayList(Sample) = .empty,
    cands: std.ArrayList(Cand) = .empty,
    leaf_cands: std.ArrayList(Cand) = .empty,
    leaf_phase: bool = false,
    // Rims are rendered separately; remember them.
    rims: std.ArrayList([4]f32) = .empty,

    bw: usize,
    bh: usize,
    bhead: []i32,
    bnext: std.ArrayList(i32) = .empty,

    fn init(gpa: Allocator, W: usize, H: usize, seed: u64, B: f32, opts: ScrollOptions) !Grower {
        const n = W * H;
        const occ = try gpa.alloc(u32, n);
        @memset(occ, 0);
        const tried = try gpa.alloc(u8, n);
        @memset(tried, 0);
        const dt = try gpa.alloc(f32, n);
        const bw: usize = @as(usize, @intFromFloat(@as(f32, @floatFromInt(W)) / bucket_size)) + 1;
        const bh: usize = @as(usize, @intFromFloat(@as(f32, @floatFromInt(H)) / bucket_size)) + 1;
        const bhead = try gpa.alloc(i32, bw * bh);
        @memset(bhead, -1);
        return .{
            .gpa = gpa,
            .W = W,
            .H = H,
            .prng = std.Random.DefaultPrng.init(seed *% 0x9E3779B97F4A7C15 +% 0x1234567),
            .opts = opts,
            .B = B,
            .w_main = 0.15 * B,
            .w_min = @max(1.1, 0.02 * B),
            .gap = @max(1.8, 0.085 * B * opts.gap),
            .occ = occ,
            .tried = tried,
            .dt = dt,
            .bw = bw,
            .bh = bh,
            .bhead = bhead,
        };
    }

    fn deinit(g: *Grower) void {
        g.gpa.free(g.occ);
        g.gpa.free(g.tried);
        g.gpa.free(g.dt);
        g.gpa.free(g.bhead);
        g.samples.deinit(g.gpa);
        g.strokes.deinit(g.gpa);
        g.path.deinit(g.gpa);
        g.cands.deinit(g.gpa);
        g.leaf_cands.deinit(g.gpa);
        g.rims.deinit(g.gpa);
        g.bnext.deinit(g.gpa);
    }

    fn rng(g: *Grower) std.Random {
        return g.prng.random();
    }

    fn rand(g: *Grower, lo: f32, hi: f32) f32 {
        return lo + (hi - lo) * g.prng.random().float(f32);
    }

    fn addImage(g: *Grower, m: [4]f32) void {
        g.imgs[g.n_img] = m;
        g.n_img += 1;
    }

    fn imagePoint(g: *const Grower, k: usize, x: f32, y: f32) [2]f32 {
        if (!g.dom.radial) return .{ x, y };
        const m = g.imgs[k];
        const px = x - g.dom.cx;
        const py = y - g.dom.cy;
        return .{ g.dom.cx + m[0] * px + m[1] * py, g.dom.cy + m[2] * px + m[3] * py };
    }

    fn occAt(g: *const Grower, x: f32, y: f32) u32 {
        if (!(x >= 0 and y >= 0)) return id_wall;
        const ix: usize = @intFromFloat(x);
        const iy: usize = @intFromFloat(y);
        if (ix >= g.W or iy >= g.H) return id_wall;
        return g.occ[iy * g.W + ix];
    }

    fn stampDisc(g: *Grower, x: f32, y: f32, rad: f32, id: u32) void {
        const fw: f32 = @floatFromInt(g.W);
        const fh: f32 = @floatFromInt(g.H);
        const x0f = @max(0, @floor(x - rad));
        const y0f = @max(0, @floor(y - rad));
        const x1f = @min(fw - 1, @ceil(x + rad));
        const y1f = @min(fh - 1, @ceil(y + rad));
        if (x1f < x0f or y1f < y0f) return;
        const x0: usize = @intFromFloat(x0f);
        const y0: usize = @intFromFloat(y0f);
        const x1: usize = @intFromFloat(x1f);
        const y1: usize = @intFromFloat(y1f);
        const r2 = rad * rad;
        var iy = y0;
        while (iy <= y1) : (iy += 1) {
            const dy = @as(f32, @floatFromInt(iy)) + 0.5 - y;
            var ix = x0;
            while (ix <= x1) : (ix += 1) {
                const dx = @as(f32, @floatFromInt(ix)) + 0.5 - x;
                if (dx * dx + dy * dy <= r2) {
                    const p = &g.occ[iy * g.W + ix];
                    if (p.* == id_empty) p.* = id;
                }
            }
        }
    }

    fn markTried(g: *Grower, x: f32, y: f32, rad: f32) void {
        const fw: f32 = @floatFromInt(g.W);
        const fh: f32 = @floatFromInt(g.H);
        const x0: usize = @intFromFloat(@max(0, @floor(x - rad)));
        const y0: usize = @intFromFloat(@max(0, @floor(y - rad)));
        const x1: usize = @intFromFloat(@max(0, @min(fw - 1, @ceil(x + rad))));
        const y1: usize = @intFromFloat(@max(0, @min(fh - 1, @ceil(y + rad))));
        var iy = y0;
        while (iy <= y1) : (iy += 1) {
            const dy = @as(f32, @floatFromInt(iy)) + 0.5 - y;
            var ix = x0;
            while (ix <= x1) : (ix += 1) {
                const dx = @as(f32, @floatFromInt(ix)) + 0.5 - x;
                if (dx * dx + dy * dy <= rad * rad) g.tried[iy * g.W + ix] = 1;
            }
        }
    }

    // ---- path tracing ----------------------------------------------------------------------

    /// Lead-in of length `lead` with curvature k_start/R0 whose last `ramp` is a clothoid
    /// (curvature ramps from k_start/R0 to 1/R0), then a
    /// logarithmic spiral that turns `turns` full turns while its radius of curvature shrinks
    /// to `end_ratio`·R0. `curl` = +1 turns toward increasing heading, -1 the other way.
    fn traceScroll(g: *Grower, x: f32, y: f32, head: f32, curl: f32, r0: f32, lead: f32, ramp_in: f32, k_start: f32, turns: f32, end_ratio: f32) !void {
        const ramp = std.math.clamp(ramp_in, 1e-3, @max(lead, 1e-3));
        g.path.clearRetainingCapacity();
        const total_turn = turns * tau;
        const c = @log(1.0 / end_ratio) / total_turn;
        var px = x;
        var py = y;
        var th = head;
        var s: f32 = 0;
        var phi: f32 = 0;
        try g.path.append(g.gpa, .{ .x = px, .y = py, .r = 0, .th = th, .s = 0 });
        while (g.path.items.len < 6000) {
            var k: f32 = undefined;
            var rad: f32 = undefined;
            if (s < lead) {
                const t = std.math.clamp((s - (lead - ramp)) / ramp, 0, 1);
                const kk = (k_start + (1.0 - k_start) * t) / r0;
                k = curl * kk;
                rad = r0;
            } else {
                rad = r0 * @exp(-c * phi);
                k = curl / rad;
            }
            const ds = std.math.clamp(rad * 0.08, 0.3, 0.8);
            const thm = th + k * ds * 0.5;
            px += ds * @cos(thm);
            py += ds * @sin(thm);
            th += k * ds;
            s += ds;
            if (s > lead) phi += @abs(k) * ds;
            try g.path.append(g.gpa, .{ .x = px, .y = py, .r = 0, .th = th, .s = s });
            if (phi >= total_turn) break;
        }
    }

    /// A gently bending leaf / barb of given length. Curvature grows toward the tip.
    fn traceLeaf(g: *Grower, x: f32, y: f32, head: f32, curl: f32, length: f32, bend: f32) !void {
        g.path.clearRetainingCapacity();
        var px = x;
        var py = y;
        var th = head;
        var s: f32 = 0;
        const ds: f32 = 0.6;
        try g.path.append(g.gpa, .{ .x = px, .y = py, .r = 0, .th = th, .s = 0 });
        while (s < length) {
            const t = s / length;
            const k = curl * bend / length * (0.4 + 1.6 * t * t);
            const thm = th + k * ds * 0.5;
            px += ds * @cos(thm);
            py += ds * @sin(thm);
            th += k * ds;
            s += ds;
            try g.path.append(g.gpa, .{ .x = px, .y = py, .r = 0, .th = th, .s = s });
        }
    }

    fn widthsScroll(g: *Grower, w0: f32, start_ratio: f32, tip_ratio: f32) void {
        const items = g.path.items;
        const L = items[items.len - 1].s;
        for (items) |*p| {
            const t = p.s / L;
            const rise = start_ratio + (1 - start_ratio) * smoothstep(0, 0.14, t);
            const fall = 1 - (1 - tip_ratio) * std.math.pow(f32, t, 1.4);
            p.r = @max(0.55, w0 * rise * fall);
        }
    }

    fn widthsLeaf(g: *Grower, w0: f32) void {
        const items = g.path.items;
        const L = items[items.len - 1].s;
        for (items) |*p| {
            const t = p.s / L;
            const f = std.math.pow(f32, 1 - t, 0.7) * (0.45 + 2.2 * t) / 0.954;
            p.r = @max(0.5, w0 * f);
        }
    }

    /// Whether occupancy owner `id` blocks a sample. Within the start window a branch may sit
    /// on its parent, and (once leaves exist) tuck under the parent's own leaves.
    inline fn blocks(g: *const Grower, id: u32, ign: bool, ignore: u32) bool {
        if (id == id_empty) return false;
        if (!ign) return true;
        if (id == ignore) return false;
        if (id >= id_first and ignore >= id_first) {
            const o = g.strokes.items[id - id_first];
            if (o.kind == .leaf and o.parent == ignore) return false;
        }
        return true;
    }

    /// Returns the index of the first sample that collides, or null if the path fits.
    fn checkPath(g: *Grower, ignore: u32, ignore_len: f32) ?usize {
        const items = g.path.items;
        const dirs = comptime blk: {
            var d: [12][2]f32 = undefined;
            for (0..12) |i| {
                const a = @as(f32, @floatFromInt(i)) * tau / 12.0;
                d[i] = .{ @cos(a), @sin(a) };
            }
            break :blk d;
        };
        for (items, 0..) |p, i| {
            const dom_ok = if (p.s < g.wall_ignore) g.dom.okRadial(p.x, p.y, p.r) else g.dom.ok(p.x, p.y, p.r);
            if (!dom_ok) return i;
            const ign = p.s < ignore_len;
            // occupancy: centre + two rings of probes
            if (g.blocks(g.occAt(p.x, p.y), ign, ignore)) return i;
            for (dirs) |d| {
                if (g.blocks(g.occAt(p.x + d[0] * p.r, p.y + d[1] * p.r), ign, ignore)) return i;
                if (p.r > 3.0 and g.blocks(g.occAt(p.x + d[0] * p.r * 0.55, p.y + d[1] * p.r * 0.55), ign, ignore)) return i;
            }
            // self-collision with samples far enough back along the arc
            const excl = 2.6 * p.r + 2.0 * g.gap + 2.0;
            var j: usize = 0;
            while (j < i and items[j].s < p.s - excl) {
                const q = items[j];
                const dx = p.x - q.x;
                const dy = p.y - q.y;
                const dist = @sqrt(dx * dx + dy * dy);
                const need = p.r + q.r + g.gap;
                if (dist < need) return i;
                const skip: usize = @intFromFloat(@max(1.0, (dist - need) / 0.8));
                j += skip;
            }
        }
        return null;
    }

    fn commit(g: *Grower, kind: Kind, curl: f32, top: f32, r0: f32, depth: u8, parent: u32) !u32 {
        const id: u32 = @as(u32, @intCast(g.strokes.items.len)) + id_first;
        const start: u32 = @intCast(g.samples.items.len);
        for (g.path.items) |p| {
            var q = p;
            q.sid = id;
            try g.samples.append(g.gpa, q);
            try g.bucketInsert(g.samples.items.len - 1);
        }
        try g.strokes.append(g.gpa, .{
            .start = start,
            .len = @intCast(g.path.items.len),
            .kind = kind,
            .curl = curl,
            .top = top,
            .r0 = r0,
            .depth = depth,
            .parent = parent,
        });
        // Occupancy (dilated by the gap) under all symmetry images.
        for (0..g.n_img) |k| {
            var last_s: f32 = -1e9;
            const items = g.path.items;
            for (items, 0..) |p, i| {
                const rad = p.r + g.gap;
                if (p.s - last_s < 0.25 * rad and i + 1 != items.len) continue;
                last_s = p.s;
                const q = g.imagePoint(k, p.x, p.y);
                g.stampDisc(q[0], q[1], rad, id);
            }
        }
        return id;
    }

    fn bucketInsert(g: *Grower, si: usize) !void {
        const p = g.samples.items[si];
        try g.bnext.append(g.gpa, -1);
        const bx: usize = @intFromFloat(std.math.clamp(p.x / bucket_size, 0, @as(f32, @floatFromInt(g.bw - 1))));
        const by: usize = @intFromFloat(std.math.clamp(p.y / bucket_size, 0, @as(f32, @floatFromInt(g.bh - 1))));
        const b = by * g.bw + bx;
        g.bnext.items[si] = g.bhead[b];
        g.bhead[b] = @intCast(si);
    }

    /// Up to `out.len` well-separated stem samples nearest (by distance to their edge) to (x,y)
    /// within `max_d`, nearest first. Returns how many were found.
    fn nearestSamples(g: *Grower, x: f32, y: f32, max_d: f32, out: []usize) !usize {
        const Hit = struct { d: f32, i: usize };
        var hits: std.ArrayList(Hit) = .empty;
        defer hits.deinit(g.gpa);
        const bxc: i32 = @intFromFloat(x / bucket_size);
        const byc: i32 = @intFromFloat(y / bucket_size);
        const reach: i32 = @intFromFloat(@ceil(max_d / bucket_size) + 1);
        var by = byc - reach;
        while (by <= byc + reach) : (by += 1) {
            if (by < 0 or by >= @as(i32, @intCast(g.bh))) continue;
            var bx = bxc - reach;
            while (bx <= bxc + reach) : (bx += 1) {
                if (bx < 0 or bx >= @as(i32, @intCast(g.bw))) continue;
                var si = g.bhead[@as(usize, @intCast(by)) * g.bw + @as(usize, @intCast(bx))];
                while (si >= 0) : (si = g.bnext.items[@intCast(si)]) {
                    const p = g.samples.items[@intCast(si)];
                    const dx = p.x - x;
                    const dy = p.y - y;
                    const d = @sqrt(dx * dx + dy * dy) - p.r;
                    if (d > max_d) continue;
                    if (!g.dom.ok(p.x, p.y, 0)) continue;
                    // Only branch off scroll stems (not leaves, not the thin eye) and frames.
                    const st = g.strokes.items[p.sid - id_first];
                    if (st.kind == .leaf) continue;
                    if (st.kind == .scroll) {
                        const L = g.samples.items[st.start + st.len - 1].s;
                        if (p.s > 0.75 * L) continue;
                    }
                    try hits.append(g.gpa, .{ .d = d, .i = @intCast(si) });
                }
            }
        }
        std.mem.sort(Hit, hits.items, {}, struct {
            fn lt(_: void, a: Hit, b: Hit) bool {
                return a.d < b.d;
            }
        }.lt);
        var n: usize = 0;
        for (hits.items) |h| {
            if (n == out.len) break;
            const p = g.samples.items[h.i];
            var dup = false;
            for (out[0..n]) |o| {
                const q = g.samples.items[o];
                const dx = p.x - q.x;
                const dy = p.y - q.y;
                const sep = 2.5 * @max(p.r, q.r) + 6;
                if (dx * dx + dy * dy < sep * sep) {
                    dup = true;
                    break;
                }
            }
            if (dup) continue;
            out[n] = h.i;
            n += 1;
        }
        return n;
    }

    /// For holes that touch a mirror line: grow from the mirror line itself, perpendicular to
    /// it, so that the stroke and its reflection form one symmetric motif bridging the line.
    fn fromWall(g: *Grower, sp: Spot) !bool {
        const d = g.dom;
        const px = sp.x - d.cx;
        const py = sp.y - d.cy;
        const ns = [2][2]f32{ d.n1, d.n2 };
        for (ns) |n| {
            const dist = px * n[0] + py * n[1];
            if (dist > sp.d * 0.6) continue;
            const fx = sp.x - n[0] * dist;
            const fy = sp.y - n[1] * dist;
            const nrm = std.math.atan2(n[1], n[0]);
            const sizes = [_]f32{ 0.85, 0.68, 0.52 };
            for (sizes) |f| {
                const r0 = @min(sp.d * f, g.B * 0.9);
                if (r0 < g.minScroll()) break;
                const w0 = @max(g.wScrollMin(), r0 * 0.18);
                g.wall_ignore = w0 * 1.3 + g.gap;
                defer g.wall_ignore = 0;
                for ([_]f32{ 1, -1 }) |curl| {
                    const head = nrm + curl * g.rand(0.0, 0.35);
                    const lead = @max(0.0, dist - r0 * 0.6) + r0 * 0.25;
                    try g.traceScroll(fx, fy, head, curl, r0, lead, lead, g.rand(-0.3, 0.1), g.rand(1.0, 1.45), g.rand(0.14, 0.2));
                    g.widthsScroll(w0, 0.8, 0.3);
                    if (g.checkPath(0, 0) == null) {
                        const id = try g.commit(.scroll, curl, 1.0, r0, 1, 0);
                        try g.spawnChildren(id);
                        return true;
                    }
                }
            }
            // A spine lying on the mirror line (its own reflection), sprouting paired scrolls.
            const ax = n[1];
            const ay = -n[0];
            for ([_]f32{ 2.2, 1.6, 1.1 }) |lf| {
                const len = sp.d * lf;
                const w0 = @max(g.w_min, @min(sp.d * 0.22, g.w_main));
                if (len < 4 * w0) break;
                for ([_]f32{ 1, -1 }) |dir| {
                    const hx = ax * dir;
                    const hy = ay * dir;
                    const head = std.math.atan2(hy, hx);
                    try g.traceLeaf(fx - hx * len * 0.5, fy - hy * len * 0.5, head, 0, len, 0);
                    g.widthsLeaf(w0);
                    g.wall_ignore = 1e9;
                    defer g.wall_ignore = 0;
                    if (g.checkPath(0, 0) == null) {
                        // children must sprout toward the wedge interior (+n side)
                        const nlx = -@sin(head);
                        const nly = @cos(head);
                        const sig: f32 = if (nlx * n[0] + nly * n[1] > 0) -1 else 1;
                        const id = try g.commit(.scroll, sig, 1.0, sp.d * 1.1, 1, 0);
                        g.strokes.items[id - id_first].spine = true;
                        try g.spawnChildren(id);
                        return true;
                    }
                }
            }
        }
        return false;
    }

    /// Grow a scroll (or failing that a leaf) from stem sample `p` into the hole `sp`, aiming
    /// so that the scroll's eye lands near the middle of the hole.
    fn branchToward(g: *Grower, p: Sample, sp: Spot) !bool {
        const st = g.strokes.items[p.sid - id_first];
        const depth: u8 = @min(st.depth + 1, 6);
        const tx = @cos(p.th);
        const ty = @sin(p.th);
        const scroll_ok = sp.d * 0.6 >= g.minScroll();
        if (scroll_ok) {
            const sizes = [_]f32{ 0.78, 0.62, 0.48 };
            for (sizes) |f| {
                const r0 = @min(sp.d * f, g.B * 0.9);
                if (r0 < g.minScroll()) break;
                const cap = if (st.kind == .frame) r0 else p.r * 1.4;
                const w0 = @max(g.wScrollMin(), @min(cap, r0 * 0.19));
                for ([_]f32{ 1, -1 }) |curl| {
                    // Aim the end of the lead so the curl centre falls on the hole centre.
                    var ex = sp.x;
                    var ey = sp.y;
                    var head: f32 = 0;
                    var along: f32 = 1;
                    for (0..3) |_| {
                        var vx = ex - p.x;
                        var vy = ey - p.y;
                        const vl = @sqrt(vx * vx + vy * vy) + 1e-3;
                        vx /= vl;
                        vy /= vl;
                        along = if (vx * tx + vy * ty >= 0) 1 else -1;
                        head = std.math.atan2(vy + 0.35 * along * ty, vx + 0.35 * along * tx);
                        ex = sp.x + curl * @sin(head) * r0 * 0.85;
                        ey = sp.y - curl * @cos(head) * r0 * 0.85;
                    }
                    const lead = @sqrt((ex - p.x) * (ex - p.x) + (ey - p.y) * (ey - p.y));
                    const rel = angleDiff(head, if (along > 0) p.th else p.th + std.math.pi);
                    const ign = g.ignoreFor(p.r, w0, rel);
                    try g.traceScroll(p.x, p.y, head, curl, r0, @max(lead, ign * 0.5), r0 * 0.45, g.rand(-0.1, 0.15), g.rand(1.0, 1.4), g.rand(0.14, 0.2));
                    g.widthsScroll(w0, if (st.kind == .frame) 0.55 else 0.75, 0.32);
                    const bad = g.checkPath(p.sid, ign);
                    if (bad == null or (@as(f32, @floatFromInt(bad.?)) / @as(f32, @floatFromInt(g.path.items.len)) > 0.92)) {
                        if (bad) |b| g.path.shrinkRetainingCapacity(@max(2, b -| 4));
                        const id = try g.commit(.scroll, curl, 1.0, r0, depth, p.sid);
                        try g.spawnChildren(id);
                        return true;
                    }
                }
            }
        }
        // leaf toward the hole
        if (!g.leaf_phase) return false;
        var vx = sp.x - p.x;
        var vy = sp.y - p.y;
        const D = @sqrt(vx * vx + vy * vy) + 1e-3;
        vx /= D;
        vy /= D;
        const along: f32 = if (vx * tx + vy * ty >= 0) 1 else -1;
        const head = std.math.atan2(vy + 0.4 * along * ty, vx + 0.4 * along * tx);
        const side = tx * vy - ty * vx;
        const lw = @max(g.w_min, @min(p.r * 0.95, sp.d * 0.75));
        const len = @min(D + sp.d * 0.7, 6.0 * lw);
        if (D > len - 1.5 * lw) return false;
        const rel = angleDiff(head, if (along > 0) p.th else p.th + std.math.pi);
        return g.tryCand(.{
            .prio = 0,
            .kind = .leaf,
            .x = p.x,
            .y = p.y,
            .head = head,
            .curl = if (side >= 0) -along else along,
            .size = len,
            .w0 = lw,
            .parent = p.sid,
            .ignore_len = g.ignoreFor(p.r, lw * 0.6, rel),
            .depth = depth,
        });
    }

    // ---- frames ------------------------------------------------------------------------------

    fn addRim(g: *Grower, cx: f32, cy: f32, rc: f32, half_w: f32) !void {
        try g.rims.append(g.gpa, .{ cx, cy, rc, half_w });
        // interior: hard wall, under all images
        for (0..g.n_img) |k| {
            const q = g.imagePoint(k, cx, cy);
            g.stampDisc(q[0], q[1], rc - half_w, id_wall);
        }
        // the rim ring itself as a frame stroke (so scrolls can branch off it)
        g.path.clearRetainingCapacity();
        const n: usize = @max(16, @as(usize, @intFromFloat(tau * rc / 0.8)));
        for (0..n + 1) |i| {
            const a = tau * @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(n));
            try g.path.append(g.gpa, .{
                .x = cx + rc * @cos(a),
                .y = cy + rc * @sin(a),
                .r = half_w,
                .th = a + tau / 4.0,
                .s = rc * a,
            });
        }
        _ = try g.commit(.frame, 1, 1.0, rc, 0, 0);
    }

    // ---- growth -----------------------------------------------------------------------------

    fn trySeedScroll(g: *Grower, x: f32, y: f32, head: f32, curl: f32, r0_in: f32, w0: f32, ignore: u32) ?u32 {
        var r0 = r0_in;
        var attempt: usize = 0;
        while (attempt < 10) : (attempt += 1) {
            const turns = g.rand(1.15, 1.55);
            const lead = r0 * g.rand(0.5, 1.1);
            g.traceScroll(x, y, head, curl, r0, lead, lead, g.rand(-0.35, 0.0), turns, g.rand(0.13, 0.19)) catch return null;
            g.widthsScroll(w0 * (r0 / r0_in), 1.0, 0.3);
            const bad = g.checkPath(ignore, w0 * 4 + g.gap);
            if (bad == null or (@as(f32, @floatFromInt(bad.?)) / @as(f32, @floatFromInt(g.path.items.len)) > 0.93)) {
                if (bad) |b| g.path.shrinkRetainingCapacity(@max(2, b -| 4));
                const id = g.commit(.scroll, curl, 1.0, r0, 0, 0) catch return null;
                g.spawnChildren(id) catch {};
                return id;
            }
            r0 *= 0.9;
        }
        return null;
    }

    /// Scrolls that start on a mirror line heading away from it: together with their mirror
    /// image they form the symmetric C / lyre motifs that tie neighbouring sectors together.
    fn seedWalls(g: *Grower) !void {
        const d = g.dom;
        const walls = [2][2][2]f32{
            .{ .{ d.n1[1], -d.n1[0] }, d.n1 }, // direction along wall 1, inward normal
            .{ .{ -d.n2[1], d.n2[0] }, d.n2 },
        };
        for (walls, 0..) |wl, wi| {
            _ = wi;
            const n_seed: usize = 2;
            for (0..n_seed) |k| {
                const fk: f32 = @floatFromInt(k);
                const rho = d.rmax * (0.3 + 0.32 * fk + g.rand(0.0, 0.25));
                const x = d.cx + wl[0][0] * rho;
                const y = d.cy + wl[0][1] * rho;
                const nrm = std.math.atan2(wl[1][1], wl[1][0]);
                var r0 = g.B * g.rand(0.75, 1.0);
                const w0 = r0 * 0.17;
                g.wall_ignore = w0 * 1.3 + g.gap;
                defer g.wall_ignore = 0;
                var attempt: usize = 0;
                while (attempt < 8 and r0 >= g.minScroll()) : (attempt += 1) {
                    const curl: f32 = if (g.rng().boolean()) 1 else -1;
                    const lead = r0 * g.rand(0.3, 0.9);
                    try g.traceScroll(x, y, nrm + g.rand(-0.25, 0.25), curl, r0, lead, lead, g.rand(-0.5, 0.3), g.rand(1.1, 1.5), g.rand(0.14, 0.2));
                    g.widthsScroll(@min(w0, r0 * 0.17), 0.8, 0.3);
                    if (g.checkPath(0, 0) == null) {
                        const id = try g.commit(.scroll, curl, 1.0, r0, 0, 0);
                        try g.spawnChildren(id);
                        break;
                    }
                    r0 *= 0.85;
                }
            }
        }
    }

    /// Like an engraver: first lay out the scroll skeleton (scrolls only, coarse to fine),
    /// then dress it with leaves, then fill what is left with small leaves and sprigs.
    fn grow(g: *Grower) !void {
        g.leaf_phase = false;
        var rounds: usize = 0;
        while (rounds < 40) : (rounds += 1) {
            try g.processCandidates();
            if (!try g.gapFillRound()) break;
        }
        try g.processCandidates();
        g.leaf_phase = true;
        @memset(g.tried, 0);
        try g.cands.appendSlice(g.gpa, g.leaf_cands.items);
        g.leaf_cands.clearRetainingCapacity();
        try g.processCandidates();
        rounds = 0;
        while (rounds < 40) : (rounds += 1) {
            try g.processCandidates();
            if (!try g.gapFillRound()) break;
        }
        try g.processCandidates();
    }

    fn processCandidates(g: *Grower) !void {
        while (g.cands.items.len > 0) {
            var bi: usize = 0;
            for (g.cands.items, 0..) |c, i| {
                if (c.prio > g.cands.items[bi].prio) bi = i;
            }
            const c = g.cands.swapRemove(bi);
            _ = try g.tryCand(c);
        }
    }

    fn tryCand(g: *Grower, c: Cand) !bool {
        const saved_wall = g.wall_ignore;
        g.wall_ignore = c.wall_ignore;
        defer g.wall_ignore = saved_wall;
        switch (c.kind) {
            .scroll => {
                var r0 = c.size;
                var tries: usize = 0;
                while (tries < 5 and r0 >= g.minScroll()) : (tries += 1) {
                    const turns = g.rand(0.95, 1.45);
                    const lead = r0 * g.rand(0.15, 0.7);
                    const w0 = @max(g.wScrollMin(), @min(c.w0, r0 * 0.19));
                    try g.traceScroll(c.x, c.y, c.head, c.curl, r0, lead, r0 * 0.6, g.rand(0.0, 0.4), turns, g.rand(0.14, 0.22));
                    g.widthsScroll(w0, 0.75, 0.32);
                    const bad = g.checkPath(c.parent, c.ignore_len);
                    if (bad == null or (@as(f32, @floatFromInt(bad.?)) / @as(f32, @floatFromInt(g.path.items.len)) > 0.92)) {
                        if (bad) |b| g.path.shrinkRetainingCapacity(@max(2, b -| 4));
                        const id = try g.commit(.scroll, c.curl, 1.0, r0, c.depth, c.parent);
                        try g.spawnChildren(id);
                        return true;
                    }
                    r0 *= 0.8;
                }
                // Did not fit as a scroll: fall back to a leaf in the same direction.
                if (c.depth > 0) {
                    var lc = c;
                    lc.kind = .leaf;
                    lc.size = c.size * 1.2;
                    lc.w0 = @min(c.w0, lc.size * 0.18);
                    if (!g.leaf_phase) {
                        try g.leaf_cands.append(g.gpa, lc);
                        return false;
                    }
                    return g.tryCand(lc);
                }
                return false;
            },
            .leaf => {
                var len = c.size;
                var tries: usize = 0;
                const bend = g.rand(0.15, 0.7);
                while (tries < 5) : (tries += 1) {
                    const w0 = @max(g.w_min, @min(c.w0, len * 0.2));
                    if (len < @max(4.0, 3.2 * w0)) return false;
                    try g.traceLeaf(c.x, c.y, c.head, c.curl, len, bend);
                    g.widthsLeaf(w0);
                    const bad = g.checkPath(c.parent, c.ignore_len);
                    if (bad == null) {
                        const id = try g.commit(.leaf, c.curl, 0.93, len, c.depth, c.parent);
                        _ = id;
                        return true;
                    }
                    const frac = g.path.items[bad.?].s / len;
                    len *= std.math.clamp(frac * 0.9, 0.5, 0.85);
                }
                return false;
            },
            .frame => return false,
        }
    }

    fn minScroll(g: *Grower) f32 {
        return @max(6.0 * g.w_min, (if (g.leaf_phase) @as(f32, 0.15) else 0.2) * g.B);
    }

    /// Thinnest a scroll stem may start (keeps small scrolls from reading as hairlines).
    fn wScrollMin(g: *Grower) f32 {
        return @max(g.w_min, 0.032 * g.B);
    }

    fn pushCand(g: *Grower, c: Cand) !void {
        if (c.kind == .leaf and !g.leaf_phase) {
            try g.leaf_cands.append(g.gpa, c);
        } else {
            try g.cands.append(g.gpa, c);
        }
    }

    /// Arc length a branch needs before it is clear of its parent's (dilated) body when it
    /// leaves at `angle` to the parent's tangent; the parent is ignored over that stretch.
    fn ignoreFor(g: *Grower, parent_r: f32, w0: f32, angle: f32) f32 {
        return (parent_r + g.gap + w0 * 1.1) / @max(@abs(@sin(angle)), 0.3) + 2.0;
    }

    /// Children of a freshly committed scroll: counter-curling scrolls and acanthus leaves on
    /// its outer flank, a sprig into its bay.
    fn spawnChildren(g: *Grower, id: u32) !void {
        const st = g.strokes.items[id - id_first];
        if (st.kind != .scroll) return;
        const pts = g.samples.items[st.start .. st.start + st.len];
        const L = pts[pts.len - 1].s;
        const sig = st.curl;
        const depth = st.depth;
        if (depth > 6) return;

        // child scrolls
        const n_child: usize = if (depth < 2) 3 else if (depth < 4) 2 else 1;
        for (0..n_child) |ci| {
            const fi: f32 = @floatFromInt(ci);
            const t = std.math.clamp(0.04 + 0.17 * fi + g.rand(0.0, 0.17), 0.03, 0.62);
            const p = sampleAt(pts, t * L);
            const r0c = st.r0 * g.rand(0.4, 0.68);
            if (r0c < g.minScroll()) continue;
            const alpha = g.rand(0.45, 0.95);
            const counter = g.rng().float(f32) < 0.8;
            const w0 = @min(p.r * 1.4, r0c * 0.19);
            try g.pushCand(.{
                .prio = r0c * g.rand(0.85, 1.15),
                .kind = .scroll,
                .x = p.x,
                .y = p.y,
                .head = p.th - sig * alpha,
                .curl = if (counter) -sig else sig,
                .size = r0c,
                .w0 = w0,
                .parent = id,
                .ignore_len = g.ignoreFor(p.r, w0, alpha),
                .depth = depth + 1,
                .wall_ignore = if (st.spine) g.ignoreFor(p.r, w0, alpha) else 0,
            });
        }

        // acanthus leaves on the outer flank, sweeping forward along the flow
        var s = L * g.rand(0.06, 0.14);
        while (s < L * 0.7) {
            const p = sampleAt(pts, s);
            const t = s / L;
            const len = st.r0 * g.rand(0.38, 0.55) * (1.0 - 0.45 * t);
            const ang = g.rand(0.4, 0.75);
            const w0 = @max(g.w_min, p.r * g.rand(0.9, 1.15));
            try g.pushCand(.{
                .prio = len * 0.4 * g.rand(0.8, 1.2),
                .kind = .leaf,
                .x = p.x,
                .y = p.y,
                .head = p.th - sig * ang,
                .curl = sig,
                .size = len,
                .w0 = w0,
                .parent = id,
                .ignore_len = g.ignoreFor(p.r, w0 * 0.6, ang),
                .depth = depth + 1,
                .wall_ignore = if (st.spine) g.ignoreFor(p.r, w0 * 0.6, ang) else 0,
            });
            s += @max(len * g.rand(0.55, 0.85), 5.0);
        }

        // a sprig into the bay of the curl
        if (!st.spine) {
            const t = g.rand(0.18, 0.4);
            const p = sampleAt(pts, t * L);
            const len = st.r0 * g.rand(0.4, 0.6);
            const ang = g.rand(0.5, 0.8);
            const w0 = p.r * 0.8;
            try g.pushCand(.{
                .prio = len * 0.4,
                .kind = .leaf,
                .x = p.x,
                .y = p.y,
                .head = p.th + sig * ang,
                .curl = sig,
                .size = len,
                .w0 = w0,
                .parent = id,
                .ignore_len = g.ignoreFor(p.r, w0 * 0.6, ang),
                .depth = depth + 1,
            });
        }
    }

    fn computeDT(g: *Grower) void {
        const W = g.W;
        const H = g.H;
        const big: f32 = 1e9;
        for (0..H) |y| {
            for (0..W) |x| {
                const i = y * W + x;
                const fx = @as(f32, @floatFromInt(x)) + 0.5;
                const fy = @as(f32, @floatFromInt(y)) + 0.5;
                g.dt[i] = if (g.occ[i] != id_empty or !g.dom.okRadial(fx, fy, 0)) 0 else big;
            }
        }
        const d1: f32 = 1.0;
        const d2: f32 = 1.41421356;
        for (0..H) |y| {
            for (0..W) |x| {
                const i = y * W + x;
                var v = g.dt[i];
                if (v == 0) continue;
                if (x > 0) v = @min(v, g.dt[i - 1] + d1) else v = @min(v, d1);
                if (y > 0) {
                    v = @min(v, g.dt[i - W] + d1);
                    if (x > 0) v = @min(v, g.dt[i - W - 1] + d2);
                    if (x + 1 < W) v = @min(v, g.dt[i - W + 1] + d2);
                } else v = @min(v, d1);
                g.dt[i] = v;
            }
        }
        var y: usize = H;
        while (y > 0) {
            y -= 1;
            var x: usize = W;
            while (x > 0) {
                x -= 1;
                const i = y * W + x;
                var v = g.dt[i];
                if (v == 0) continue;
                if (x + 1 < W) v = @min(v, g.dt[i + 1] + d1) else v = @min(v, d1);
                if (y + 1 < H) {
                    v = @min(v, g.dt[i + W] + d1);
                    if (x + 1 < W) v = @min(v, g.dt[i + W + 1] + d2);
                    if (x > 0) v = @min(v, g.dt[i + W - 1] + d2);
                } else v = @min(v, d1);
                g.dt[i] = v;
            }
        }
    }

    const Spot = struct { x: f32, y: f32, d: f32 };

    fn gapFillRound(g: *Grower) !bool {
        g.computeDT();
        const min_clear = if (g.leaf_phase) @max(2.0, 2.0 * g.w_min) else g.minScroll() / 0.75;
        const cs: usize = @intFromFloat(@max(6.0, 0.25 * g.B));
        var spots: std.ArrayList(Spot) = .empty;
        defer spots.deinit(g.gpa);
        var cy: usize = 0;
        while (cy < g.H) : (cy += cs) {
            var cx: usize = 0;
            while (cx < g.W) : (cx += cs) {
                var best: f32 = min_clear;
                var bx: usize = 0;
                var by: usize = 0;
                var found = false;
                for (cy..@min(cy + cs, g.H)) |y| {
                    for (cx..@min(cx + cs, g.W)) |x| {
                        const i = y * g.W + x;
                        if (g.dt[i] >= best and g.tried[i] == 0 and g.dom.inWedge(@as(f32, @floatFromInt(x)) + 0.5, @as(f32, @floatFromInt(y)) + 0.5)) {
                            best = g.dt[i];
                            bx = x;
                            by = y;
                            found = true;
                        }
                    }
                }
                if (found) try spots.append(g.gpa, .{ .x = @as(f32, @floatFromInt(bx)) + 0.5, .y = @as(f32, @floatFromInt(by)) + 0.5, .d = best });
            }
        }
        if (spots.items.len == 0) return false;
        std.mem.sort(Spot, spots.items, {}, struct {
            fn lt(_: void, a: Spot, b: Spot) bool {
                return a.d > b.d;
            }
        }.lt);
        var accepted: usize = 0;
        var tried_n: usize = 0;
        const top_d = spots.items[0].d;
        for (spots.items) |sp| {
            if (tried_n >= 48) break;
            // Work coarse-to-fine: in each round only handle spots comparable to the largest.
            if (sp.d < top_d * 0.55 and accepted > 0) break;
            if (g.occAt(sp.x, sp.y) != id_empty) continue;
            tried_n += 1;
            if (try g.fillSpot(sp)) {
                accepted += 1;
                try g.processCandidates();
            }
            g.markTried(sp.x, sp.y, @max(2.0, sp.d * 0.3));
        }
        return true;
    }

    fn fillSpot(g: *Grower, sp_full: Spot) !bool {
        // A hole straddling a mirror line is filled by a motif bridging the line.
        const wd = g.dom.wallDist(sp_full.x, sp_full.y);
        if (wd < sp_full.d * 0.6 and !g.leaf_phase) {
            if (try g.fromWall(sp_full)) return true;
        }
        // Otherwise only the part of the hole on this side of the mirror lines is usable.
        var sp = sp_full;
        sp.d = @min(sp.d, wd - g.dom.gap_half);
        if (sp.d < 2.0) return false;
        // Branch toward the hole from one of the nearest stroke stems.
        var near: [5]usize = undefined;
        const n_near = try g.nearestSamples(sp.x, sp.y, sp.d * 3.0 + g.gap * 2 + 8, &near);
        for (near[0..n_near]) |ni| {
            if (try g.branchToward(g.samples.items[ni], sp)) return true;
        }
        // Nothing to branch from (or no branch fits): a free-standing scroll whose thin tail
        // reads as tucked under its neighbours, centred in the hole.
        if (sp.d * 0.6 < g.minScroll()) return false;
        var attempt: usize = 0;
        while (attempt < 8) : (attempt += 1) {
            const r0 = @min(sp.d * g.rand(0.55, 0.8), g.B);
            if (r0 < g.minScroll()) continue;
            const head = g.rand(0, tau);
            const curl: f32 = if (g.rng().boolean()) 1 else -1;
            try g.traceScroll(0, 0, head, curl, r0, r0 * 0.7, r0 * 0.7, g.rand(-0.4, 0.1), g.rand(1.0, 1.4), g.rand(0.14, 0.2));
            var minx: f32 = 1e9;
            var maxx: f32 = -1e9;
            var miny: f32 = 1e9;
            var maxy: f32 = -1e9;
            for (g.path.items) |q| {
                minx = @min(minx, q.x);
                maxx = @max(maxx, q.x);
                miny = @min(miny, q.y);
                maxy = @max(maxy, q.y);
            }
            const dx = sp.x - (minx + maxx) * 0.5;
            const dy = sp.y - (miny + maxy) * 0.5;
            for (g.path.items) |*q| {
                q.x += dx;
                q.y += dy;
            }
            g.widthsScroll(@max(g.wScrollMin(), @min(g.w_main, r0 * 0.18)), 0.3, 0.32);
            if (g.checkPath(0, 0) == null) {
                const id = try g.commit(.scroll, curl, 1.0, r0, 2, 0);
                try g.spawnChildren(id);
                return true;
            }
        }
        return false;
    }

    // ---- rendering ---------------------------------------------------------------------------

    fn render(g: *Grower, clear: ?[]const [3]f32) !Heightmap {
        const W = g.W;
        const H = g.H;
        const out = try g.gpa.alloc(f32, W * H);
        errdefer g.gpa.free(out);
        @memset(out, 0);
        const fw: f32 = @floatFromInt(W);
        const fh: f32 = @floatFromInt(H);
        const shade = g.opts.shading;

        for (g.strokes.items) |st| {
            if (st.kind == .frame) continue;
            const pts = g.samples.items[st.start .. st.start + st.len];
            const L = pts[pts.len - 1].s;
            for (0..g.n_img) |k| {
                const m = g.imgs[k];
                const det: f32 = if (g.dom.radial) m[0] * m[3] - m[1] * m[2] else 1;
                for (pts) |p0| {
                    const q = g.imagePoint(k, p0.x, p0.y);
                    const r = p0.r;
                    // side normal (left of heading) in image space, for the shading cut
                    var nx = -@sin(p0.th);
                    var ny = @cos(p0.th);
                    if (g.dom.radial) {
                        const ax = m[0] * nx + m[1] * ny;
                        const ay = m[2] * nx + m[3] * ny;
                        nx = ax;
                        ny = ay;
                    }
                    // Inner side of the curl = side the curvature centre lies on.
                    const inner = st.curl * det;
                    const t = p0.s / L;
                    const x0: usize = @intFromFloat(@max(0, @floor(q[0] - r - 1)));
                    const y0: usize = @intFromFloat(@max(0, @floor(q[1] - r - 1)));
                    const x1f = @min(fw - 1, @ceil(q[0] + r + 1));
                    const y1f = @min(fh - 1, @ceil(q[1] + r + 1));
                    if (x1f < 0 or y1f < 0) continue;
                    const x1: usize = @intFromFloat(x1f);
                    const y1: usize = @intFromFloat(y1f);
                    var iy = y0;
                    while (iy <= y1) : (iy += 1) {
                        const dy = @as(f32, @floatFromInt(iy)) + 0.5 - q[1];
                        var ix = x0;
                        while (ix <= x1) : (ix += 1) {
                            const dx = @as(f32, @floatFromInt(ix)) + 0.5 - q[0];
                            const d2 = (dx * dx + dy * dy) / (r * r);
                            if (d2 >= 1) continue;
                            var hgt = st.top * ridge(d2);
                            if (shade > 0 and r > 2.0) {
                                // engraver's shading: a fine cut running along the inner flank
                                const lat = (dx * nx + dy * ny) / r * inner; // +1 = inner edge
                                hgt -= shade * st.top * shadingCut(lat, t, st.kind, r);
                            }
                            const o = &out[iy * W + ix];
                            if (hgt > o.*) o.* = hgt;
                        }
                    }
                }
            }
        }

        // rims
        for (g.rims.items) |rm| {
            const rc = rm[2];
            const hw = rm[3];
            const ext = rc + hw + 1;
            const x0: usize = @intFromFloat(@max(0, @floor(rm[0] - ext)));
            const y0: usize = @intFromFloat(@max(0, @floor(rm[1] - ext)));
            const x1: usize = @intFromFloat(@max(0, @min(fw - 1, @ceil(rm[0] + ext))));
            const y1: usize = @intFromFloat(@max(0, @min(fh - 1, @ceil(rm[1] + ext))));
            var iy = y0;
            while (iy <= y1) : (iy += 1) {
                var ix = x0;
                while (ix <= x1) : (ix += 1) {
                    const dx = @as(f32, @floatFromInt(ix)) + 0.5 - rm[0];
                    const dy = @as(f32, @floatFromInt(iy)) + 0.5 - rm[1];
                    const d = (@sqrt(dx * dx + dy * dy) - rc) / hw;
                    if (@abs(d) >= 1) continue;
                    const hgt = ridge(d * d);
                    const o = &out[iy * W + ix];
                    if (hgt > o.*) o.* = hgt;
                }
            }
        }

        // stippled ground
        if (g.opts.stipple > 0) {
            const sp = @max(2.6, 0.035 * g.B);
            const dot_r = sp * 0.42;
            const ny: usize = @intFromFloat(fh / sp + 2);
            const nx: usize = @intFromFloat(fw / sp + 2);
            var hs: u64 = 0x51ED27;
            for (0..ny) |gy| {
                for (0..nx) |gx| {
                    hs = splitmix(hs);
                    const jx = @as(f32, @floatFromInt(hs & 0xffff)) / 65535.0;
                    const jy = @as(f32, @floatFromInt((hs >> 16) & 0xffff)) / 65535.0;
                    const ja = @as(f32, @floatFromInt((hs >> 32) & 0xffff)) / 65535.0;
                    const cxp = (@as(f32, @floatFromInt(gx)) + jx) * sp;
                    const cyp = (@as(f32, @floatFromInt(gy)) + jy) * sp;
                    const rr = dot_r * (0.75 + 0.5 * ja);
                    const x0: usize = @intFromFloat(@max(0, @floor(cxp - rr)));
                    const y0: usize = @intFromFloat(@max(0, @floor(cyp - rr)));
                    const x1f = @min(fw - 1, @ceil(cxp + rr));
                    const y1f = @min(fh - 1, @ceil(cyp + rr));
                    if (x1f < @as(f32, @floatFromInt(x0)) or y1f < @as(f32, @floatFromInt(y0))) continue;
                    const x1: usize = @intFromFloat(x1f);
                    const y1: usize = @intFromFloat(y1f);
                    var iy = y0;
                    while (iy <= y1) : (iy += 1) {
                        var ix = x0;
                        while (ix <= x1) : (ix += 1) {
                            const dx = @as(f32, @floatFromInt(ix)) + 0.5 - cxp;
                            const dy = @as(f32, @floatFromInt(iy)) + 0.5 - cyp;
                            const d2 = (dx * dx + dy * dy) / (rr * rr);
                            if (d2 >= 1) continue;
                            // punched dimple ground: small domes between pits read as matte
                            const hgt = g.opts.stipple * (1 - d2);
                            const o = &out[iy * W + ix];
                            if (o.* < g.opts.stipple and hgt > o.*) o.* = hgt;
                        }
                    }
                }
            }
        }

        // Clear windows stay flat at 0 (inside the rim).
        if (clear) |cl| {
            const half = fw * 0.5;
            for (0..H) |iy| {
                for (0..W) |ix| {
                    const ux = (@as(f32, @floatFromInt(ix)) + 0.5) / half - 1;
                    const uy = (@as(f32, @floatFromInt(iy)) + 0.5) / half - 1;
                    for (cl) |c| {
                        const dx = ux - c[0];
                        const dy = uy - c[1];
                        if (dx * dx + dy * dy < c[2] * c[2]) {
                            out[iy * W + ix] = 0;
                            break;
                        }
                    }
                }
            }
        }
        return .{ .w = W, .h = H, .data = out };
    }
};

fn sampleAt(pts: []const Sample, s: f32) Sample {
    // binary search on arc length
    var lo: usize = 0;
    var hi: usize = pts.len - 1;
    while (hi - lo > 1) {
        const mid = (lo + hi) / 2;
        if (pts[mid].s <= s) lo = mid else hi = mid;
    }
    return pts[lo];
}

/// Rounded ridge cross-section; d2 = (lateral/halfwidth)². Slightly flattened dome so the top
/// of each stroke reads as a polished band with crisp shoulders.
fn ridge(d2: f32) f32 {
    const v = 1 - d2;
    return std.math.pow(f32, v, 0.42);
}

/// A narrow V-cut parallel to the stroke on its inner flank, fading in after the stroke start
/// and out before the eye — what engravers cut to model a scroll as a turned-over leaf.
fn shadingCut(lat: f32, t: f32, kind: Kind, r: f32) f32 {
    const centre: f32 = 0.38;
    const hw: f32 = std.math.clamp(1.3 / r, 0.1, 0.24);
    const d = @abs(lat - centre) / hw;
    if (d >= 1) return 0;
    const along = switch (kind) {
        .scroll => smoothstep(0.03, 0.15, t) * (1 - smoothstep(0.6, 0.85, t)),
        .leaf => smoothstep(0.05, 0.2, t) * (1 - smoothstep(0.55, 0.8, t)),
        .frame => 0,
    };
    return (1 - d) * along;
}

fn smoothstep(a: f32, b: f32, x: f32) f32 {
    const t = std.math.clamp((x - a) / (b - a), 0.0, 1.0);
    return t * t * (3 - 2 * t);
}

fn splitmix(x: u64) u64 {
    var z = x +% 0x9E3779B97F4A7C15;
    z = (z ^ (z >> 30)) *% 0xBF58476D1CE4E5B9;
    z = (z ^ (z >> 27)) *% 0x94D049BB133111EB;
    return z ^ (z >> 31);
}

// ---------------------------------------------------------------------------------------------
// Cracks
// ---------------------------------------------------------------------------------------------

/// Bullet-impact "spider-web" fracture pattern for a w×h rectangle, impact point at
/// (impact[0], impact[1]) in [0,1] coordinates (it may be off-centre or outside the rect).
/// Radial cracks fan out from the impact with slight angular jitter and forking; concentric
/// polygonal crack rings get sparser further out; each cell between cracks is a flat facet
/// tilted slightly differently (so metal facets catch light like shattered glass);
/// cracks are thin V-grooves (height dips toward 0 at the crack line). Facet heights ≈ 0.5–1.
pub fn cracks(gpa: Allocator, w: usize, h: usize, impact: [2]f32, seed: u64) !Heightmap {
    var prng = std.Random.DefaultPrng.init(seed *% 0xD1B54A32D192ED03 +% 77);
    const rng = prng.random();
    const fw: f32 = @floatFromInt(w);
    const fh: f32 = @floatFromInt(h);
    const ix = impact[0] * fw;
    const iy = impact[1] * fh;

    // farthest corner
    var rmax: f32 = 0;
    for ([_][2]f32{ .{ 0, 0 }, .{ fw, 0 }, .{ 0, fh }, .{ fw, fh } }) |c| {
        const dx = c[0] - ix;
        const dy = c[1] - iy;
        rmax = @max(rmax, @sqrt(dx * dx + dy * dy));
    }
    rmax += 4;
    // nearest point of the rect to the impact (0 if inside)
    const nx = std.math.clamp(ix, 0, fw);
    const ny = std.math.clamp(iy, 0, fh);
    const rnear = @sqrt((nx - ix) * (nx - ix) + (ny - iy) * (ny - iy));
    const S = @max(fw, fh); // pattern scale (pixels)

    var segs: std.ArrayList(Seg) = .empty;
    defer segs.deinit(gpa);

    // ---- radial cracks -------------------------------------------------------------------
    const Ray = struct { pts: std.ArrayList([2]f32), r_start: f32, r_end: f32 };
    var rays: std.ArrayList(Ray) = .empty;
    defer {
        for (rays.items) |*r| r.pts.deinit(gpa);
        rays.deinit(gpa);
    }
    const n_rays: usize = 15 + rng.uintLessThan(usize, 7);
    const step = 0.006 * S;
    const crater = 0.022 * S;
    {
        var base_angles: [32]f32 = undefined;
        const a0 = rng.float(f32) * tau;
        for (0..n_rays) |i| {
            const fi: f32 = @floatFromInt(i);
            base_angles[i] = a0 + tau * (fi + (rng.float(f32) - 0.5) * 0.6) / @as(f32, @floatFromInt(n_rays));
        }
        // queue of (start point, angle, start radius, width, generation)
        const Job = struct { x: f32, y: f32, a: f32, r: f32, wdt: f32, gen: u8 };
        var jobs: std.ArrayList(Job) = .empty;
        defer jobs.deinit(gpa);
        for (0..n_rays) |i| {
            const r0 = crater * (0.2 + 0.6 * rng.float(f32));
            try jobs.append(gpa, .{ .x = ix + r0 * @cos(base_angles[i]), .y = iy + r0 * @sin(base_angles[i]), .a = base_angles[i], .r = r0, .wdt = 1.0, .gen = 0 });
        }
        var ji: usize = 0;
        while (ji < jobs.items.len) : (ji += 1) {
            const j = jobs.items[ji];
            var ray = Ray{ .pts = .empty, .r_start = j.r, .r_end = rmax };
            try ray.pts.append(gpa, .{ j.x, j.y });
            var px = j.x;
            var py = j.y;
            var a = j.a;
            var drift: f32 = (rng.float(f32) - 0.5) * 0.004;
            // early termination for some rays
            const stop_r: f32 = if (rng.float(f32) < 0.18 and j.gen == 0) rmax * (0.35 + 0.5 * rng.float(f32)) else if (j.gen > 0 and rng.float(f32) < 0.35) j.r + (rmax - j.r) * (0.25 + 0.6 * rng.float(f32)) else rmax;
            var fork_r: f32 = if (rng.float(f32) < (if (j.gen == 0) @as(f32, 0.7) else 0.3)) j.r + (stop_r - j.r) * (0.12 + 0.5 * rng.float(f32)) else 1e9;
            while (true) {
                // radial angle relative to the impact, with wander
                const rad_a = std.math.atan2(py - iy, px - ix);
                drift += (rng.float(f32) - 0.5) * 0.002;
                drift = std.math.clamp(drift, -0.006, 0.006);
                // keep roughly radial (pull back toward the radial direction); mostly straight
                // runs with an occasional small kink, like real radial cracks in glass
                a += drift + (rng.float(f32) - 0.5) * 0.035 + angleDiff(rad_a, a) * 0.06;
                if (rng.float(f32) < 0.04) a += (rng.float(f32) - 0.5) * 0.22;
                const st = step * (0.6 + 0.8 * rng.float(f32));
                const qx = px + st * @cos(a);
                const qy = py + st * @sin(a);
                const r = @sqrt((qx - ix) * (qx - ix) + (qy - iy) * (qy - iy));
                const width = j.wdt * (1.0 - 0.35 * std.math.clamp(r / (0.8 * S), 0, 1));
                try segs.append(gpa, .{ .ax = px, .ay = py, .bx = qx, .by = qy, .w = width, .kind = 0 });
                try ray.pts.append(gpa, .{ qx, qy });
                px = qx;
                py = qy;
                if (r >= stop_r) break;
                if (r >= fork_r) {
                    fork_r = if (rng.float(f32) < 0.35) r + (stop_r - r) * (0.2 + 0.5 * rng.float(f32)) else 1e9;
                    const spread = 0.12 + 0.18 * rng.float(f32);
                    const sgn: f32 = if (rng.boolean()) 1 else -1;
                    try jobs.append(gpa, .{ .x = px, .y = py, .a = a + sgn * spread, .r = r, .wdt = j.wdt * 0.75, .gen = j.gen + 1 });
                    a -= sgn * spread * 0.35;
                }
            }
            ray.r_end = stop_r;
            try rays.append(gpa, ray);
        }
        // crater: many short radial splinters
        const n_spl = 26 + rng.uintLessThan(usize, 10);
        for (0..n_spl) |_| {
            var a = rng.float(f32) * tau;
            const len = crater * (0.7 + 1.6 * rng.float(f32));
            var px = ix;
            var py = iy;
            var s: f32 = 0;
            while (s < len) {
                a += (rng.float(f32) - 0.5) * 0.25;
                const st = step * 0.5;
                const qx = px + st * @cos(a);
                const qy = py + st * @sin(a);
                try segs.append(gpa, .{ .ax = px, .ay = py, .bx = qx, .by = qy, .w = 0.6, .kind = 1 });
                px = qx;
                py = qy;
                s += st;
            }
        }
    }

    // ---- concentric polygonal rings ------------------------------------------------------
    {
        var rk: f32 = crater * (0.9 + 0.4 * rng.float(f32));
        var k: usize = 0;
        while (rk < rmax) : (k += 1) {
            const p_seg = std.math.clamp(0.97 - 0.06 * @as(f32, @floatFromInt(k)), 0.32, 0.97);
            if (rk > rnear - 0.05 * S) {
                // points where each live ray crosses this radius
                var hits: std.ArrayList([3]f32) = .empty; // angle, x, y
                defer hits.deinit(gpa);
                for (rays.items) |ray| {
                    if (ray.r_start > rk or ray.r_end < rk * 0.98) continue;
                    // jitter the ring radius per ray so the polygon steps
                    const rr = rk * (1 + (rng.float(f32) - 0.5) * 0.14);
                    if (pointAtRadius(ray.pts.items, ix, iy, rr)) |pt| {
                        try hits.append(gpa, .{ std.math.atan2(pt[1] - iy, pt[0] - ix), pt[0], pt[1] });
                    }
                }
                std.mem.sort([3]f32, hits.items, {}, struct {
                    fn lt(_: void, a: [3]f32, b: [3]f32) bool {
                        return a[0] < b[0];
                    }
                }.lt);
                const n = hits.items.len;
                if (n >= 2) {
                    for (0..n) |i| {
                        const a = hits.items[i];
                        const b = hits.items[(i + 1) % n];
                        var da = b[0] - a[0];
                        if (da <= 0) da += tau;
                        if (da > 1.3) continue;
                        if (rng.float(f32) > p_seg) continue;
                        // slightly bowed chord, with a little zig-zag
                        const bow = (rng.float(f32) - 0.3) * 0.08;
                        const mx = (a[1] + b[1]) * 0.5;
                        const my = (a[2] + b[2]) * 0.5;
                        const ox = mx - ix;
                        const oy = my - iy;
                        const ol = @sqrt(ox * ox + oy * oy) + 1e-3;
                        const chord = @sqrt((b[1] - a[1]) * (b[1] - a[1]) + (b[2] - a[2]) * (b[2] - a[2]));
                        const nseg: usize = @max(2, @as(usize, @intFromFloat(chord / (step * 0.8))));
                        var lx = a[1];
                        var ly = a[2];
                        const wring = 0.7 * (1.0 - 0.3 * std.math.clamp(rk / (0.8 * S), 0, 1));
                        for (1..nseg + 1) |si| {
                            const t = @as(f32, @floatFromInt(si)) / @as(f32, @floatFromInt(nseg));
                            const b4 = 4 * t * (1 - t);
                            const jit: f32 = if (si == nseg) 0 else (rng.float(f32) - 0.5) * 0.25 * step;
                            const qx = a[1] + (b[1] - a[1]) * t + (ox / ol) * (bow * chord * b4 + jit);
                            const qy = a[2] + (b[2] - a[2]) * t + (oy / ol) * (bow * chord * b4 + jit);
                            try segs.append(gpa, .{ .ax = lx, .ay = ly, .bx = qx, .by = qy, .w = wring, .kind = 2 });
                            lx = qx;
                            ly = qy;
                        }
                    }
                }
            }
            rk = rk * (1.16 + 0.22 * rng.float(f32)) + 0.014 * S;
        }
    }

    // ---- rasterise crack distance --------------------------------------------------------
    const n = w * h;
    const dist = try gpa.alloc(f32, n); // absolute distance to nearest crack line (px)
    defer gpa.free(dist);
    const ndist = try gpa.alloc(f32, n); // distance normalised by local groove half-width
    defer gpa.free(ndist);
    @memset(dist, 1e9);
    @memset(ndist, 1e9);
    const gw_base = @max(1.6, 0.0042 * S); // groove half-width for a main crack
    for (segs.items) |sg| {
        const gw = gw_base * sg.w;
        const pad = gw + 1.5;
        const x0f = @max(0, @floor(@min(sg.ax, sg.bx) - pad));
        const y0f = @max(0, @floor(@min(sg.ay, sg.by) - pad));
        const x1f = @min(fw - 1, @ceil(@max(sg.ax, sg.bx) + pad));
        const y1f = @min(fh - 1, @ceil(@max(sg.ay, sg.by) + pad));
        if (x1f < x0f or y1f < y0f) continue;
        const ex = sg.bx - sg.ax;
        const ey = sg.by - sg.ay;
        const el2 = ex * ex + ey * ey + 1e-6;
        var yy: usize = @intFromFloat(y0f);
        const y1: usize = @intFromFloat(y1f);
        const x1: usize = @intFromFloat(x1f);
        while (yy <= y1) : (yy += 1) {
            var xx: usize = @intFromFloat(x0f);
            while (xx <= x1) : (xx += 1) {
                const px = @as(f32, @floatFromInt(xx)) + 0.5;
                const py = @as(f32, @floatFromInt(yy)) + 0.5;
                const t = std.math.clamp(((px - sg.ax) * ex + (py - sg.ay) * ey) / el2, 0, 1);
                const dx = px - (sg.ax + ex * t);
                const dy = py - (sg.ay + ey * t);
                const d = @sqrt(dx * dx + dy * dy);
                const i = yy * w + xx;
                if (d < dist[i]) dist[i] = d;
                const nd = d / gw;
                if (nd < ndist[i]) ndist[i] = nd;
            }
        }
    }

    // ---- label facets (connected components between cracks) -------------------------------
    const label = try gpa.alloc(i32, n);
    defer gpa.free(label);
    for (0..n) |i| label[i] = if (dist[i] <= 0.85) -2 else -1;
    var stack: std.ArrayList(u32) = .empty;
    defer stack.deinit(gpa);
    const Facet = struct { h: f32, gx: f32, gy: f32, cx: f32, cy: f32, span: f32, lo: f32 = 1e9, hi: f32 = -1e9 };
    var facets: std.ArrayList(Facet) = .empty;
    defer facets.deinit(gpa);
    var sum_x: f64 = 0;
    var sum_y: f64 = 0;
    var cnt: usize = 0;
    for (0..n) |seed_i| {
        if (label[seed_i] != -1) continue;
        const lab: i32 = @intCast(facets.items.len);
        sum_x = 0;
        sum_y = 0;
        cnt = 0;
        try stack.append(gpa, @intCast(seed_i));
        label[seed_i] = lab;
        while (stack.items.len > 0) {
            const i: usize = stack.pop().?;
            const x = i % w;
            const y = i / w;
            sum_x += @floatFromInt(x);
            sum_y += @floatFromInt(y);
            cnt += 1;
            if (x > 0 and label[i - 1] == -1) {
                label[i - 1] = lab;
                try stack.append(gpa, @intCast(i - 1));
            }
            if (x + 1 < w and label[i + 1] == -1) {
                label[i + 1] = lab;
                try stack.append(gpa, @intCast(i + 1));
            }
            if (y > 0 and label[i - w] == -1) {
                label[i - w] = lab;
                try stack.append(gpa, @intCast(i - w));
            }
            if (y + 1 < h and label[i + w] == -1) {
                label[i + w] = lab;
                try stack.append(gpa, @intCast(i + w));
            }
        }
        const fc: f32 = @floatFromInt(cnt);
        const cx: f32 = @floatCast(sum_x / @as(f64, @floatFromInt(cnt)));
        const cy: f32 = @floatCast(sum_y / @as(f64, @floatFromInt(cnt)));
        _ = fc;
        // Tilt direction: random, biased toward the radial direction (facets dish toward or
        // away from the impact). The tilt amount is a height *span* across the facet, so big
        // and small facets catch the light about equally; stronger near the impact.
        const rd = @sqrt((cx - ix) * (cx - ix) + (cy - iy) * (cy - iy)) + 1;
        const near = std.math.clamp(1.0 - rd / (0.6 * S), 0.0, 1.0);
        const ga = rng.float(f32) * tau;
        const rb: f32 = (rng.float(f32) - 0.3) * 1.2;
        var gx = @cos(ga) + rb * (cx - ix) / rd;
        var gy = @sin(ga) + rb * (cy - iy) / rd;
        const gl = @sqrt(gx * gx + gy * gy) + 1e-6;
        gx /= gl;
        gy /= gl;
        const span = 0.1 + 0.2 * rng.float(f32) + 0.12 * near;
        const lo_h = 0.52;
        const hi_h = 1.0 - 0.06 * near;
        const mid = lo_h + span * 0.5 + (hi_h - lo_h - span) * rng.float(f32);
        try facets.append(gpa, .{ .h = mid, .gx = gx, .gy = gy, .cx = cx, .cy = cy, .span = span });
    }
    // extent of each facet along its tilt direction
    for (0..n) |i| {
        if (label[i] < 0) continue;
        const f = &facets.items[@intCast(label[i])];
        const t = f.gx * (@as(f32, @floatFromInt(i % w)) - f.cx) + f.gy * (@as(f32, @floatFromInt(i / w)) - f.cy);
        f.lo = @min(f.lo, t);
        f.hi = @max(f.hi, t);
    }
    for (facets.items) |*f| {
        const ext = @max(f.hi - f.lo, 4.0);
        // cap the slope so tiny splinters do not become steep spikes
        const slope = @min(f.span / ext, 0.025);
        f.gx *= slope;
        f.gy *= slope;
        // re-centre so the plane's mid height sits at h
        const tm = (f.lo + f.hi) * 0.5;
        f.h -= tm * slope;
    }
    // crack pixels take the label of the nearest labelled neighbour
    for (0..2) |_| {
        for (0..n) |i| {
            if (label[i] >= 0) continue;
            const x = i % w;
            const y = i / w;
            var best: i32 = -1;
            var bd: f32 = 1e9;
            var dy: i32 = -2;
            while (dy <= 2) : (dy += 1) {
                var dx: i32 = -2;
                while (dx <= 2) : (dx += 1) {
                    const xx = @as(i32, @intCast(x)) + dx;
                    const yy = @as(i32, @intCast(y)) + dy;
                    if (xx < 0 or yy < 0 or xx >= @as(i32, @intCast(w)) or yy >= @as(i32, @intCast(h))) continue;
                    const l = label[@as(usize, @intCast(yy)) * w + @as(usize, @intCast(xx))];
                    if (l < 0) continue;
                    const dd: f32 = @floatFromInt(dx * dx + dy * dy);
                    if (dd < bd) {
                        bd = dd;
                        best = l;
                    }
                }
            }
            if (best >= 0) label[i] = best;
        }
    }

    // ---- compose -----------------------------------------------------------------------------
    const out = try gpa.alloc(f32, n);
    errdefer gpa.free(out);
    for (0..h) |y| {
        for (0..w) |x| {
            const i = y * w + x;
            const fx: f32 = @floatFromInt(x);
            const fy: f32 = @floatFromInt(y);
            var base: f32 = 0.75;
            if (label[i] >= 0) {
                const f = facets.items[@intCast(label[i])];
                base = f.h + f.gx * (fx - f.cx) + f.gy * (fy - f.cy);
            }
            base = std.math.clamp(base, 0.5, 1.0);
            // crushed zone at the impact: a shallow dish
            const rr = @sqrt((fx - ix) * (fx - ix) + (fy - iy) * (fy - iy));
            const dish = 0.22 * @exp(-(rr * rr) / (crater * crater * 1.4));
            base = @max(0.3, base - dish);
            // V-groove
            const u = std.math.clamp(ndist[i], 0, 1);
            const v = u * (2 - u) * 0.35 + u * 0.65; // V with slightly rounded lips
            out[i] = base * v;
        }
    }
    return .{ .w = w, .h = h, .data = out };
}

const Seg = struct { ax: f32, ay: f32, bx: f32, by: f32, w: f32, kind: u8 };

fn angleDiff(a: f32, b: f32) f32 {
    var d = a - b;
    while (d > std.math.pi) d -= tau;
    while (d < -std.math.pi) d += tau;
    return d;
}

fn pointAtRadius(pts: []const [2]f32, cx: f32, cy: f32, r: f32) ?[2]f32 {
    if (pts.len < 2) return null;
    var prev = pts[0];
    var pr = @sqrt((prev[0] - cx) * (prev[0] - cx) + (prev[1] - cy) * (prev[1] - cy));
    for (pts[1..]) |p| {
        const pr2 = @sqrt((p[0] - cx) * (p[0] - cx) + (p[1] - cy) * (p[1] - cy));
        if ((pr <= r and pr2 >= r) or (pr >= r and pr2 <= r)) {
            const t = if (@abs(pr2 - pr) < 1e-6) 0 else (r - pr) / (pr2 - pr);
            return .{ prev[0] + (p[0] - prev[0]) * t, prev[1] + (p[1] - prev[1]) * t };
        }
        prev = p;
        pr = pr2;
    }
    return null;
}

test "scrollwork smoke" {
    const hm = try scrollwork(std.testing.allocator, 128, 64, 1);
    defer hm.deinit(std.testing.allocator);
    try std.testing.expect(hm.sample(0.5, 0.5) >= 0);
}
