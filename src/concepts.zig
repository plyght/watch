//! Draws the 2D concept sheets (front view of each watch idea) as SVG files
//! in concepts/. Units are millimetres; 12 o'clock is up (-Y in SVG).

const std = @import("std");

const P = [2]f32;
const tau: f32 = 2.0 * std.math.pi;

// The semicentric emblem in its native SVG coordinates. The burst's focal
// point is at `focal`; the long blade points to the right.
const focal = P{ 114.0, 266.0 };
const shard_a = [_]P{ .{ 115, 251.5 }, .{ 126, 248.5 }, .{ 250, 174.5 }, .{ 137, 194 }, .{ 116, 238 } };
const shard_b = [_]P{ .{ 57, 262.5 }, .{ 87.5, 266 }, .{ 98.5, 263.5 }, .{ 64.5, 244 } };
const shard_c = [_]P{ .{ 125.5, 265.5 }, .{ 160, 278 }, .{ 471, 256 }, .{ 147, 255.5 } };
const shard_d = [_]P{ .{ 41, 303.5 }, .{ 65.5, 326.5 }, .{ 105.5, 290 }, .{ 105.5, 276.5 } };
const shard_e = [_]P{ .{ 203.5, 336.5 }, .{ 129.5, 285.5 }, .{ 129.5, 294 }, .{ 168.5, 337.5 } };
const shards = [_][]const P{ &shard_a, &shard_b, &shard_c, &shard_d, &shard_e };

/// Point at `r` from the centre, `deg` clockwise from 12 o'clock.
fn polar(deg: f32, r: f32) P {
    const a = deg * tau / 360.0;
    return .{ r * @sin(a), -r * @cos(a) };
}

const Metal = struct { id: []const u8, light: []const u8, mid: []const u8, dark: []const u8 };

const steel = Metal{ .id = "steel", .light = "#fafbfc", .mid = "#a9afb8", .dark = "#474b53" };
const gun = Metal{ .id = "gun", .light = "#80858f", .mid = "#34373e", .dark = "#0e0f12" };
const brass = Metal{ .id = "brass", .light = "#ffe9a6", .mid = "#c2932f", .dark = "#5a3d0a" };
const bronze = Metal{ .id = "bronze", .light = "#f6cf9d", .mid = "#b47236", .dark = "#46260f" };
const titan = Metal{ .id = "titan", .light = "#d6d3cc", .mid = "#86837d", .dark = "#33312e" };
const blued = Metal{ .id = "blued", .light = "#5f7fe0", .mid = "#1c2f86", .dark = "#080f3a" };

const Svg = struct {
    gpa: std.mem.Allocator,
    out: std.ArrayList(u8) = .empty,

    fn w(s: *Svg, comptime fmt: []const u8, args: anytype) void {
        const chunk = std.fmt.allocPrint(s.gpa, fmt, args) catch @panic("out of memory");
        s.out.appendSlice(s.gpa, chunk) catch @panic("out of memory");
    }

    fn begin(s: *Svg, bg: []const u8, metals: []const Metal) void {
        s.w("<svg xmlns='http://www.w3.org/2000/svg' viewBox='-34 -40 68 94' width='1020' height='1410'>\n<defs>\n", .{});
        s.w("<filter id='sh' x='-30%' y='-30%' width='160%' height='160%'><feDropShadow dx='0.25' dy='0.7' stdDeviation='0.7' flood-opacity='0.45'/></filter>\n", .{});
        s.w("<filter id='sh2' x='-30%' y='-30%' width='160%' height='160%'><feDropShadow dx='0.1' dy='0.25' stdDeviation='0.2' flood-opacity='0.6'/></filter>\n", .{});
        for (metals) |m| {
            s.w("<linearGradient id='{s}' x1='0' y1='0' x2='1' y2='1'><stop offset='0' stop-color='{s}'/><stop offset='0.5' stop-color='{s}'/><stop offset='1' stop-color='{s}'/></linearGradient>\n", .{ m.id, m.light, m.mid, m.dark });
            s.w("<linearGradient id='{s}_r' x1='1' y1='1' x2='0' y2='0'><stop offset='0' stop-color='{s}'/><stop offset='0.5' stop-color='{s}'/><stop offset='1' stop-color='{s}'/></linearGradient>\n", .{ m.id, m.light, m.mid, m.dark });
            s.w("<linearGradient id='{s}_h' x1='0' y1='0' x2='1' y2='0'><stop offset='0' stop-color='{s}'/><stop offset='0.35' stop-color='{s}'/><stop offset='0.6' stop-color='{s}'/><stop offset='1' stop-color='{s}'/></linearGradient>\n", .{ m.id, m.dark, m.light, m.mid, m.dark });
        }
        s.w("</defs>\n<rect x='-34' y='-40' width='68' height='94' fill='{s}'/>\n", .{bg});
    }

    fn end(s: *Svg) void {
        s.w("</svg>\n", .{});
    }

    fn circle(s: *Svg, c: P, r: f32, attrs: []const u8) void {
        s.w("<circle cx='{d:.3}' cy='{d:.3}' r='{d:.3}' {s}/>\n", .{ c[0], c[1], r, attrs });
    }

    fn line(s: *Svg, a: P, b: P, attrs: []const u8) void {
        s.w("<line x1='{d:.3}' y1='{d:.3}' x2='{d:.3}' y2='{d:.3}' {s}/>\n", .{ a[0], a[1], b[0], b[1], attrs });
    }

    fn poly(s: *Svg, pts: []const P, attrs: []const u8) void {
        s.w("<polygon points='", .{});
        for (pts) |p| s.w("{d:.3},{d:.3} ", .{ p[0], p[1] });
        s.w("' {s}/>\n", .{attrs});
    }

    /// Text centred on a point at radius `r`, turned to read along the ring.
    fn ringText(s: *Svg, deg: f32, r: f32, size: f32, body: []const u8, attrs: []const u8) void {
        s.w("<text transform='rotate({d:.2}) translate(0 {d:.3})' font-size='{d:.2}' text-anchor='middle' dominant-baseline='central' {s}>{s}</text>\n", .{ deg, -r, size, attrs, body });
    }

    fn text(s: *Svg, at: P, size: f32, body: []const u8, attrs: []const u8) void {
        s.w("<text x='{d:.3}' y='{d:.3}' font-size='{d:.2}' {s}>{s}</text>\n", .{ at[0], at[1], size, attrs, body });
    }

    /// Radial tick marks. `every` picks which indices to draw (0 = all).
    fn ticks(s: *Svg, n: u32, r0: f32, r1: f32, every: u32, attrs: []const u8) void {
        var i: u32 = 0;
        while (i < n) : (i += 1) {
            if (every != 0 and i % every != 0) continue;
            const deg = 360.0 * @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(n));
            s.line(polar(deg, r0), polar(deg, r1), attrs);
        }
    }

    /// A two-tone faceted hand pointing along `deg`.
    fn hand(s: *Svg, c: P, deg: f32, len: f32, tail: f32, width: f32, m: Metal) void {
        s.w("<g transform='translate({d:.3} {d:.3}) rotate({d:.2})' filter='url(#sh2)'>", .{ c[0], c[1], deg });
        s.w("<polygon points='0,{d:.3} {d:.3},0 0,{d:.3}' fill='{s}'/>", .{ tail, -width / 2.0, -len, m.light });
        s.w("<polygon points='0,{d:.3} {d:.3},0 0,{d:.3}' fill='{s}'/>", .{ tail, width / 2.0, -len, m.mid });
        s.w("</g>\n", .{});
    }

    fn needle(s: *Svg, c: P, deg: f32, len: f32, tail: f32, color: []const u8) void {
        s.w("<g transform='translate({d:.3} {d:.3}) rotate({d:.2})' filter='url(#sh2)'><line x1='0' y1='{d:.3}' x2='0' y2='{d:.3}' stroke='{s}' stroke-width='0.22' stroke-linecap='round'/><circle r='0.55' fill='{s}'/></g>\n", .{ c[0], c[1], deg, tail, -len, color, color });
    }

    /// A toothed wheel with spokes.
    fn gear(s: *Svg, c: P, r: f32, teeth: u32, turn: f32, m: Metal) void {
        s.w("<g transform='translate({d:.3} {d:.3}) rotate({d:.1})'><polygon points='", .{ c[0], c[1], turn });
        var i: u32 = 0;
        while (i < teeth) : (i += 1) {
            const step = 360.0 / @as(f32, @floatFromInt(teeth));
            const a = step * @as(f32, @floatFromInt(i));
            for ([_][2]f32{ .{ 0.0, 0.9 }, .{ 0.2, 1.0 }, .{ 0.5, 1.0 }, .{ 0.7, 0.9 } }) |k| {
                const p = polar(a + step * k[0], r * k[1]);
                s.w("{d:.3},{d:.3} ", .{ p[0], p[1] });
            }
        }
        s.w("' fill='url(#{s})'/>", .{m.id});
        s.w("<circle r='{d:.3}' fill='#3a2706'/>", .{r * 0.72});
        i = 0;
        while (i < 5) : (i += 1) {
            const p = polar(72.0 * @as(f32, @floatFromInt(i)), r * 0.78);
            s.w("<line x1='0' y1='0' x2='{d:.3}' y2='{d:.3}' stroke='{s}' stroke-width='{d:.3}'/>", .{ p[0], p[1], m.mid, r * 0.13 });
        }
        s.w("<circle r='{d:.3}' fill='url(#{s})'/><circle r='{d:.3}' fill='#b3123a'/></g>\n", .{ r * 0.24, m.id, r * 0.1 });
    }

    /// Balance wheel with hairspring: the part of the mechanism that visibly beats.
    fn balance(s: *Svg, c: P, r: f32, m: Metal) void {
        s.w("<g transform='translate({d:.3} {d:.3})'>", .{ c[0], c[1] });
        s.w("<circle r='{d:.3}' fill='#08080a'/>", .{r * 1.12});
        s.w("<path d='M0 0", .{});
        var i: u32 = 1;
        while (i <= 140) : (i += 1) {
            const t = @as(f32, @floatFromInt(i)) / 140.0;
            const p = polar(t * 360.0 * 4.5, r * 0.62 * t);
            s.w(" L{d:.3} {d:.3}", .{ p[0], p[1] });
        }
        s.w("' fill='none' stroke='#8fa3c8' stroke-width='{d:.3}'/>", .{r * 0.035});
        s.w("<circle r='{d:.3}' fill='none' stroke='url(#{s})' stroke-width='{d:.3}'/>", .{ r * 0.9, m.id, r * 0.17 });
        for ([_]f32{ 20, 140, 260 }) |a| {
            const p = polar(a, r * 0.84);
            s.w("<line x1='0' y1='0' x2='{d:.3}' y2='{d:.3}' stroke='{s}' stroke-width='{d:.3}'/>", .{ p[0], p[1], m.mid, r * 0.11 });
        }
        s.w("<circle r='{d:.3}' fill='#b3123a' stroke='{s}' stroke-width='{d:.3}'/></g>\n", .{ r * 0.13, m.light, r * 0.05 });
    }

    fn screw(s: *Svg, c: P, r: f32, turn: f32) void {
        s.w("<g transform='translate({d:.3} {d:.3}) rotate({d:.1})'><circle r='{d:.3}' fill='url(#steel)' stroke='#22252a' stroke-width='0.06'/><line x1='{d:.3}' y1='0' x2='{d:.3}' y2='0' stroke='#22252a' stroke-width='{d:.3}'/></g>\n", .{ c[0], c[1], turn, r, -r * 0.8, r * 0.8, r * 0.28 });
    }

    /// A skeleton movement seen from the front, filling a circle of radius r.
    fn movement(s: *Svg, c: P, r: f32) void {
        s.w("<g transform='translate({d:.3} {d:.3})'>\n", .{ c[0], c[1] });
        s.circle(.{ 0, 0 }, r, "fill='url(#brass)'");
        var i: u32 = 1;
        while (i < 9) : (i += 1) s.circle(.{ 0, 0 }, r * @as(f32, @floatFromInt(i)) / 9.0, "fill='none' stroke='#5a3d0a' stroke-opacity='0.35' stroke-width='0.1'");
        s.gear(.{ -0.34 * r, -0.36 * r }, 0.44 * r, 44, 3, bronze);
        s.gear(.{ 0.42 * r, -0.40 * r }, 0.27 * r, 28, 10, steel);
        s.gear(.{ 0.10 * r, 0.02 * r }, 0.30 * r, 30, 0, bronze);
        s.gear(.{ 0.52 * r, 0.22 * r }, 0.22 * r, 22, 7, steel);
        s.gear(.{ 0.16 * r, 0.56 * r }, 0.17 * r, 15, 2, steel);
        s.balance(.{ -0.44 * r, 0.42 * r }, 0.30 * r, brass);
        // Bridges holding the wheels, with their screws.
        s.w("<path d='M{d:.3} {d:.3} Q{d:.3} {d:.3} {d:.3} {d:.3}' fill='none' stroke='url(#steel)' stroke-width='{d:.3}' stroke-linecap='round'/>\n", .{ -0.86 * r, 0.22 * r, -0.5 * r, 0.02 * r, -0.14 * r, 0.62 * r, 0.13 * r });
        s.w("<path d='M{d:.3} {d:.3} Q{d:.3} {d:.3} {d:.3} {d:.3}' fill='none' stroke='url(#steel)' stroke-width='{d:.3}' stroke-linecap='round'/>\n", .{ 0.2 * r, -0.82 * r, 0.66 * r, -0.2 * r, 0.8 * r, 0.3 * r, 0.11 * r });
        s.screw(.{ -0.86 * r, 0.22 * r }, 0.05 * r, 30);
        s.screw(.{ -0.14 * r, 0.62 * r }, 0.05 * r, 100);
        s.screw(.{ 0.2 * r, -0.82 * r }, 0.045 * r, 60);
        s.screw(.{ 0.8 * r, 0.3 * r }, 0.045 * r, 140);
        s.w("</g>\n", .{});
    }

    /// The emblem with its focal point at `at`. `explode` pushes each shard
    /// outward from the focal point by that many millimetres.
    fn emblem(s: *Svg, at: P, scale: f32, turn: f32, explode: f32, attrs: []const u8) void {
        s.w("<g transform='translate({d:.3} {d:.3}) rotate({d:.2})' {s}>\n", .{ at[0], at[1], turn, attrs });
        for (shards) |shard| {
            var cx: f32 = 0;
            var cy: f32 = 0;
            for (shard) |p| {
                cx += p[0] - focal[0];
                cy += p[1] - focal[1];
            }
            const len = @sqrt(cx * cx + cy * cy);
            const ox = explode * cx / len;
            const oy = explode * cy / len;
            s.w("<polygon points='", .{});
            for (shard) |p| s.w("{d:.3},{d:.3} ", .{ (p[0] - focal[0]) * scale + ox, (p[1] - focal[1]) * scale + oy });
            s.w("'/>\n", .{});
        }
        s.w("</g>\n", .{});
    }

    fn strap(s: *Svg, edge: []const u8, mid: []const u8, stitched: bool) void {
        s.w("<defs><linearGradient id='strap' x1='0' y1='0' x2='1' y2='0'><stop offset='0' stop-color='{s}'/><stop offset='0.5' stop-color='{s}'/><stop offset='1' stop-color='{s}'/></linearGradient></defs>\n", .{ edge, mid, edge });
        s.w("<rect x='-10' y='-40' width='20' height='83' fill='url(#strap)' filter='url(#sh)'/>\n", .{});
        if (stitched) {
            s.w("<path d='M-8.8 -40 V43 M8.8 -40 V43' stroke='#f1e3c4' stroke-width='0.22' stroke-dasharray='0.9 0.7' fill='none'/>\n", .{});
        }
    }

    fn caption(s: *Svg, color: []const u8, soft: []const u8, number: []const u8, name: []const u8, l1: []const u8, l2: []const u8) void {
        s.w("<text x='-30' y='-33.5' font-family='Inter, sans-serif' font-size='2.2' fill='{s}'>{s}</text>\n", .{ soft, number });
        s.w("<text x='-30' y='-29' font-family='Inter Display, Inter, sans-serif' font-weight='700' font-size='4.4' letter-spacing='-0.1' fill='{s}'>{s}</text>\n", .{ color, name });
        s.w("<text x='-30' y='47' font-family='Inter, sans-serif' font-size='1.6' fill='{s}'>{s}</text>\n", .{ color, l1 });
        s.w("<text x='-30' y='50' font-family='Inter, sans-serif' font-size='1.6' fill='{s}'>{s}</text>\n", .{ soft, l2 });
    }
};

// ------------------------------------------------------------------ the dial

/// SHATTER dial: the semicentric emblem cut clean through the dial plate, so
/// the mechanism shows through the five shard-shaped windows. `r` is the dial
/// radius; the emblem is centred and fills about 90% of the width.
fn shatterDial(s: *Svg, r: f32) void {
    const centre = P{ 256.0, 256.0 }; // middle of the emblem's bounding box
    const k = r * 1.8 / 430.0;

    s.circle(.{ 0, 0 }, r + 0.45, "fill='url(#steel_r)'");
    s.movement(.{ 0, 0 }, r);

    s.w("<defs><radialGradient id='plate' cx='0.3' cy='0.52' r='0.8'><stop offset='0' stop-color='#26272c'/><stop offset='1' stop-color='#050506'/></radialGradient><clipPath id='dialclip'><circle r='{d:.3}'/></clipPath></defs>\n", .{r});
    s.w("<path fill-rule='evenodd' fill='url(#plate)' filter='url(#sh)' d='M{d:.3} 0 A{d:.3} {d:.3} 0 1 0 {d:.3} 0 A{d:.3} {d:.3} 0 1 0 {d:.3} 0 Z", .{ -r, r, r, r, r, r, -r });
    for (shards) |shard| {
        for (shard, 0..) |p, n| s.w(" {s}{d:.3} {d:.3}", .{ if (n == 0) "M" else "L", (p[0] - centre[0]) * k, (p[1] - centre[1]) * k });
        s.w(" Z", .{});
    }
    s.w("'/>\n", .{});

    // Hairline fractures running on from each shard's tip to the edge.
    s.w("<g clip-path='url(#dialclip)'>\n", .{});
    const fx = (focal[0] - centre[0]) * k;
    const fy = (focal[1] - centre[1]) * k;
    for (shards) |shard| {
        var best: f32 = 0;
        var tip = P{ 0, 0 };
        for (shard) |p| {
            const x = (p[0] - centre[0]) * k;
            const y = (p[1] - centre[1]) * k;
            const d = (x - fx) * (x - fx) + (y - fy) * (y - fy);
            if (d > best) {
                best = d;
                tip = .{ x, y };
            }
        }
        const len = @sqrt(best);
        s.line(tip, .{ tip[0] + (tip[0] - fx) / len * 40.0, tip[1] + (tip[1] - fy) / len * 40.0 }, "stroke='#9aa0a8' stroke-opacity='0.55' stroke-width='0.07'");
    }
    s.w("</g>\n", .{});

    // Polished chamfer around every cut.
    s.w("<g transform='translate({d:.3} {d:.3})' fill='none' stroke-linejoin='miter'>\n", .{ -centre[0] * k, -centre[1] * k });
    for (shards) |shard| {
        for ([_][2][]const u8{ .{ "url(#steel)", "0.16" }, .{ "#0a0a0c", "0.04" } }) |pass| {
            s.w("<polygon points='", .{});
            for (shard) |p| s.w("{d:.3},{d:.3} ", .{ p[0] * k, p[1] * k });
            s.w("' stroke='{s}' stroke-width='{s}'/>\n", .{ pass[0], pass[1] });
        }
    }
    s.w("</g>\n", .{});

    s.ticks(60, r - 0.35, r - 0.95, 0, "stroke='#d9dbdf' stroke-width='0.09'");
    // Baton markers; 3 and 9 are left out because the emblem reaches the edge there.
    var h: u32 = 0;
    while (h < 12) : (h += 1) {
        if (h == 3 or h == 9) continue;
        s.line(polar(30.0 * @as(f32, @floatFromInt(h)), r - 0.45), polar(30.0 * @as(f32, @floatFromInt(h)), r - 2.5), "stroke='url(#steel)' stroke-width='0.75' filter='url(#sh2)'");
    }
    s.text(.{ r * 0.22, r * 0.62 }, r * 0.082, "semicentric", "font-family='Inter Display, Inter, sans-serif' font-weight='600' fill='#e9e9e6'");
    s.hand(.{ 0, 0 }, 305, r * 0.52, r * 0.12, r * 0.13, steel);
    s.hand(.{ 0, 0 }, 48, r * 0.82, r * 0.14, r * 0.1, steel);
    s.needle(.{ 0, 0 }, 196, r * 0.88, r * 0.22, "#ff4a26");
}

// ------------------------------------------------------------------ case shapes

/// Three-link metal bracelet running from y0 to the edge of the sheet on both
/// sides, tapering from w0 to w1.
fn bracelet(s: *Svg, m: Metal, w0: f32, w1: f32, y0: f32) void {
    for ([_]f32{ 1, -1 }) |sy| {
        s.w("<g transform='scale(1 {d})' filter='url(#sh)'>\n", .{sy});
        var row: u32 = 0;
        while (row < 5) : (row += 1) {
            const t = @min(1.0, @as(f32, @floatFromInt(row)) / 5.0);
            const half = (w0 + (w1 - w0) * t) / 2.0;
            const y = y0 + 3.9 * @as(f32, @floatFromInt(row));
            s.w("<rect x='{d:.3}' y='{d:.3}' width='{d:.3}' height='3.7' rx='0.5' fill='url(#{s}_h)' stroke='#0b0c0e' stroke-width='0.1'/>\n", .{ -half, y, half * 2.0, m.id });
            s.w("<rect x='{d:.3}' y='{d:.3}' width='{d:.3}' height='3.7' rx='0.5' fill='url(#{s})' stroke='#0b0c0e' stroke-width='0.1'/>\n", .{ -half * 0.42, y + 1.95, half * 0.84, m.id });
        }
        s.w("</g>\n", .{});
    }
}

fn crown(s: *Svg, m: Metal, deg: f32, r: f32, len: f32, width: f32) void {
    s.w("<g transform='rotate({d:.1})' filter='url(#sh)'><rect x='{d:.3}' y='{d:.3}' width='{d:.3}' height='{d:.3}' rx='0.5' fill='url(#{s}_r)'/>", .{ deg - 90.0, r, -width / 2.0, len, width, m.id });
    var n: u32 = 1;
    while (n < 6) : (n += 1) {
        const y = -width / 2.0 + width * @as(f32, @floatFromInt(n)) / 6.0;
        s.w("<line x1='{d:.3}' y1='{d:.3}' x2='{d:.3}' y2='{d:.3}' stroke='#0b0c0e' stroke-opacity='0.5' stroke-width='0.12'/>", .{ r + 0.5, y, r + len - 0.2, y });
    }
    s.w("</g>\n", .{});
}

/// A: classic dive-watch shape, like "Your Lucky Day".
fn caseDiver(s: *Svg) void {
    s.begin("#e9e9e6", &.{ steel, gun, brass, bronze });
    bracelet(s, steel, 20.0, 17.5, 23.6);
    for ([_]f32{ 1, -1 }) |sx| {
        for ([_]f32{ 1, -1 }) |sy| {
            s.w("<path transform='scale({d} {d})' d='M9.9 12 L9.9 25.2 Q11.4 26 12.9 25.3 Q14.6 18.5 17.4 10.5 Z' fill='url(#steel_h)' filter='url(#sh)'/>\n", .{ sx, sy });
        }
    }
    s.w("<path d='M19 -6.2 Q24.2 -5.6 24.2 -3 L24.2 3 Q24.2 5.6 19 6.2 Z' fill='url(#steel)' filter='url(#sh)'/>\n", .{});
    crown(s, steel, 90, 22.4, 4.2, 4.6);
    s.circle(.{ 0, 0 }, 20.6, "fill='url(#steel)' filter='url(#sh)'");
    s.ticks(120, 20.5, 19.2, 0, "stroke='#3c4047' stroke-width='0.3'");
    s.circle(.{ 0, 0 }, 19.2, "fill='#0b0c0f'");
    s.ticks(60, 18.6, 17.9, 0, "stroke='#aeb3bb' stroke-width='0.12'");
    for ([_]u32{ 10, 20, 30, 40, 50 }) |n| {
        var buf: [4]u8 = undefined;
        const label = std.fmt.bufPrint(&buf, "{d}", .{n}) catch unreachable;
        s.ringText(6.0 * @as(f32, @floatFromInt(n)), 17.75, 1.9, label, "font-family='Inter, sans-serif' font-weight='600' fill='#d9dbdf'");
    }
    s.poly(&.{ .{ -1.2, -18.8 }, .{ 1.2, -18.8 }, .{ 0, -16.7 } }, "fill='#e9e9e6'");
    shatterDial(s, 15.6);
    s.caption("#101010", "#6a6d73", "CASE A", "DIVER", "Round case, flowing lugs, crown guards, rotating coin-edge bezel.", "Closest to Your Lucky Day. Steel bracelet.");
    s.end();
}

/// B: cushion case, a rounded square.
fn caseCushion(s: *Svg) void {
    s.begin("#1a1b1e", &.{ steel, gun, brass, bronze });
    s.strap("#060607", "#232428", false);
    for ([_]f32{ 1, -1 }) |sx| {
        for ([_]f32{ 1, -1 }) |sy| {
            s.w("<path transform='scale({d} {d})' d='M10.1 15 L10.1 24.6 Q12.6 25 14.6 23.6 L17.6 16 Z' fill='url(#gun_h)' filter='url(#sh)'/>\n", .{ sx, sy });
        }
    }
    crown(s, gun, 90, 21.4, 3.6, 4.8);
    s.w("<rect x='-21.5' y='-21.5' width='43' height='43' rx='12.5' fill='url(#gun)' filter='url(#sh)'/>\n", .{});
    s.w("<rect x='-20.3' y='-20.3' width='40.6' height='40.6' rx='11.6' fill='url(#gun_r)'/>\n", .{});
    s.w("<rect x='-19.0' y='-19.0' width='38' height='38' rx='10.6' fill='url(#gun)'/>\n", .{});
    s.circle(.{ 0, 0 }, 16.9, "fill='url(#steel)'");
    s.circle(.{ 0, 0 }, 16.3, "fill='#0b0c0f'");
    shatterDial(s, 15.6);
    s.caption("#f4f4f0", "#8e939c", "CASE B", "CUSHION", "Rounded-square case with a round dial, short lugs, stepped bezel.", "Chunky and soft-edged. Dark gunmetal, rubber or leather strap.");
    s.end();
}

/// C: octagonal sports case with an integrated bracelet.
fn caseOctagon(s: *Svg) void {
    s.begin("#dfe1e4", &.{ steel, gun, brass, bronze });
    bracelet(s, steel, 27.0, 19.0, 22.5);
    crown(s, steel, 90, 20.6, 3.4, 4.4);
    s.w("<path d='M-19.6 -15 Q-21.6 0 -19.6 15 L-13.6 25.4 L13.6 25.4 L19.6 15 Q21.6 0 19.6 -15 L13.6 -25.4 L-13.6 -25.4 Z' fill='url(#steel_h)' filter='url(#sh)'/>\n", .{});
    var oct: [8]P = undefined;
    var inner: [8]P = undefined;
    for (&oct, &inner, 0..) |*o, *n, i| {
        o.* = polar(22.5 + 45.0 * @as(f32, @floatFromInt(i)), 21.2);
        n.* = polar(22.5 + 45.0 * @as(f32, @floatFromInt(i)), 19.9);
    }
    s.poly(&oct, "fill='url(#steel)' filter='url(#sh)'");
    s.poly(&inner, "fill='url(#steel_r)'");
    var i: u32 = 0;
    while (i < 8) : (i += 1) s.screw(polar(45.0 * @as(f32, @floatFromInt(i)), 17.45), 0.78, 30.0 + 45.0 * @as(f32, @floatFromInt(i)));
    s.circle(.{ 0, 0 }, 16.2, "fill='#0b0c0f'");
    shatterDial(s, 15.5);
    s.caption("#101010", "#6a6d73", "CASE C", "OCTAGON", "Eight-sided bezel with exposed screws; the case flows into the bracelet.", "Angular, so it echoes the shards. Brushed steel or titanium.");
    s.end();
}

/// D: an irregular faceted case, cut like the emblem itself.
fn caseShard(s: *Svg) void {
    s.begin("#141517", &.{ steel, titan, brass, bronze });
    s.strap("#060607", "#202124", false);
    const outline = [_]P{ .{ -15.5, -21.5 }, .{ 7.5, -24.0 }, .{ 20.8, -13.0 }, .{ 24.2, 3.4 }, .{ 13.6, 21.6 }, .{ -8.6, 24.2 }, .{ -21.4, 11.2 }, .{ -22.6, -8.4 } };
    crown(s, titan, 101, 22.6, 3.6, 4.4);
    s.poly(&outline, "fill='#55524d' filter='url(#sh)'");
    // Each facet runs from an outside edge in to the round dial opening.
    for (outline, 0..) |a, n| {
        const b = outline[(n + 1) % outline.len];
        const mx = (a[0] + b[0]) / 2.0;
        const my = (a[1] + b[1]) / 2.0;
        const facing = std.math.atan2(my, mx);
        const lit = 0.5 + 0.45 * @cos(facing - (-2.2)); // light from upper left
        const g: u32 = @intFromFloat(60.0 + 175.0 * lit);
        const la = @sqrt(a[0] * a[0] + a[1] * a[1]);
        const lb = @sqrt(b[0] * b[0] + b[1] * b[1]);
        const ia = P{ a[0] / la * 16.4, a[1] / la * 16.4 };
        const ib = P{ b[0] / lb * 16.4, b[1] / lb * 16.4 };
        s.w("<polygon points='{d:.3},{d:.3} {d:.3},{d:.3} {d:.3},{d:.3} {d:.3},{d:.3}' fill='rgb({d},{d},{d})' stroke='#101010' stroke-opacity='0.35' stroke-width='0.08'/>\n", .{ a[0], a[1], b[0], b[1], ib[0], ib[1], ia[0], ia[1], g, g - 4, g - 10 });
    }
    s.circle(.{ 0, 0 }, 16.9, "fill='url(#titan)'");
    s.circle(.{ 0, 0 }, 16.2, "fill='#0b0c0f'");
    shatterDial(s, 15.5);
    s.caption("#f4f4f0", "#8e939c", "CASE D", "SHARD", "Irregular faceted case cut like the emblem; no two sides match.", "The most unusual of the four. Suits 3D printing well. Titanium.");
    s.end();
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.arena.allocator();
    const cwd = std.Io.Dir.cwd();
    try cwd.createDirPath(io, "concepts");

    const Sheet = struct { file: []const u8, draw: *const fn (*Svg) void };
    const all = [_]Sheet{
        .{ .file = "concepts/case-a-diver.svg", .draw = caseDiver },
        .{ .file = "concepts/case-b-cushion.svg", .draw = caseCushion },
        .{ .file = "concepts/case-c-octagon.svg", .draw = caseOctagon },
        .{ .file = "concepts/case-d-shard.svg", .draw = caseShard },
    };
    for (all) |c| {
        var svg = Svg{ .gpa = gpa };
        c.draw(&svg);
        try cwd.writeFile(io, .{ .sub_path = c.file, .data = svg.out.items });
        std.debug.print("wrote {s}\n", .{c.file});
    }
}
