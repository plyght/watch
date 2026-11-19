const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "watch",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    b.installArtifact(exe);

    // `zig build run -- <model> [wrist w d zc]` writes out/<model>.obj
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    run_cmd.addPassthruArgs();
    const run_step = b.step("run", "Generate the watch geometry into out/");
    run_step.dependOn(&run_cmd.step);

    // `zig build concepts` writes the 2D concept sheets into concepts/
    const concepts = b.addExecutable(.{
        .name = "concepts",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/concepts.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const concepts_cmd = b.addRunArtifact(concepts);
    const concepts_step = b.step("concepts", "Draw the 2D concept sheets into concepts/");
    concepts_step.dependOn(&concepts_cmd.step);
}
