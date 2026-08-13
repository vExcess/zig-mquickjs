//
// Micro QuickJS build utility types (stdlib codegen)
//
// Ported from mquickjs_build.h
//

pub const DefType = enum {
    end,
    cfunc,
    cgetset,
    prop_double,
    prop_undefined,
    prop_string,
    prop_null,
    class,
};

pub const Func = struct {
    length: u8,
    magic: [:0]const u8,
    cproto_name: [:0]const u8,
    func_name: [:0]const u8,
};

pub const GetSet = struct {
    magic: [:0]const u8,
    cproto_name: [:0]const u8,
    get_func_name: [:0]const u8,
    set_func_name: [:0]const u8,
};

pub const ClassDef = struct {
    name: [:0]const u8,
    length: c_int,
    cproto_name: ?[:0]const u8,
    func_name: ?[:0]const u8,
    class_id: ?[:0]const u8,
    class_props: ?[]const PropDef,
    proto_props: ?[]const PropDef,
    parent_class: ?*const ClassDef,
    finalizer_name: ?[:0]const u8,
};

pub const PropDef = struct {
    def_type: DefType,
    name: [:0]const u8 = "",
    u: union {
        none: void,
        func: Func,
        getset: GetSet,
        f64: f64,
        class1: *const ClassDef,
        str: [:0]const u8,
    } = .{ .none = {} },
};

pub fn propEnd() PropDef {
    return .{ .def_type = .end };
}

pub fn cfuncDef(name: [:0]const u8, length: u8, comptime func_name: [:0]const u8) PropDef {
    return .{
        .def_type = .cfunc,
        .name = name,
        .u = .{ .func = .{
            .length = length,
            .magic = "0",
            .cproto_name = "generic",
            .func_name = func_name,
        } },
    };
}

pub fn cfuncMagicDef(
    name: [:0]const u8,
    length: u8,
    comptime func_name: [:0]const u8,
    comptime magic: [:0]const u8,
) PropDef {
    return .{
        .def_type = .cfunc,
        .name = name,
        .u = .{ .func = .{
            .length = length,
            .magic = magic,
            .cproto_name = "generic_magic",
            .func_name = func_name,
        } },
    };
}

pub fn cfuncSpecialDef(
    name: [:0]const u8,
    length: u8,
    comptime proto: [:0]const u8,
    comptime func_name: [:0]const u8,
) PropDef {
    return .{
        .def_type = .cfunc,
        .name = name,
        .u = .{ .func = .{
            .length = length,
            .magic = "0",
            .cproto_name = proto,
            .func_name = func_name,
        } },
    };
}

pub fn cgetsetDef(
    name: [:0]const u8,
    comptime get_name: [:0]const u8,
    comptime set_name: [:0]const u8,
) PropDef {
    return .{
        .def_type = .cgetset,
        .name = name,
        .u = .{ .getset = .{
            .magic = "0",
            .cproto_name = "generic",
            .get_func_name = get_name,
            .set_func_name = set_name,
        } },
    };
}

pub fn cgetsetMagicDef(
    name: [:0]const u8,
    comptime get_name: [:0]const u8,
    comptime set_name: [:0]const u8,
    comptime magic: [:0]const u8,
) PropDef {
    return .{
        .def_type = .cgetset,
        .name = name,
        .u = .{ .getset = .{
            .magic = magic,
            .cproto_name = "generic_magic",
            .get_func_name = get_name,
            .set_func_name = set_name,
        } },
    };
}

pub fn propClassDef(name: [:0]const u8, class1: *const ClassDef) PropDef {
    return .{
        .def_type = .class,
        .name = name,
        .u = .{ .class1 = class1 },
    };
}

pub fn propDoubleDef(name: [:0]const u8, val: f64) PropDef {
    return .{
        .def_type = .prop_double,
        .name = name,
        .u = .{ .f64 = val },
    };
}

pub fn propUndefinedDef(name: [:0]const u8) PropDef {
    return .{
        .def_type = .prop_undefined,
        .name = name,
    };
}

pub fn propNullDef(name: [:0]const u8) PropDef {
    return .{
        .def_type = .prop_null,
        .name = name,
    };
}

pub fn propStringDef(name: [:0]const u8, cstr: [:0]const u8) PropDef {
    return .{
        .def_type = .prop_string,
        .name = name,
        .u = .{ .str = cstr },
    };
}

pub fn classDef(
    name: [:0]const u8,
    length: c_int,
    comptime func_name: [:0]const u8,
    comptime class_id: [:0]const u8,
    class_props: ?[]const PropDef,
    proto_props: ?[]const PropDef,
    parent_class: ?*const ClassDef,
    comptime finalizer_name: [:0]const u8,
) ClassDef {
    return .{
        .name = name,
        .length = length,
        .cproto_name = "constructor",
        .func_name = func_name,
        .class_id = class_id,
        .class_props = class_props,
        .proto_props = proto_props,
        .parent_class = parent_class,
        .finalizer_name = finalizer_name,
    };
}

pub fn classMagicDef(
    name: [:0]const u8,
    length: c_int,
    comptime func_name: [:0]const u8,
    comptime class_id: [:0]const u8,
    class_props: ?[]const PropDef,
    proto_props: ?[]const PropDef,
    parent_class: ?*const ClassDef,
    comptime finalizer_name: [:0]const u8,
) ClassDef {
    return .{
        .name = name,
        .length = length,
        .cproto_name = "constructor_magic",
        .func_name = func_name,
        .class_id = class_id,
        .class_props = class_props,
        .proto_props = proto_props,
        .parent_class = parent_class,
        .finalizer_name = finalizer_name,
    };
}

pub fn objectDef(name: [:0]const u8, obj_props: []const PropDef) ClassDef {
    return .{
        .name = name,
        .length = 0,
        .cproto_name = null,
        .func_name = null,
        .class_id = null,
        .class_props = obj_props,
        .proto_props = null,
        .parent_class = null,
        .finalizer_name = null,
    };
}
