// And the build.zig is longer than the makefile
// Give it up for the best systems language having a horrible build system
// Still better than no official build system cough* cough* C

const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    if (optimize == .Debug or optimize == .ReleaseSafe) {
        std.debug.print("The C version of mquickjs relies on undefined behavior to function.\nIt cannot be compiled in debug or safe mode.\nRun zig build with -Doptimize=ReleaseFast or -Doptimize=ReleaseSmall\n", .{});
        return;
    }

    const configSmall = b.option(bool, "small", "Optimize for size") orelse true;
    const configSoftFloat = b.option(bool, "softfloat", "Use soft float") orelse false;

    var cFlags = try std.ArrayList([]const u8).initCapacity(b.allocator, 16);
    defer cFlags.deinit(b.allocator);
    try cFlags.appendSlice(b.allocator, &.{
        "-Wall",
        "-g",
        "-Werror",
        "-Wno-macro-redefined", // zig passes -DNDEBUG to the C compiler by default. we don't want this
        "-D_GNU_SOURCE",
        "-fno-math-errno",
        "-fno-trapping-math",
    });
    if (configSmall) {
        try cFlags.append(b.allocator, "-Os");
    } else {
        try cFlags.append(b.allocator, "-O2");
    }
    if (configSoftFloat) {
        try cFlags.append(b.allocator, "-msoft-float");
        try cFlags.append(b.allocator, "-DUSE_SOFTFLOAT");
    }

    var cHostFlags = try std.ArrayList([]const u8).initCapacity(b.allocator, 16);
    defer cHostFlags.deinit(b.allocator);
    try cHostFlags.appendSlice(b.allocator, &.{
        "-Wall",
        "-g",
        "-Werror",
        "-D_GNU_SOURCE",
        "-fno-math-errno",
        "-fno-trapping-math",
        "-O2",
    });

    // The standard library is compiled by a custom tool (mquickjs_build.c) to 
    // C structures that may reside in ROM. Hence the standard library 
    // instantiation is very fast and requires almost no RAM. An example of 
    // standard library for mqjs is provided in mqjs_stdlib.c. The result of 
    // its compilation is mqjs_stdlib.h
    const mqjs_stdlib_tool = b.addExecutable(.{
        .name = "mqjs_stdlib",
        .root_module = b.createModule(.{
            .target = b.graph.host,
            .optimize = .ReleaseFast,
            .link_libc = true,
        }),
    });
    mqjs_stdlib_tool.addCSourceFiles(.{
        .files = &.{ "mqjs_stdlib.c", "mquickjs_build.c" },
        .flags = cHostFlags.items,
    });

    // Generate Header Files
    const gen_atoms = b.addRunArtifact(mqjs_stdlib_tool);
    gen_atoms.addArg("-a");
    const mquickjs_atom_h = gen_atoms.captureStdOut();
    const gen_stdlib = b.addRunArtifact(mqjs_stdlib_tool);
    const mqjs_stdlib_h = gen_stdlib.captureStdOut();
    const wf = b.addWriteFiles();
    _ = wf.addCopyFile(mquickjs_atom_h, "mquickjs_atom.h");
    _ = wf.addCopyFile(mqjs_stdlib_h, "mqjs_stdlib.h");

    // example
    const example_stdlib_tool = b.addExecutable(.{
        .name = "example_stdlib",
        .root_module = b.createModule(.{
            .target = b.graph.host,
            .optimize = .ReleaseFast,
            .link_libc = true,
        }),
    });
    example_stdlib_tool.addCSourceFiles(.{
        .files = &.{ "example_stdlib.c", "mquickjs_build.c" },
        .flags = &.{ "-O2", "-D_GNU_SOURCE" },
    });
    const gen_example_stdlib = b.addRunArtifact(example_stdlib_tool);
    const example_stdlib_h = gen_example_stdlib.captureStdOut();
    const example_exe = b.addExecutable(.{
        .name = "example",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    _ = wf.addCopyFile(example_stdlib_h, "example_stdlib.h");
    example_exe.addConfigHeader(
        b.addConfigHeader(.{.style = .blank }, .{})
    );
    example_exe.addIncludePath(wf.getDirectory());
    example_exe.addIncludePath(b.path("."));
    example_exe.addCSourceFiles(.{
        .files = &.{
            "example.c",
            "mquickjs.c",
            "dtoa.c",
            "libm.c",
            "cutils.c",
        },
        .flags = cFlags.items,
    });
    const build_example_step = b.step("example", "Build example");
    const install_example = b.addInstallArtifact(example_exe, .{});
    build_example_step.dependOn(&install_example.step);

    // mqjs
    const exe = b.addExecutable(.{
        .name = "mqjs",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    exe.addCSourceFiles(.{
        .files = &.{
            "mqjs.c",
            "readline_tty.c",
            "readline.c",
            "mquickjs.c",
            "dtoa.c",
            "libm.c",
            "cutils.c",
        },
        .flags = cFlags.items,
    });
    exe.addConfigHeader(
        b.addConfigHeader(.{.style = .blank }, .{})
    );
    exe.addIncludePath(wf.getDirectory());
    exe.addIncludePath(b.path("."));
    b.installArtifact(exe);

    // make test
    // apparently stdio = .inherit; doesn't actually work
    // oh well I guess
    const test_step = b.step("test", "Run the tests duhhhhh");
    const js_tests = [_][]const u8{
        "tests/test_closure.js",
        "tests/test_language.js",
        "tests/test_loop.js",
        "tests/test_builtin.js",
    };
    for (js_tests) |test_path| {
        const run_test = b.addRunArtifact(exe);
        run_test.stdio = .inherit;
        run_test.addArg(test_path);
        test_step.dependOn(&run_test.step);
    }
    const gen_bytecode = b.addRunArtifact(exe);
    gen_bytecode.stdio = .inherit;
    gen_bytecode.addArg("-o");
    const bin_file = gen_bytecode.addOutputFileArg("test_builtin.bin");
    gen_bytecode.addArg("tests/test_builtin.js");
    const run_bytecode = b.addRunArtifact(exe);
    run_bytecode.stdio = .inherit;
    run_bytecode.addFileArg(bin_file);
    test_step.dependOn(&run_bytecode.step);

    // microbench
    const bench_step = b.step("microbench", "Run microbenchmarks");
    const run_bench = b.addRunArtifact(exe);
    run_bench.addArg("tests/microbench.js");
    bench_step.dependOn(&run_bench.step);

    // octane benchmark
    const octane_step = b.step("octane", "Run Octane benchmark");
    const run_octane = b.addRunArtifact(exe);
    run_octane.addArgs(&.{ "--memory-limit", "256M", "tests/octane/run.js" });
    octane_step.dependOn(&run_octane.step);

    std.debug.print("Build complete. The executable is located in ./zig-out/bin/\n", .{});
}