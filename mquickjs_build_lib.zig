//
// Micro QuickJS build utility
//
// Ported from mquickjs_build.c
//

const std = @import("std");
const builtin = @import("builtin");
const bt = @import("mquickjs_build_types.zig");

const ATOM_ALIGN: i32 = 256;

const JS_SHORTINT_MIN: f64 = -(@as(f64, 1) * (1 << 30));
const JS_SHORTINT_MAX: f64 = @as(f64, (1 << 30) - 1);

const predefined_atoms = [_][:0]const u8{
    "null",
    "false",
    "true",
    "if",
    "else",
    "return",
    "var",
    "this",
    "delete",
    "void",
    "typeof",
    "new",
    "in",
    "instanceof",
    "do",
    "while",
    "for",
    "break",
    "continue",
    "switch",
    "case",
    "default",
    "throw",
    "try",
    "catch",
    "finally",
    "function",
    "debugger",
    "with",
    "class",
    "const",
    "enum",
    "export",
    "extends",
    "import",
    "super",
    "implements",
    "interface",
    "let",
    "package",
    "private",
    "protected",
    "public",
    "static",
    "yield",
    "",
    "toString",
    "valueOf",
    "number",
    "object",
    "undefined",
    "string",
    "boolean",
    "<ret>",
    "<eval>",
    "eval",
    "arguments",
    "value",
    "get",
    "set",
    "prototype",
    "constructor",
    "length",
    "target",
    "of",
    "NaN",
    "Infinity",
    "-Infinity",
    "name",
    "Error",
    "__proto__",
    "index",
    "input",
};

const dummy_props = [_]bt.PropDef{bt.propEnd()};

const AtomDef = struct {
    str: []u8,
    offset: i32,
};

const CFuncDef = struct {
    name: []u8,
    length: i32,
    magic: []u8,
    cproto_name: []u8,
    cfunc_name: []u8,
};

const ClassDefEntry = struct {
    class1: *const bt.ClassDef,
    class_idx: i32,
    finalizer_name: ?[]u8,
    class_id: ?[]u8,
};

const PropsKind = enum {
    global,
    proto,
    class,
    object,
};

const BuildContext = struct {
    allocator: std.mem.Allocator,
    out: *std.Io.Writer,
    jsw: u32,
    atom_list: std.ArrayList(AtomDef),
    atom_offset: i32,
    cfunc_list: std.ArrayList(CFuncDef),
    class_list: std.ArrayList(ClassDefEntry),
    cur_offset: i32,
    sorted_atom_table_offset: i32,
    global_object_offset: i32,
};

fn minU32(a: u32, b: u32) u32 {
    return if (a < b) a else b;
}

fn clz32(a: u32) u32 {
    return @clz(a);
}

fn float64AsUint64(d: f64) u64 {
    return @bitCast(d);
}

fn isShortInt(d: f64) bool {
    return (d >= JS_SHORTINT_MIN and d <= JS_SHORTINT_MAX and @as(f64, @floatFromInt(@as(i32, @intFromFloat(d)))) == d);
}

fn cvtName(buf: []u8, str: []const u8) []const u8 {
    std.debug.assert(str.len < buf.len);
    if (str.len == 0) {
        const empty = "empty";
        @memcpy(buf[0..empty.len], empty);
        return buf[0..empty.len];
    }
    @memcpy(buf[0..str.len], str);
    for (buf[0..str.len]) |*ch| {
        if (ch.* == '<' or ch.* == '>' or ch.* == '-')
            ch.* = '_';
    }
    return buf[0..str.len];
}

fn isAsciiString(buf: []const u8) bool {
    for (buf) |ch| {
        if (ch > 0x7f) return false;
    }
    return true;
}

fn isNumericString(buf: []const u8) bool {
    return std.mem.eql(u8, buf, "NaN") or
        std.mem.eql(u8, buf, "Infinity") or
        std.mem.eql(u8, buf, "-Infinity");
}

fn findAtom(s: *const std.ArrayList(AtomDef), str: []const u8) i32 {
    for (s.items, 0..) |e, i| {
        if (std.mem.eql(u8, str, e.str))
            return @intCast(i);
    }
    return -1;
}

fn addAtom(ctx: *BuildContext, str: []const u8) !i32 {
    const i = findAtom(&ctx.atom_list, str);
    if (i >= 0)
        return ctx.atom_list.items[@intCast(i)].offset;
    const e = AtomDef{
        .str = try ctx.allocator.dupe(u8, str),
        .offset = ctx.atom_offset,
    };
    try ctx.atom_list.append(ctx.allocator, e);
    ctx.atom_offset += 1 + @as(i32, @intCast((str.len + ctx.jsw) / ctx.jsw));
    return @intCast(ctx.atom_list.items.len - 1);
}

fn addCfunc(
    ctx: *BuildContext,
    name: []const u8,
    length: i32,
    magic: []const u8,
    cproto_name: []const u8,
    cfunc_name: []const u8,
) !i32 {
    for (ctx.cfunc_list.items, 0..) |e, i| {
        if (std.mem.eql(u8, name, e.name) and
            length == e.length and
            std.mem.eql(u8, magic, e.magic) and
            std.mem.eql(u8, cproto_name, e.cproto_name) and
            std.mem.eql(u8, cfunc_name, e.cfunc_name))
        {
            return @intCast(i);
        }
    }
    try ctx.cfunc_list.append(ctx.allocator, .{
        .name = try ctx.allocator.dupe(u8, name),
        .length = length,
        .magic = try ctx.allocator.dupe(u8, magic),
        .cproto_name = try ctx.allocator.dupe(u8, cproto_name),
        .cfunc_name = try ctx.allocator.dupe(u8, cfunc_name),
    });
    return @intCast(ctx.cfunc_list.items.len - 1);
}

fn dumpAtomDefines(out: *std.Io.Writer, jsw: u32, allocator: std.mem.Allocator) !void {
    var ctx = BuildContext{
        .allocator = allocator,
        .out = out,
        .jsw = jsw,
        .atom_list = .empty,
        .atom_offset = 0,
        .cfunc_list = .empty,
        .class_list = .empty,
        .cur_offset = 0,
        .sorted_atom_table_offset = 0,
        .global_object_offset = 0,
    };
    defer deinitContext(&ctx);

    for (predefined_atoms) |atom| {
        _ = try addAtom(&ctx, atom);
    }

    var buf: [256]u8 = undefined;
    for (ctx.atom_list.items) |e| {
        try out.print("#define JS_ATOM_{s} {d}\n", .{ cvtName(&buf, e.str), e.offset });
    }
    try out.print("\n#define JS_ATOM_END {d}\n\n", .{ctx.atom_offset});
}

fn dumpAtoms(ctx: *BuildContext) !void {
    const s = &ctx.atom_list;
    const sorted_atoms = try ctx.allocator.dupe(AtomDef, s.items);
    defer ctx.allocator.free(sorted_atoms);
    std.mem.sort(AtomDef, sorted_atoms, {}, struct {
        fn lessThan(_: void, a: AtomDef, b: AtomDef) bool {
            return std.mem.order(u8, a.str, b.str) == .lt;
        }
    }.lessThan);

    try ctx.out.print("  /* atom_table */\n", .{});
    for (s.items) |e| {
        const str = e.str;
        const len: u32 = @intCast(str.len);
        const is_ascii: u32 = if (isAsciiString(str)) 1 else 0;
        const is_numeric: u32 = if (isNumericString(str)) 1 else 0;
        try ctx.out.print(
            "  (JS_MTAG_STRING << 1) | (1 << JS_MTAG_BITS) | ({d} << (JS_MTAG_BITS + 1)) | ({d} << (JS_MTAG_BITS + 2)) | ({d} << (JS_MTAG_BITS + 3)), /* \"{s}\" (offset={d}) */\n",
            .{ is_ascii, is_numeric, len, str, ctx.cur_offset },
        );
        const len1: u32 = (len + ctx.jsw) / ctx.jsw;
        var j: u32 = 0;
        while (j < len1) : (j += 1) {
            const l = minU32(ctx.jsw, len - j * ctx.jsw);
            var v: u64 = 0;
            var k: u32 = 0;
            while (k < l) : (k += 1) {
                v |= @as(u64, str[j * ctx.jsw + k]) << @intCast(k * 8);
            }
            if (ctx.jsw == 8) {
                try ctx.out.print("  0x{x:0>16},\n", .{v});
            } else {
                try ctx.out.print("  0x{x:0>8},\n", .{v});
            }
        }
        std.debug.assert(ctx.cur_offset == e.offset);
        ctx.cur_offset += @intCast(len1 + 1);
    }
    try ctx.out.print("\n", .{});

    ctx.sorted_atom_table_offset = ctx.cur_offset;

    try ctx.out.print("  /* sorted atom table (offset={d}) */\n", .{ctx.cur_offset});
    try ctx.out.print("  JS_VALUE_ARRAY_HEADER({d}),\n", .{s.items.len});
    var buf: [256]u8 = undefined;
    for (sorted_atoms) |e| {
        try ctx.out.print("  JS_ROM_VALUE({d}), /* {s} */\n", .{ e.offset, cvtName(&buf, e.str) });
    }
    ctx.cur_offset += @intCast(s.items.len + 1);
    try ctx.out.print("\n", .{});
}

fn dumpAtom(ctx: *BuildContext, str: []const u8, value_only: bool) !u32 {
    for (str) |ch| {
        if (ch >= 128) {
            std.debug.print("unicode property names are not supported yet ({s})\n", .{str});
            std.process.exit(1);
        }
    }
    if (str.len >= 1 and (str[0] >= '0' and str[0] <= '9')) {
        std.debug.print("numeric property names are not supported yet ({s})\n", .{str});
        std.process.exit(1);
    }
    if (str.len == 1) {
        if (value_only) {
            return (@as(u32, str[0]) << 5) | 0x1b;
        }
        try ctx.out.print("JS_VALUE_MAKE_SPECIAL(JS_TAG_STRING_CHAR, {d})", .{str[0]});
    } else {
        const idx = findAtom(&ctx.atom_list, str);
        if (idx < 0) {
            std.debug.print("atom '{s}' is undefined\n", .{str});
            std.process.exit(1);
        }
        const offset = ctx.atom_list.items[@intCast(idx)].offset;
        if (value_only)
            return @as(u32, @intCast(offset)) * ctx.jsw + 1;
        try ctx.out.print("JS_ROM_VALUE({d})", .{offset});
    }
    try ctx.out.print(" /* {s} */", .{str});
    return 0;
}

fn dumpCfuncs(ctx: *BuildContext) !void {
    try ctx.out.print("static const JSCFunctionDef js_c_function_table[] = {{\n", .{});
    for (ctx.cfunc_list.items) |e| {
        try ctx.out.print("  {{ {{ .{s} = {s} }},\n", .{ e.cproto_name, e.cfunc_name });
        try ctx.out.print("    ", .{});
        _ = try dumpAtom(ctx, e.name, false);
        try ctx.out.print(",\n", .{});
        try ctx.out.print("    JS_CFUNC_{s}, {d}, {s} }},\n", .{ e.cproto_name, e.length, e.magic });
    }
    try ctx.out.print("}};\n\n", .{});
}

fn dumpCfinalizers(ctx: *BuildContext) !void {
    try ctx.out.print("static const JSCFinalizer js_c_finalizer_table[JS_CLASS_COUNT - JS_CLASS_USER] = {{\n", .{});
    for (ctx.class_list.items) |e| {
        if (e.finalizer_name) |name| {
            if (!std.mem.eql(u8, name, "NULL")) {
                try ctx.out.print("  [{s} - JS_CLASS_USER] = {s},\n", .{ e.class_id.?, name });
            }
        }
    }
    try ctx.out.print("}};\n\n", .{});
}

fn hashProp(ctx: *BuildContext, name: []const u8) !u32 {
    const prop = try dumpAtom(ctx, name, true);
    return (prop / ctx.jsw) ^ (prop % ctx.jsw);
}

fn defineProps(
    ctx: *BuildContext,
    props_def_in: ?[]const bt.PropDef,
    props_kind: PropsKind,
    class_id_str: ?[:0]const u8,
) anyerror!i32 {
    const is_global_object = (props_kind == .global);
    const props_def = props_def_in orelse dummy_props[0..];

    var n_props: i32 = 0;
    for (props_def) |d| {
        if (d.def_type == .end) break;
        n_props += 1;
    }
    if (props_kind == .proto or props_kind == .class)
        n_props += 1;

    const ident_tab = try ctx.allocator.alloc(i32, @intCast(n_props));
    defer ctx.allocator.free(ident_tab);

    {
        var i: usize = 0;
        for (props_def) |*d| {
            if (d.def_type == .end) break;
            ident_tab[i] = try defineValue(ctx, d);
            i += 1;
        }
    }

    var props_ident: i32 = -1;
    var prop_hash: []u32 = &.{};
    defer if (prop_hash.len > 0) ctx.allocator.free(prop_hash);

    if (is_global_object) {
        props_ident = ctx.cur_offset;
        try ctx.out.print("  /* global object properties (offset={d}) */\n", .{props_ident});
        try ctx.out.print("  JS_VALUE_ARRAY_HEADER({d}),\n", .{2 * n_props});
        ctx.cur_offset += 2 * n_props + 1;
    } else {
        var hash_size_log2: u32 = 0;
        if (n_props > 1)
            hash_size_log2 = (32 - clz32(@intCast(n_props - 1))) - 1;
        var hash_size: u32 = @as(u32, 1) << @intCast(hash_size_log2);
        if (hash_size > @as(u32, @intCast(ATOM_ALIGN)) / ctx.jsw) {
            if (builtin.os.tag != .macos) {
                std.debug.print("Too many properties, consider increasing ATOM_ALIGN\n", .{});
            }
            hash_size = @as(u32, @intCast(ATOM_ALIGN)) / ctx.jsw;
        }
        const hash_mask: u32 = hash_size - 1;

        const hash_table = try ctx.allocator.alloc(u32, hash_size);
        defer ctx.allocator.free(hash_table);
        @memset(hash_table, 0);
        prop_hash = try ctx.allocator.alloc(u32, @intCast(n_props));

        var prop_idx: usize = 0;
        var i: usize = 0;
        while (i < @as(usize, @intCast(n_props))) : (i += 1) {
            const d = &props_def[i];
            const name: []const u8 = if (d.def_type != .end) d.name else if (props_kind == .proto) "constructor" else "prototype";
            const h = (try hashProp(ctx, name)) & hash_mask;
            prop_hash[prop_idx] = hash_table[h];
            hash_table[h] = @intCast(2 + hash_size + 3 * prop_idx);
            prop_idx += 1;
        }

        props_ident = ctx.cur_offset;
        try ctx.out.print("  /* properties (offset={d}) */\n", .{props_ident});
        try ctx.out.print("  JS_VALUE_ARRAY_HEADER({d}),\n", .{2 + hash_size + @as(u32, @intCast(n_props)) * 3});
        try ctx.out.print("  {d} << 1, /* n_props */\n", .{n_props});
        try ctx.out.print("  {d} << 1, /* hash_mask */\n", .{hash_mask});
        for (hash_table) |h| {
            try ctx.out.print("  {d} << 1,\n", .{h});
        }
        ctx.cur_offset += @intCast(hash_size + 3 + 3 * @as(u32, @intCast(n_props)));
    }

    var prop_idx: usize = 0;
    var i: usize = 0;
    while (i < @as(usize, @intCast(n_props))) : (i += 1) {
        const d = &props_def[i];
        try ctx.out.print("  ", .{});
        const name: []const u8 = if (d.def_type != .end) d.name else if (props_kind == .proto) "constructor" else "prototype";
        _ = try dumpAtom(ctx, name, false);
        try ctx.out.print(",\n", .{});

        try ctx.out.print("  ", .{});
        var prop_type: []const u8 = "NORMAL";
        switch (d.def_type) {
            .prop_double => {
                if (ident_tab[i] >= 0) {
                    try ctx.out.print("JS_ROM_VALUE({d}),", .{ident_tab[i]});
                } else {
                    try ctx.out.print("{d} << 1,", .{@as(i32, @intFromFloat(d.u.f64))});
                }
            },
            .cgetset => {
                if (is_global_object) {
                    std.debug.print("getter/setter forbidden in global object\n", .{});
                    std.process.exit(1);
                }
                prop_type = "GETSET";
                std.debug.assert(ident_tab[i] >= 0);
                try ctx.out.print("JS_ROM_VALUE({d}),", .{ident_tab[i]});
            },
            .class => {
                if (!is_global_object) {
                    std.debug.print("class definition only allowed in global object\n", .{});
                    std.process.exit(1);
                }
                std.debug.assert(ident_tab[i] >= 0);
                try ctx.out.print("JS_ROM_VALUE({d}),", .{ident_tab[i]});
            },
            .prop_undefined => {
                try ctx.out.print("JS_UNDEFINED,", .{});
            },
            .prop_null => {
                try ctx.out.print("JS_NULL,", .{});
            },
            .prop_string => {
                _ = try dumpAtom(ctx, d.u.str, false);
                try ctx.out.print(",", .{});
            },
            .cfunc => {
                const idx = try addCfunc(
                    ctx,
                    d.name,
                    d.u.func.length,
                    d.u.func.magic,
                    d.u.func.cproto_name,
                    d.u.func.func_name,
                );
                try ctx.out.print("JS_VALUE_MAKE_SPECIAL(JS_TAG_SHORT_FUNC, {d}),", .{idx});
            },
            .end => {
                if (props_kind == .proto) {
                    try ctx.out.print("(uint32_t)(-{s} - 1) << 1,", .{class_id_str.?});
                } else {
                    try ctx.out.print("{s} << 1,", .{class_id_str.?});
                }
                prop_type = "SPECIAL";
            },
        }
        try ctx.out.print("\n", .{});
        if (!is_global_object) {
            try ctx.out.print("  ({d} << 1) | (JS_PROP_{s} << 30),\n", .{ prop_hash[prop_idx], prop_type });
        }
        prop_idx += 1;
    }

    return props_ident;
}

fn findClass(ctx: *BuildContext, d: *const bt.ClassDef) ?*ClassDefEntry {
    for (ctx.class_list.items) |*e| {
        if (e.class1 == d)
            return e;
    }
    return null;
}

fn freeClassEntries(ctx: *BuildContext) void {
    for (ctx.class_list.items) |e| {
        if (e.class_id) |id| ctx.allocator.free(id);
        if (e.finalizer_name) |name| ctx.allocator.free(name);
    }
    ctx.class_list.clearRetainingCapacity();
}

fn defineClass(ctx: *BuildContext, d: *const bt.ClassDef) anyerror!i32 {
    if (findClass(ctx, d)) |e|
        return e.class_idx;

    var parent_class_idx: i32 = -1;
    if (d.parent_class) |parent|
        parent_class_idx = try defineClass(ctx, parent);

    var ctor_func_idx: i32 = -1;
    if (d.func_name) |func_name| {
        ctor_func_idx = try addCfunc(
            ctx,
            d.name,
            d.length,
            d.class_id.?,
            d.cproto_name.?,
            func_name,
        );
    }

    var class_props_idx: i32 = -1;
    var proto_props_idx: i32 = -1;
    if (ctor_func_idx >= 0) {
        class_props_idx = try defineProps(ctx, d.class_props, .class, d.class_id);
        proto_props_idx = try defineProps(ctx, d.proto_props, .proto, d.class_id);
    } else {
        if (d.class_props) |class_props|
            class_props_idx = try defineProps(ctx, class_props, .object, d.class_id);
    }

    const ident = ctx.cur_offset;
    try ctx.out.print("  /* class (offset={d}) */\n", .{ident});
    try ctx.out.print("  JS_MB_HEADER_DEF(JS_MTAG_OBJECT),\n", .{});
    if (class_props_idx >= 0)
        try ctx.out.print("  JS_ROM_VALUE({d}),\n", .{class_props_idx})
    else
        try ctx.out.print("  JS_NULL,\n", .{});
    try ctx.out.print("  {d},\n", .{ctor_func_idx});
    if (proto_props_idx >= 0)
        try ctx.out.print("  JS_ROM_VALUE({d}),\n", .{proto_props_idx})
    else
        try ctx.out.print("  JS_NULL,\n", .{});
    if (parent_class_idx >= 0) {
        try ctx.out.print("  JS_ROM_VALUE({d}),\n", .{parent_class_idx});
    } else {
        try ctx.out.print("  JS_NULL,\n", .{});
    }
    try ctx.out.print("\n", .{});

    ctx.cur_offset += 5;

    var class_id: ?[]u8 = null;
    var finalizer_name: ?[]u8 = null;
    if (ctor_func_idx >= 0) {
        class_id = try ctx.allocator.dupe(u8, d.class_id.?);
        finalizer_name = try ctx.allocator.dupe(u8, d.finalizer_name.?);
    }
    try ctx.class_list.append(ctx.allocator, .{
        .class_idx = ident,
        .class1 = d,
        .class_id = class_id,
        .finalizer_name = finalizer_name,
    });
    return ident;
}

fn defineValue(ctx: *BuildContext, d: *const bt.PropDef) anyerror!i32 {
    var ident: i32 = -1;
    switch (d.def_type) {
        .prop_double => {
            if (!isShortInt(d.u.f64)) {
                ident = ctx.cur_offset;
                try ctx.out.print("  /* float64 (offset={d}) */\n", .{ident});
                try ctx.out.print("  JS_MB_HEADER_DEF(JS_MTAG_FLOAT64),\n", .{});
                const v = float64AsUint64(d.u.f64);
                if (ctx.jsw == 8) {
                    try ctx.out.print("  0x{x:0>16},\n", .{v});
                    try ctx.out.print("\n", .{});
                    ctx.cur_offset += 2;
                } else {
                    try ctx.out.print("  0x{x:0>8},\n", .{@as(u32, @truncate(v))});
                    try ctx.out.print("  0x{x:0>8},\n", .{@as(u32, @truncate(v >> 32))});
                    try ctx.out.print("\n", .{});
                    ctx.cur_offset += 3;
                }
            }
        },
        .class => {
            ident = try defineClass(ctx, d.u.class1);
        },
        .cgetset => {
            var get_idx: i32 = -1;
            var set_idx: i32 = -1;
            var buf: [256]u8 = undefined;
            if (!std.mem.eql(u8, d.u.getset.get_func_name, "NULL")) {
                const name = std.fmt.bufPrint(&buf, "get {s}", .{d.name}) catch {
                    std.debug.print("name too long\n", .{});
                    std.process.exit(1);
                };
                get_idx = try addCfunc(
                    ctx,
                    name,
                    0,
                    d.u.getset.magic,
                    d.u.getset.cproto_name,
                    d.u.getset.get_func_name,
                );
            }
            if (!std.mem.eql(u8, d.u.getset.set_func_name, "NULL")) {
                const name = std.fmt.bufPrint(&buf, "set {s}", .{d.name}) catch {
                    std.debug.print("name too long\n", .{});
                    std.process.exit(1);
                };
                set_idx = try addCfunc(
                    ctx,
                    name,
                    1,
                    d.u.getset.magic,
                    d.u.getset.cproto_name,
                    d.u.getset.set_func_name,
                );
            }
            ident = ctx.cur_offset;
            try ctx.out.print("  /* getset (offset={d}) */\n", .{ident});
            try ctx.out.print("  JS_VALUE_ARRAY_HEADER(2),\n", .{});
            if (get_idx >= 0)
                try ctx.out.print("  JS_VALUE_MAKE_SPECIAL(JS_TAG_SHORT_FUNC, {d}),\n", .{get_idx})
            else
                try ctx.out.print("  JS_UNDEFINED,\n", .{});
            if (set_idx >= 0)
                try ctx.out.print("  JS_VALUE_MAKE_SPECIAL(JS_TAG_SHORT_FUNC, {d}),\n", .{set_idx})
            else
                try ctx.out.print("  JS_UNDEFINED,\n", .{});
            try ctx.out.print("\n", .{});
            ctx.cur_offset += 3;
        },
        else => {},
    }
    return ident;
}

fn defineAtomsClass(ctx: *BuildContext, d: *const bt.ClassDef) std.mem.Allocator.Error!void {
    if (findClass(ctx, d) != null)
        return;
    if (d.parent_class) |parent|
        try defineAtomsClass(ctx, parent);
    if (d.func_name != null)
        _ = try addAtom(ctx, d.name);
    if (d.class_props) |class_props|
        try defineAtomsProps(ctx, class_props, if (d.func_name != null) .class else .object);
    if (d.proto_props) |proto_props|
        try defineAtomsProps(ctx, proto_props, .proto);
}

fn defineAtomsProps(ctx: *BuildContext, props_def: []const bt.PropDef, props_kind: PropsKind) std.mem.Allocator.Error!void {
    _ = props_kind;
    for (props_def) |d| {
        if (d.def_type == .end) break;
        _ = try addAtom(ctx, d.name);
        switch (d.def_type) {
            .prop_string => {
                _ = try addAtom(ctx, d.u.str);
            },
            .class => {
                try defineAtomsClass(ctx, d.u.class1);
            },
            .cgetset => {
                var buf: [256]u8 = undefined;
                if (!std.mem.eql(u8, d.u.getset.get_func_name, "NULL")) {
                    const name = std.fmt.bufPrint(&buf, "get {s}", .{d.name}) catch {
                        std.debug.print("name too long\n", .{});
                        std.process.exit(1);
                    };
                    _ = try addAtom(ctx, name);
                }
                if (!std.mem.eql(u8, d.u.getset.set_func_name, "NULL")) {
                    const name = std.fmt.bufPrint(&buf, "set {s}", .{d.name}) catch {
                        std.debug.print("name too long\n", .{});
                        std.process.exit(1);
                    };
                    _ = try addAtom(ctx, name);
                }
            },
            else => {},
        }
    }
}

fn usage(out: *std.Io.Writer, name: []const u8) !u8 {
    try out.print("usage: {s} {{-m32 | -m64}} [-a]\n", .{name});
    try out.print(
        \\    create a ROM file for the mquickjs standard library
        \\--help       list options
        \\-m32         force generation for a 32 bit target
        \\-m64         force generation for a 64 bit target
        \\-a           generate the mquickjs_atom.h header
        \\
    , .{});
    return 1;
}

fn deinitContext(ctx: *BuildContext) void {
    for (ctx.atom_list.items) |e| ctx.allocator.free(e.str);
    ctx.atom_list.deinit(ctx.allocator);
    for (ctx.cfunc_list.items) |e| {
        ctx.allocator.free(e.name);
        ctx.allocator.free(e.magic);
        ctx.allocator.free(e.cproto_name);
        ctx.allocator.free(e.cfunc_name);
    }
    ctx.cfunc_list.deinit(ctx.allocator);
    freeClassEntries(ctx);
    ctx.class_list.deinit(ctx.allocator);
}

pub fn buildAtoms(
    stdlib_name: []const u8,
    global_obj: []const bt.PropDef,
    c_function_decl: ?[]const bt.PropDef,
    args: []const []const u8,
) !u8 {
    var jsw: u32 = if (@sizeOf(usize) >= 8) 8 else 4;
    var build_atom_defines = false;

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "-m64")) {
            jsw = 8;
        } else if (std.mem.eql(u8, args[i], "-m32")) {
            jsw = 4;
        } else if (std.mem.eql(u8, args[i], "-a")) {
            build_atom_defines = true;
        } else if (std.mem.eql(u8, args[i], "--help")) {
            var stderr_buf: [1024]u8 = undefined;
            var stderr_w = std.fs.File.stderr().writerStreaming(&stderr_buf);
            const code = try usage(&stderr_w.interface, args[0]);
            try stderr_w.interface.flush();
            return code;
        } else {
            var stderr_buf: [1024]u8 = undefined;
            var stderr_w = std.fs.File.stderr().writerStreaming(&stderr_buf);
            try stderr_w.interface.print("invalid argument '{s}'\n", .{args[i]});
            const code = try usage(&stderr_w.interface, args[0]);
            try stderr_w.interface.flush();
            return code;
        }
    }

    var stdout_buf: [8192]u8 = undefined;
    var stdout_w = std.fs.File.stdout().writerStreaming(&stdout_buf);
    const out = &stdout_w.interface;
    defer out.flush() catch {};

    const allocator = std.heap.page_allocator;

    if (build_atom_defines) {
        try dumpAtomDefines(out, jsw, allocator);
        return 0;
    }

    var ctx = BuildContext{
        .allocator = allocator,
        .out = out,
        .jsw = jsw,
        .atom_list = .empty,
        .atom_offset = 0,
        .cfunc_list = .empty,
        .class_list = .empty,
        .cur_offset = 0,
        .sorted_atom_table_offset = 0,
        .global_object_offset = 0,
    };
    defer deinitContext(&ctx);

    for (predefined_atoms) |atom| {
        _ = try addAtom(&ctx, atom);
    }

    if (c_function_decl) |decls| {
        for (decls) |d| {
            if (d.def_type == .end) break;
            if (d.def_type != .cfunc) {
                std.debug.print("only C functions are allowed in c_function_decl[]\n", .{});
                std.process.exit(1);
            }
            _ = try addAtom(&ctx, d.name);
            _ = try addCfunc(
                &ctx,
                d.name,
                d.u.func.length,
                d.u.func.magic,
                d.u.func.cproto_name,
                d.u.func.func_name,
            );
        }
    }

    try defineAtomsProps(&ctx, global_obj, .global);
    freeClassEntries(&ctx);

    try out.print("/* this file is automatically generated - do not edit */\n\n", .{});
    try out.print("#include \"mquickjs_priv.h\"\n\n", .{});
    try out.print("static const uint{d}_t __attribute((aligned({d}))) js_stdlib_table[] = {{\n", .{
        jsw * 8,
        ATOM_ALIGN,
    });

    try dumpAtoms(&ctx);

    ctx.global_object_offset = try defineProps(&ctx, global_obj, .global, null);

    try out.print("}};\n\n", .{});

    try dumpCfuncs(&ctx);

    try out.print(
        \\#ifndef JS_CLASS_COUNT
        \\#define JS_CLASS_COUNT JS_CLASS_USER /* total number of classes */
        \\#endif
        \\
        \\
    , .{});

    try dumpCfinalizers(&ctx);

    freeClassEntries(&ctx);

    try out.print("const JSSTDLibraryDef {s} = {{\n", .{stdlib_name});
    try out.print("  js_stdlib_table,\n", .{});
    try out.print("  js_c_function_table,\n", .{});
    try out.print("  js_c_finalizer_table,\n", .{});
    try out.print("  {d},\n", .{ctx.cur_offset});
    try out.print("  {d},\n", .{ATOM_ALIGN});
    try out.print("  {d},\n", .{ctx.sorted_atom_table_offset});
    try out.print("  {d},\n", .{ctx.global_object_offset});
    try out.print("  JS_CLASS_COUNT,\n", .{});
    try out.print("}};\n\n", .{});

    return 0;
}
