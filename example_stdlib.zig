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
        \\pub const JS_CLASS_RECTANGLE = c.JS_CLASS_USER + 0;
        \\pub const JS_CLASS_FILLED_RECTANGLE = c.JS_CLASS_USER + 1;
        \\pub const JS_CLASS_COUNT = c.JS_CLASS_USER + 2;
        \\pub const JS_CFUNCTION_rectangle_closure_test = c.JS_CFUNCTION_USER + 0;
        \\
    ) catch 1;
}
