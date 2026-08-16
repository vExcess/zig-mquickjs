//
// Engine struct layouts for mquickjs_value Zig port
//

const std = @import("std");

pub const mc = @import("mquickjs_utils_types.zig");
pub const mi = @import("mquickjs_internal.zig");
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
pub const JS_FLOAT64_VALUE_ADDEND: u64 = if (@sizeOf(c.JSWord) == 8)
    @as(u64, @bitCast(@as(i64, JS_FLOAT64_VALUE_EXP_MIN - (@as(i32, @intCast(c.JS_TAG_SHORT_FLOAT)) << 8)))) << 52
else
    0;

pub const StringBuffer = extern struct {
    buffer_ref: c.JSGCRef,
    len: c_int,
    is_ascii: c.JS_BOOL,
};

pub const JSROMClassExt = extern struct {
    header: c.JSWord,
    props: c.JSValue,
    ctor_idx: i32,
    // 64-bit only: proto_props is 8-byte aligned. 32-bit C has no gap.
    _pad: [if (@sizeOf(c.JSWord) == 8) 1 else 0]i32 = undefined,
    proto_props: c.JSValue,
    parent_class: c.JSValue,
};

pub const JSFloat64Ext = extern struct {
    header: c.JSWord,
    dval: f64,
};

pub const JSStringExt = mc.JSStringExt;
pub const JSStringCharBufExt = extern struct {
    header: c.JSWord,
    buf: [5]u8,
};

pub const JSValueArrayExt = mc.JSValueArrayExt;
pub const JSByteArrayExt = mc.JSByteArrayExt;
pub const JSVarRefExt = mc.JSVarRefExt;
pub const JSPropertyExt = mc.JSPropertyExt;

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
    return mi.valueGetInt(v);
}

pub fn newShortInt(val: i32) c.JSValue {
    if (@sizeOf(c.JSWord) == 8) {
        return @as(c.JSValue, @bitCast(@as(i64, val << 1)));
    }
    return @as(c.JSValue, @bitCast(@as(i32, val << 1)));
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

pub const stringBuf = mi.stringBuf;
pub const stringLen = mi.stringLen;
pub const stringIsUnique = mi.stringIsUnique;
pub const stringIsAscii = mi.stringIsAscii;
pub const stringIsNumeric = mi.stringIsNumeric;
pub const stringSetMeta = mi.stringSetMeta;
pub const stringSetUnique = mi.stringSetUnique;
pub const stringSetAscii = mi.stringSetAscii;
pub const stringSetNumeric = mi.stringSetNumeric;
pub const mbSetMtag = mi.mbSetMtag;
pub const valueArraySize = mi.valueArraySize;
pub const valueArraySetSize = mi.valueArraySetSize;
pub const valueArrayItems = mi.valueArrayItems;
pub const byteArraySize = mi.byteArraySize;
pub const byteArraySetSize = mi.byteArraySetSize;
pub const byteArrayBuf = mi.byteArrayBuf;
pub const varRefSetDetached = mi.varRefSetDetached;
pub const propHashNext = mi.propHashNext;
pub const propSetHashNext = mi.propSetHashNext;
pub const propType = mi.propType;
pub const propSetType = mi.propSetType;

pub fn findOwnPropertyInlined(p: *mc.JSObjectExt, prop: c.JSValue) ?*JSPropertyExt {
    const arr: *JSValueArrayExt = @ptrCast(@alignCast(mc.valueToPtr(p.props)));
    const items = valueArrayItems(arr);
    const hash_mask: u32 = @intCast(mi.valueGetInt(items[1]));
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
