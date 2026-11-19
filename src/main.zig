//! Watch geometry generator. Writes out/<model>.obj (flat on a table) or
//! out/<model>-wrist.obj (bracelet wrapped round a wrist).
//!
//!   zig build run -- <model> [wrist <half_width> <half_depth> <centre_z>]
//!
//! Models: diver, chamber (study of the reference watch), impact (the
//! semicentric take on it).

const std = @import("std");
const geo = @import("geo.zig");
const diver = @import("diver.zig");
const chamber = @import("chamber.zig");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.arena.allocator();
    const args = try init.minimal.args.toSlice(gpa);
    const model = if (args.len > 1) args[1] else "diver";

    var wrist: ?geo.Wrist = null;
    if (args.len >= 6 and std.mem.eql(u8, args[2], "wrist")) {
        wrist = .{
            .half_width = try std.fmt.parseFloat(f32, args[3]),
            .half_depth = try std.fmt.parseFloat(f32, args[4]),
            .centre_z = try std.fmt.parseFloat(f32, args[5]),
        };
    }

    var mesh = geo.Mesh{ .gpa = gpa };
    if (std.mem.eql(u8, model, "diver")) {
        diver.build(&mesh, wrist);
    } else if (std.mem.eql(u8, model, "chamber")) {
        try chamber.build(&mesh, gpa, io, .study, wrist);
    } else if (std.mem.eql(u8, model, "impact")) {
        try chamber.build(&mesh, gpa, io, .impact, wrist);
    } else {
        std.debug.print("unknown model '{s}' (diver, chamber, impact)\n", .{model});
        return error.UnknownModel;
    }

    const cwd = std.Io.Dir.cwd();
    try cwd.createDirPath(io, "out");
    const path = try std.fmt.allocPrint(gpa, "out/{s}{s}.obj", .{ model, if (wrist != null) "-wrist" else "" });
    try cwd.writeFile(io, .{ .sub_path = path, .data = mesh.out.items });
    std.debug.print("wrote {s} ({d} vertices)\n", .{ path, mesh.nv });
}
