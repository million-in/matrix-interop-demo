// build.zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Build the benchmark executable
    const bench = b.addExecutable(.{
        .name = "bench",
        .root_module = b.createModule(.{
            .root_source_file = b.path("bench/bench.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    // Link C++ implementation
    bench.addCSourceFiles(.{
        .files = &.{"cpp/matrix.cpp"},
        .flags = &.{"-std=c++17"},
    });
    bench.addIncludePath(b.path("cpp"));
    bench.linkLibCpp();

    // Compile and link Zig implementation (it exports zig_matrix_multiply)
    const zig_obj = b.addObject(.{
        .name = "zig_matrix",
        .root_module = b.createModule(.{
            .root_source_file = b.path("zig/matrix.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    bench.addObject(zig_obj);

    // Link Rust static lib (GNU target)
    bench.addObjectFile(b.path("rust/target/x86_64-pc-windows-gnu/release/libmatrix_rs.a"));

    // On Windows GNU, we often need to link these for Rust/C++ interop
    bench.linkSystemLibrary("user32");
    bench.linkSystemLibrary("kernel32");
    bench.linkSystemLibrary("ws2_32");
    bench.linkSystemLibrary("advapi32");
    bench.linkSystemLibrary("ntdll");

    // Link libc for interop
    bench.linkLibC();

    b.installArtifact(bench);

    const run_cmd = b.addRunArtifact(bench);
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run the benchmark");
    run_step.dependOn(&run_cmd.step);
}
