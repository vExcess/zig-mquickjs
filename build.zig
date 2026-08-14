// And the build.zig is longer than the makefile
// Give it up for the best systems language having a horrible build system
// Still better than no official build system cough* cough* C

const std = @import("std");

fn addRuntimeObjects(
    exe: *std.Build.Step.Compile,
    cutils_obj: *std.Build.Step.Compile,
    dtoa_obj: ?*std.Build.Step.Compile,
    libm_obj: ?*std.Build.Step.Compile,
    readline_obj: ?*std.Build.Step.Compile,
    mquickjs_utils_obj: *std.Build.Step.Compile,
    mquickjs_value_obj: *std.Build.Step.Compile,
    mquickjs_runtime_obj: *std.Build.Step.Compile,
    mquickjs_lexer_obj: *std.Build.Step.Compile,
    mquickjs_parser_obj: *std.Build.Step.Compile,
    mquickjs_gc_obj: *std.Build.Step.Compile,
    mquickjs_builtins_obj: *std.Build.Step.Compile,
) void {
    exe.addObject(mquickjs_utils_obj);
    exe.addObject(mquickjs_value_obj);
    exe.addObject(mquickjs_runtime_obj);
    exe.addObject(mquickjs_lexer_obj);
    exe.addObject(mquickjs_parser_obj);
    exe.addObject(mquickjs_gc_obj);
    exe.addObject(mquickjs_builtins_obj);
    exe.addObject(cutils_obj);
    if (dtoa_obj) |dtoa| {
        exe.addObject(dtoa);
    }
    if (libm_obj) |libm| {
        exe.addObject(libm);
    }
    if (readline_obj) |rl| {
        exe.addObject(rl);
    }
}

fn addCommonIncludes(
    exe: *std.Build.Step.Compile,
    b: *std.Build,
    wf: *std.Build.Step.WriteFile,
) void {
    exe.addConfigHeader(b.addConfigHeader(.{ .style = .blank }, .{}));
    exe.addIncludePath(wf.getDirectory());
    exe.addIncludePath(b.path("include"));
}

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    if (optimize == .Debug or optimize == .ReleaseSafe) {
        std.debug.print("The engine uses tagged-pointer JSValues that violate Zig's alignment checks in Debug/ReleaseSafe. \nRun zig build with -Doptimize=ReleaseFast or -Doptimize=ReleaseSmall\n", .{});
        return;
    }

    _ = b.option(bool, "small", "Optimize for size (no-op: no C translation units remain)");
    const configSoftFloat = b.option(bool, "softfloat", "Use soft float") orelse false;

    // The standard library is compiled by a custom tool (mquickjs_build_lib.zig)
    // to C structures that may reside in ROM. Hence the standard library
    // instantiation is very fast and requires almost no RAM. An example of
    // standard library for mqjs is provided in mqjs_stdlib_tables.zig. The
    // result of its compilation is mqjs_stdlib.h
    const mqjs_stdlib_tool = b.addExecutable(.{
        .name = "mqjs_stdlib",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/mqjs_stdlib.zig"),
            .target = b.graph.host,
            .optimize = .ReleaseFast,
        }),
    });

    // Generate Header Files
    const gen_atoms = b.addRunArtifact(mqjs_stdlib_tool);
    gen_atoms.addArg("-a");
    const mquickjs_atom_h = gen_atoms.captureStdOut();
    const gen_stdlib = b.addRunArtifact(mqjs_stdlib_tool);
    const mqjs_stdlib_h = gen_stdlib.captureStdOut();
    const gen_stdlib_zig = b.addRunArtifact(mqjs_stdlib_tool);
    gen_stdlib_zig.addArg("-z");
    const mqjs_stdlib_data_zig = gen_stdlib_zig.captureStdOut();
    const wf = b.addWriteFiles();
    _ = wf.addCopyFile(mquickjs_atom_h, "mquickjs_atom.h");
    _ = wf.addCopyFile(mqjs_stdlib_h, "mqjs_stdlib.h");
    const mqjs_stdlib_data_file = wf.addCopyFile(mqjs_stdlib_data_zig, "mqjs_stdlib_data.zig");

    // Compile the Zig version of cutils into an object file
    const cutils_obj = b.addObject(.{
        .name = "cutils",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .root_source_file = b.path("src/cutils.zig"),
            .link_libc = true,
        }),
    });

    // Compile the Zig version of readline into an object file
    const readline_obj = b.addObject(.{
        .name = "readline",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .root_source_file = b.path("src/readline.zig"),
            .link_libc = true,
        }),
    });

    const dtoa_obj = b.addObject(.{
        .name = "dtoa",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .root_source_file = b.path("src/dtoa.zig"),
            .link_libc = true,
        }),
    });

    const libm_obj = b.addObject(.{
        .name = "libm",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .root_source_file = b.path("src/libm.zig"),
            .link_libc = true,
        }),
    });
    const libm_opts = b.addOptions();
    libm_opts.addOption(bool, "softfloat", configSoftFloat);
    libm_obj.root_module.addOptions("build_options", libm_opts);
    libm_obj.root_module.addIncludePath(b.path("include"));

    const mquickjs_utils_obj = b.addObject(.{
        .name = "mquickjs_utils",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .root_source_file = b.path("src/mquickjs_utils.zig"),
            .link_libc = true,
        }),
    });
    addCommonIncludes(mquickjs_utils_obj, b, wf);

    const mquickjs_value_obj = b.addObject(.{
        .name = "mquickjs_value",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .root_source_file = b.path("src/mquickjs_value.zig"),
            .link_libc = true,
        }),
    });
    addCommonIncludes(mquickjs_value_obj, b, wf);

    const mquickjs_runtime_obj = b.addObject(.{
        .name = "mquickjs_runtime",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .root_source_file = b.path("src/mquickjs_runtime.zig"),
            .link_libc = true,
        }),
    });
    addCommonIncludes(mquickjs_runtime_obj, b, wf);

    const mquickjs_lexer_obj = b.addObject(.{
        .name = "mquickjs_lexer",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .root_source_file = b.path("src/mquickjs_lexer.zig"),
            .link_libc = true,
        }),
    });
    addCommonIncludes(mquickjs_lexer_obj, b, wf);

    const mquickjs_parser_obj = b.addObject(.{
        .name = "mquickjs_parser",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .root_source_file = b.path("src/mquickjs_parser.zig"),
            .link_libc = true,
        }),
    });
    addCommonIncludes(mquickjs_parser_obj, b, wf);

    const mquickjs_gc_obj = b.addObject(.{
        .name = "mquickjs_gc",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .root_source_file = b.path("src/mquickjs_gc.zig"),
            .link_libc = true,
        }),
    });
    addCommonIncludes(mquickjs_gc_obj, b, wf);

    const mquickjs_builtins_obj = b.addObject(.{
        .name = "mquickjs_builtins",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .root_source_file = b.path("src/mquickjs_builtins.zig"),
            .link_libc = true,
        }),
    });
    addCommonIncludes(mquickjs_builtins_obj, b, wf);

    // example
    const example_stdlib_tool = b.addExecutable(.{
        .name = "example_stdlib",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/example_stdlib.zig"),
            .target = b.graph.host,
            .optimize = .ReleaseFast,
        }),
    });
    const gen_example_stdlib = b.addRunArtifact(example_stdlib_tool);
    const example_stdlib_h = gen_example_stdlib.captureStdOut();
    const gen_example_stdlib_zig = b.addRunArtifact(example_stdlib_tool);
    gen_example_stdlib_zig.addArg("-z");
    const example_stdlib_data_zig = gen_example_stdlib_zig.captureStdOut();
    _ = wf.addCopyFile(example_stdlib_h, "example_stdlib.h");
    const example_stdlib_data_file = wf.addCopyFile(example_stdlib_data_zig, "example_stdlib_data.zig");

    const mqjs_stdlib_data_mod = b.createModule(.{
        .root_source_file = mqjs_stdlib_data_file,
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    mqjs_stdlib_data_mod.addIncludePath(b.path("include"));
    mqjs_stdlib_data_mod.addIncludePath(wf.getDirectory());

    const example_stdlib_data_mod = b.createModule(.{
        .root_source_file = example_stdlib_data_file,
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    example_stdlib_data_mod.addIncludePath(b.path("include"));
    example_stdlib_data_mod.addIncludePath(wf.getDirectory());

    const example_exe = b.addExecutable(.{
        .name = "example",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .root_source_file = b.path("src/example.zig"),
            .imports = &.{
                .{ .name = "example_stdlib_data", .module = example_stdlib_data_mod },
            },
        }),
    });
    addCommonIncludes(example_exe, b, wf);
    addRuntimeObjects(example_exe, cutils_obj, dtoa_obj, libm_obj, null, mquickjs_utils_obj, mquickjs_value_obj, mquickjs_runtime_obj, mquickjs_lexer_obj, mquickjs_parser_obj, mquickjs_gc_obj, mquickjs_builtins_obj);
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
            .root_source_file = b.path("src/mqjs.zig"),
            .imports = &.{
                .{ .name = "mqjs_stdlib_data", .module = mqjs_stdlib_data_mod },
            },
        }),
    });
    addRuntimeObjects(exe, cutils_obj, dtoa_obj, libm_obj, readline_obj, mquickjs_utils_obj, mquickjs_value_obj, mquickjs_runtime_obj, mquickjs_lexer_obj, mquickjs_parser_obj, mquickjs_gc_obj, mquickjs_builtins_obj);
    addCommonIncludes(exe, b, wf);
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
    run_bytecode.addArg("-b");
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
