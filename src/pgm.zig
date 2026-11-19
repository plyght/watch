//! Loads 16-bit binary PGM height maps (written by tools/extract_reference.py).

const std = @import("std");
const patterns = @import("patterns.zig");

pub fn load(gpa: std.mem.Allocator, io: std.Io, path: []const u8) !patterns.Heightmap {
    const bytes = try std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(64 << 20));
    // Header: "P5\n<w> <h>\n65535\n"
    var it = std.mem.tokenizeAny(u8, bytes, " \n\r\t");
    if (!std.mem.eql(u8, it.next() orelse return error.BadPgm, "P5")) return error.BadPgm;
    const w = try std.fmt.parseInt(usize, it.next() orelse return error.BadPgm, 10);
    const h = try std.fmt.parseInt(usize, it.next() orelse return error.BadPgm, 10);
    const maxval = try std.fmt.parseInt(u32, it.next() orelse return error.BadPgm, 10);
    if (maxval != 65535) return error.BadPgm;
    const start = it.index + 1; // one whitespace byte after maxval
    if (bytes.len < start + w * h * 2) return error.BadPgm;
    const data = try gpa.alloc(f32, w * h);
    for (data, 0..) |*d, i| {
        const v = std.mem.readInt(u16, bytes[start + 2 * i ..][0..2], .big);
        d.* = @as(f32, @floatFromInt(v)) / 65535.0;
    }
    return .{ .w = w, .h = h, .data = data };
}
