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
    mquickjs_engine_obj: *std.Build.Step.Compile,
) void {
    exe.addObject(mquickjs_engine_obj);
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

fn addFreestandingLibcIncludes(mod: *std.Build.Module, b: *std.Build) void {
    const zig_lib_path = b.graph.zig_lib_directory.path orelse @panic("missing zig lib directory");
    mod.addIncludePath(.{ .cwd_relative = b.fmt("{s}/libc/include/generic-musl", .{zig_lib_path}) });
    mod.addIncludePath(.{ .cwd_relative = b.fmt("{s}/libc/include/any-linux-any", .{zig_lib_path}) });
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
    const gen_atoms_wasm = b.addRunArtifact(mqjs_stdlib_tool);
    gen_atoms_wasm.addArgs(&.{ "-m32", "-a" });
    const mquickjs_atom_h_wasm = gen_atoms_wasm.captureStdOut();
    const gen_stdlib = b.addRunArtifact(mqjs_stdlib_tool);
    const mqjs_stdlib_h = gen_stdlib.captureStdOut();
    const gen_stdlib_zig = b.addRunArtifact(mqjs_stdlib_tool);
    gen_stdlib_zig.addArg("-z");
    const mqjs_stdlib_data_zig = gen_stdlib_zig.captureStdOut();
    const gen_stdlib_zig_wasm = b.addRunArtifact(mqjs_stdlib_tool);
    gen_stdlib_zig_wasm.addArgs(&.{ "-m32", "-z" });
    const mqjs_stdlib_data_zig_wasm = gen_stdlib_zig_wasm.captureStdOut();
    const wf = b.addWriteFiles();
    _ = wf.addCopyFile(mquickjs_atom_h, "mquickjs_atom.h");
    _ = wf.addCopyFile(mqjs_stdlib_h, "mqjs_stdlib.h");
    const mqjs_stdlib_data_file = wf.addCopyFile(mqjs_stdlib_data_zig, "mqjs_stdlib_data.zig");
    const mqjs_stdlib_data_file_wasm = wf.addCopyFile(mqjs_stdlib_data_zig_wasm, "mqjs_stdlib_data_wasm.zig");
    const wf_wasm = b.addWriteFiles();
    _ = wf_wasm.addCopyFile(mquickjs_atom_h_wasm, "mquickjs_atom.h");
    _ = wf_wasm.addCopyFile(mqjs_stdlib_h, "mqjs_stdlib.h");

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

    const mquickjs_engine_obj = b.addObject(.{
        .name = "mquickjs_engine",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .root_source_file = b.path("src/mquickjs_engine.zig"),
            .link_libc = true,
        }),
    });
    addCommonIncludes(mquickjs_engine_obj, b, wf);

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
    addRuntimeObjects(example_exe, cutils_obj, dtoa_obj, libm_obj, null, mquickjs_engine_obj);
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
    addRuntimeObjects(exe, cutils_obj, dtoa_obj, libm_obj, readline_obj, mquickjs_engine_obj);
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

    // wasm32-freestanding browser playground
    const wasm_target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .freestanding,
    });

    const wasm_cutils_obj = b.addObject(.{
        .name = "cutils_wasm",
        .root_module = b.createModule(.{
            .target = wasm_target,
            .optimize = optimize,
            .root_source_file = b.path("src/cutils.zig"),
            .link_libc = false,
        }),
    });
    addCommonIncludes(wasm_cutils_obj, b, wf_wasm);
    addFreestandingLibcIncludes(wasm_cutils_obj.root_module, b);

    const wasm_dtoa_obj = b.addObject(.{
        .name = "dtoa_wasm",
        .root_module = b.createModule(.{
            .target = wasm_target,
            .optimize = optimize,
            .root_source_file = b.path("src/dtoa.zig"),
            .link_libc = false,
        }),
    });
    addFreestandingLibcIncludes(wasm_dtoa_obj.root_module, b);

    const wasm_libm_obj = b.addObject(.{
        .name = "libm_wasm",
        .root_module = b.createModule(.{
            .target = wasm_target,
            .optimize = optimize,
            .root_source_file = b.path("src/libm.zig"),
            .link_libc = false,
        }),
    });
    wasm_libm_obj.root_module.addOptions("build_options", libm_opts);
    wasm_libm_obj.root_module.addIncludePath(b.path("include"));

    const wasm_engine_obj = b.addObject(.{
        .name = "mquickjs_engine_wasm",
        .root_module = b.createModule(.{
            .target = wasm_target,
            .optimize = optimize,
            .root_source_file = b.path("src/mquickjs_engine.zig"),
            .link_libc = false,
        }),
    });
    addCommonIncludes(wasm_engine_obj, b, wf_wasm);
    addFreestandingLibcIncludes(wasm_engine_obj.root_module, b);

    const mqjs_stdlib_data_mod_wasm = b.createModule(.{
        .root_source_file = mqjs_stdlib_data_file_wasm,
        .target = wasm_target,
        .optimize = optimize,
        .link_libc = false,
    });
    mqjs_stdlib_data_mod_wasm.addIncludePath(b.path("include"));
    mqjs_stdlib_data_mod_wasm.addIncludePath(wf_wasm.getDirectory());
    addFreestandingLibcIncludes(mqjs_stdlib_data_mod_wasm, b);

    const wasm_exe = b.addExecutable(.{
        .name = "mqjs",
        .root_module = b.createModule(.{
            .target = wasm_target,
            .optimize = optimize,
            .link_libc = false,
            .root_source_file = b.path("src/wasm_host.zig"),
            .imports = &.{
                .{ .name = "mqjs_stdlib_data", .module = mqjs_stdlib_data_mod_wasm },
            },
        }),
    });
    addCommonIncludes(wasm_exe, b, wf_wasm);
    addFreestandingLibcIncludes(wasm_exe.root_module, b);
    addRuntimeObjects(wasm_exe, wasm_cutils_obj, wasm_dtoa_obj, wasm_libm_obj, null, wasm_engine_obj);
    wasm_exe.entry = .disabled;
    wasm_exe.rdynamic = true;
    // 2 MiB JS heap + data + 1 MiB native stack. Emscripten demo uses 16 MiB.
    wasm_exe.stack_size = 1024 * 1024;
    wasm_exe.initial_memory = 16 * 1024 * 1024;
    wasm_exe.max_memory = 16 * 1024 * 1024;

    const wasm_step = b.step("wasm", "Build WebAssembly browser playground");
    const install_wasm = b.addInstallArtifact(wasm_exe, .{
        .dest_dir = .{ .override = .{ .custom = "web" } },
    });
    wasm_step.dependOn(&install_wasm.step);

    const copy_wasm_to_src = b.addSystemCommand(&.{ "cp", "-f" });
    copy_wasm_to_src.addFileArg(wasm_exe.getEmittedBin());
    copy_wasm_to_src.addArg(b.pathJoin(&.{ b.build_root.path.?, "web", "mqjs.wasm" }));
    copy_wasm_to_src.step.dependOn(&wasm_exe.step);
    wasm_step.dependOn(&copy_wasm_to_src.step);

    std.debug.print("Build complete. The executable is located in ./zig-out/bin/\n", .{});
}
