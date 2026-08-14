//
// Shared engine accessors (JSValue, memory blocks, strings, arrays)
//

const ut = @import("mquickjs_utils_types.zig");

pub const c = ut.c;
pub const JSContextExt = ut.JSContextExt;
pub const JSObjectExt = ut.JSObjectExt;
pub const JSStringExt = ut.JSStringExt;
pub const JSValueArrayExt = ut.JSValueArrayExt;
pub const JSByteArrayExt = ut.JSByteArrayExt;
pub const JSVarRefExt = ut.JSVarRefExt;
pub const JSPropertyExt = ut.JSPropertyExt;

pub fn ctxExt(ctx: *c.JSContext) *JSContextExt {
    return @ptrCast(@alignCast(ctx));
}

pub fn valueToPtr(val: c.JSValue) *anyopaque {
    return @ptrFromInt(@as(usize, @intCast(val - 1)));
}

pub fn valueFromPtr(ptr: *anyopaque) c.JSValue {
    return @as(c.JSWord, @intCast(@intFromPtr(ptr))) + 1;
}

pub fn valueGetInt(v: c.JSValue) c_int {
    const as_int: i32 = @bitCast(@as(u32, @truncate(v)));
    return as_int >> 1;
}

pub fn valueGetSpecialTag(v: c.JSValue) c.JSWord {
    return v & ((@as(c.JSWord, 1) << c.JS_TAG_SPECIAL_BITS) - 1);
}

pub fn valueGetSpecialValue(v: c.JSValue) c_int {
    return @as(c_int, @intCast(v >> c.JS_TAG_SPECIAL_BITS));
}

pub fn isInt(v: c.JSValue) bool {
    return (v & 1) == c.JS_TAG_INT;
}

pub fn isPtr(v: c.JSValue) bool {
    return (v & (c.JSW - 1)) == c.JS_TAG_PTR;
}

pub fn isShortFloat(v: c.JSValue) bool {
    return (v & (c.JSW - 1)) == c.JS_TAG_SHORT_FLOAT;
}

pub fn isNull(v: c.JSValue) bool {
    return valueGetSpecialTag(v) == c.JS_TAG_NULL;
}

pub fn isException(v: c.JSValue) bool {
    return valueGetSpecialTag(v) == c.JS_TAG_EXCEPTION;
}

pub fn alignUp(size: c_uint, alignment: c_uint) c_uint {
    return (size + alignment - 1) & ~@as(c_uint, alignment - 1);
}

pub fn mbInit(ptr: *anyopaque, mtag: c_int) void {
    const w: *c.JSWord = @ptrCast(@alignCast(ptr));
    w.* = @as(c.JSWord, @intCast(mtag)) << 1;
}

pub fn mbGetMtag(ptr: *anyopaque) c_int {
    const w: *const c.JSWord = @ptrCast(@alignCast(ptr));
    return @intCast((w.* >> 1) & 0x7);
}

pub fn mbSetMtag(ptr: *anyopaque, mtag: c_int) void {
    const w: *c.JSWord = @ptrCast(@alignCast(ptr));
    w.* = (w.* & ~@as(c.JSWord, 0xe)) | (@as(c.JSWord, @intCast(mtag)) << 1);
}

pub fn mbSetFreeBlock(ptr: *anyopaque, size: c_uint) void {
    const w: *c.JSWord = @ptrCast(@alignCast(ptr));
    const payload_words = (size - @sizeOf(c.JSWord)) / @sizeOf(c.JSWord);
    w.* = (@as(c.JSWord, @intCast(ut.JS_MTAG_FREE)) << 1) | (@as(c.JSWord, payload_words) << 4);
}

pub fn objectClassId(p: *const JSObjectExt) c_int {
    return @intCast((p.header >> 4) & 0xff);
}

pub fn float64Value(ptr: *anyopaque) f64 {
    const bp: [*c]u8 = @ptrCast(ptr);
    const dptr: *f64 = @ptrCast(@alignCast(bp + @sizeOf(c.JSWord)));
    return dptr.*;
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

pub fn valueArrayItems(arr: *const JSValueArrayExt) [*]c.JSValue {
    return @constCast(@ptrCast(@alignCast(&arr.arr)));
}

pub fn valueArraySize(p: *const JSValueArrayExt) c_int {
    return @intCast(p.header >> 4);
}

pub fn valueArraySetSize(p: *JSValueArrayExt, size: c_int) void {
    p.header = (p.header & 0xf) | (@as(c.JSWord, @intCast(size)) << 4);
}

pub fn byteArrayBuf(arr: *const JSByteArrayExt) [*]u8 {
    return @constCast(@ptrCast(@alignCast(&arr.buf)));
}

pub fn byteArraySize(p: *const JSByteArrayExt) c_int {
    return @intCast(p.header >> 4);
}

pub fn byteArraySetSize(p: *JSByteArrayExt, size: c_int) void {
    p.header = (p.header & 0xf) | (@as(c.JSWord, @intCast(size)) << 4);
}

pub fn varRefIsDetached(p: *const JSVarRefExt) bool {
    return (p.header >> 4) & 1 != 0;
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
