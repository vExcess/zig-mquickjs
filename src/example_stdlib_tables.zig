//
// Micro QuickJS example stdlib tables
//
// Ported from example_stdlib.c
//

const bt = @import("mquickjs_build_types.zig");
const mqjs = @import("mqjs_stdlib_tables.zig");

const js_rectangle_proto = [_]bt.PropDef{
    bt.cgetsetDef("x", "js_rectangle_get_x", "NULL"),
    bt.cgetsetDef("y", "js_rectangle_get_y", "NULL"),
    bt.propEnd(),
};

const js_rectangle = [_]bt.PropDef{
    bt.cfuncDef("getClosure", 1, "js_rectangle_getClosure"),
    bt.cfuncDef("call", 2, "js_rectangle_call"),
    bt.propEnd(),
};

pub const js_rectangle_class: bt.ClassDef = bt.classDef(
    "Rectangle",
    2,
    "js_rectangle_constructor",
    "JS_CLASS_RECTANGLE",
    &js_rectangle,
    &js_rectangle_proto,
    null,
    "js_rectangle_finalizer",
);

const js_filled_rectangle_proto = [_]bt.PropDef{
    bt.cgetsetDef("color", "js_filled_rectangle_get_color", "NULL"),
    bt.propEnd(),
};

pub const js_filled_rectangle_class: bt.ClassDef = bt.classDef(
    "FilledRectangle",
    3,
    "js_filled_rectangle_constructor",
    "JS_CLASS_FILLED_RECTANGLE",
    null,
    &js_filled_rectangle_proto,
    &js_rectangle_class,
    "js_filled_rectangle_finalizer",
);

pub const global_object = mqjs.globalProps(.{
    .class_example = true,
    .rectangle_class = &js_rectangle_class,
    .filled_rectangle_class = &js_filled_rectangle_class,
});

pub const c_function_decl = mqjs.cFunctionDeclProps(.{
    .class_example = true,
});
