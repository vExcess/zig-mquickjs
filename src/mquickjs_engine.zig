//
// Micro QuickJS engine compilation unit
//
// Imports all engine implementation modules so they compile as a single
// object. C ABI symbols live in mquickjs_c_abi.zig.
//

pub const utils = @import("mquickjs_utils_lib.zig");
pub const value = @import("mquickjs_value_lib.zig");
pub const runtime = @import("mquickjs_runtime_lib.zig");
pub const lexer = @import("mquickjs_lexer_lib.zig");
pub const parser = @import("mquickjs_parser_lib.zig");
pub const gc = @import("mquickjs_gc_lib.zig");
pub const builtins = @import("mquickjs_builtins_lib.zig");

comptime {
    _ = utils;
    _ = value;
    _ = runtime;
    _ = lexer;
    _ = parser;
    _ = gc;
    _ = builtins;
    _ = @import("mquickjs_c_abi.zig");
}
