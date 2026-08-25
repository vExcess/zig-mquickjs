//
// Micro QuickJS REPL stdlib host tool
//
// Ported from mqjs_stdlib.c
//

const std = @import("std");
const build = @import("mquickjs_build_lib.zig");
const tables = @import("mqjs_stdlib_tables.zig");

pub fn main(init: std.process.Init.Minimal) u8 {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const args = init.args.toSlice(arena.allocator()) catch return 1;
    return build.buildAtoms(
        "js_stdlib",
        tables.globalProps(.{}),
        tables.cFunctionDeclProps(.{}),
        args,
        "",
    ) catch 1;
}
