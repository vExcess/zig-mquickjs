//
// Micro QuickJS REPL stdlib host tool
//
// Ported from mqjs_stdlib.c
//

const std = @import("std");
const build = @import("mquickjs_build_lib.zig");
const tables = @import("mqjs_stdlib_tables.zig");

pub fn main() u8 {
    const allocator = std.heap.page_allocator;
    const args = std.process.argsAlloc(allocator) catch return 1;
    defer std.process.argsFree(allocator, args);
    return build.buildAtoms(
        "js_stdlib",
        tables.globalProps(.{}),
        tables.cFunctionDeclProps(.{}),
        args,
        "",
    ) catch 1;
}
