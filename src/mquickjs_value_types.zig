//
// Engine struct layouts for mquickjs_value Zig port
//

const std = @import("std");

pub const mc = @import("mquickjs_utils_types.zig");
pub const c = mc.c;

pub const JS_SHORTINT_MIN: i32 = -(@as(i32, 1) << 30);
pub const JS_SHORTINT_MAX: i32 = (@as(i32, 1) << 30) - 1;
pub const JS_MTAG_BITS: u6 = 4;
pub const JS_STRING_LEN_MAX: u32 = 0x7ffffffe;
pub const JS_VALUE_ARRAY_SIZE_MAX: c_int = (@as(c_int, 1) << (32 - JS_MTAG_BITS)) - 1;
pub const JS_BYTE_ARRAY_SIZE_MAX: c_int = JS_VALUE_ARRAY_SIZE_MAX;
pub const JS_STRING_POS_CACHE_SIZE: usize = 2;
pub const JS_STRING_POS_CACHE_MIN_LEN: usize = 16;
pub const FRAME_CF_POP_RET: c_int = 1 << 17;
pub const magic_internalAt: c_int = 0;

pub const JS_PROP_NORMAL: u32 = 0;
pub const JS_PROP_GETSET: u32 = 1;
pub const JS_PROP_VARREF: u32 = 2;
pub const JS_PROP_SPECIAL: u32 = 3;

pub const JS_DEF_PROP_LOOKUP: c_int = 1 << 0;
pub const JS_DEF_PROP_RET_VAL: c_int = 1 << 1;
pub const JS_DEF_PROP_HAS_VALUE: c_int = 1 << 2;
pub const JS_DEF_PROP_HAS_GET: c_int = 1 << 3;
pub const JS_DEF_PROP_HAS_SET: c_int = 1 << 4;

pub const POS_TYPE_UTF8: c_int = 0;
pub const POS_TYPE_UTF16: c_int = 1;

pub const JS_FLOAT64_VALUE_EXP_MIN: i32 = 1023 - 127;
pub const JS_FLOAT64_VALUE_ADDEND: u64 =
    @as(u64, @bitCast(@as(i64, JS_FLOAT64_VALUE_EXP_MIN - (@as(i32, @intCast(c.JS_TAG_SHORT_FLOAT)) << 8)))) << 52;

pub const StringBuffer = extern struct {
    buffer_ref: c.JSGCRef,
    len: c_int,
    is_ascii: c.JS_BOOL,
};

pub const JSROMClassExt = extern struct {
    header: c.JSWord,
    props: c.JSValue,
    ctor_idx: i32,
    _pad: i32 = 0,
    proto_props: c.JSValue,
    parent_class: c.JSValue,
};

pub const JSFloat64Ext = extern struct {
    header: c.JSWord,
    dval: f64,
};

pub const JSStringExt = extern struct {
    header: c.JSWord,
    buf: [0]u8,
};

pub const JSStringCharBufExt = extern struct {
    header: c.JSWord,
    buf: [5]u8,
};

pub const JSValueArrayExt = extern struct {
    header: c.JSWord,
    arr: [0]c.JSValue,
};

pub const JSByteArrayExt = extern struct {
    header: c.JSWord,
    buf: [0]u8,
};

pub const JSVarRefExt = extern struct {
    header: c.JSWord,
    u: extern union {
        value: c.JSValue,
        live: extern struct {
            next: c.JSValue,
            pvalue: *c.JSValue,
        },
    },
};

pub const JSPropertyExt = extern struct {
    key: c.JSValue,
    value: c.JSValue,
    hash_and_type: u32,
    _pad: u32 = 0,
};

pub const JSCFunctionDefExt = extern struct {
    func: ?*const anyopaque,
    name: c.JSValue,
    def_type: u8,
    arg_count: u8,
    magic: i16,
};

pub const JSObjectUserDataExt = extern struct {
    opaque_val: ?*anyopaque,
};

pub fn rotl64(a: u64, n: u6) u64 {
    return std.math.rotl(u64, a, n);
}

pub fn valueGetInt(v: c.JSValue) c_int {
    const as_int: i32 = @bitCast(@as(u32, @truncate(v)));
    return as_int >> 1;
}

pub fn newShortInt(val: i32) c.JSValue {
    return @as(c.JSValue, @bitCast(@as(i64, val << 1)));
}

pub fn newStringChar(ch: u32) c.JSValue {
    return @as(c.JSValue, @intCast(c.JS_TAG_STRING_CHAR)) |
        (@as(c.JSValue, @intCast(ch)) << @as(u6, @intCast(c.JS_TAG_SPECIAL_BITS)));
}

pub fn newTailCall(val: c_int) c.JSValue {
    return @as(c.JSValue, @intCast(c.JS_TAG_EXCEPTION)) |
        (@as(c.JSValue, @intCast(c.JS_EX_CALL + val)) << @as(u6, @intCast(c.JS_TAG_SPECIAL_BITS)));
}

pub fn isNum(ch: c_int) c_int {
    return @intFromBool(ch >= '0' and ch <= '9');
}

pub fn isIntOrShortFloat(val: c.JSValue) bool {
    return mc.isInt(val) or mc.isShortFloat(val);
}

pub fn isUninitialized(val: c.JSValue) bool {
    return val == c.JS_UNINITIALIZED;
}

pub fn isUndefined(val: c.JSValue) bool {
    return val == c.JS_UNDEFINED;
}

pub fn isExactException(val: c.JSValue) bool {
    return val == c.JS_EXCEPTION;
}

pub fn utf8CharLen(byte: u8) c_int {
    if (byte < 0x80) return 1;
    if (byte < 0xc0) return 1;
    if (byte < 0xe0) return 2;
    if (byte < 0xf0) return 3;
    if (byte < 0xf8) return 4;
    return 1;
}

pub fn hashProp(prop: c.JSValue) u32 {
    const jsw: c.JSValue = @intCast(c.JSW);
    return @intCast((prop / jsw) ^ (prop % jsw));
}

pub fn jsIsRomPtr(ctx: *c.JSContext, ptr: *const anyopaque) bool {
    const x = mc.ctxExt(ctx);
    const p = @intFromPtr(ptr);
    return p < @intFromPtr(ctx) or p >= @intFromPtr(x.stack_top);
}

pub fn classProto(x: *mc.JSContextExt, class_id: c_int) *c.JSValue {
    const proto: [*]c.JSValue = @ptrCast(@alignCast(&x.class_proto));
    return &proto[@intCast(class_id)];
}

pub fn classObj(x: *mc.JSContextExt, class_id: c_int) *c.JSValue {
    const objs: [*]c.JSValue = @ptrCast(x.class_obj.?);
    return &objs[@intCast(class_id)];
}

pub fn cFunctionTable(x: *mc.JSContextExt) [*]const JSCFunctionDefExt {
    return @ptrCast(@alignCast(x.c_function_table));
}

pub fn objectSetClassAndExtra(p: *mc.JSObjectExt, class_id: c_int, extra_size: c.JSWord) void {
    p.header = (p.header & 0xf) |
        (@as(c.JSWord, @intCast(class_id)) << 4) |
        (extra_size << 12);
}

pub fn objectUserOpaque(p: *mc.JSObjectExt) *?*anyopaque {
    return @ptrCast(@alignCast(&p.u));
}

pub fn stringBuf(p: *const JSStringExt) [*]u8 {
    return @constCast(@ptrCast(@alignCast(&p.buf)));
}

pub fn stringLen(p: *const JSStringExt) usize {
    return @intCast(p.header >> 7);
}

pub fn stringIsUnique(p: *const JSStringExt) bool {
    return (p.header >> 4) & 1 != 0;
}

pub fn stringIsAscii(p: *const JSStringExt) bool {
    return (p.header >> 5) & 1 != 0;
}

pub fn stringIsNumeric(p: *const JSStringExt) bool {
    return (p.header >> 6) & 1 != 0;
}

pub fn stringSetMeta(p: *JSStringExt, is_unique: bool, is_ascii: bool, is_numeric: bool, len: usize) void {
    p.header = (p.header & 0xf) |
        (if (is_unique) @as(c.JSWord, 1) << 4 else 0) |
        (if (is_ascii) @as(c.JSWord, 1) << 5 else 0) |
        (if (is_numeric) @as(c.JSWord, 1) << 6 else 0) |
        (@as(c.JSWord, @intCast(len)) << 7);
}

pub fn stringSetUnique(p: *JSStringExt, v: bool) void {
    if (v) {
        p.header |= @as(c.JSWord, 1) << 4;
    } else {
        p.header &= ~(@as(c.JSWord, 1) << 4);
    }
}

pub fn stringSetAscii(p: *JSStringExt, v: bool) void {
    if (v) {
        p.header |= @as(c.JSWord, 1) << 5;
    } else {
        p.header &= ~(@as(c.JSWord, 1) << 5);
    }
}

pub fn stringSetNumeric(p: *JSStringExt, v: bool) void {
    if (v) {
        p.header |= @as(c.JSWord, 1) << 6;
    } else {
        p.header &= ~(@as(c.JSWord, 1) << 6);
    }
}

pub fn mbSetMtag(ptr: *anyopaque, mtag: c_int) void {
    const w: *c.JSWord = @ptrCast(@alignCast(ptr));
    w.* = (w.* & ~@as(c.JSWord, 0xe)) | (@as(c.JSWord, @intCast(mtag)) << 1);
}

pub fn valueArraySize(p: *const JSValueArrayExt) c_int {
    return @intCast(p.header >> 4);
}

pub fn valueArraySetSize(p: *JSValueArrayExt, size: c_int) void {
    p.header = (p.header & 0xf) | (@as(c.JSWord, @intCast(size)) << 4);
}

pub fn valueArrayItems(arr: *const JSValueArrayExt) [*]c.JSValue {
    return @constCast(@ptrCast(@alignCast(&arr.arr)));
}

pub fn byteArraySize(p: *const JSByteArrayExt) c_int {
    return @intCast(p.header >> 4);
}

pub fn byteArraySetSize(p: *JSByteArrayExt, size: c_int) void {
    p.header = (p.header & 0xf) | (@as(c.JSWord, @intCast(size)) << 4);
}

pub fn byteArrayBuf(arr: *const JSByteArrayExt) [*]u8 {
    return @constCast(@ptrCast(@alignCast(&arr.buf)));
}

pub fn varRefSetDetached(p: *JSVarRefExt, detached: bool) void {
    if (detached) {
        p.header |= @as(c.JSWord, 1) << 4;
    } else {
        p.header &= ~(@as(c.JSWord, 1) << 4);
    }
}

pub fn propHashNext(pr: *const JSPropertyExt) u32 {
    return pr.hash_and_type & 0x3fffffff;
}

pub fn propSetHashNext(pr: *JSPropertyExt, v: u32) void {
    pr.hash_and_type = (pr.hash_and_type & 0xc0000000) | (v & 0x3fffffff);
}

pub fn propType(pr: *const JSPropertyExt) u32 {
    return pr.hash_and_type >> 30;
}

pub fn propSetType(pr: *JSPropertyExt, t: u32) void {
    pr.hash_and_type = (pr.hash_and_type & 0x3fffffff) | (t << 30);
}

pub fn findOwnPropertyInlined(p: *mc.JSObjectExt, prop: c.JSValue) ?*JSPropertyExt {
    const arr: *JSValueArrayExt = @ptrCast(@alignCast(mc.valueToPtr(p.props)));
    const items = valueArrayItems(arr);
    const hash_mask: u32 = @intCast(mc.valueGetInt(items[1]));
    const h = hashProp(prop) & hash_mask;
    var idx: c.JSValue = items[2 + h];
    const jsw_half: c.JSValue = @intCast(@sizeOf(c.JSValue) / 2);
    while (idx != 0) {
        const pr: *JSPropertyExt = @ptrCast(@alignCast(
            @as([*]u8, @ptrCast(items)) + @as(usize, @intCast(idx * jsw_half)),
        ));
        if (pr.key == prop)
            return pr;
        idx = propHashNext(pr);
    }
    return null;
}

pub fn objectOffsetOfU() c_uint {
    return @intCast(@offsetOf(mc.JSObjectExt, "u"));
}

pub fn varRefAllocSize() c_uint {
    return @intCast(@sizeOf(JSVarRefExt) - @sizeOf(c.JSValue));
}

pub fn stringAllocSize(buf_len: u32) c_uint {
    return @intCast(@sizeOf(JSStringExt) + buf_len + 1);
}

pub fn valueArrayAllocSize(n: c_int) c_uint {
    return @intCast(@sizeOf(JSValueArrayExt) + @as(usize, @intCast(n)) * @sizeOf(c.JSValue));
}

pub fn byteArrayAllocSize(n: c_int) c_uint {
    return @intCast(@sizeOf(JSByteArrayExt) + @as(usize, @intCast(n)));
}
