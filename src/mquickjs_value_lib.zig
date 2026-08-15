//
// Micro QuickJS engine values (shared implementation)
//
// Copyright (c) 2017-2025 Fabrice Bellard
// Copyright (c) 2017-2025 Charlie Gordon
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
// THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.
//

// Ported from C to Zig by Composer 2.5 + Grok 4.6 + Gemini 3 Pro + VExcess

const std = @import("std");
const cutils = @import("cutils_lib.zig");
const utils = @import("mquickjs_utils_lib.zig");
const dtoa = @import("dtoa_lib.zig");
const runtime = @import("mquickjs_runtime_lib.zig");
const builtins = @import("mquickjs_builtins_lib.zig");
const vt = @import("mquickjs_value_types.zig");
const mc = vt.mc;
pub const c = vt.c;

fn max_int(a: c_int, b: c_int) c_int {
    return if (a > b) a else b;
}

fn float64AsUint64(d: f64) u64 {
    return @bitCast(d);
}

fn uint64AsFloat64(u: u64) f64 {
    return @bitCast(u);
}

fn boolVal(v: bool) c.JS_BOOL {
    return @intFromBool(v);
}

pub fn js_get_short_float(v: c.JSValue) f64 {
    return uint64AsFloat64(vt.rotl64(v, 60) + vt.JS_FLOAT64_VALUE_ADDEND);
}

pub fn js_to_short_float(d: f64) c.JSValue {
    return vt.rotl64(float64AsUint64(d) -% vt.JS_FLOAT64_VALUE_ADDEND, 4);
}

pub fn js_alloc_float64(ctx: *c.JSContext, d: f64) c.JSValue {
    const f: *vt.JSFloat64Ext = @ptrCast(@alignCast(
        utils.js_malloc(ctx, @sizeOf(vt.JSFloat64Ext), mc.JS_MTAG_FLOAT64) orelse return c.JS_EXCEPTION,
    ));
    f.dval = d;
    return mc.valueFromPtr(f);
}

pub fn __JS_NewFloat64(ctx: *c.JSContext, d: f64) c.JSValue {
    if (float64AsUint64(d) == 0x8000000000000000) {
        return mc.ctxExt(ctx).minus_zero;
    } else if (@abs(d) >= 0x1p-127 and @abs(d) <= 0x1p+128) {
        return js_to_short_float(d);
    } else {
        return js_alloc_float64(ctx, d);
    }
}

pub fn JS_NewShortInt(val: i32) c.JSValue {
    return vt.newShortInt(val);
}

pub fn JS_NewFloat64(ctx: *c.JSContext, d: f64) c.JSValue {
    if (d >= @as(f64, @floatFromInt(vt.JS_SHORTINT_MIN)) and d <= @as(f64, @floatFromInt(vt.JS_SHORTINT_MAX))) {
        const val: i32 = @intFromFloat(d);
        if (float64AsUint64(d) == float64AsUint64(@as(f64, @floatFromInt(val))))
            return JS_NewShortInt(val);
    }
    return __JS_NewFloat64(ctx, d);
}

pub fn int64_is_short_int(val: i64) c.JS_BOOL {
    return boolVal(val >= vt.JS_SHORTINT_MIN and val <= vt.JS_SHORTINT_MAX);
}

pub fn JS_NewInt64(ctx: *c.JSContext, val: i64) c.JSValue {
    if (int64_is_short_int(val) != 0) {
        return JS_NewShortInt(@intCast(val));
    } else {
        return __JS_NewFloat64(ctx, @floatFromInt(val));
    }
}

pub fn JS_NewInt32(ctx: *c.JSContext, val: i32) c.JSValue {
    return JS_NewInt64(ctx, val);
}

pub fn JS_NewUint32(ctx: *c.JSContext, val: u32) c.JSValue {
    return JS_NewInt64(ctx, val);
}

pub fn JS_IsPrimitive(ctx: *c.JSContext, val: c.JSValue) c.JS_BOOL {
    _ = ctx;
    if (!mc.isPtr(val)) {
        return boolVal(mc.valueGetSpecialTag(val) != c.JS_TAG_SHORT_FUNC);
    } else {
        return boolVal(utils.js_get_mtag(mc.valueToPtr(val)) != mc.JS_MTAG_OBJECT);
    }
}

pub fn JS_IsObject(ctx: *c.JSContext, val: c.JSValue) c.JS_BOOL {
    _ = ctx;
    if (!mc.isPtr(val)) {
        return c.FALSE;
    } else {
        const p: *mc.JSObjectExt = @ptrCast(@alignCast(mc.valueToPtr(val)));
        return boolVal(mc.mbGetMtag(p) == mc.JS_MTAG_OBJECT);
    }
}

pub fn JS_GetClassID(ctx: *c.JSContext, val: c.JSValue) c_int {
    _ = ctx;
    if (!mc.isPtr(val)) {
        return -1;
    } else {
        const p: *mc.JSObjectExt = @ptrCast(@alignCast(mc.valueToPtr(val)));
        if (mc.mbGetMtag(p) != mc.JS_MTAG_OBJECT)
            return -1
        else
            return mc.objectClassId(p);
    }
}

pub fn JS_SetOpaque(ctx: *c.JSContext, val: c.JSValue, opaque_val: ?*anyopaque) void {
    _ = ctx;
    std.debug.assert(mc.isPtr(val));
    const p: *mc.JSObjectExt = @ptrCast(@alignCast(mc.valueToPtr(val)));
    std.debug.assert(mc.mbGetMtag(p) == mc.JS_MTAG_OBJECT);
    std.debug.assert(mc.objectClassId(p) >= c.JS_CLASS_USER);
    vt.objectUserOpaque(p).* = opaque_val;
}

pub fn JS_GetOpaque(ctx: *c.JSContext, val: c.JSValue) ?*anyopaque {
    _ = ctx;
    std.debug.assert(mc.isPtr(val));
    const p: *mc.JSObjectExt = @ptrCast(@alignCast(mc.valueToPtr(val)));
    std.debug.assert(mc.mbGetMtag(p) == mc.JS_MTAG_OBJECT);
    std.debug.assert(mc.objectClassId(p) >= c.JS_CLASS_USER);
    return vt.objectUserOpaque(p).*;
}

pub fn js_get_object_class(ctx: *c.JSContext, val: c.JSValue, class_id: c_int) ?*mc.JSObjectExt {
    _ = ctx;
    if (!mc.isPtr(val)) {
        return null;
    } else {
        const p: *mc.JSObjectExt = @ptrCast(@alignCast(mc.valueToPtr(val)));
        if (mc.mbGetMtag(p) != mc.JS_MTAG_OBJECT or mc.objectClassId(p) != class_id)
            return null
        else
            return p;
    }
}

pub fn JS_IsFunction(ctx: *c.JSContext, val: c.JSValue) c.JS_BOOL {
    _ = ctx;
    if (!mc.isPtr(val)) {
        return boolVal(mc.valueGetSpecialTag(val) == c.JS_TAG_SHORT_FUNC);
    } else {
        const p: *mc.JSObjectExt = @ptrCast(@alignCast(mc.valueToPtr(val)));
        const class_id = mc.objectClassId(p);
        return boolVal(mc.mbGetMtag(p) == mc.JS_MTAG_OBJECT and
            (class_id == c.JS_CLASS_CLOSURE or class_id == c.JS_CLASS_C_FUNCTION));
    }
}

pub fn JS_IsFunctionObject(ctx: *c.JSContext, val: c.JSValue) c.JS_BOOL {
    _ = ctx;
    if (!mc.isPtr(val)) {
        return c.FALSE;
    } else {
        const p: *mc.JSObjectExt = @ptrCast(@alignCast(mc.valueToPtr(val)));
        const class_id = mc.objectClassId(p);
        return boolVal(mc.mbGetMtag(p) == mc.JS_MTAG_OBJECT and
            (class_id == c.JS_CLASS_CLOSURE or class_id == c.JS_CLASS_C_FUNCTION));
    }
}

pub fn JS_IsError(ctx: *c.JSContext, val: c.JSValue) c.JS_BOOL {
    _ = ctx;
    if (!mc.isPtr(val)) {
        return c.FALSE;
    } else {
        const p: *mc.JSObjectExt = @ptrCast(@alignCast(mc.valueToPtr(val)));
        return boolVal(mc.mbGetMtag(p) == mc.JS_MTAG_OBJECT and mc.objectClassId(p) == c.JS_CLASS_ERROR);
    }
}

pub fn JS_IsNumber(ctx: *c.JSContext, val: c.JSValue) c.JS_BOOL {
    _ = ctx;
    if (vt.isIntOrShortFloat(val)) {
        return c.TRUE;
    } else if (mc.isPtr(val)) {
        return boolVal(utils.js_get_mtag(mc.valueToPtr(val)) == mc.JS_MTAG_FLOAT64);
    } else {
        return c.FALSE;
    }
}

pub fn JS_IsString(ctx: *c.JSContext, val: c.JSValue) c.JS_BOOL {
    _ = ctx;
    if (!mc.isPtr(val)) {
        return boolVal(mc.valueGetSpecialTag(val) == c.JS_TAG_STRING_CHAR);
    } else {
        return boolVal(utils.js_get_mtag(mc.valueToPtr(val)) == mc.JS_MTAG_STRING);
    }
}

pub fn js_alloc_string(ctx: *c.JSContext, buf_len: u32) ?*vt.JSStringExt {
    if (buf_len > vt.JS_STRING_LEN_MAX) {
        _ = utils.JS_ThrowError(ctx, c.JS_CLASS_INTERNAL_ERROR, "string too long");
        return null;
    }
    const p: *vt.JSStringExt = @ptrCast(@alignCast(
        utils.js_malloc(ctx, vt.stringAllocSize(buf_len), mc.JS_MTAG_STRING) orelse return null,
    ));
    vt.stringSetMeta(p, false, false, false, buf_len);
    vt.stringBuf(p)[buf_len] = 0;
    return p;
}

pub fn JS_NewStringChar(ch: u32) c.JSValue {
    return vt.newStringChar(ch);
}

pub fn is_ascii_string(buf: [*c]const u8, len: usize) c.JS_BOOL {
    var i: usize = 0;
    while (i < len) : (i += 1) {
        if (buf[i] > 0x7f)
            return c.FALSE;
    }
    return c.TRUE;
}

pub fn get_string_ptr(ctx: *c.JSContext, buf: *vt.JSStringCharBufExt, val: c.JSValue) *vt.JSStringExt {
    _ = ctx;
    if (mc.valueGetSpecialTag(val) == c.JS_TAG_STRING_CHAR) {
        const p: *vt.JSStringExt = @ptrCast(@alignCast(buf));
        const ascii = mc.valueGetSpecialValue(val) <= 0x7f;
        const len: u32 = @intCast(utils.get_short_string(&buf.buf, val));
        vt.stringSetMeta(p, false, ascii, false, len);
        return p;
    } else {
        return @ptrCast(@alignCast(mc.valueToPtr(val)));
    }
}

pub fn js_sub_string_utf8(ctx: *c.JSContext, val: c.JSValue, start0: u32, end0: u32) c.JSValue {
    var val_mut = val;
    if (end0 - start0 == 0) {
        return utils.js_get_atom(ctx, c.JS_ATOM_empty);
    }
    const start_surrogate = start0 & 1 != 0;
    const end_surrogate = end0 & 1 != 0;
    var start: u32 = start0 >> 1;
    const end: u32 = end0 >> 1;
    const len: i32 = @intCast(end - start);
    var buf: vt.JSStringCharBufExt = undefined;
    var p1 = get_string_ptr(ctx, &buf, val_mut);
    var ptr = vt.stringBuf(p1);
    if (!start_surrogate and !end_surrogate and vt.utf8CharLen(ptr[start]) == len) {
        var clen: usize = undefined;
        const ch = cutils.utf8_get(ptr + start, &clen);
        return JS_NewStringChar(@intCast(ch));
    }

    var val_ref: c.JSGCRef = undefined;
    utils.pushValue(ctx, &val_ref, val_mut);
    const extra: i32 = if (end_surrogate) 3 else 0;
    const p = js_alloc_string(ctx, @intCast(len - @as(i32, @intFromBool(start_surrogate)) + extra));
    val_mut = utils.popValue(ctx, &val_ref);
    if (p == null)
        return c.JS_EXCEPTION;
    p1 = get_string_ptr(ctx, &buf, val_mut);
    ptr = vt.stringBuf(p1);
    if (start_surrogate or end_surrogate) {
        var q = vt.stringBuf(p.?);
        vt.stringSetAscii(p.?, false);
        if (start_surrogate) {
            var clen: usize = undefined;
            var ch = cutils.utf8_get(ptr + start, &clen);
            ch = 0xdc00 + ((ch - 0x10000) & 0x3ff);
            q += cutils.unicode_to_utf8(q, @intCast(ch));
            start += 4;
        }
        const copy_len: usize = @intCast(end - start);
        @memcpy(q[0..copy_len], (ptr + start)[0..copy_len]);
        q += copy_len;
        if (end_surrogate) {
            var clen: usize = undefined;
            var ch = cutils.utf8_get(ptr + end, &clen);
            ch = 0xd800 + ((ch - 0x10000) >> 10);
            q += cutils.unicode_to_utf8(q, @intCast(ch));
        }
        std.debug.assert(@intFromPtr(q) - @intFromPtr(vt.stringBuf(p.?)) == vt.stringLen(p.?));
    } else {
        const ascii = vt.stringIsAscii(p1) or is_ascii_string(@ptrCast(ptr + start), @intCast(len)) != 0;
        vt.stringSetAscii(p.?, ascii);
        @memcpy(vt.stringBuf(p.?)[0..@intCast(len)], (ptr + start)[0..@intCast(len)]);
    }
    return mc.valueFromPtr(p.?);
}

pub fn JS_NewStringLen(ctx: *c.JSContext, buf: [*c]const u8, len: usize) c.JSValue {
    if (len == 0) {
        return utils.js_get_atom(ctx, c.JS_ATOM_empty);
    } else {
        if (vt.utf8CharLen(buf[0]) == len) {
            var clen: usize = undefined;
            const ch = cutils.utf8_get(buf, &clen);
            return JS_NewStringChar(@intCast(ch));
        }
    }
    const p = js_alloc_string(ctx, @intCast(len)) orelse return c.JS_EXCEPTION;
    vt.stringSetAscii(p, is_ascii_string(buf, len) != 0);
    @memcpy(vt.stringBuf(p)[0..len], buf[0..len]);
    return mc.valueFromPtr(p);
}

pub fn JS_NewString(ctx: *c.JSContext, buf: [*:0]const u8) c.JSValue {
    return JS_NewStringLen(ctx, buf, std.mem.len(buf));
}

pub fn js_byte_array_to_string(ctx: *c.JSContext, val: c.JSValue, len: c_int, is_ascii: c.JS_BOOL) c.JSValue {
    var val_mut = val;
    const arr: *vt.JSByteArrayExt = @ptrCast(@alignCast(mc.valueToPtr(val_mut)));
    std.debug.assert(len + 1 <= vt.byteArraySize(arr));
    if (len == 0) {
        return utils.js_get_atom(ctx, c.JS_ATOM_empty);
    } else if (vt.utf8CharLen(vt.byteArrayBuf(arr)[0]) == len) {
        var clen: usize = undefined;
        return JS_NewStringChar(@intCast(cutils.utf8_get(vt.byteArrayBuf(arr), &clen)));
    } else {
        js_shrink_byte_array(ctx, &val_mut, len + 1);
        const p: *vt.JSStringExt = @ptrCast(@alignCast(arr));
        vt.mbSetMtag(p, mc.JS_MTAG_STRING);
        vt.stringSetMeta(p, false, is_ascii != 0, false, @intCast(len));
        return val_mut;
    }
}

pub fn js_string_byte_len(ctx: *c.JSContext, val: c.JSValue) c_int {
    _ = ctx;
    if (mc.valueGetSpecialTag(val) == c.JS_TAG_STRING_CHAR) {
        const ch = mc.valueGetSpecialValue(val);
        if (ch < 0x80)
            return 1
        else if (ch < 0x800)
            return 2
        else if (ch < 0x10000)
            return 3
        else
            return 4;
    } else {
        const p: *vt.JSStringExt = @ptrCast(@alignCast(mc.valueToPtr(val)));
        return @intCast(vt.stringLen(p));
    }
}

pub fn is_valid_len4_utf8(buf: [*c]const u8) c.JS_BOOL {
    return boolVal(((@as(u32, buf[0] & 0xf) << 6) | (buf[1] & 0x3f)) >= 0x10);
}

pub fn dump_string_pos_cache(ctx: *c.JSContext) void {
    const x = mc.ctxExt(ctx);
    var i: usize = 0;
    while (i < vt.JS_STRING_POS_CACHE_SIZE) : (i += 1) {
        const ce = &x.string_pos_cache[i];
        _ = std.c.printf("%d: ", @as(c_int, @intCast(i)));
        if (ce.str == c.JS_NULL) {
            _ = std.c.printf("<empty>\n");
        } else {
            const p: *vt.JSStringExt = @ptrCast(@alignCast(mc.valueToPtr(ce.str)));
            _ = std.c.printf(" utf8_pos=%u/%u utf16_pos=%u\n", ce.str_pos[vt.POS_TYPE_UTF8], @as(c_uint, @intCast(vt.stringLen(p))), ce.str_pos[vt.POS_TYPE_UTF16]);
        }
    }
}

pub fn js_string_convert_pos(ctx: *c.JSContext, val: c.JSValue, pos_in: u32, pos_type: c_int) u32 {
    var buf: vt.JSStringCharBufExt = undefined;
    const p = get_string_ptr(ctx, &buf, val);
    var len: usize = vt.stringLen(p);
    if (vt.stringIsAscii(p)) {
        if (pos_type == vt.POS_TYPE_UTF8)
            return @intCast(cutils.min_int(@intCast(len), @intCast(pos_in / 2)))
        else
            return @intCast(cutils.min_int(@intCast(len), @intCast(pos_in)) * 2);
    }

    var pos = pos_in;
    var has_surrogate: u32 = 0;
    if (pos_type == vt.POS_TYPE_UTF8) {
        has_surrogate = pos & 1;
        pos >>= 1;
    }

    var ce: ?*mc.JSStringPosCacheEntryExt = null;
    var i: usize = 0;
    var j: u32 = 0;
    var uncached = false;
    if (len < vt.JS_STRING_POS_CACHE_MIN_LEN) {
        j = 0;
        i = 0;
        uncached = true;
    }

    if (!uncached) {
        var d_min: u32 = pos;
        var ce_idx: usize = 0;
        while (ce_idx < vt.JS_STRING_POS_CACHE_SIZE) : (ce_idx += 1) {
            const ce1 = &mc.ctxExt(ctx).string_pos_cache[ce_idx];
            if (ce1.str == val) {
                var d = ce1.str_pos[@intCast(pos_type)];
                d = if (d >= pos) d - pos else pos - d;
                if (d < d_min) {
                    d_min = d;
                    ce = ce1;
                }
            }
        }
        if (ce == null) {
            const x = mc.ctxExt(ctx);
            ce = &x.string_pos_cache[x.string_pos_cache_counter];
            x.string_pos_cache_counter += 1;
            if (x.string_pos_cache_counter == vt.JS_STRING_POS_CACHE_SIZE)
                x.string_pos_cache_counter = 0;
            ce.?.str = val;
            ce.?.str_pos[vt.POS_TYPE_UTF8] = 0;
            ce.?.str_pos[vt.POS_TYPE_UTF16] = 0;
        }
        i = ce.?.str_pos[vt.POS_TYPE_UTF8];
        j = ce.?.str_pos[vt.POS_TYPE_UTF16];
        if (ce.?.str_pos[@intCast(pos_type)] > pos) {
            var surrogate_flag: u32 = 0;
            var start: usize = 0;
            var limit: u32 = 0;
            if (pos_type == vt.POS_TYPE_UTF8) {
                start = pos;
                limit = std.math.maxInt(i32);
            } else {
                limit = pos;
                start = 0;
            }
            while (i > start) {
                const i_start = i;
                i -= 1;
                while ((vt.stringBuf(p)[i] & 0xc0) == 0x80)
                    i -= 1;
                const clen = i_start - i;
                if (clen == 4 and is_valid_len4_utf8(vt.stringBuf(p) + i) != 0) {
                    j -= 2;
                    if ((j + 1) == limit) {
                        surrogate_flag = 1;
                        break;
                    }
                } else {
                    j -= 1;
                }
                if (j == limit)
                    break;
            }
            if (ce) |ce_ptr| {
                ce_ptr.str_pos[vt.POS_TYPE_UTF8] = @intCast(i);
                ce_ptr.str_pos[vt.POS_TYPE_UTF16] = j;
            }
            if (pos_type == vt.POS_TYPE_UTF8)
                return j + has_surrogate
            else
                return @as(u32, @intCast(i)) * 2 + surrogate_flag;
        }
    }

    var surrogate_flag: u32 = 0;
    var limit: u32 = 0;
    if (pos_type == vt.POS_TYPE_UTF8) {
        limit = std.math.maxInt(i32);
        len = pos;
    } else {
        limit = pos;
    }
    var clen: usize = 0;
    while (i < len) : (i += clen) {
        if (j == limit)
            break;
        clen = @intCast(vt.utf8CharLen(vt.stringBuf(p)[i]));
        if (clen == 4 and is_valid_len4_utf8(vt.stringBuf(p) + i) != 0) {
            if ((j + 1) == limit) {
                surrogate_flag = 1;
                break;
            }
            j += 2;
        } else {
            j += 1;
        }
    }
    if (ce) |ce_ptr| {
        ce_ptr.str_pos[vt.POS_TYPE_UTF8] = @intCast(i);
        ce_ptr.str_pos[vt.POS_TYPE_UTF16] = j;
    }
    if (pos_type == vt.POS_TYPE_UTF8)
        return j + has_surrogate
    else
        return @as(u32, @intCast(i)) * 2 + surrogate_flag;
}

pub fn js_string_utf16_to_utf8_pos(ctx: *c.JSContext, val: c.JSValue, utf16_pos: u32) u32 {
    return js_string_convert_pos(ctx, val, utf16_pos, vt.POS_TYPE_UTF16);
}

pub fn js_string_utf8_to_utf16_pos(ctx: *c.JSContext, val: c.JSValue, utf8_pos: u32) u32 {
    return js_string_convert_pos(ctx, val, utf8_pos, vt.POS_TYPE_UTF8);
}

pub fn is_utf8_left_surrogate(p: [*c]const u8) c.JS_BOOL {
    return boolVal(p[0] == 0xed and (p[1] >= 0xa0 and p[1] <= 0xaf));
}

pub fn is_utf8_right_surrogate(p: [*c]const u8) c.JS_BOOL {
    return boolVal(p[0] == 0xed and (p[1] >= 0xb0 and p[1] <= 0xbf));
}

pub fn string_buffer_push(ctx: *c.JSContext, s: *vt.StringBuffer, len: c_int) c_int {
    s.len = 0;
    s.is_ascii = c.TRUE;
    if (len > 0) {
        const arr = js_alloc_byte_array(ctx, len) orelse return -1;
        s.buffer_ref.val = mc.valueFromPtr(arr);
    } else {
        s.buffer_ref.val = utils.js_get_atom(ctx, c.JS_ATOM_empty);
    }
    s.buffer_ref.prev = @ptrCast(mc.ctxExt(ctx).top_gc_ref);
    mc.ctxExt(ctx).top_gc_ref = @ptrCast(@alignCast(&s.buffer_ref));
    return 0;
}

pub fn string_buffer_concat_str(ctx: *c.JSContext, s: *vt.StringBuffer, val2_in: c.JSValue) c_int {
    var val2 = val2_in;
    var buf1: vt.JSStringCharBufExt = undefined;
    var buf2: vt.JSStringCharBufExt = undefined;
    if (vt.isExactException(s.buffer_ref.val))
        return -1;
    var p2 = get_string_ptr(ctx, &buf2, val2);
    var len2: c_int = @intCast(vt.stringLen(p2));
    if (len2 == 0)
        return 0;
    var arr: ?*vt.JSByteArrayExt = null;
    var val1: c.JSValue = c.JS_NULL;
    var len1: c_int = 0;
    if (JS_IsString(ctx, s.buffer_ref.val) != 0) {
        const p1 = get_string_ptr(ctx, &buf1, s.buffer_ref.val);
        len1 = @intCast(vt.stringLen(p1));
        if (len1 == 0) {
            s.buffer_ref.val = val2;
            return 0;
        }
        arr = null;
        val1 = s.buffer_ref.val;
        s.buffer_ref.val = c.JS_NULL;
    } else {
        arr = @ptrCast(@alignCast(mc.valueToPtr(s.buffer_ref.val)));
        len1 = s.len;
        val1 = c.JS_NULL;
    }

    var len = len1 + len2;
    if (len > vt.JS_STRING_LEN_MAX) {
        s.buffer_ref.val = utils.JS_ThrowError(ctx, c.JS_CLASS_INTERNAL_ERROR, "string too long");
        return -1;
    }

    if (arr == null or (len + 1) > vt.byteArraySize(arr.?)) {
        var val1_ref: c.JSGCRef = undefined;
        var val2_ref: c.JSGCRef = undefined;
        utils.pushValue(ctx, &val1_ref, val1);
        utils.pushValue(ctx, &val2_ref, val2);
        s.buffer_ref.val = js_resize_byte_array(ctx, s.buffer_ref.val, len + 1);
        val2 = utils.popValue(ctx, &val2_ref);
        val1 = utils.popValue(ctx, &val1_ref);
        if (vt.isExactException(s.buffer_ref.val))
            return -1;
        arr = @ptrCast(@alignCast(mc.valueToPtr(s.buffer_ref.val)));
        if (val1 != c.JS_NULL) {
            const p1 = get_string_ptr(ctx, &buf1, val1);
            s.is_ascii = @intFromBool(vt.stringIsAscii(p1));
            @memcpy(vt.byteArrayBuf(arr.?)[0..@intCast(len1)], vt.stringBuf(p1)[0..@intCast(len1)]);
        }
        p2 = get_string_ptr(ctx, &buf2, val2);
    }

    var q = vt.byteArrayBuf(arr.?) + @as(usize, @intCast(len1));
    if (len2 >= 3 and is_utf8_right_surrogate(vt.stringBuf(p2)) != 0 and
        len1 >= 3 and is_utf8_left_surrogate(q - 3) != 0)
    {
        var clen: usize = undefined;
        var ch: c_int = (cutils.utf8_get(q - 3, &clen) & 0x3ff) << 10;
        ch |= cutils.utf8_get(vt.stringBuf(p2), &clen) & 0x3ff;
        ch += 0x10000;
        len -= 2;
        len2 -= 3;
        q -= 3;
        q += cutils.unicode_to_utf8(q, @intCast(ch));
        s.is_ascii = c.FALSE;
    }
    @memcpy(q[0..@intCast(len2)], (vt.stringBuf(p2) + vt.stringLen(p2) - @as(usize, @intCast(len2)))[0..@intCast(len2)]);
    s.len = len;
    s.is_ascii = @intFromBool(s.is_ascii != 0 and vt.stringIsAscii(p2));
    return 0;
}

pub fn string_buffer_concat_utf8(ctx: *c.JSContext, s: *vt.StringBuffer, str: c.JSValue, start: u32, end: u32) c_int {
    if (end <= start)
        return 0;
    const val2 = js_sub_string_utf8(ctx, str, start, end);
    if (vt.isExactException(val2)) {
        s.buffer_ref.val = c.JS_EXCEPTION;
        return -1;
    }
    return string_buffer_concat_str(ctx, s, val2);
}

pub fn string_buffer_concat_utf16(ctx: *c.JSContext, s: *vt.StringBuffer, str: c.JSValue, start: u32, end: u32) c_int {
    if (end <= start)
        return 0;
    const start_utf8 = js_string_utf16_to_utf8_pos(ctx, str, start);
    const end_utf8 = js_string_utf16_to_utf8_pos(ctx, str, end);
    return string_buffer_concat_utf8(ctx, s, str, start_utf8, end_utf8);
}

pub fn string_buffer_concat(ctx: *c.JSContext, s: *vt.StringBuffer, val2: c.JSValue) c_int {
    const str = runtime.JS_ToString(ctx, val2);
    if (vt.isExactException(str)) {
        s.buffer_ref.val = c.JS_EXCEPTION;
        return -1;
    }
    return string_buffer_concat_str(ctx, s, str);
}

pub fn string_buffer_putc(ctx: *c.JSContext, s: *vt.StringBuffer, ch: c_int) c_int {
    return string_buffer_concat_str(ctx, s, JS_NewStringChar(@intCast(ch)));
}

pub fn string_buffer_puts(ctx: *c.JSContext, s: *vt.StringBuffer, str: [*:0]const u8) c_int {
    const val = JS_NewString(ctx, str);
    if (vt.isExactException(val))
        return -1;
    return string_buffer_concat_str(ctx, s, val);
}

pub fn string_buffer_pop(ctx: *c.JSContext, s: *vt.StringBuffer) c.JSValue {
    var res: c.JSValue = undefined;
    if (vt.isExactException(s.buffer_ref.val) or JS_IsString(ctx, s.buffer_ref.val) != 0) {
        res = s.buffer_ref.val;
    } else {
        if (s.len != 0) {
            const arr: *vt.JSByteArrayExt = @ptrCast(@alignCast(mc.valueToPtr(s.buffer_ref.val)));
            vt.byteArrayBuf(arr)[@intCast(s.len)] = 0;
        }
        res = js_byte_array_to_string(ctx, s.buffer_ref.val, s.len, s.is_ascii);
    }
    mc.ctxExt(ctx).top_gc_ref = @ptrCast(s.buffer_ref.prev);
    return res;
}

pub fn JS_ConcatString(ctx: *c.JSContext, val1: c.JSValue, val2: c.JSValue) c.JSValue {
    if (vt.isExactException(val1) or vt.isExactException(val2))
        return c.JS_EXCEPTION;
    var b: vt.StringBuffer = undefined;
    _ = string_buffer_push(ctx, &b, 0);
    _ = string_buffer_concat_str(ctx, &b, val1);
    _ = string_buffer_concat_str(ctx, &b, val2);
    return string_buffer_pop(ctx, &b);
}

pub fn js_string_eq(ctx: *c.JSContext, val1: c.JSValue, val2: c.JSValue) c.JS_BOOL {
    var buf1: vt.JSStringCharBufExt = undefined;
    var buf2: vt.JSStringCharBufExt = undefined;
    const p1 = get_string_ptr(ctx, &buf1, val1);
    const p2 = get_string_ptr(ctx, &buf2, val2);
    if (vt.stringLen(p1) != vt.stringLen(p2))
        return c.FALSE;
    return boolVal(std.mem.eql(u8, vt.stringBuf(p1)[0..vt.stringLen(p1)], vt.stringBuf(p2)[0..vt.stringLen(p2)]));
}

pub fn string_get_cp(p_in: [*c]const u8) c_int {
    var p = p_in;
    var clen: usize = undefined;
    while ((p[0] & 0xc0) == 0x80)
        p -= 1;
    return cutils.utf8_get(p, &clen);
}

pub fn js_string_compare(ctx: *c.JSContext, val1: c.JSValue, val2: c.JSValue) c_int {
    var buf1: vt.JSStringCharBufExt = undefined;
    var buf2: vt.JSStringCharBufExt = undefined;
    const p1 = get_string_ptr(ctx, &buf1, val1);
    const p2 = get_string_ptr(ctx, &buf2, val2);
    const len = cutils.min_int(@intCast(vt.stringLen(p1)), @intCast(vt.stringLen(p2)));
    var i: c_int = 0;
    while (i < len) : (i += 1) {
        if (vt.stringBuf(p1)[@intCast(i)] != vt.stringBuf(p2)[@intCast(i)])
            break;
    }
    var res: c_int = 0;
    if (i != len) {
        var c1 = string_get_cp(vt.stringBuf(p1) + @as(usize, @intCast(i)));
        var c2 = string_get_cp(vt.stringBuf(p2) + @as(usize, @intCast(i)));
        if ((c1 < 0x10000 and c2 < 0x10000) or
            (c1 >= 0x10000 and c2 >= 0x10000))
        {
            res = if (c1 < c2) -1 else 1;
        } else if (c1 < 0x10000) {
            c2 = 0xd800 + ((c2 - 0x10000) >> 10);
            res = if (c1 <= c2) -1 else 1;
        } else {
            c1 = 0xd800 + ((c1 - 0x10000) >> 10);
            res = if (c1 < c2) -1 else 1;
        }
    } else {
        if (vt.stringLen(p1) == vt.stringLen(p2))
            res = 0
        else if (vt.stringLen(p1) < vt.stringLen(p2))
            res = -1
        else
            res = 1;
    }
    return res;
}

pub fn js_string_len(ctx: *c.JSContext, val: c.JSValue) c_int {
    if (mc.valueGetSpecialTag(val) == c.JS_TAG_STRING_CHAR) {
        return if (mc.valueGetSpecialValue(val) >= 0x10000) 2 else 1;
    } else {
        const p: *vt.JSStringExt = @ptrCast(@alignCast(mc.valueToPtr(val)));
        if (vt.stringIsAscii(p))
            return @intCast(vt.stringLen(p))
        else
            return @intCast(js_string_utf8_to_utf16_pos(ctx, val, @intCast(vt.stringLen(p) * 2)));
    }
}

pub fn string_getcp(ctx: *c.JSContext, str: c.JSValue, utf16_pos: u32, is_codepoint: c.JS_BOOL) c_int {
    var utf8_pos = js_string_utf16_to_utf8_pos(ctx, str, utf16_pos);
    const surrogate_flag = utf8_pos & 1;
    utf8_pos >>= 1;
    var buf: vt.JSStringCharBufExt = undefined;
    const p = get_string_ptr(ctx, &buf, str);
    if (utf8_pos >= vt.stringLen(p))
        return -1;
    var clen: usize = undefined;
    var ch: u32 = @intCast(cutils.utf8_get(vt.stringBuf(p) + utf8_pos, &clen));
    if (ch < 0x10000 or (surrogate_flag == 0 and is_codepoint != 0)) {
        return @intCast(ch);
    } else {
        ch -= 0x10000;
        if (surrogate_flag == 0)
            return @intCast(0xd800 + (ch >> 10))
        else
            return @intCast(0xdc00 + (ch & 0x3ff));
    }
}

pub fn string_getc(ctx: *c.JSContext, str: c.JSValue, utf16_pos: u32) c_int {
    return string_getcp(ctx, str, utf16_pos, c.FALSE);
}

pub fn js_sub_string(ctx: *c.JSContext, val: c.JSValue, start: c_int, end: c_int) c.JSValue {
    if (end <= start)
        return utils.js_get_atom(ctx, c.JS_ATOM_empty);
    const start_utf8 = js_string_utf16_to_utf8_pos(ctx, val, @intCast(start));
    const end_utf8 = js_string_utf16_to_utf8_pos(ctx, val, @intCast(end));
    return js_sub_string_utf8(ctx, val, start_utf8, end_utf8);
}

pub fn is_num(ch: c_int) c_int {
    return vt.isNum(ch);
}

pub fn js_is_numeric_string(ctx: *c.JSContext, val_in: c.JSValue) c_int {
    var val = val_in;
    var p: *vt.JSStringExt = @ptrCast(@alignCast(mc.valueToPtr(val)));
    if (vt.stringLen(p) == 0 or !vt.stringIsAscii(p))
        return c.FALSE;
    var q: [*c]const u8 = vt.stringBuf(p);
    var ch: c_int = q[0];
    if (ch == '-') {
        if (vt.stringLen(p) == 1)
            return c.FALSE;
        q += 1;
        ch = q[0];
    }
    if (is_num(ch) == 0)
        return c.FALSE;

    var val_ref: c.JSGCRef = undefined;
    utils.pushValue(ctx, &val_ref, val);
    const tmp_size = max_int(@intCast(@sizeOf(c.JSATODTempMem)), @intCast(@sizeOf(c.JSDTOATempMem)));
    const tmp_arr = js_alloc_byte_array(ctx, tmp_size);
    val = utils.popValue(ctx, &val_ref);
    if (tmp_arr == null)
        return -1;
    p = @ptrCast(@alignCast(mc.valueToPtr(val)));
    var r: [*c]const u8 = undefined;
    const d = dtoa.js_atod(vt.stringBuf(p), @ptrCast(&r), 10, 0, @ptrCast(@alignCast(vt.byteArrayBuf(tmp_arr.?))));
    if (@intFromPtr(r) - @intFromPtr(vt.stringBuf(p)) != vt.stringLen(p)) {
        utils.js_free(ctx, tmp_arr);
        return c.FALSE;
    }
    var nbuf: [32]u8 = undefined;
    const nlen = dtoa.js_dtoa(&nbuf, d, 10, 0, c.JS_DTOA_FORMAT_FREE, @ptrCast(@alignCast(vt.byteArrayBuf(tmp_arr.?))));
    utils.js_free(ctx, tmp_arr);
    return boolVal(vt.stringLen(p) == @as(usize, @intCast(nlen)) and
        std.mem.eql(u8, nbuf[0..@intCast(nlen)], vt.stringBuf(p)[0..@intCast(nlen)]));
}

pub fn find_atom(ctx: *c.JSContext, pidx: *c_int, arr: *const vt.JSValueArrayExt, len: c_int, val: c.JSValue) c.JSValue {
    var a: c_int = 0;
    var b: c_int = len - 1;
    const items = vt.valueArrayItems(arr);
    while (a <= b) {
        const m = (a + b) >> 1;
        const val1 = items[@intCast(m)];
        const r = js_string_compare(ctx, val, val1);
        if (r == 0) {
            pidx.* = m;
            return val1;
        } else if (r < 0) {
            b = m - 1;
        } else {
            a = m + 1;
        }
    }
    pidx.* = a;
    return c.JS_NULL;
}

pub fn JS_MakeUniqueString(ctx: *c.JSContext, val_in: c.JSValue) c.JSValue {
    var val = val_in;
    if (!mc.isPtr(val))
        return val;
    var p: *vt.JSStringExt = @ptrCast(@alignCast(mc.valueToPtr(val)));
    if (mc.mbGetMtag(p) != mc.JS_MTAG_STRING or vt.stringIsUnique(p))
        return val;

    const x = mc.ctxExt(ctx);
    var i: u8 = 0;
    var a: c_int = 0;
    while (i < x.n_rom_atom_tables) : (i += 1) {
        if (x.rom_atom_tables[i]) |arr1_ptr| {
            const arr1: *const vt.JSValueArrayExt = @ptrCast(@alignCast(arr1_ptr));
            const val1 = find_atom(ctx, &a, arr1, vt.valueArraySize(arr1), val);
            if (!mc.isNull(val1))
                return val1;
        }
    }

    const arr: *vt.JSValueArrayExt = @ptrCast(@alignCast(mc.valueToPtr(x.unique_strings)));
    const val1 = find_atom(ctx, &a, arr, x.unique_strings_len, val);
    if (!mc.isNull(val1))
        return val1;

    var val_ref: c.JSGCRef = undefined;
    utils.pushValue(ctx, &val_ref, val);
    const is_numeric = js_is_numeric_string(ctx, val);
    val = utils.popValue(ctx, &val_ref);
    if (is_numeric < 0)
        return c.JS_EXCEPTION;

    utils.pushValue(ctx, &val_ref, val);
    const new_tab = js_resize_value_array(ctx, x.unique_strings, x.unique_strings_len + 1);
    val = utils.popValue(ctx, &val_ref);
    if (vt.isExactException(new_tab))
        return c.JS_EXCEPTION;
    x.unique_strings = new_tab;
    const arr2: *vt.JSValueArrayExt = @ptrCast(@alignCast(mc.valueToPtr(x.unique_strings)));
    const items = vt.valueArrayItems(arr2);
    const nmove: usize = @intCast(x.unique_strings_len - a);
    if (nmove > 0) {
        std.mem.copyBackwards(c.JSValue, items[@intCast(a + 1)..][0..nmove], items[@intCast(a)..][0..nmove]);
    }
    items[@intCast(a)] = val;
    p = @ptrCast(@alignCast(mc.valueToPtr(val)));
    vt.stringSetUnique(p, true);
    vt.stringSetNumeric(p, is_numeric != 0);
    x.unique_strings_len += 1;
    return val;
}

pub fn JS_ToBool(ctx: *c.JSContext, val: c.JSValue) c_int {
    _ = ctx;
    if (mc.isInt(val)) {
        return @intFromBool(vt.valueGetInt(val) != 0);
    } else if (mc.isShortFloat(val)) {
        const d = js_get_short_float(val);
        return @intFromBool(!std.math.isNan(d) and d != 0);
    } else if (!mc.isPtr(val)) {
        switch (mc.valueGetSpecialTag(val)) {
            c.JS_TAG_BOOL, c.JS_TAG_NULL, c.JS_TAG_UNDEFINED => return mc.valueGetSpecialValue(val),
            c.JS_TAG_SHORT_FUNC, c.JS_TAG_STRING_CHAR => return c.TRUE,
            else => return c.FALSE,
        }
    } else {
        const h = mc.valueToPtr(val);
        switch (utils.js_get_mtag(h)) {
            mc.JS_MTAG_STRING => {
                const p: *vt.JSStringExt = @ptrCast(@alignCast(h));
                return @intFromBool(vt.stringLen(p) != 0);
            },
            mc.JS_MTAG_FLOAT64 => {
                const p: *vt.JSFloat64Ext = @ptrCast(@alignCast(h));
                return @intFromBool(!std.math.isNan(p.dval) and p.dval != 0);
            },
            else => return c.TRUE,
        }
    }
}

pub fn JS_ToCStringLen(ctx: *c.JSContext, plen: ?*usize, val: c.JSValue, buf: *c.JSCStringBuf) ?[*:0]const u8 {
    const converted = runtime.JS_ToString(ctx, val);
    if (vt.isExactException(converted))
        return null;
    var p: [*:0]const u8 = undefined;
    var len: c_int = 0;
    if (mc.valueGetSpecialTag(converted) == c.JS_TAG_STRING_CHAR) {
        len = utils.get_short_string(&buf.buf, converted);
        p = @ptrCast(&buf.buf);
    } else {
        const r: *vt.JSStringExt = @ptrCast(@alignCast(mc.valueToPtr(converted)));
        p = @ptrCast(vt.stringBuf(r));
        len = @intCast(vt.stringLen(r));
    }
    if (plen) |out|
        out.* = @intCast(len);
    return p;
}

pub fn JS_ToCString(ctx: *c.JSContext, val: c.JSValue, buf: *c.JSCStringBuf) ?[*:0]const u8 {
    return JS_ToCStringLen(ctx, null, val, buf);
}

pub fn JS_HasException(ctx: *c.JSContext) c.JS_BOOL {
    return boolVal(!vt.isUninitialized(mc.ctxExt(ctx).current_exception));
}

pub fn JS_GetException(ctx: *c.JSContext) c.JSValue {
    const x = mc.ctxExt(ctx);
    const obj = x.current_exception;
    x.current_exception = c.JS_UNINITIALIZED;
    return obj;
}

pub fn JS_ToStringCheckObject(ctx: *c.JSContext, val: c.JSValue) c.JSValue {
    if (val == c.JS_NULL or val == c.JS_UNDEFINED)
        return utils.JS_ThrowError(ctx, c.JS_CLASS_TYPE_ERROR, "null or undefined are forbidden");
    return runtime.JS_ToString(ctx, val);
}

pub fn JS_ThrowTypeErrorNotAnObject(ctx: *c.JSContext) c.JSValue {
    return utils.JS_ThrowError(ctx, c.JS_CLASS_TYPE_ERROR, "not an object");
}

pub fn is_num_string(ctx: *c.JSContext, pval: *i32, val: c.JSValue) c.JS_BOOL {
    var buf: vt.JSStringCharBufExt = undefined;
    const p1 = get_string_ptr(ctx, &buf, val);
    if (vt.stringLen(p1) == 0 or vt.stringLen(p1) > 11 or !vt.stringIsAscii(p1))
        return c.FALSE;
    var p: [*c]const u8 = vt.stringBuf(p1);
    const p_end = p + vt.stringLen(p1);
    var ch: c_int = p[0];
    p += 1;
    var is_neg: c_int = 0;
    if (ch == '-') {
        if (@intFromPtr(p) >= @intFromPtr(p_end))
            return c.FALSE;
        is_neg = 1;
        ch = p[0];
        p += 1;
    }
    if (is_num(ch) == 0)
        return c.FALSE;
    var n: u32 = 0;
    if (ch == '0') {
        if (p != p_end or is_neg != 0)
            return c.FALSE;
        n = 0;
    } else {
        n = @intCast(ch - '0');
        while (@intFromPtr(p) < @intFromPtr(p_end)) {
            ch = p[0];
            p += 1;
            if (is_num(ch) == 0)
                return c.FALSE;
            const n64: u64 = @as(u64, n) * 10 + @as(u64, @intCast(ch - '0'));
            if (n64 > @as(u64, @intCast(vt.JS_SHORTINT_MAX)) + @as(u64, @intCast(is_neg)))
                return c.FALSE;
            n = @intCast(n64);
        }
        if (is_neg != 0)
            n = 0 -% n;
    }
    pval.* = @bitCast(n);
    return c.TRUE;
}

pub fn JS_IsNumericProperty(ctx: *c.JSContext, val: c.JSValue) c.JS_BOOL {
    _ = ctx;
    if (!mc.isPtr(val))
        return c.FALSE;
    const p: *vt.JSStringExt = @ptrCast(@alignCast(mc.valueToPtr(val)));
    return boolVal(vt.stringIsNumeric(p));
}

pub fn js_alloc_value_array(ctx: *c.JSContext, init_base: c_int, new_size: c_int) ?*vt.JSValueArrayExt {
    if (new_size > vt.JS_VALUE_ARRAY_SIZE_MAX) {
        _ = utils.JS_ThrowOutOfMemory(ctx);
        return null;
    }
    const arr: *vt.JSValueArrayExt = @ptrCast(@alignCast(
        utils.js_malloc(ctx, vt.valueArrayAllocSize(new_size), mc.JS_MTAG_VALUE_ARRAY) orelse return null,
    ));
    vt.valueArraySetSize(arr, new_size);
    const items = vt.valueArrayItems(arr);
    var i = init_base;
    while (i < new_size) : (i += 1)
        items[@intCast(i)] = c.JS_UNDEFINED;
    return arr;
}

pub fn js_resize_value_array2(ctx: *c.JSContext, val: c.JSValue, new_size_in: c_int, prop_base: c_int) c.JSValue {
    var new_size = new_size_in;
    var old_size: c_int = 0;
    if (val != c.JS_NULL) {
        const slots: *vt.JSValueArrayExt = @ptrCast(@alignCast(mc.valueToPtr(val)));
        old_size = vt.valueArraySize(slots);
    }
    if (new_size > old_size) {
        const new_size1 = old_size + @divTrunc(old_size, 2);
        if (new_size1 > new_size) {
            new_size = new_size1;
            if (prop_base != 0) {
                const align_n = @mod(new_size - prop_base, 3);
                if (align_n != 0)
                    new_size += 3 - align_n;
            }
        }
        new_size = max_int(new_size, old_size + @divTrunc(old_size, 2));
        var val_ref: c.JSGCRef = undefined;
        var val_mut = val;
        utils.pushValue(ctx, &val_ref, val_mut);
        const new_slots = js_alloc_value_array(ctx, old_size, new_size);
        val_mut = utils.popValue(ctx, &val_ref);
        if (new_slots == null)
            return c.JS_EXCEPTION;
        if (old_size > 0) {
            const slots: *vt.JSValueArrayExt = @ptrCast(@alignCast(mc.valueToPtr(val_mut)));
            const nbytes: usize = @intCast(old_size * @as(c_int, @intCast(@sizeOf(c.JSValue))));
            @memcpy(
                @as([*]u8, @ptrCast(vt.valueArrayItems(new_slots.?)))[0..nbytes],
                @as([*]u8, @ptrCast(vt.valueArrayItems(slots)))[0..nbytes],
            );
        }
        return mc.valueFromPtr(new_slots.?);
    }
    return val;
}

pub fn js_resize_value_array(ctx: *c.JSContext, val: c.JSValue, new_size: c_int) c.JSValue {
    return js_resize_value_array2(ctx, val, new_size, 0);
}

pub fn js_shrink_value_array(ctx: *c.JSContext, pval: *c.JSValue, new_size: c_int) void {
    if (pval.* == c.JS_NULL)
        return;
    var arr: *vt.JSValueArrayExt = @ptrCast(@alignCast(mc.valueToPtr(pval.*)));
    std.debug.assert(new_size <= vt.valueArraySize(arr));
    if (new_size == 0) {
        utils.js_free(ctx, arr);
        pval.* = c.JS_NULL;
    } else {
        arr = @ptrCast(@alignCast(utils.js_shrink(ctx, arr, vt.valueArrayAllocSize(new_size)).?));
        vt.valueArraySetSize(arr, new_size);
    }
}

pub fn js_alloc_byte_array(ctx: *c.JSContext, size: c_int) ?*vt.JSByteArrayExt {
    if (size > vt.JS_BYTE_ARRAY_SIZE_MAX) {
        _ = utils.JS_ThrowOutOfMemory(ctx);
        return null;
    }
    const arr: *vt.JSByteArrayExt = @ptrCast(@alignCast(
        utils.js_malloc(ctx, vt.byteArrayAllocSize(size), mc.JS_MTAG_BYTE_ARRAY) orelse return null,
    ));
    vt.byteArraySetSize(arr, size);
    return arr;
}

pub fn js_resize_byte_array(ctx: *c.JSContext, val: c.JSValue, new_size_in: c_int) c.JSValue {
    var new_size = new_size_in;
    var old_size: c_int = 0;
    if (val != c.JS_NULL) {
        const arr: *vt.JSByteArrayExt = @ptrCast(@alignCast(mc.valueToPtr(val)));
        old_size = vt.byteArraySize(arr);
    }
    if (new_size > old_size) {
        new_size = max_int(new_size, old_size + @divTrunc(old_size, 2));
        var val_ref: c.JSGCRef = undefined;
        var val_mut = val;
        utils.pushValue(ctx, &val_ref, val_mut);
        const new_arr = js_alloc_byte_array(ctx, new_size);
        val_mut = utils.popValue(ctx, &val_ref);
        if (new_arr == null)
            return c.JS_EXCEPTION;
        if (old_size > 0) {
            const arr: *vt.JSByteArrayExt = @ptrCast(@alignCast(mc.valueToPtr(val_mut)));
            @memcpy(vt.byteArrayBuf(new_arr.?)[0..@intCast(old_size)], vt.byteArrayBuf(arr)[0..@intCast(old_size)]);
        }
        return mc.valueFromPtr(new_arr.?);
    }
    return val;
}

pub fn js_shrink_byte_array(ctx: *c.JSContext, pval: *c.JSValue, new_size: c_int) void {
    if (pval.* == c.JS_NULL)
        return;
    var arr: *vt.JSByteArrayExt = @ptrCast(@alignCast(mc.valueToPtr(pval.*)));
    std.debug.assert(new_size <= vt.byteArraySize(arr));
    if (new_size == 0) {
        utils.js_free(ctx, arr);
        pval.* = c.JS_NULL;
    } else {
        arr = @ptrCast(@alignCast(utils.js_shrink(ctx, arr, vt.byteArrayAllocSize(new_size)).?));
        vt.byteArraySetSize(arr, new_size);
    }
}

pub fn JS_NewObjectProtoClass1(ctx: *c.JSContext, proto: c.JSValue, class_id: c_int, extra_size_in: c_int) ?*mc.JSObjectExt {
    const jsw: c_uint = @intCast(c.JSW);
    const extra_size: c.JSWord = @intCast((@as(c_uint, @bitCast(extra_size_in)) + jsw - 1) / jsw);
    var proto_ref: c.JSGCRef = undefined;
    var proto_mut = proto;
    utils.pushValue(ctx, &proto_ref, proto_mut);
    const p: ?*mc.JSObjectExt = @ptrCast(@alignCast(
        utils.js_malloc(ctx, vt.objectOffsetOfU() + @as(c_uint, @intCast(extra_size)) * jsw, mc.JS_MTAG_OBJECT),
    ));
    proto_mut = utils.popValue(ctx, &proto_ref);
    if (p == null)
        return null;
    vt.objectSetClassAndExtra(p.?, class_id, extra_size);
    p.?.proto = proto_mut;
    p.?.props = mc.ctxExt(ctx).empty_props;
    return p;
}

pub fn JS_NewObjectProtoClass(ctx: *c.JSContext, proto: c.JSValue, class_id: c_int, extra_size: c_int) c.JSValue {
    const p = JS_NewObjectProtoClass1(ctx, proto, class_id, extra_size) orelse return c.JS_EXCEPTION;
    return mc.valueFromPtr(p);
}

pub fn JS_NewObjectClass(ctx: *c.JSContext, class_id: c_int, extra_size: c_int) c.JSValue {
    return JS_NewObjectProtoClass(ctx, vt.classProto(mc.ctxExt(ctx), class_id).*, class_id, extra_size);
}

pub fn JS_NewObjectClassUser(ctx: *c.JSContext, class_id: c_int) c.JSValue {
    std.debug.assert(class_id >= c.JS_CLASS_USER);
    const p = JS_NewObjectProtoClass1(ctx, vt.classProto(mc.ctxExt(ctx), class_id).*, class_id, @sizeOf(vt.JSObjectUserDataExt)) orelse
        return c.JS_EXCEPTION;
    vt.objectUserOpaque(p).* = null;
    return mc.valueFromPtr(p);
}

pub fn JS_NewObject(ctx: *c.JSContext) c.JSValue {
    return JS_NewObjectClass(ctx, c.JS_CLASS_OBJECT, 0);
}

pub fn JS_NewObjectPrealloc(ctx: *c.JSContext, n: c_int) c.JSValue {
    const obj = JS_NewObjectClass(ctx, c.JS_CLASS_OBJECT, 0);
    if (vt.isExactException(obj) or n <= 0)
        return obj;
    var obj_ref: c.JSGCRef = undefined;
    var obj_mut = obj;
    utils.pushValue(ctx, &obj_ref, obj_mut);
    const arr = js_alloc_props(ctx, n);
    obj_mut = utils.popValue(ctx, &obj_ref);
    if (arr == null)
        return c.JS_EXCEPTION;
    const p: *mc.JSObjectExt = @ptrCast(@alignCast(mc.valueToPtr(obj_mut)));
    p.props = mc.valueFromPtr(arr.?);
    return obj_mut;
}

pub fn JS_NewArray(ctx: *c.JSContext, initial_len: c_int) c.JSValue {
    var val = JS_NewObjectClass(ctx, c.JS_CLASS_ARRAY, @sizeOf(mc.JSArrayDataExt));
    if (vt.isExactException(val))
        return val;
    var p: *mc.JSObjectExt = @ptrCast(@alignCast(mc.valueToPtr(val)));
    p.u.array.tab = c.JS_NULL;
    p.u.array.len = 0;
    if (initial_len > 0) {
        var val_ref: c.JSGCRef = undefined;
        utils.pushValue(ctx, &val_ref, val);
        const arr = js_alloc_value_array(ctx, 0, initial_len);
        val = utils.popValue(ctx, &val_ref);
        if (arr == null)
            return c.JS_EXCEPTION;
        p = @ptrCast(@alignCast(mc.valueToPtr(val)));
        p.u.array.tab = mc.valueFromPtr(arr.?);
        p.u.array.len = @intCast(initial_len);
    }
    return val;
}

pub fn find_own_property(ctx: *c.JSContext, p: *mc.JSObjectExt, prop: c.JSValue) ?*vt.JSPropertyExt {
    _ = ctx;
    return vt.findOwnPropertyInlined(p, prop);
}

pub fn get_special_prop(ctx: *c.JSContext, val: c.JSValue) c.JSValue {
    const idx = vt.valueGetInt(val);
    if (idx >= 0)
        return vt.classProto(mc.ctxExt(ctx), idx).*
    else
        return vt.classObj(mc.ctxExt(ctx), -idx - 1).*;
}

fn protoObject(x: *mc.JSContextExt, class_id: c_int) *mc.JSObjectExt {
    return @ptrCast(@alignCast(mc.valueToPtr(vt.classProto(x, class_id).*)));
}

pub fn JS_GetPropertyInternal(ctx: *c.JSContext, obj: c.JSValue, prop: c.JSValue, allow_tail_call: c.JS_BOOL) c.JSValue {
    const x = mc.ctxExt(ctx);
    var p: *mc.JSObjectExt = undefined;
    var handle_string = false;

    if (!mc.isPtr(obj)) {
        if (vt.isIntOrShortFloat(obj)) {
            p = protoObject(x, c.JS_CLASS_NUMBER);
        } else {
            switch (mc.valueGetSpecialTag(obj)) {
                c.JS_TAG_BOOL => p = protoObject(x, c.JS_CLASS_BOOLEAN),
                c.JS_TAG_SHORT_FUNC => p = protoObject(x, c.JS_CLASS_CLOSURE),
                c.JS_TAG_STRING_CHAR => handle_string = true,
                c.JS_TAG_NULL => return utils.JS_ThrowError(ctx, c.JS_CLASS_TYPE_ERROR, "cannot read property '%lo' of null", prop),
                c.JS_TAG_UNDEFINED => return utils.JS_ThrowError(ctx, c.JS_CLASS_TYPE_ERROR, "cannot read property '%lo' of undefined", prop),
                else => return utils.JS_ThrowError(ctx, c.JS_CLASS_TYPE_ERROR, "cannot read property '%lo' of value", prop),
            }
        }
    } else {
        p = @ptrCast(@alignCast(mc.valueToPtr(obj)));
    }

    if (!handle_string and mc.mbGetMtag(p) != mc.JS_MTAG_OBJECT) {
        switch (mc.mbGetMtag(p)) {
            mc.JS_MTAG_FLOAT64 => p = protoObject(x, c.JS_CLASS_NUMBER),
            mc.JS_MTAG_STRING => handle_string = true,
            else => return utils.JS_ThrowError(ctx, c.JS_CLASS_TYPE_ERROR, "cannot read property '%lo' of value", prop),
        }
    }
    if (handle_string) {
        if (mc.isInt(prop)) {
            var obj_mut = obj;
            var prop_mut = prop;
            const ret = builtins.js_string_charAt(ctx, &obj_mut, 1, @ptrCast(&prop_mut), vt.magic_internalAt);
            if (!vt.isUndefined(ret))
                return ret;
        }
        p = protoObject(x, c.JS_CLASS_STRING);
    }

    while (true) {
        const class_id = mc.objectClassId(p);
        if (class_id == c.JS_CLASS_ARRAY) {
            if (mc.isInt(prop)) {
                const idx: u32 = @bitCast(vt.valueGetInt(prop));
                if (idx < p.u.array.len) {
                    const arr: *vt.JSValueArrayExt = @ptrCast(@alignCast(mc.valueToPtr(p.u.array.tab)));
                    return vt.valueArrayItems(arr)[idx];
                }
            } else if (JS_IsNumericProperty(ctx, prop) != 0) {
                return c.JS_UNDEFINED;
            }
        } else if (class_id >= c.JS_CLASS_UINT8C_ARRAY and class_id <= c.JS_CLASS_FLOAT64_ARRAY) {
            if (mc.isInt(prop)) {
                var idx: u32 = @bitCast(vt.valueGetInt(prop));
                if (idx < p.u.typed_array.len) {
                    idx += p.u.typed_array.offset;
                    const pbuffer: *mc.JSObjectExt = @ptrCast(@alignCast(mc.valueToPtr(p.u.typed_array.buffer)));
                    const arr: *vt.JSByteArrayExt = @ptrCast(@alignCast(mc.valueToPtr(pbuffer.u.array_buffer.byte_buffer)));
                    const buf = vt.byteArrayBuf(arr);
                    switch (class_id) {
                        c.JS_CLASS_UINT8C_ARRAY, c.JS_CLASS_UINT8_ARRAY => return JS_NewShortInt(buf[idx]),
                        c.JS_CLASS_INT8_ARRAY => {
                            const v: *const i8 = @ptrCast(&buf[idx]);
                            return JS_NewShortInt(v.*);
                        },
                        c.JS_CLASS_INT16_ARRAY => {
                            const v: *const i16 = @ptrCast(@alignCast(&buf[idx * 2]));
                            return JS_NewShortInt(v.*);
                        },
                        c.JS_CLASS_UINT16_ARRAY => {
                            const v: *const u16 = @ptrCast(@alignCast(&buf[idx * 2]));
                            return JS_NewShortInt(@intCast(v.*));
                        },
                        c.JS_CLASS_INT32_ARRAY => {
                            const v: *const i32 = @ptrCast(@alignCast(&buf[idx * 4]));
                            return JS_NewInt32(ctx, v.*);
                        },
                        c.JS_CLASS_UINT32_ARRAY => {
                            const v: *const u32 = @ptrCast(@alignCast(&buf[idx * 4]));
                            return JS_NewUint32(ctx, v.*);
                        },
                        c.JS_CLASS_FLOAT32_ARRAY => {
                            const v: *const f32 = @ptrCast(@alignCast(&buf[idx * 4]));
                            return JS_NewFloat64(ctx, v.*);
                        },
                        c.JS_CLASS_FLOAT64_ARRAY => {
                            const v: *const f64 = @ptrCast(@alignCast(&buf[idx * 8]));
                            return JS_NewFloat64(ctx, v.*);
                        },
                        else => return JS_NewShortInt(buf[idx]),
                    }
                }
            } else if (JS_IsNumericProperty(ctx, prop) != 0) {
                return c.JS_UNDEFINED;
            }
        }

        if (find_own_property(ctx, p, prop)) |pr| {
            const ptype = vt.propType(pr);
            if (ptype == vt.JS_PROP_NORMAL) {
                return pr.value;
            } else if (ptype == vt.JS_PROP_VARREF) {
                const pv: *vt.JSVarRefExt = @ptrCast(@alignCast(mc.valueToPtr(pr.value)));
                return pv.u.value;
            } else if (ptype == vt.JS_PROP_SPECIAL) {
                return get_special_prop(ctx, pr.value);
            } else {
                const arr: *vt.JSValueArrayExt = @ptrCast(@alignCast(mc.valueToPtr(pr.value)));
                const getter = vt.valueArrayItems(arr)[0];
                if (getter == c.JS_UNDEFINED)
                    return c.JS_UNDEFINED;
                if (allow_tail_call != 0) {
                    var sp: [*]c.JSValue = @ptrCast(x.sp);
                    (sp - 1)[0] = sp[0];
                    sp[0] = getter;
                    x.sp = @ptrCast(sp - 1);
                    return vt.newTailCall(0);
                } else {
                    var getter_ref: c.JSGCRef = undefined;
                    var obj_ref: c.JSGCRef = undefined;
                    var obj_mut = obj;
                    var getter_mut = getter;
                    utils.pushValue(ctx, &getter_ref, getter_mut);
                    utils.pushValue(ctx, &obj_ref, obj_mut);
                    const err = utils.JS_StackCheck(ctx, 2);
                    obj_mut = utils.popValue(ctx, &obj_ref);
                    getter_mut = utils.popValue(ctx, &getter_ref);
                    if (err != 0)
                        return c.JS_EXCEPTION;
                    runtime.JS_PushArg(ctx, getter_mut);
                    runtime.JS_PushArg(ctx, obj_mut);
                    return runtime.JS_Call(ctx, 0);
                }
            }
        }
        const proto = p.proto;
        if (proto == c.JS_NULL)
            break;
        p = @ptrCast(@alignCast(mc.valueToPtr(proto)));
    }
    return c.JS_UNDEFINED;
}

pub fn JS_GetProperty(ctx: *c.JSContext, obj: c.JSValue, prop: c.JSValue) c.JSValue {
    return JS_GetPropertyInternal(ctx, obj, prop, c.FALSE);
}

pub fn JS_GetPropertyStr(ctx: *c.JSContext, this_obj: c.JSValue, str: [*:0]const u8) c.JSValue {
    var this_obj_ref: c.JSGCRef = undefined;
    var this_mut = this_obj;
    utils.pushValue(ctx, &this_obj_ref, this_mut);
    var prop = JS_NewString(ctx, str);
    if (!vt.isExactException(prop))
        prop = runtime.JS_ToPropertyKey(ctx, prop);
    this_mut = utils.popValue(ctx, &this_obj_ref);
    if (vt.isExactException(prop))
        return prop;
    return JS_GetProperty(ctx, this_mut, prop);
}

pub fn JS_GetPropertyUint32(ctx: *c.JSContext, obj: c.JSValue, idx: u32) c.JSValue {
    if (idx > @as(u32, @intCast(vt.JS_SHORTINT_MAX)))
        return utils.JS_ThrowError(ctx, c.JS_CLASS_RANGE_ERROR, "invalid array index");
    return JS_GetProperty(ctx, obj, JS_NewInt32(ctx, @intCast(idx)));
}

pub fn JS_HasProperty(ctx: *c.JSContext, obj: c.JSValue, prop: c.JSValue) c.JS_BOOL {
    if (!mc.isPtr(obj))
        return c.FALSE;
    var p: *mc.JSObjectExt = @ptrCast(@alignCast(mc.valueToPtr(obj)));
    if (mc.mbGetMtag(p) != mc.JS_MTAG_OBJECT)
        return c.FALSE;
    var cur = obj;
    while (true) {
        if (find_own_property(ctx, p, prop) != null)
            return c.TRUE;
        cur = p.proto;
        if (cur == c.JS_NULL)
            break;
        p = @ptrCast(@alignCast(mc.valueToPtr(cur)));
    }
    return c.FALSE;
}

pub fn get_prop_hash_size_log2(prop_count: c_int) c_int {
    if (prop_count <= 1)
        return 0
    else
        return @as(c_int, @intCast(32 - @clz(@as(u32, @intCast(prop_count - 1))))) - 1;
}

pub fn js_alloc_props(ctx: *c.JSContext, n: c_int) ?*vt.JSValueArrayExt {
    const hash_size_log2 = get_prop_hash_size_log2(n);
    const hash_mask = (@as(c_int, 1) << @intCast(hash_size_log2)) - 1;
    const first_free = 2 + hash_mask + 1;
    const size = first_free + 3 * n;
    const arr = js_alloc_value_array(ctx, 0, size) orelse return null;
    const items = vt.valueArrayItems(arr);
    items[0] = JS_NewShortInt(0);
    items[1] = JS_NewShortInt(hash_mask);
    var i: c_int = 0;
    while (i <= hash_mask) : (i += 1)
        items[@intCast(2 + i)] = 0;
    var pr: *vt.JSPropertyExt = undefined;
    i = 0;
    while (i < n) : (i += 1) {
        pr = @ptrCast(@alignCast(&items[@intCast(2 + hash_mask + 1 + 3 * i)]));
        pr.key = c.JS_UNINITIALIZED;
    }
    vt.propSetHashNext(pr, @intCast(first_free << 1));
    return arr;
}

pub fn js_rehash_props(ctx: *c.JSContext, p: *mc.JSObjectExt, gc_rehash: c.JS_BOOL) void {
    const arr: *vt.JSValueArrayExt = @ptrCast(@alignCast(mc.valueToPtr(p.props)));
    if (vt.jsIsRomPtr(ctx, arr))
        return;
    const hash_mask = vt.valueGetInt(vt.valueArrayItems(arr)[1]);
    if (hash_mask == 0 and gc_rehash != 0)
        return;
    const prop_count = vt.valueGetInt(vt.valueArrayItems(arr)[0]);
    const items = vt.valueArrayItems(arr);
    var i: c_int = 0;
    while (i <= hash_mask) : (i += 1)
        items[@intCast(2 + i)] = JS_NewShortInt(0);
    i = 0;
    var j: c_int = 0;
    while (j < prop_count) : (i += 1) {
        const idx = 2 + (hash_mask + 1) + 3 * i;
        const pr: *vt.JSPropertyExt = @ptrCast(@alignCast(&items[@intCast(idx)]));
        if (pr.key != c.JS_UNINITIALIZED) {
            const h = vt.hashProp(pr.key) & @as(u32, @intCast(hash_mask));
            vt.propSetHashNext(pr, @intCast(items[2 + h]));
            items[2 + h] = JS_NewShortInt(idx);
            j += 1;
        }
    }
}

pub fn js_compact_props(ctx: *c.JSContext, p: *mc.JSObjectExt) void {
    const arr: *vt.JSValueArrayExt = @ptrCast(@alignCast(mc.valueToPtr(p.props)));
    const prop_count = vt.valueGetInt(vt.valueArrayItems(arr)[0]);
    if (prop_count == 0) {
        if (p.props != mc.ctxExt(ctx).empty_props)
            p.props = mc.ctxExt(ctx).empty_props;
        return;
    }
    const hash_mask = vt.valueGetInt(vt.valueArrayItems(arr)[1]);
    const hash_size_log2 = get_prop_hash_size_log2(prop_count);
    const new_hash_mask = cutils.min_int(hash_mask, (@as(c_int, 1) << @intCast(hash_size_log2)) - 1);
    const new_size = 2 + new_hash_mask + 1 + 3 * prop_count;
    if (new_size >= vt.valueArraySize(arr))
        return;
    vt.valueArrayItems(arr)[1] = JS_NewShortInt(new_hash_mask);
    const items = vt.valueArrayItems(arr);
    var i: c_int = 0;
    var j: c_int = 0;
    while (j < prop_count) : (i += 1) {
        const pr: *vt.JSPropertyExt = @ptrCast(@alignCast(&items[@intCast(2 + (hash_mask + 1) + 3 * i)]));
        if (pr.key != c.JS_UNINITIALIZED) {
            const pr1: *vt.JSPropertyExt = @ptrCast(@alignCast(&items[@intCast(2 + (new_hash_mask + 1) + 3 * j)]));
            pr1.* = pr.*;
            j += 1;
        }
    }
    js_shrink_value_array(ctx, &p.props, new_size);
    js_rehash_props(ctx, p, c.FALSE);
}

pub fn js_update_props(ctx: *c.JSContext, obj: c.JSValue) c_int {
    var p: *mc.JSObjectExt = @ptrCast(@alignCast(mc.valueToPtr(obj)));
    const arr: *vt.JSValueArrayExt = @ptrCast(@alignCast(mc.valueToPtr(p.props)));
    if (!vt.jsIsRomPtr(ctx, arr))
        return 0;
    var obj_ref: c.JSGCRef = undefined;
    var obj_mut = obj;
    utils.pushValue(ctx, &obj_ref, obj_mut);
    const arr1 = js_alloc_value_array(ctx, 0, vt.valueArraySize(arr));
    obj_mut = utils.popValue(ctx, &obj_ref);
    if (arr1 == null)
        return -1;
    const nbytes: usize = @intCast(vt.valueArraySize(arr) * @as(c_int, @intCast(@sizeOf(c.JSValue))));
    @memcpy(
        @as([*]u8, @ptrCast(vt.valueArrayItems(arr1.?)))[0..nbytes],
        @as([*]u8, @ptrCast(vt.valueArrayItems(arr)))[0..nbytes],
    );
    const prop_count = vt.valueGetInt(vt.valueArrayItems(arr1.?)[0]);
    const hash_mask = vt.valueGetInt(vt.valueArrayItems(arr1.?)[1]);
    std.debug.assert(vt.valueArraySize(arr1.?) == 2 + (hash_mask + 1) + 3 * prop_count);
    var i: c_int = 0;
    while (i < prop_count) : (i += 1) {
        const idx = 2 + (hash_mask + 1) + 3 * i;
        const pr: *vt.JSPropertyExt = @ptrCast(@alignCast(&vt.valueArrayItems(arr1.?)[@intCast(idx)]));
        if (vt.propType(pr) == vt.JS_PROP_SPECIAL) {
            pr.value = get_special_prop(ctx, pr.value);
            vt.propSetType(pr, vt.JS_PROP_NORMAL);
        }
    }
    p = @ptrCast(@alignCast(mc.valueToPtr(obj_mut)));
    p.props = mc.valueFromPtr(arr1.?);
    return 0;
}

pub fn get_first_free(arr: *vt.JSValueArrayExt) c_int {
    const items = vt.valueArrayItems(arr);
    const pr1: *vt.JSPropertyExt = @ptrCast(@alignCast(&items[@intCast(vt.valueArraySize(arr) - 3)]));
    if (pr1.key == c.JS_UNINITIALIZED)
        return @intCast(vt.propHashNext(pr1) >> 1)
    else
        return vt.valueArraySize(arr);
}

pub fn js_create_property(ctx: *c.JSContext, obj: c.JSValue, prop: c.JSValue) ?*vt.JSPropertyExt {
    var p: *mc.JSObjectExt = @ptrCast(@alignCast(mc.valueToPtr(obj)));
    var arr: *vt.JSValueArrayExt = @ptrCast(@alignCast(mc.valueToPtr(p.props)));
    var items = vt.valueArrayItems(arr);
    var prop_count = vt.valueGetInt(items[0]);
    var hash_mask = vt.valueGetInt(items[1]);
    var pr1: *vt.JSPropertyExt = @ptrCast(@alignCast(&items[@intCast(vt.valueArraySize(arr) - 3)]));
    var first_free: c_int = undefined;
    if (pr1.key != c.JS_UNINITIALIZED) {
        if (p.props == mc.ctxExt(ctx).empty_props) {
            var obj_ref: c.JSGCRef = undefined;
            var prop_ref: c.JSGCRef = undefined;
            var obj_mut = obj;
            var prop_mut = prop;
            utils.pushValue(ctx, &obj_ref, obj_mut);
            utils.pushValue(ctx, &prop_ref, prop_mut);
            arr = js_alloc_props(ctx, 1) orelse {
                _ = utils.popValue(ctx, &prop_ref);
                _ = utils.popValue(ctx, &obj_ref);
                return null;
            };
            prop_mut = utils.popValue(ctx, &prop_ref);
            obj_mut = utils.popValue(ctx, &obj_ref);
            p = @ptrCast(@alignCast(mc.valueToPtr(obj_mut)));
            p.props = mc.valueFromPtr(arr);
            items = vt.valueArrayItems(arr);
            prop_count = vt.valueGetInt(items[0]);
            hash_mask = vt.valueGetInt(items[1]);
            first_free = 3;
        } else {
            first_free = vt.valueArraySize(arr);
            var new_size = first_free + 3;
            var new_hash_mask = hash_mask;
            if ((prop_count + 1) > 2 * (hash_mask + 1)) {
                new_hash_mask = 2 * (hash_mask + 1) - 1;
                new_size += new_hash_mask - hash_mask;
            }
            var obj_ref: c.JSGCRef = undefined;
            var prop_ref: c.JSGCRef = undefined;
            var obj_mut = obj;
            var prop_mut = prop;
            utils.pushValue(ctx, &obj_ref, obj_mut);
            utils.pushValue(ctx, &prop_ref, prop_mut);
            const new_props = js_resize_value_array2(ctx, p.props, new_size, 2 + new_hash_mask + 1);
            prop_mut = utils.popValue(ctx, &prop_ref);
            obj_mut = utils.popValue(ctx, &obj_ref);
            if (vt.isExactException(new_props))
                return null;
            p = @ptrCast(@alignCast(mc.valueToPtr(obj_mut)));
            p.props = new_props;
            arr = @ptrCast(@alignCast(mc.valueToPtr(p.props)));
            items = vt.valueArrayItems(arr);
            if (new_hash_mask != hash_mask) {
                const nmove: usize = @intCast(first_free - (2 + hash_mask + 1));
                std.mem.copyBackwards(
                    c.JSValue,
                    items[@intCast(2 + (new_hash_mask + 1))..][0..nmove],
                    items[@intCast(2 + (hash_mask + 1))..][0..nmove],
                );
                first_free += new_hash_mask - hash_mask;
                hash_mask = new_hash_mask;
                items[1] = JS_NewShortInt(hash_mask);
                js_rehash_props(ctx, p, c.FALSE);
            }
        }
        pr1 = @ptrCast(@alignCast(&items[@intCast(vt.valueArraySize(arr) - 3)]));
        pr1.key = c.JS_UNINITIALIZED;
    } else {
        first_free = @intCast(vt.propHashNext(pr1) >> 1);
    }

    const pr: *vt.JSPropertyExt = @ptrCast(@alignCast(&items[@intCast(first_free)]));
    pr.key = prop;
    pr.value = c.JS_UNDEFINED;
    vt.propSetType(pr, vt.JS_PROP_NORMAL);
    const h = vt.hashProp(prop) & @as(u32, @intCast(hash_mask));
    vt.propSetHashNext(pr, @intCast(items[2 + h]));
    items[2 + h] = JS_NewShortInt(first_free);
    items[0] = JS_NewShortInt(prop_count + 1);
    first_free += 3;
    if (first_free < vt.valueArraySize(arr)) {
        pr1 = @ptrCast(@alignCast(&items[@intCast(vt.valueArraySize(arr) - 3)]));
        vt.propSetHashNext(pr1, @intCast(first_free << 1));
    }
    return pr;
}

pub fn JS_DefinePropertyInternal(ctx: *c.JSContext, obj: c.JSValue, prop: c.JSValue, val: c.JSValue, setter: c.JSValue, flags: c_int) c.JSValue {
    var obj_mut = obj;
    var prop_mut = prop;
    var val_mut = val;
    var setter_mut = setter;
    var obj_ref: c.JSGCRef = undefined;
    var prop_ref: c.JSGCRef = undefined;
    var val_ref: c.JSGCRef = undefined;
    var setter_ref: c.JSGCRef = undefined;
    utils.pushValue(ctx, &obj_ref, obj_mut);
    utils.pushValue(ctx, &prop_ref, prop_mut);
    utils.pushValue(ctx, &val_ref, val_mut);
    utils.pushValue(ctx, &setter_ref, setter_mut);
    const ret = js_update_props(ctx, obj_mut);
    setter_mut = utils.popValue(ctx, &setter_ref);
    val_mut = utils.popValue(ctx, &val_ref);
    prop_mut = utils.popValue(ctx, &prop_ref);
    obj_mut = utils.popValue(ctx, &obj_ref);
    if (ret != 0)
        return c.JS_EXCEPTION;

    var pr: *vt.JSPropertyExt = undefined;
    if (flags & vt.JS_DEF_PROP_LOOKUP != 0) {
        if (find_own_property(ctx, @ptrCast(@alignCast(mc.valueToPtr(obj_mut))), prop_mut)) |found| {
            pr = found;
            if (flags & vt.JS_DEF_PROP_HAS_VALUE != 0) {
                if (vt.propType(pr) == vt.JS_PROP_NORMAL) {
                    pr.value = val_mut;
                } else if (vt.propType(pr) == vt.JS_PROP_VARREF) {
                    const pv: *vt.JSVarRefExt = @ptrCast(@alignCast(mc.valueToPtr(pr.value)));
                    pv.u.value = val_mut;
                } else {
                    return utils.JS_ThrowError(ctx, c.JS_CLASS_TYPE_ERROR, "cannot modify getter/setter/value kind");
                }
            } else if (flags & (vt.JS_DEF_PROP_HAS_GET | vt.JS_DEF_PROP_HAS_SET) != 0) {
                if (vt.propType(pr) != vt.JS_PROP_GETSET)
                    return utils.JS_ThrowError(ctx, c.JS_CLASS_TYPE_ERROR, "cannot modify getter/setter/value kind");
                var arr: *vt.JSValueArrayExt = @ptrCast(@alignCast(mc.valueToPtr(pr.value)));
                if (vt.jsIsRomPtr(ctx, arr)) {
                    utils.pushValue(ctx, &obj_ref, obj_mut);
                    utils.pushValue(ctx, &prop_ref, prop_mut);
                    utils.pushValue(ctx, &val_ref, val_mut);
                    utils.pushValue(ctx, &setter_ref, setter_mut);
                    const arr2 = js_alloc_value_array(ctx, 0, 2);
                    setter_mut = utils.popValue(ctx, &setter_ref);
                    val_mut = utils.popValue(ctx, &val_ref);
                    prop_mut = utils.popValue(ctx, &prop_ref);
                    obj_mut = utils.popValue(ctx, &obj_ref);
                    if (arr2 == null)
                        return c.JS_EXCEPTION;
                    pr = find_own_property(ctx, @ptrCast(@alignCast(mc.valueToPtr(obj_mut))), prop_mut).?;
                    arr = @ptrCast(@alignCast(mc.valueToPtr(pr.value)));
                    vt.valueArrayItems(arr2.?)[0] = vt.valueArrayItems(arr)[0];
                    vt.valueArrayItems(arr2.?)[1] = vt.valueArrayItems(arr)[1];
                    pr.value = mc.valueFromPtr(arr2.?);
                    arr = arr2.?;
                }
                if (flags & vt.JS_DEF_PROP_HAS_GET != 0)
                    vt.valueArrayItems(arr)[0] = val_mut;
                if (flags & vt.JS_DEF_PROP_HAS_SET != 0)
                    vt.valueArrayItems(arr)[1] = setter_mut;
            }
            if (flags & vt.JS_DEF_PROP_RET_VAL != 0)
                return pr.value
            else
                return c.JS_UNDEFINED;
        }
    }

    var prop_type: u32 = undefined;
    if (flags & (vt.JS_DEF_PROP_HAS_GET | vt.JS_DEF_PROP_HAS_SET) != 0) {
        prop_type = vt.JS_PROP_GETSET;
        utils.pushValue(ctx, &obj_ref, obj_mut);
        utils.pushValue(ctx, &prop_ref, prop_mut);
        utils.pushValue(ctx, &val_ref, val_mut);
        utils.pushValue(ctx, &setter_ref, setter_mut);
        const arr = js_alloc_value_array(ctx, 0, 2);
        setter_mut = utils.popValue(ctx, &setter_ref);
        val_mut = utils.popValue(ctx, &val_ref);
        prop_mut = utils.popValue(ctx, &prop_ref);
        obj_mut = utils.popValue(ctx, &obj_ref);
        if (arr == null)
            return c.JS_EXCEPTION;
        vt.valueArrayItems(arr.?)[0] = val_mut;
        vt.valueArrayItems(arr.?)[1] = setter_mut;
        val_mut = mc.valueFromPtr(arr.?);
    } else if (obj_mut == mc.ctxExt(ctx).global_obj) {
        prop_type = vt.JS_PROP_VARREF;
        utils.pushValue(ctx, &obj_ref, obj_mut);
        utils.pushValue(ctx, &prop_ref, prop_mut);
        utils.pushValue(ctx, &val_ref, val_mut);
        const pv: ?*vt.JSVarRefExt = @ptrCast(@alignCast(
            utils.js_malloc(ctx, vt.varRefAllocSize(), mc.JS_MTAG_VARREF),
        ));
        val_mut = utils.popValue(ctx, &val_ref);
        prop_mut = utils.popValue(ctx, &prop_ref);
        obj_mut = utils.popValue(ctx, &obj_ref);
        if (pv == null)
            return c.JS_EXCEPTION;
        vt.varRefSetDetached(pv.?, true);
        pv.?.u.value = val_mut;
        val_mut = mc.valueFromPtr(pv.?);
    } else {
        prop_type = vt.JS_PROP_NORMAL;
    }
    utils.pushValue(ctx, &val_ref, val_mut);
    const created = js_create_property(ctx, obj_mut, prop_mut);
    val_mut = utils.popValue(ctx, &val_ref);
    if (created == null)
        return c.JS_EXCEPTION;
    pr = created.?;
    vt.propSetType(pr, prop_type);
    pr.value = val_mut;
    if (flags & vt.JS_DEF_PROP_RET_VAL != 0)
        return pr.value
    else
        return c.JS_UNDEFINED;
}

pub fn JS_DefinePropertyValue(ctx: *c.JSContext, obj: c.JSValue, prop: c.JSValue, val: c.JSValue) c.JSValue {
    return JS_DefinePropertyInternal(ctx, obj, prop, val, c.JS_NULL, vt.JS_DEF_PROP_LOOKUP | vt.JS_DEF_PROP_HAS_VALUE);
}

pub fn JS_DefinePropertyGetSet(ctx: *c.JSContext, obj: c.JSValue, prop: c.JSValue, getter: c.JSValue, setter: c.JSValue, flags: c_int) c.JSValue {
    return JS_DefinePropertyInternal(ctx, obj, prop, getter, setter, vt.JS_DEF_PROP_LOOKUP | flags);
}

pub fn add_global_var(ctx: *c.JSContext, prop: c.JSValue, define_flag: c.JS_BOOL) c.JSValue {
    const p: *mc.JSObjectExt = @ptrCast(@alignCast(mc.valueToPtr(mc.ctxExt(ctx).global_obj)));
    if (find_own_property(ctx, p, prop)) |pr| {
        if (vt.propType(pr) != vt.JS_PROP_VARREF)
            return utils.JS_ThrowError(ctx, c.JS_CLASS_REFERENCE_ERROR, "global variable '%lo' must be a reference", prop);
        if (define_flag != 0) {
            const pv: *vt.JSVarRefExt = @ptrCast(@alignCast(mc.valueToPtr(pr.value)));
            if (pv.u.value == c.JS_UNINITIALIZED)
                pv.u.value = c.JS_UNDEFINED;
        }
        return pr.value;
    }
    return JS_DefinePropertyInternal(
        ctx,
        mc.ctxExt(ctx).global_obj,
        prop,
        if (define_flag != 0) c.JS_UNDEFINED else c.JS_UNINITIALIZED,
        c.JS_NULL,
        vt.JS_DEF_PROP_RET_VAL | vt.JS_DEF_PROP_HAS_VALUE,
    );
}

pub fn JS_SetPropertyInternal(ctx: *c.JSContext, this_obj: c.JSValue, prop: c.JSValue, val: c.JSValue, allow_tail_call: c.JS_BOOL) c.JSValue {
    const x = mc.ctxExt(ctx);
    var p: *mc.JSObjectExt = undefined;
    var is_obj: bool = undefined;
    var this_mut = this_obj;
    var val_mut = val;

    if (!mc.isPtr(this_mut)) {
        is_obj = false;
        if (vt.isIntOrShortFloat(this_mut)) {
            p = protoObject(x, c.JS_CLASS_NUMBER);
            return setPropertyProtoLookup(ctx, this_mut, prop, val_mut, allow_tail_call, p, is_obj);
        } else {
            switch (mc.valueGetSpecialTag(this_mut)) {
                c.JS_TAG_BOOL => {
                    p = protoObject(x, c.JS_CLASS_BOOLEAN);
                    return setPropertyProtoLookup(ctx, this_mut, prop, val_mut, allow_tail_call, p, is_obj);
                },
                c.JS_TAG_SHORT_FUNC => {
                    p = protoObject(x, c.JS_CLASS_CLOSURE);
                    return setPropertyProtoLookup(ctx, this_mut, prop, val_mut, allow_tail_call, p, is_obj);
                },
                c.JS_TAG_STRING_CHAR => {
                    p = protoObject(x, c.JS_CLASS_STRING);
                    return setPropertyProtoLookup(ctx, this_mut, prop, val_mut, allow_tail_call, p, is_obj);
                },
                c.JS_TAG_NULL => return utils.JS_ThrowError(ctx, c.JS_CLASS_TYPE_ERROR, "cannot set property '%lo' of null", prop),
                c.JS_TAG_UNDEFINED => return utils.JS_ThrowError(ctx, c.JS_CLASS_TYPE_ERROR, "cannot set property '%lo' of undefined", prop),
                else => return utils.JS_ThrowError(ctx, c.JS_CLASS_TYPE_ERROR, "cannot set property '%lo' of value", prop),
            }
        }
    } else {
        is_obj = true;
        p = @ptrCast(@alignCast(mc.valueToPtr(this_mut)));
    }
    if (mc.mbGetMtag(p) != mc.JS_MTAG_OBJECT) {
        is_obj = false;
        switch (mc.mbGetMtag(p)) {
            mc.JS_MTAG_FLOAT64 => {
                p = protoObject(x, c.JS_CLASS_NUMBER);
                return setPropertyProtoLookup(ctx, this_mut, prop, val_mut, allow_tail_call, p, is_obj);
            },
            mc.JS_MTAG_STRING => {
                p = protoObject(x, c.JS_CLASS_STRING);
                return setPropertyProtoLookup(ctx, this_mut, prop, val_mut, allow_tail_call, p, is_obj);
            },
            else => return utils.JS_ThrowError(ctx, c.JS_CLASS_TYPE_ERROR, "cannot set property '%lo' of value", prop),
        }
    }

    const class_id = mc.objectClassId(p);
    if (class_id == c.JS_CLASS_ARRAY) {
        if (mc.isInt(prop)) {
            const idx: u32 = @bitCast(vt.valueGetInt(prop));
            if (idx < p.u.array.len) {
                const arr: *vt.JSValueArrayExt = @ptrCast(@alignCast(mc.valueToPtr(p.u.array.tab)));
                vt.valueArrayItems(arr)[idx] = val_mut;
                return c.JS_UNDEFINED;
            } else if (idx == p.u.array.len) {
                var this_obj_ref: c.JSGCRef = undefined;
                var val_ref: c.JSGCRef = undefined;
                utils.pushValue(ctx, &this_obj_ref, this_mut);
                utils.pushValue(ctx, &val_ref, val_mut);
                const new_tab = js_resize_value_array(ctx, p.u.array.tab, @intCast(idx + 1));
                val_mut = utils.popValue(ctx, &val_ref);
                this_mut = utils.popValue(ctx, &this_obj_ref);
                if (vt.isExactException(new_tab))
                    return c.JS_EXCEPTION;
                p = @ptrCast(@alignCast(mc.valueToPtr(this_mut)));
                p.u.array.tab = new_tab;
                const arr: *vt.JSValueArrayExt = @ptrCast(@alignCast(mc.valueToPtr(p.u.array.tab)));
                vt.valueArrayItems(arr)[idx] = val_mut;
                p.u.array.len += 1;
                return c.JS_UNDEFINED;
            } else {
                return utils.JS_ThrowError(ctx, c.JS_CLASS_TYPE_ERROR, "invalid array subscript");
            }
        } else if (JS_IsNumericProperty(ctx, prop) != 0) {
            return utils.JS_ThrowError(ctx, c.JS_CLASS_TYPE_ERROR, "invalid array subscript");
        }
    } else if (class_id >= c.JS_CLASS_UINT8C_ARRAY and class_id <= c.JS_CLASS_FLOAT64_ARRAY) {
        if (mc.isInt(prop)) {
            var idx: u32 = @bitCast(vt.valueGetInt(prop));
            var v: c_int = 0;
            var d: f64 = 0;
            var conv_ret: c_int = 0;
            var this_obj_ref: c.JSGCRef = undefined;
            var val_ref: c.JSGCRef = undefined;
            utils.pushValue(ctx, &this_obj_ref, this_mut);
            utils.pushValue(ctx, &val_ref, val_mut);
            switch (class_id) {
                c.JS_CLASS_UINT8C_ARRAY => conv_ret = runtime.JS_ToUint8Clamp(ctx, &v, val_mut),
                c.JS_CLASS_FLOAT32_ARRAY, c.JS_CLASS_FLOAT64_ARRAY => conv_ret = runtime.JS_ToNumber(ctx, &d, val_mut),
                else => conv_ret = runtime.JS_ToInt32(ctx, &v, val_mut),
            }
            val_mut = utils.popValue(ctx, &val_ref);
            this_mut = utils.popValue(ctx, &this_obj_ref);
            if (conv_ret != 0)
                return c.JS_EXCEPTION;
            p = @ptrCast(@alignCast(mc.valueToPtr(this_mut)));
            if (idx >= p.u.typed_array.len)
                return utils.JS_ThrowError(ctx, c.JS_CLASS_TYPE_ERROR, "invalid array subscript");
            idx += p.u.typed_array.offset;
            const pbuffer: *mc.JSObjectExt = @ptrCast(@alignCast(mc.valueToPtr(p.u.typed_array.buffer)));
            const arr: *vt.JSByteArrayExt = @ptrCast(@alignCast(mc.valueToPtr(pbuffer.u.array_buffer.byte_buffer)));
            const buf = vt.byteArrayBuf(arr);
            switch (mc.objectClassId(p)) {
                c.JS_CLASS_UINT8C_ARRAY, c.JS_CLASS_INT8_ARRAY, c.JS_CLASS_UINT8_ARRAY => buf[idx] = @truncate(@as(u32, @bitCast(v))),
                c.JS_CLASS_INT16_ARRAY, c.JS_CLASS_UINT16_ARRAY => {
                    const dest: *u16 = @ptrCast(@alignCast(&buf[idx * 2]));
                    dest.* = @truncate(@as(u32, @bitCast(v)));
                },
                c.JS_CLASS_INT32_ARRAY, c.JS_CLASS_UINT32_ARRAY => {
                    const dest: *u32 = @ptrCast(@alignCast(&buf[idx * 4]));
                    dest.* = @bitCast(v);
                },
                c.JS_CLASS_FLOAT32_ARRAY => {
                    const dest: *f32 = @ptrCast(@alignCast(&buf[idx * 4]));
                    dest.* = @floatCast(d);
                },
                c.JS_CLASS_FLOAT64_ARRAY => {
                    const dest: *f64 = @ptrCast(@alignCast(&buf[idx * 8]));
                    dest.* = d;
                },
                else => buf[idx] = @truncate(@as(u32, @bitCast(v))),
            }
            return c.JS_UNDEFINED;
        } else if (JS_IsNumericProperty(ctx, prop) != 0) {
            return utils.JS_ThrowError(ctx, c.JS_CLASS_TYPE_ERROR, "invalid array subscript");
        }
    }

    return setPropertyOwnAndProto(ctx, this_mut, prop, val_mut, allow_tail_call, p, is_obj);
}

fn setPropertyGetSet(ctx: *c.JSContext, this_obj: c.JSValue, val: c.JSValue, allow_tail_call: c.JS_BOOL, pr: *vt.JSPropertyExt) c.JSValue {
    const arr: *vt.JSValueArrayExt = @ptrCast(@alignCast(mc.valueToPtr(pr.value)));
    const setter = vt.valueArrayItems(arr)[1];
    if (allow_tail_call != 0) {
        var sp: [*]c.JSValue = @ptrCast(mc.ctxExt(ctx).sp);
        (sp - 2)[0] = sp[0];
        (sp - 1)[0] = setter;
        sp[0] = val;
        mc.ctxExt(ctx).sp = @ptrCast(sp - 2);
        return vt.newTailCall(1 | vt.FRAME_CF_POP_RET);
    } else {
        var val_ref: c.JSGCRef = undefined;
        var setter_ref: c.JSGCRef = undefined;
        var this_obj_ref: c.JSGCRef = undefined;
        var val_mut = val;
        var setter_mut = setter;
        var this_mut = this_obj;
        utils.pushValue(ctx, &val_ref, val_mut);
        utils.pushValue(ctx, &setter_ref, setter_mut);
        utils.pushValue(ctx, &this_obj_ref, this_mut);
        const err = utils.JS_StackCheck(ctx, 3);
        this_mut = utils.popValue(ctx, &this_obj_ref);
        setter_mut = utils.popValue(ctx, &setter_ref);
        val_mut = utils.popValue(ctx, &val_ref);
        if (err != 0)
            return c.JS_EXCEPTION;
        runtime.JS_PushArg(ctx, val_mut);
        runtime.JS_PushArg(ctx, setter_mut);
        runtime.JS_PushArg(ctx, this_mut);
        return runtime.JS_Call(ctx, 1);
    }
}

fn setPropertyProtoLookup(ctx: *c.JSContext, this_obj: c.JSValue, prop: c.JSValue, val: c.JSValue, allow_tail_call: c.JS_BOOL, p_in: *mc.JSObjectExt, is_obj: bool) c.JSValue {
    var p = p_in;
    while (true) {
        if (find_own_property(ctx, p, prop)) |pr| {
            if (vt.propType(pr) == vt.JS_PROP_GETSET)
                return setPropertyGetSet(ctx, this_obj, val, allow_tail_call, pr)
            else
                break;
        }
        const proto = p.proto;
        if (proto == c.JS_NULL)
            break;
        p = @ptrCast(@alignCast(mc.valueToPtr(proto)));
    }
    if (!is_obj)
        return JS_ThrowTypeErrorNotAnObject(ctx);
    return JS_DefinePropertyInternal(ctx, this_obj, prop, val, c.JS_UNDEFINED, vt.JS_DEF_PROP_HAS_VALUE);
}

fn setPropertyOwnAndProto(ctx: *c.JSContext, this_obj: c.JSValue, prop: c.JSValue, val: c.JSValue, allow_tail_call: c.JS_BOOL, p_in: *mc.JSObjectExt, is_obj: bool) c.JSValue {
    var p = p_in;
    var this_mut = this_obj;
    var prop_mut = prop;
    var val_mut = val;
    while (true) {
        if (find_own_property(ctx, p, prop_mut)) |pr| {
            const ptype = vt.propType(pr);
            if (ptype == vt.JS_PROP_NORMAL) {
                if (vt.jsIsRomPtr(ctx, pr)) {
                    var this_obj_ref: c.JSGCRef = undefined;
                    var prop_ref: c.JSGCRef = undefined;
                    var val_ref: c.JSGCRef = undefined;
                    utils.pushValue(ctx, &this_obj_ref, this_mut);
                    utils.pushValue(ctx, &prop_ref, prop_mut);
                    utils.pushValue(ctx, &val_ref, val_mut);
                    const err = js_update_props(ctx, this_mut);
                    val_mut = utils.popValue(ctx, &val_ref);
                    prop_mut = utils.popValue(ctx, &prop_ref);
                    this_mut = utils.popValue(ctx, &this_obj_ref);
                    if (err != 0)
                        return c.JS_EXCEPTION;
                    p = @ptrCast(@alignCast(mc.valueToPtr(this_mut)));
                    continue;
                }
                pr.value = val_mut;
                return c.JS_UNDEFINED;
            } else if (ptype == vt.JS_PROP_VARREF) {
                const pv: *vt.JSVarRefExt = @ptrCast(@alignCast(mc.valueToPtr(pr.value)));
                pv.u.value = val_mut;
                return c.JS_UNDEFINED;
            } else if (ptype == vt.JS_PROP_SPECIAL) {
                var this_obj_ref: c.JSGCRef = undefined;
                var prop_ref: c.JSGCRef = undefined;
                var val_ref: c.JSGCRef = undefined;
                utils.pushValue(ctx, &this_obj_ref, this_mut);
                utils.pushValue(ctx, &prop_ref, prop_mut);
                utils.pushValue(ctx, &val_ref, val_mut);
                const err = js_update_props(ctx, this_mut);
                val_mut = utils.popValue(ctx, &val_ref);
                prop_mut = utils.popValue(ctx, &prop_ref);
                this_mut = utils.popValue(ctx, &this_obj_ref);
                if (err != 0)
                    return c.JS_EXCEPTION;
                p = @ptrCast(@alignCast(mc.valueToPtr(this_mut)));
                continue;
            } else {
                return setPropertyGetSet(ctx, this_mut, val_mut, allow_tail_call, pr);
            }
        }
        break;
    }
    return setPropertyProtoLookup(ctx, this_mut, prop_mut, val_mut, allow_tail_call, p, is_obj);
}

pub fn JS_SetPropertyStr(ctx: *c.JSContext, this_obj: c.JSValue, str: [*:0]const u8, val: c.JSValue) c.JSValue {
    var this_obj_ref: c.JSGCRef = undefined;
    var val_ref: c.JSGCRef = undefined;
    var this_mut = this_obj;
    var val_mut = val;
    utils.pushValue(ctx, &this_obj_ref, this_mut);
    utils.pushValue(ctx, &val_ref, val_mut);
    var prop = JS_NewString(ctx, str);
    if (!vt.isExactException(prop))
        prop = runtime.JS_ToPropertyKey(ctx, prop);
    val_mut = utils.popValue(ctx, &val_ref);
    this_mut = utils.popValue(ctx, &this_obj_ref);
    if (vt.isExactException(prop))
        return prop;
    return JS_SetPropertyInternal(ctx, this_mut, prop, val_mut, c.FALSE);
}

pub fn JS_SetPropertyUint32(ctx: *c.JSContext, this_obj: c.JSValue, idx: u32, val: c.JSValue) c.JSValue {
    if (idx > @as(u32, @intCast(vt.JS_SHORTINT_MAX)))
        return utils.JS_ThrowError(ctx, c.JS_CLASS_RANGE_ERROR, "invalid array index");
    return JS_SetPropertyInternal(ctx, this_obj, JS_NewShortInt(@intCast(idx)), val, c.FALSE);
}

pub fn JS_DeleteProperty(ctx: *c.JSContext, this_obj: c.JSValue, prop_in: c.JSValue) c.JSValue {
    var this_obj_ref: c.JSGCRef = undefined;
    var this_mut = this_obj;
    utils.pushValue(ctx, &this_obj_ref, this_mut);
    const prop = runtime.JS_ToPropertyKey(ctx, prop_in);
    this_mut = utils.popValue(ctx, &this_obj_ref);
    if (vt.isExactException(prop))
        return prop;
    if (!mc.isPtr(this_mut))
        return c.JS_TRUE;
    var p: *mc.JSObjectExt = @ptrCast(@alignCast(mc.valueToPtr(this_mut)));
    if (mc.mbGetMtag(p) != mc.JS_MTAG_OBJECT)
        return c.JS_TRUE;

    var arr: *vt.JSValueArrayExt = @ptrCast(@alignCast(mc.valueToPtr(p.props)));
    var items = vt.valueArrayItems(arr);
    const hash_mask = vt.valueGetInt(items[1]);
    const h = vt.hashProp(prop) & @as(u32, @intCast(hash_mask));
    var idx = vt.valueGetInt(items[2 + h]);
    var last_idx: c_int = -1;
    while (idx != 0) {
        var pr: *vt.JSPropertyExt = @ptrCast(@alignCast(&items[@intCast(idx)]));
        if (pr.key == prop) {
            if (vt.jsIsRomPtr(ctx, arr)) {
                utils.pushValue(ctx, &this_obj_ref, this_mut);
                const ret = js_update_props(ctx, this_mut);
                this_mut = utils.popValue(ctx, &this_obj_ref);
                if (ret != 0)
                    return c.JS_EXCEPTION;
                p = @ptrCast(@alignCast(mc.valueToPtr(this_mut)));
                arr = @ptrCast(@alignCast(mc.valueToPtr(p.props)));
                items = vt.valueArrayItems(arr);
                pr = @ptrCast(@alignCast(&items[@intCast(idx)]));
            }
            if (last_idx >= 0) {
                const lpr: *vt.JSPropertyExt = @ptrCast(@alignCast(&items[@intCast(last_idx)]));
                vt.propSetHashNext(lpr, vt.propHashNext(pr));
            } else {
                items[2 + h] = vt.propHashNext(pr);
            }
            var first_free = get_first_free(arr);
            const prop_count = vt.valueGetInt(items[0]);
            items[0] = JS_NewShortInt(prop_count - 1);
            vt.propSetType(pr, vt.JS_PROP_NORMAL);
            pr.key = c.JS_UNINITIALIZED;
            pr.value = c.JS_UNDEFINED;

            while (first_free > 2 + hash_mask + 1) {
                const pr1: *vt.JSPropertyExt = @ptrCast(@alignCast(&items[@intCast(first_free - 3)]));
                if (pr1.key != c.JS_UNINITIALIZED)
                    break;
                first_free -= 3;
            }
            if (first_free < vt.valueArraySize(arr)) {
                const pr1: *vt.JSPropertyExt = @ptrCast(@alignCast(&items[@intCast(vt.valueArraySize(arr) - 3)]));
                vt.propSetHashNext(pr1, @intCast(first_free << 1));
            }
            if ((2 + hash_mask + 1 + 3 * prop_count) < @divTrunc(vt.valueArraySize(arr), 2))
                js_compact_props(ctx, p);
            return c.JS_TRUE;
        }
        last_idx = idx;
        idx = @intCast(vt.propHashNext(pr) >> 1);
    }
    return c.JS_TRUE;
}

pub fn stdlib_init_class(ctx: *c.JSContext, class_def: *const vt.JSROMClassExt) c.JSValue {
    const x = mc.ctxExt(ctx);
    const ctor_idx = class_def.ctor_idx;
    var obj: c.JSValue = undefined;
    var p: *mc.JSObjectExt = undefined;
    if (ctor_idx >= 0) {
        const class_id: c_int = vt.cFunctionTable(x)[@intCast(ctor_idx)].magic;
        obj = vt.classObj(x, class_id).*;
        if (!mc.isNull(obj))
            return obj;

        var parent_class: c.JSValue = undefined;
        var parent_proto: c.JSValue = undefined;
        if (!mc.isNull(class_def.parent_class)) {
            const parent_class_def: *vt.JSROMClassExt = @ptrCast(@alignCast(mc.valueToPtr(class_def.parent_class)));
            parent_class = stdlib_init_class(ctx, parent_class_def);
            const parent_class_id: c_int = vt.cFunctionTable(x)[@intCast(parent_class_def.ctor_idx)].magic;
            parent_proto = vt.classProto(x, parent_class_id).*;
        } else {
            parent_class = c.JS_NULL;
            parent_proto = vt.classProto(x, c.JS_CLASS_OBJECT).*;
        }
        var proto = vt.classProto(x, class_id).*;
        if (mc.isNull(proto)) {
            var parent_class_ref: c.JSGCRef = undefined;
            utils.pushValue(ctx, &parent_class_ref, parent_class);
            proto = JS_NewObjectProtoClass(ctx, parent_proto, c.JS_CLASS_OBJECT, 0);
            parent_class = utils.popValue(ctx, &parent_class_ref);
            vt.classProto(x, class_id).* = proto;
        }
        p = @ptrCast(@alignCast(mc.valueToPtr(proto)));
        if (!mc.isNull(class_def.proto_props))
            p.props = class_def.proto_props;

        if (mc.isNull(parent_class))
            parent_class = vt.classProto(x, c.JS_CLASS_CLOSURE).*;
        obj = runtime.js_new_c_function_proto(ctx, ctor_idx, parent_class, c.FALSE, c.JS_NULL);
        vt.classObj(x, class_id).* = obj;
    } else {
        obj = JS_NewObject(ctx);
    }
    p = @ptrCast(@alignCast(mc.valueToPtr(obj)));
    if (!mc.isNull(class_def.props))
        p.props = class_def.props;
    return obj;
}

pub fn stdlib_init(ctx: *c.JSContext, arr: *const vt.JSValueArrayExt) void {
    const items = vt.valueArrayItems(arr);
    var i: c_int = 0;
    while (i < vt.valueArraySize(arr)) : (i += 2) {
        const name = items[@intCast(i)];
        var val = items[@intCast(i + 1)];
        if (JS_IsObject(ctx, val) != 0) {
            val = stdlib_init_class(ctx, @ptrCast(@alignCast(mc.valueToPtr(val))));
        } else if (val == c.JS_NULL) {
            val = mc.ctxExt(ctx).global_obj;
        }
        _ = JS_DefinePropertyInternal(ctx, mc.ctxExt(ctx).global_obj, name, val, c.JS_NULL, vt.JS_DEF_PROP_HAS_VALUE);
    }
}
