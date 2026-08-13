//
// Micro QuickJS example stdlib host tool
//
// Ported from example_stdlib.c
//

const std = @import("std");
const build = @import("mquickjs_build_lib.zig");
const tables = @import("example_stdlib_tables.zig");

pub fn main() u8 {
    const allocator = std.heap.page_allocator;
    const args = std.process.argsAlloc(allocator) catch return 1;
    defer std.process.argsFree(allocator, args);
    return build.buildAtoms(
        "js_stdlib",
        tables.global_object,
        tables.c_function_decl,
        args,
    ) catch 1;
}
