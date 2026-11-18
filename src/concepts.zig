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
        s.w("<circle r='{d:.3}' fill='#0b0b0e'/>", .{r * 0.72});
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
        s.circle(.{ 0, 0 }, r, "fill='#101014'");
        var i: u32 = 1;
        while (i < 9) : (i += 1) s.circle(.{ 0, 0 }, r * @as(f32, @floatFromInt(i)) / 9.0, "fill='none' stroke='#ffffff' stroke-opacity='0.05' stroke-width='0.08'");
        s.gear(.{ -0.34 * r, -0.36 * r }, 0.44 * r, 44, 3, brass);
        s.gear(.{ 0.42 * r, -0.40 * r }, 0.27 * r, 28, 10, brass);
        s.gear(.{ 0.10 * r, 0.02 * r }, 0.30 * r, 30, 0, brass);
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

    fn lugs(s: *Svg, m: Metal) void {
        for ([_]f32{ 1, -1 }) |sx| {
            for ([_]f32{ 1, -1 }) |sy| {
                const pts = [_]P{ .{ sx * 10.2, sy * 13.0 }, .{ sx * 15.8, sy * 12.0 }, .{ sx * 15.2, sy * 25.2 }, .{ sx * 10.2, sy * 26.6 } };
                s.w("<polygon points='", .{});
                for (pts) |p| s.w("{d:.3},{d:.3} ", .{ p[0], p[1] });
                s.w("' fill='url(#{s}_h)' filter='url(#sh)'/>\n", .{m.id});
            }
        }
    }

    fn caption(s: *Svg, color: []const u8, soft: []const u8, number: []const u8, name: []const u8, l1: []const u8, l2: []const u8) void {
        s.w("<text x='-30' y='-33.5' font-family='Inter, sans-serif' font-size='2.2' fill='{s}'>{s}</text>\n", .{ soft, number });
        s.w("<text x='-30' y='-29' font-family='Inter Display, Inter, sans-serif' font-weight='700' font-size='4.4' letter-spacing='-0.1' fill='{s}'>{s}</text>\n", .{ color, name });
        s.w("<text x='-30' y='47' font-family='Inter, sans-serif' font-size='1.6' fill='{s}'>{s}</text>\n", .{ color, l1 });
        s.w("<text x='-30' y='50' font-family='Inter, sans-serif' font-size='1.6' fill='{s}'>{s}</text>\n", .{ soft, l2 });
    }
};

// ------------------------------------------------------------------ concepts

/// 01 VAULT: a safe door on the wrist.
fn vault(s: *Svg) void {
    s.begin("#17181b", &.{ steel, gun, brass });
    s.strap("#050506", "#1d1e22", false);
    s.lugs(gun);
    // Three locking bolts thrown out of the case side; the middle one is the crown.
    for ([_]f32{ -7.2, 0, 7.2 }) |y| {
        const long: f32 = if (y == 0) 5.2 else 3.4;
        s.w("<rect x='19' y='{d:.3}' width='{d:.3}' height='3.6' rx='0.5' fill='url(#brass_h)' transform='rotate(90 {d:.3} {d:.3}) rotate(-90 {d:.3} {d:.3})' filter='url(#sh)'/>\n", .{ y - 1.8, long, 0.0, 0.0, 0.0, 0.0 });
    }
    s.circle(.{ 0, 0 }, 21.0, "fill='url(#gun)' filter='url(#sh)'");
    s.circle(.{ 0, 0 }, 20.2, "fill='url(#gun_r)'");
    s.circle(.{ 0, 0 }, 16.6, "fill='url(#gun)'");
    // Door bolts around the bezel.
    var i: u32 = 0;
    while (i < 8) : (i += 1) {
        const c = polar(22.5 + 45.0 * @as(f32, @floatFromInt(i)), 18.4);
        s.circle(c, 1.35, "fill='url(#brass)' filter='url(#sh2)'");
        var hex: [6]P = undefined;
        for (&hex, 0..) |*h, k| {
            const p = polar(60.0 * @as(f32, @floatFromInt(k)) + 15.0, 0.78);
            h.* = .{ c[0] + p[0], c[1] + p[1] };
        }
        s.poly(&hex, "fill='url(#brass_r)'");
    }
    s.text(.{ 0, 18.75 }, 1.05, "SEMICENTRIC", "font-family='Inter, sans-serif' font-weight='600' letter-spacing='0.35' text-anchor='middle' fill='#9ba0a9'");
    // Combination ring, numbered like a safe dial.
    s.circle(.{ 0, 0 }, 16.2, "fill='#08080a'");
    s.ticks(100, 16.0, 15.4, 0, "stroke='#d8d8d4' stroke-width='0.09'");
    s.ticks(100, 16.0, 14.9, 5, "stroke='#f4f4f0' stroke-width='0.13'");
    s.ticks(100, 16.0, 14.5, 10, "stroke='#ffffff' stroke-width='0.2'");
    i = 0;
    while (i < 10) : (i += 1) {
        var buf: [4]u8 = undefined;
        const label = std.fmt.bufPrint(&buf, "{d}", .{i * 10}) catch unreachable;
        s.ringText(36.0 * @as(f32, @floatFromInt(i)), 13.45, 1.55, label, "font-family='Inter, sans-serif' font-weight='600' fill='#f4f4f0'");
    }
    // The emblem is the lock's index mark, pointing in at 12.
    s.emblem(.{ 0, -20.7 }, 0.0125, 90, 0, "fill='#ff4a26'");
    // Open centre: the mechanism behind the spoked handle.
    s.circle(.{ 0, 0 }, 12.5, "fill='url(#gun_r)'");
    s.movement(.{ 0, 0 }, 12.1);
    s.circle(.{ 0, 0 }, 12.1, "fill='none' stroke='#000' stroke-opacity='0.55' stroke-width='0.5'");
    // Vault handle: turns once a minute in place of a seconds hand.
    s.w("<g transform='rotate(17)' filter='url(#sh)'>\n", .{});
    s.circle(.{ 0, 0 }, 9.0, "fill='none' stroke='url(#brass)' stroke-width='1.05'");
    i = 0;
    while (i < 5) : (i += 1) {
        const a = 72.0 * @as(f32, @floatFromInt(i));
        s.line(.{ 0, 0 }, polar(a, 10.6), "stroke='url(#brass_h)' stroke-width='1.0' stroke-linecap='round'");
        s.circle(polar(a, 10.9), 0.95, "fill='url(#brass)'");
    }
    s.circle(.{ 0, 0 }, 2.7, "fill='url(#brass)'");
    s.w("</g>\n", .{});
    s.hand(.{ 0, 0 }, 305, 7.6, 1.6, 2.0, steel);
    s.hand(.{ 0, 0 }, 52, 11.6, 2.0, 1.6, steel);
    s.circle(.{ 0, 0 }, 1.0, "fill='url(#steel)' stroke='#22252a' stroke-width='0.1'");
    s.caption("#f4f4f0", "#8e939c", "CONCEPT 01", "VAULT", "Safe-door bezel, combination ring, handle that turns once a minute.", "Mechanism on show behind it. Miyota 8N24 skeleton. Gunmetal + brass.");
    s.end();
}

/// 02 SHATTER: the dial is broken open along the emblem.
fn shatter(s: *Svg) void {
    s.begin("#e9e9e6", &.{ steel, gun, brass });
    s.strap("#1b1c1f", "#3a3c42", false);
    s.lugs(steel);
    s.w("<rect x='20' y='-2.4' width='4.6' height='4.8' rx='0.7' fill='url(#steel_h)' filter='url(#sh)'/>\n", .{});
    s.circle(.{ 0, 0 }, 21.0, "fill='url(#steel)' filter='url(#sh)'");
    // Twelve-sided bezel, each facet catching the light differently.
    var i: u32 = 0;
    while (i < 12) : (i += 1) {
        const a = 30.0 * @as(f32, @floatFromInt(i)) - 15.0;
        const shade = [_][]const u8{ "#f6f7f9", "#c9ced6", "#8e949d", "#5d626b", "#7b818a", "#b3b8c0" };
        const tri = [_]P{ .{ 0, 0 }, polar(a, 20.6), polar(a + 30.0, 20.6) };
        s.w("<polygon points='{d:.3},{d:.3} {d:.3},{d:.3} {d:.3},{d:.3}' fill='{s}'/>\n", .{ tri[0][0], tri[0][1], tri[1][0], tri[1][1], tri[2][0], tri[2][1], shade[(i + 5) % 6] });
    }
    s.circle(.{ 0, 0 }, 16.7, "fill='url(#steel_r)'");
    s.movement(.{ 0, 0 }, 16.2);

    // Dial plate with a jagged hole broken out around the focal point.
    const hit = P{ -4.6, 2.4 };
    const reach = [_]f32{ 10.5, 5.2, 12.5, 6.0, 9.0, 4.6, 11.5, 5.6, 8.8, 4.8, 13.0, 6.4 };
    var hole: [12]P = undefined;
    for (&hole, 0..) |*h, k| {
        const p = polar(30.0 * @as(f32, @floatFromInt(k)) + 8.0, reach[k]);
        var x = hit[0] + p[0];
        var y = hit[1] + p[1];
        const d = @sqrt(x * x + y * y);
        if (d > 14.2) { // keep the break inside the minute track
            x *= 14.2 / d;
            y *= 14.2 / d;
        }
        h.* = .{ x, y };
    }
    s.w("<path fill-rule='evenodd' fill='#0a0a0c' filter='url(#sh)' d='M-16.2 0 A16.2 16.2 0 1 0 16.2 0 A16.2 16.2 0 1 0 -16.2 0 Z M", .{});
    for (hole) |h| s.w("{d:.3} {d:.3} L", .{ h[0], h[1] });
    s.w("{d:.3} {d:.3} Z'/>\n", .{ hole[0][0], hole[0][1] });
    s.poly(&hole, "fill='none' stroke='#9aa0a8' stroke-width='0.12' stroke-linejoin='miter'");
    // Cracks running from the break out to the edge.
    s.w("<defs><clipPath id='dialclip'><circle r='16.2'/></clipPath></defs><g clip-path='url(#dialclip)'>\n", .{});
    for (hole, 0..) |h, k| {
        if (k % 2 == 1) continue;
        const dx = h[0] - hit[0];
        const dy = h[1] - hit[1];
        const d = @sqrt(dx * dx + dy * dy);
        s.line(h, .{ h[0] + dx / d * 9.0, h[1] + dy / d * 9.0 }, "stroke='#6d727a' stroke-width='0.07'");
    }
    s.w("</g>\n", .{});
    s.ticks(60, 15.9, 15.2, 0, "stroke='#e9e9e6' stroke-width='0.1'");
    s.ticks(12, 15.9, 14.2, 0, "stroke='#ffffff' stroke-width='0.45'");
    // The emblem's shards float over the break as polished bridges.
    s.emblem(hit, 0.054, 0, 0.6, "fill='url(#steel)' stroke='#ffffff' stroke-width='0.08' filter='url(#sh)'");
    s.text(.{ 3.2, 11.2 }, 1.25, "semicentric", "font-family='Inter Display, Inter, sans-serif' font-weight='600' fill='#e9e9e6'");
    s.hand(.{ 0, 0 }, 300, 8.4, 1.8, 2.1, steel);
    s.hand(.{ 0, 0 }, 48, 13.2, 2.2, 1.6, steel);
    s.needle(.{ 0, 0 }, 200, 14.2, 3.4, "#e23a1e");
    s.caption("#101010", "#6a6d73", "CONCEPT 02", "SHATTER", "Dial broken open around the emblem, mechanism showing through.", "Twelve-facet bezel. Miyota 8N24 skeleton. Steel or titanium.");
    s.end();
}

fn subdial(s: *Svg, c: P, r: f32, labels: []const []const u8, hand_deg: f32) void {
    s.w("<g transform='translate({d:.3} {d:.3})'>\n", .{ c[0], c[1] });
    s.circle(.{ 0, 0 }, r, "fill='#e4dcc6' stroke='#3c2a18' stroke-width='0.1'");
    var i: u32 = 1;
    while (i < 6) : (i += 1) s.circle(.{ 0, 0 }, r * @as(f32, @floatFromInt(i)) / 6.5, "fill='none' stroke='#3c2a18' stroke-opacity='0.13' stroke-width='0.05'");
    s.ticks(60, r * 0.96, r * 0.86, 0, "stroke='#1a1410' stroke-width='0.06'");
    s.ticks(12, r * 0.96, r * 0.76, 0, "stroke='#1a1410' stroke-width='0.14'");
    for (labels, 0..) |label, k| {
        const p = polar(360.0 * @as(f32, @floatFromInt(k)) / @as(f32, @floatFromInt(labels.len)), r * 0.55);
        s.w("<text x='{d:.3}' y='{d:.3}' font-family='DejaVu Serif, serif' font-size='{d:.2}' text-anchor='middle' dominant-baseline='central' fill='#1a1410'>{s}</text>\n", .{ p[0], p[1], r * 0.27, label });
    }
    s.hand(.{ 0, 0 }, hand_deg, r * 0.82, r * 0.25, r * 0.16, blued);
    s.circle(.{ 0, 0 }, r * 0.07, "fill='#0a1340'");
    s.w("</g>\n", .{});
}

/// 03 FATHOM: a ship's chronometer with two sub-dials.
fn fathom(s: *Svg) void {
    s.begin("#10202b", &.{ steel, bronze, blued });
    s.strap("#4d2e12", "#8a5a2b", true);
    s.lugs(bronze);
    // Onion crown and two mushroom pushers.
    s.w("<g filter='url(#sh)'><rect x='20' y='-1.1' width='2.2' height='2.2' fill='url(#bronze_h)'/><ellipse cx='24.4' cy='0' rx='2.6' ry='3.1' fill='url(#bronze)'/>", .{});
    for ([_]f32{ -1.8, -0.6, 0.6, 1.8 }) |y| s.w("<path d='M22.2 {d:.2} Q24.6 {d:.2} 26.8 {d:.2}' stroke='#46260f' stroke-width='0.14' fill='none'/>", .{ y, y * 1.5, y });
    s.w("</g>\n", .{});
    for ([_]f32{ 57, 123 }) |a| {
        s.w("<g transform='rotate({d:.1})' filter='url(#sh)'><rect x='-0.9' y='-23.4' width='1.8' height='3' fill='url(#bronze_h)'/><rect x='-1.7' y='-24.9' width='3.4' height='1.9' rx='0.6' fill='url(#bronze)'/></g>\n", .{a});
    }
    s.circle(.{ 0, 0 }, 21.0, "fill='url(#bronze)' filter='url(#sh)'");
    s.ticks(150, 20.8, 19.0, 0, "stroke='#46260f' stroke-width='0.2'");
    s.circle(.{ 0, 0 }, 18.9, "fill='url(#bronze_r)'");
    s.circle(.{ 0, 0 }, 17.5, "fill='url(#bronze)'");
    s.w("<defs><radialGradient id='enamel'><stop offset='0' stop-color='#fdfaf0'/><stop offset='0.8' stop-color='#f1ead7'/><stop offset='1' stop-color='#ddd3b9'/></radialGradient></defs>\n", .{});
    s.circle(.{ 0, 0 }, 17.0, "fill='url(#enamel)'");
    // Railroad minute track.
    s.circle(.{ 0, 0 }, 16.5, "fill='none' stroke='#1a1410' stroke-width='0.08'");
    s.circle(.{ 0, 0 }, 15.6, "fill='none' stroke='#1a1410' stroke-width='0.08'");
    s.ticks(60, 16.5, 15.6, 0, "stroke='#1a1410' stroke-width='0.08'");
    s.ticks(12, 16.5, 15.6, 0, "stroke='#1a1410' stroke-width='0.4'");
    const roman = [_][]const u8{ "XII", "I", "II", "", "IIII", "V", "", "VII", "VIII", "", "X", "XI" };
    for (roman, 0..) |n, k| {
        if (n.len == 0) continue;
        s.ringText(30.0 * @as(f32, @floatFromInt(k)), 12.9, 3.1, n, "font-family='DejaVu Serif, serif' fill='#1a1410'");
    }
    subdial(s, .{ -7.6, 0 }, 4.5, &.{ "60", "20", "40" }, 140);
    subdial(s, .{ 7.6, 0 }, 4.5, &.{ "30", "10", "20" }, 0);
    // Power-reserve style arc at 6 carrying the name.
    s.emblem(.{ -3.9, -6.3 }, 0.022, 0, 0, "fill='#1a1410'");
    s.text(.{ 0, 7.4 }, 1.3, "semicentric", "font-family='Inter Display, Inter, sans-serif' font-weight='600' text-anchor='middle' fill='#1a1410'");
    s.text(.{ 0, 9.5 }, 0.85, "CHRONOGRAPH", "font-family='DejaVu Serif, serif' letter-spacing='0.3' text-anchor='middle' fill='#7a1a12'");
    s.hand(.{ 0, 0 }, 304, 8.8, 2.0, 2.3, blued);
    s.hand(.{ 0, 0 }, 50, 14.6, 2.4, 1.7, blued);
    s.needle(.{ 0, 0 }, 0, 15.8, 4.2, "#7a1a12");
    s.caption("#f1ead7", "#8fa4b3", "CONCEPT 03", "FATHOM", "Ship's-chronometer face, two sub-dials, stopwatch pushers.", "Sea-Gull ST1901 chronograph, visible through the back. Bronze.");
    s.end();
}

/// 04 FOCAL: the burst radiates from a spinning tourbillon.
fn focalPoint(s: *Svg) void {
    s.begin("#d9d6cf", &.{ steel, titan, brass });
    s.strap("#0a0a0b", "#232326", false);
    s.lugs(titan);
    s.w("<rect x='20' y='-2.2' width='4.4' height='4.4' rx='1.2' fill='url(#titan_h)' filter='url(#sh)'/>\n", .{});
    s.circle(.{ 0, 0 }, 21.0, "fill='url(#titan)' filter='url(#sh)'");
    s.circle(.{ 0, 0 }, 19.2, "fill='url(#titan_r)'");
    s.circle(.{ 0, 0 }, 18.6, "fill='#0b0b0d'");
    // Rays engraved from the tourbillon, not from the dial centre.
    const eye = P{ 0, 7.4 };
    s.w("<defs><clipPath id='rayclip'><circle r='18.6'/></clipPath></defs><g clip-path='url(#rayclip)'>\n", .{});
    var i: u32 = 0;
    while (i < 120) : (i += 1) {
        const p = polar(3.0 * @as(f32, @floatFromInt(i)), 40.0);
        s.line(eye, .{ eye[0] + p[0], eye[1] + p[1] }, if (i % 2 == 0) "stroke='#ffffff' stroke-opacity='0.13' stroke-width='0.2'" else "stroke='#000000' stroke-opacity='0.5' stroke-width='0.16'");
    }
    s.w("</g>\n", .{});
    s.ticks(60, 18.2, 17.6, 0, "stroke='#d9d6cf' stroke-width='0.09'");
    s.ticks(12, 18.2, 16.6, 0, "stroke='#ffffff' stroke-width='0.5'");
    // Tourbillon: the whole escapement turns once a minute in this window.
    s.circle(eye, 6.1, "fill='url(#titan)' filter='url(#sh2)'");
    s.circle(eye, 5.6, "fill='#060608'");
    s.balance(eye, 4.0, brass);
    s.w("<g transform='translate({d:.3} {d:.3}) rotate(25)'>", .{ eye[0], eye[1] });
    s.circle(.{ 0, 0 }, 5.0, "fill='none' stroke='url(#steel)' stroke-width='0.45'");
    for ([_]f32{ 0, 120, 240 }) |a| {
        const p = polar(a, 5.0);
        s.w("<line x1='0' y1='0' x2='{d:.3}' y2='{d:.3}' stroke='url(#steel)' stroke-width='0.5'/>", .{ p[0], p[1] });
    }
    s.w("<polygon points='0,-5.6 0.6,-4.6 -0.6,-4.6' fill='#e23a1e'/></g>\n", .{});
    s.w("<rect x='-6.4' y='{d:.3}' width='12.8' height='1.5' rx='0.75' fill='url(#steel)' filter='url(#sh2)'/>\n", .{eye[1] - 0.75});
    s.screw(.{ -5.6, eye[1] }, 0.5, 40);
    s.screw(.{ 5.6, eye[1] }, 0.5, 120);
    s.circle(eye, 0.55, "fill='#b3123a' stroke='#ffe9a6' stroke-width='0.15'");
    // The emblem, burst outward around the tourbillon with its blade to 12.
    s.emblem(eye, 0.047, -90, 6.6, "fill='url(#steel)' stroke='#ffffff' stroke-width='0.07' filter='url(#sh)'");
    s.text(.{ -14.2, -4.6 }, 1.25, "semicentric", "font-family='Inter Display, Inter, sans-serif' font-weight='600' fill='#d9d6cf'");
    s.text(.{ -14.2, -2.9 }, 0.8, "TOURBILLON", "font-family='Inter, sans-serif' letter-spacing='0.3' fill='#86837d'");
    s.hand(.{ 0, 0 }, 300, 8.2, 1.8, 2.0, steel);
    s.hand(.{ 0, 0 }, 52, 13.4, 2.2, 1.5, steel);
    s.circle(.{ 0, 0 }, 0.9, "fill='url(#steel)' stroke='#22252a' stroke-width='0.1'");
    s.caption("#101010", "#6a6d73", "CONCEPT 04", "FOCAL", "The emblem bursts out of a tourbillon that turns once a minute.", "Off-centre engraved rays. Sea-Gull ST8000 tourbillon. Titanium.");
    s.end();
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.arena.allocator();
    const cwd = std.Io.Dir.cwd();
    try cwd.createDirPath(io, "concepts");

    const Concept = struct { file: []const u8, draw: *const fn (*Svg) void };
    const all = [_]Concept{
        .{ .file = "concepts/01-vault.svg", .draw = vault },
        .{ .file = "concepts/02-shatter.svg", .draw = shatter },
        .{ .file = "concepts/03-fathom.svg", .draw = fathom },
        .{ .file = "concepts/04-focal.svg", .draw = focalPoint },
    };
    for (all) |c| {
        var svg = Svg{ .gpa = gpa };
        c.draw(&svg);
        try cwd.writeFile(io, .{ .sub_path = c.file, .data = svg.out.items });
        std.debug.print("wrote {s}\n", .{c.file});
    }
}
