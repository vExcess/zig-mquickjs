//
// Micro QuickJS engine builtins — String (internal submodule)
//
// Copyright (c) 2017-2025 Fabrice Bellard
// Copyright (c) 2017-2025 Charlie Gordon
//
// Ported from C to Zig by Composer 2.5 + Grok 4.6 + Gemini 3 Pro + VExcess
//

const std = @import("std");
const utils = @import("mquickjs_utils_lib.zig");
const bt = @import("mquickjs_builtins_types.zig");
const rt = bt.rt;
const vt = bt.vt;
const mc = bt.mc;
pub const c = bt.c;

const value = @import("mquickjs_value_lib.zig");
const runtime = @import("mquickjs_runtime_lib.zig");
const regexp = @import("mquickjs_builtins_regexp_lib.zig");

fn throwTypeError(ctx: *c.JSContext, msg: [*:0]const u8) c.JSValue {
    return utils.JS_ThrowError(ctx, c.JS_CLASS_TYPE_ERROR, msg);
}

fn throwRangeError(ctx: *c.JSContext, msg: [*:0]const u8) c.JSValue {
    return utils.JS_ThrowError(ctx, c.JS_CLASS_RANGE_ERROR, msg);
}

fn objPtr(val: c.JSValue) *mc.JSObjectExt {
    return @ptrCast(@alignCast(mc.valueToPtr(val)));
}

fn valueArr(val: c.JSValue) *vt.JSValueArrayExt {
    return @ptrCast(@alignCast(mc.valueToPtr(val)));
}

fn byteArr(val: c.JSValue) *vt.JSByteArrayExt {
    return @ptrCast(@alignCast(mc.valueToPtr(val)));
}

fn minInt(a: c_int, b: c_int) c_int {
    return if (a < b) a else b;
}

fn maxInt(a: c_int, b: c_int) c_int {
    return if (a > b) a else b;
}

fn unicode_is_space_ascii(ch: u32) bool {
    return (ch >= 0x0009 and ch <= 0x000D) or (ch == 0x0020);
}

fn unicode_is_space_non_ascii(ch: u32) bool {
    return ch == 0x00A0 or
        ch == 0x1680 or
        (ch >= 0x2000 and ch <= 0x200A) or
        (ch >= 0x2028 and ch <= 0x2029) or
        ch == 0x202F or
        ch == 0x205F or
        ch == 0x3000 or
        ch == 0xFEFF;
}

fn unicode_is_space(ch: u32) bool {
    if (ch < 128) return unicode_is_space_ascii(ch);
    return unicode_is_space_non_ascii(ch);
}

pub fn js_string_get_length(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    _ = argc;
    _ = argv;
    if (value.JS_IsString(ctx, this_val.*) == 0)
        return throwTypeError(ctx, "not a string");
    return vt.newShortInt(value.js_string_len(ctx, this_val.*));
}

pub fn js_string_set_length(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    _ = ctx;
    _ = this_val;
    _ = argc;
    _ = argv;
    return c.JS_UNDEFINED;
}

pub fn js_string_slice(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    _ = argc;
    this_val.* = value.JS_ToStringCheckObject(ctx, this_val.*);
    if (vt.isExactException(this_val.*))
        return c.JS_EXCEPTION;
    const len = value.js_string_len(ctx, this_val.*);
    var start: c_int = undefined;
    if (runtime.JS_ToInt32Clamp(ctx, &start, argv[0], 0, len, len) != 0)
        return c.JS_EXCEPTION;
    var end = len;
    if (!vt.isUndefined(argv[1])) {
        if (runtime.JS_ToInt32Clamp(ctx, &end, argv[1], 0, len, len) != 0)
            return c.JS_EXCEPTION;
    }
    return value.js_sub_string(ctx, this_val.*, start, maxInt(end, start));
}

pub fn js_string_substring(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    _ = argc;
    this_val.* = value.JS_ToStringCheckObject(ctx, this_val.*);
    if (vt.isExactException(this_val.*))
        return c.JS_EXCEPTION;
    const len = value.js_string_len(ctx, this_val.*);
    var a: c_int = undefined;
    if (runtime.JS_ToInt32Clamp(ctx, &a, argv[0], 0, len, 0) != 0)
        return c.JS_EXCEPTION;
    var b = len;
    if (!vt.isUndefined(argv[1])) {
        if (runtime.JS_ToInt32Clamp(ctx, &b, argv[1], 0, len, 0) != 0)
            return c.JS_EXCEPTION;
    }
    const start = if (a < b) a else b;
    const end = if (a < b) b else a;
    return value.js_sub_string(ctx, this_val.*, start, end);
}

pub fn js_string_charAt(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue, magic: c_int) c.JSValue {
    _ = argc;
    this_val.* = value.JS_ToStringCheckObject(ctx, this_val.*);
    if (vt.isExactException(this_val.*))
        return c.JS_EXCEPTION;
    var idx: c_int = undefined;
    if (runtime.JS_ToInt32Sat(ctx, &idx, argv[0]) != 0)
        return c.JS_EXCEPTION;
    if (idx < 0)
        return charAtUndef(ctx, magic);
    const cp = value.string_getcp(ctx, this_val.*, @intCast(idx), @intFromBool(magic == bt.magic_codePointAt));
    if (cp == -1)
        return charAtUndef(ctx, magic);
    if (magic == bt.magic_charCodeAt or magic == bt.magic_codePointAt)
        return vt.newShortInt(cp);
    return value.JS_NewStringChar(@intCast(cp));
}

fn charAtUndef(ctx: *c.JSContext, magic: c_int) c.JSValue {
    if (magic == bt.magic_charCodeAt)
        return value.JS_NewFloat64(ctx, std.math.nan(f64));
    if (magic == bt.magic_charAt)
        return utils.js_get_atom(ctx, c.JS_ATOM_empty);
    return c.JS_UNDEFINED;
}

pub fn js_string_constructor(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    _ = this_val;
    if (argc & c.FRAME_CF_CTOR != 0)
        return throwTypeError(ctx, "string constructor not supported");
    if (argc <= 0)
        return utils.js_get_atom(ctx, c.JS_ATOM_empty);
    return runtime.JS_ToString(ctx, argv[0]);
}

pub fn js_string_fromCharCode(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue, is_fromCodePoint: c_int) c.JSValue {
    _ = this_val;
    var b: vt.StringBuffer = undefined;
    _ = value.string_buffer_push(ctx, @ptrCast(&b), 0);
    var i: c_int = 0;
    while (i < argc) : (i += 1) {
        var ch: c_int = undefined;
        if (runtime.JS_ToInt32(ctx, &ch, argv[@intCast(i)]) != 0) {
            _ = value.string_buffer_pop(ctx, @ptrCast(&b));
            return c.JS_EXCEPTION;
        }
        if (is_fromCodePoint != 0) {
            if (ch < 0 or ch > 0x10ffff) {
                _ = throwRangeError(ctx, "invalid code point");
                _ = value.string_buffer_pop(ctx, @ptrCast(&b));
                return c.JS_EXCEPTION;
            }
        } else {
            ch &= 0xffff;
        }
        if (value.string_buffer_putc(ctx, @ptrCast(&b), ch) != 0)
            break;
    }
    return value.string_buffer_pop(ctx, @ptrCast(&b));
}

pub fn js_string_concat(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    const r = value.JS_ToStringCheckObject(ctx, this_val.*);
    if (vt.isExactException(r))
        return c.JS_EXCEPTION;
    var b: vt.StringBuffer = undefined;
    _ = value.string_buffer_push(ctx, @ptrCast(&b), 0);
    if (value.string_buffer_concat(ctx, @ptrCast(&b), r) != 0)
        return value.string_buffer_pop(ctx, @ptrCast(&b));
    var i: c_int = 0;
    while (i < argc) : (i += 1) {
        if (value.string_buffer_concat(ctx, @ptrCast(&b), argv[@intCast(i)]) != 0)
            break;
    }
    return value.string_buffer_pop(ctx, @ptrCast(&b));
}

pub fn js_string_indexOf(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue, lastIndexOf: c_int) c.JSValue {
    this_val.* = value.JS_ToStringCheckObject(ctx, this_val.*);
    if (vt.isExactException(this_val.*))
        return c.JS_EXCEPTION;
    argv[0] = runtime.JS_ToString(ctx, argv[0]);
    if (vt.isExactException(argv[0]))
        return c.JS_EXCEPTION;
    const len = value.js_string_len(ctx, this_val.*);
    const v_len = value.js_string_len(ctx, argv[0]);
    var pos: c_int = undefined;
    var start: c_int = undefined;
    var stop: c_int = undefined;
    var inc: c_int = undefined;
    if (lastIndexOf != 0) {
        pos = len - v_len;
        if (argc > 1) {
            var d: f64 = undefined;
            if (runtime.JS_ToNumber(ctx, &d, argv[1]) != 0)
                return c.JS_EXCEPTION;
            if (!std.math.isNan(d)) {
                if (d <= 0) {
                    pos = 0;
                } else if (d < @as(f64, @floatFromInt(pos))) {
                    pos = @intFromFloat(d);
                }
            }
        }
        start = pos;
        stop = 0;
        inc = -1;
    } else {
        pos = 0;
        if (argc > 1) {
            if (runtime.JS_ToInt32Clamp(ctx, &pos, argv[1], 0, len, 0) != 0)
                return c.JS_EXCEPTION;
        }
        start = pos;
        stop = len - v_len;
        inc = 1;
    }
    var ret: c_int = -1;
    if (len >= v_len and inc * (stop - start) >= 0) {
        var i = start;
        while (true) : (i += inc) {
            var j: c_int = 0;
            var matched = true;
            while (j < v_len) : (j += 1) {
                if (value.string_getc(ctx, this_val.*, @intCast(i + j)) != value.string_getc(ctx, argv[0], @intCast(j))) {
                    matched = false;
                    break;
                }
            }
            if (matched) {
                ret = i;
                break;
            }
            if (i == stop)
                break;
        }
    }
    return vt.newShortInt(ret);
}

pub fn js_string_indexof(ctx: *c.JSContext, str: c.JSValue, needle: c.JSValue, start: c_int, str_len: c_int, needle_len: c_int) c_int {
    var i = start;
    while (i <= str_len - needle_len) : (i += 1) {
        var j: c_int = 0;
        var matched = true;
        while (j < needle_len) : (j += 1) {
            if (value.string_getc(ctx, str, @intCast(i + j)) != value.string_getc(ctx, needle, @intCast(j))) {
                matched = false;
                break;
            }
        }
        if (matched)
            return i;
    }
    return -1;
}

pub fn js_string_toLowerCase(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue, to_lower: c_int) c.JSValue {
    _ = argc;
    _ = argv;
    this_val.* = value.JS_ToStringCheckObject(ctx, this_val.*);
    if (vt.isExactException(this_val.*))
        return this_val.*;
    const len = value.js_string_len(ctx, this_val.*);
    var b: vt.StringBuffer = undefined;
    if (value.string_buffer_push(ctx, @ptrCast(&b), len) != 0)
        return c.JS_EXCEPTION;
    var i: c_int = 0;
    while (i < len) : (i += 1) {
        var ch = value.string_getc(ctx, this_val.*, @intCast(i));
        if (to_lower != 0) {
            if (ch >= 'A' and ch <= 'Z')
                ch += 'a' - 'A';
        } else {
            if (ch >= 'a' and ch <= 'z')
                ch += 'A' - 'a';
        }
        _ = value.string_buffer_putc(ctx, @ptrCast(&b), ch);
    }
    return value.string_buffer_pop(ctx, @ptrCast(&b));
}

pub fn js_string_trim(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue, magic: c_int) c.JSValue {
    _ = argc;
    _ = argv;
    this_val.* = value.JS_ToStringCheckObject(ctx, this_val.*);
    if (vt.isExactException(this_val.*))
        return this_val.*;
    const len = value.js_string_len(ctx, this_val.*);
    var a: c_int = 0;
    var b = len;
    if (magic & 1 != 0) {
        while (a < len and unicode_is_space(@intCast(value.string_getc(ctx, this_val.*, @intCast(a)))))
            a += 1;
    }
    if (magic & 2 != 0) {
        while (b > a and unicode_is_space(@intCast(value.string_getc(ctx, this_val.*, @intCast(b - 1)))))
            b -= 1;
    }
    return value.js_sub_string(ctx, this_val.*, a, b);
}

pub fn js_string_toString(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    _ = argc;
    _ = argv;
    if (value.JS_IsString(ctx, this_val.*) == 0)
        return throwTypeError(ctx, "not a string");
    return this_val.*;
}

pub fn js_string_repeat(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    _ = argc;
    if (value.JS_IsString(ctx, this_val.*) == 0)
        return throwTypeError(ctx, "not a string");
    var n: c_int = undefined;
    if (runtime.JS_ToInt32Sat(ctx, &n, argv[0]) != 0)
        return @as(c.JSValue, @bitCast(@as(isize, -1)));
    var buf: vt.JSStringCharBufExt = undefined;
    const p: *vt.JSStringExt = @ptrCast(@alignCast(value.get_string_ptr(ctx, @ptrCast(&buf), this_val.*)));
    const plen: i64 = @intCast(vt.stringLen(p));
    const len: i64 = @as(i64, n) * plen;
    if (n < 0 or len > vt.JS_STRING_LEN_MAX)
        return throwRangeError(ctx, "invalid repeat count");
    if (vt.stringLen(p) == 0 or n == 1)
        return this_val.*;
    var b: vt.StringBuffer = undefined;
    if (value.string_buffer_push(ctx, @ptrCast(&b), @intCast(len)) != 0)
        return c.JS_EXCEPTION;
    while (n > 0) {
        n -= 1;
        _ = value.string_buffer_concat_str(ctx, @ptrCast(&b), this_val.*);
    }
    return value.string_buffer_pop(ctx, @ptrCast(&b));
}
fn js_string_concat_subst(ctx: *c.JSContext, b: *anyopaque, str: *c.JSValue, rep: *c.JSValue, pos: u32, end_of_match: u32, capture_buf: ?*c.JSValue, captures_len: u32, needle: ?*c.JSValue) c_int {
    const sb: *vt.StringBuffer = @ptrCast(@alignCast(b));
    if (value.JS_IsFunction(ctx, rep.*) != 0) {
        if (utils.JS_StackCheck(ctx, 4 + captures_len) != 0)
            return -1;
        runtime.JS_PushArg(ctx, str.*);
        runtime.JS_PushArg(ctx, vt.newShortInt(@intCast(pos)));
        if (capture_buf) |cb| {
            var k: c_int = @intCast(captures_len - 1);
            while (k >= 0) : (k -= 1) {
                const captures: [*]u32 = @ptrCast(@alignCast(vt.byteArrayBuf(byteArr(cb.*))));
                var val: c.JSValue = undefined;
                if (captures[@intCast(2 * k)] != @as(u32, @bitCast(@as(i32, -1))) and
                    captures[@intCast(2 * k + 1)] != @as(u32, @bitCast(@as(i32, -1))))
                {
                    val = value.js_sub_string_utf8(ctx, str.*, captures[@intCast(2 * k)] * 2, captures[@intCast(2 * k + 1)] * 2);
                    if (vt.isExactException(val))
                        return -1;
                    var val_ref: c.JSGCRef = undefined;
                    utils.pushValue(ctx, &val_ref, val);
                    const ret = utils.JS_StackCheck(ctx, @intCast(3 + k));
                    val = utils.popValue(ctx, &val_ref);
                    if (ret != 0)
                        return -1;
                } else {
                    val = c.JS_UNDEFINED;
                }
                runtime.JS_PushArg(ctx, val);
            }
        } else {
            runtime.JS_PushArg(ctx, needle.?.*);
        }
        runtime.JS_PushArg(ctx, rep.*);
        runtime.JS_PushArg(ctx, c.JS_UNDEFINED);
        const res = runtime.JS_Call(ctx, @intCast(2 + captures_len));
        if (vt.isExactException(res))
            return -1;
        return value.string_buffer_concat(ctx, sb, res);
    }

    var buf_rep: vt.JSStringCharBufExt = undefined;
    var pstr: *vt.JSStringExt = @ptrCast(@alignCast(value.get_string_ptr(ctx, @ptrCast(&buf_rep), rep.*)));
    const rep_len: c_int = @intCast(vt.stringLen(pstr));
    var i: c_int = 0;
    while (true) {
        pstr = @ptrCast(@alignCast(value.get_string_ptr(ctx, @ptrCast(&buf_rep), rep.*)));
        var j = i;
        while (j < rep_len and vt.stringBuf(pstr)[@intCast(j)] != '$')
            j += 1;
        if (j + 1 >= rep_len)
            break;
        const j0 = j;
        j += 1;
        var ch: c_int = vt.stringBuf(pstr)[@intCast(j)];
        j += 1;
        _ = value.string_buffer_concat_utf8(ctx, sb, rep.*, @intCast(2 * i), @intCast(2 * j0));
        if (ch == '$') {
            _ = value.string_buffer_putc(ctx, sb, '$');
        } else if (ch == '&') {
            if (capture_buf != null) {
                _ = value.string_buffer_concat_utf16(ctx, sb, str.*, pos, end_of_match);
            } else {
                _ = value.string_buffer_concat_str(ctx, sb, needle.?.*);
            }
        } else if (ch == '`') {
            _ = value.string_buffer_concat_utf16(ctx, sb, str.*, 0, pos);
        } else if (ch == '\'') {
            _ = value.string_buffer_concat_utf16(ctx, sb, str.*, end_of_match, @intCast(value.js_string_len(ctx, str.*)));
        } else if (ch >= '0' and ch <= '9') {
            var k: c_int = ch - '0';
            if (j < rep_len) {
                ch = vt.stringBuf(pstr)[@intCast(j)];
                if (ch >= '0' and ch <= '9') {
                    k = k * 10 + ch - '0';
                    j += 1;
                }
            }
            if (k >= 1 and k < @as(c_int, @intCast(captures_len))) {
                const captures: [*]u32 = @ptrCast(@alignCast(vt.byteArrayBuf(byteArr(capture_buf.?.*))));
                if (captures[@intCast(2 * k)] != @as(u32, @bitCast(@as(i32, -1))) and
                    captures[@intCast(2 * k + 1)] != @as(u32, @bitCast(@as(i32, -1))))
                {
                    _ = value.string_buffer_concat_utf8(ctx, sb, str.*, captures[@intCast(2 * k)] * 2, captures[@intCast(2 * k + 1)] * 2);
                }
            } else {
                _ = value.string_buffer_concat_utf8(ctx, sb, rep.*, @intCast(2 * j0), @intCast(2 * j));
            }
        } else {
            _ = value.string_buffer_concat_utf8(ctx, sb, rep.*, @intCast(2 * j0), @intCast(2 * j));
        }
        i = j;
    }
    return value.string_buffer_concat_utf8(ctx, sb, rep.*, @intCast(2 * i), @intCast(2 * rep_len));
}

pub fn js_string_replace(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue, is_replaceAll: c_int) c.JSValue {
    _ = argc;
    var b: vt.StringBuffer = undefined;

    this_val.* = runtime.JS_ToString(ctx, this_val.*);
    if (vt.isExactException(this_val.*))
        return c.JS_EXCEPTION;
    const is_regexp = value.JS_GetClassID(ctx, argv[0]) == c.JS_CLASS_REGEXP;
    if (!is_regexp) {
        argv[0] = runtime.JS_ToString(ctx, argv[0]);
        if (vt.isExactException(argv[0]))
            return c.JS_EXCEPTION;
    }
    if (value.JS_IsFunction(ctx, argv[1]) == 0) {
        argv[1] = runtime.JS_ToString(ctx, argv[1]);
        if (vt.isExactException(argv[1]))
            return c.JS_EXCEPTION;
    }
    const input_len = value.js_string_len(ctx, this_val.*);
    var endOfLastMatch: c_int = 0;

    _ = value.string_buffer_push(ctx, @ptrCast(&b), 0);

    if (is_regexp) {
        var p = objPtr(argv[0]);
        const bc_arr = byteArr(rt.objectRegexp(p).byte_code);
        const re_flags = regexp.lre_get_flags(vt.byteArrayBuf(bc_arr));
        const capture_count = regexp.lre_get_capture_count(vt.byteArrayBuf(bc_arr));

        if (re_flags & bt.LRE_FLAG_GLOBAL != 0)
            rt.objectRegexp(p).last_index = 0;

        var last_index: c_int = if ((re_flags & (bt.LRE_FLAG_GLOBAL | bt.LRE_FLAG_STICKY)) == 0)
            0
        else
            maxInt(rt.objectRegexp(p).last_index, 0);

        const carr0 = value.js_alloc_byte_array(ctx, @as(c_int, @intCast(@sizeOf(u32))) * regexp.lre_get_alloc_count(vt.byteArrayBuf(bc_arr)));
        const carr: *vt.JSByteArrayExt = @ptrCast(@alignCast(carr0 orelse {
            _ = value.string_buffer_pop(ctx, @ptrCast(&b));
            return c.JS_EXCEPTION;
        }));
        var capture_buf_ref: c.JSGCRef = undefined;
        const capture_buf = utils.JS_PushGCRef(ctx, &capture_buf_ref);
        capture_buf.* = mc.valueFromPtr(carr);
        var capture: [*]u32 = @ptrCast(@alignCast(vt.byteArrayBuf(carr)));
        var i: c_int = 0;
        while (i < 2 * capture_count) : (i += 1) {
            capture[@intCast(i)] = @bitCast(@as(i32, -1));
        }

        while (true) {
            const ret: c_int = if (last_index > input_len)
                0
            else blk: {
                var str_buf: vt.JSStringCharBufExt = undefined;
                p = objPtr(argv[0]);
                const str: *vt.JSStringExt = @ptrCast(@alignCast(value.get_string_ptr(ctx, @ptrCast(&str_buf), this_val.*)));
                break :blk regexp.lre_exec(ctx, capture_buf.*, rt.objectRegexp(p).byte_code, mc.valueFromPtr(str), @intCast(value.js_string_utf16_to_utf8_pos(ctx, this_val.*, @intCast(last_index)) / 2));
            };
            if (ret < 0) {
                _ = utils.popValue(ctx, &capture_buf_ref);
                _ = value.string_buffer_pop(ctx, @ptrCast(&b));
                return c.JS_EXCEPTION;
            }
            if (ret == 0) {
                if (re_flags & (bt.LRE_FLAG_GLOBAL | bt.LRE_FLAG_STICKY) != 0) {
                    p = objPtr(argv[0]);
                    rt.objectRegexp(p).last_index = 0;
                }
                break;
            }
            capture = @ptrCast(@alignCast(vt.byteArrayBuf(byteArr(capture_buf.*))));
            const start: c_int = @intCast(value.js_string_utf8_to_utf16_pos(ctx, this_val.*, capture[0] * 2));
            var end: c_int = @intCast(value.js_string_utf8_to_utf16_pos(ctx, this_val.*, capture[1] * 2));
            _ = value.string_buffer_concat_utf16(ctx, @ptrCast(&b), this_val.*, @intCast(endOfLastMatch), @intCast(start));
            _ = js_string_concat_subst(ctx, @ptrCast(&b), this_val, &argv[1], @intCast(start), @intCast(end), capture_buf, @intCast(capture_count), null);
            endOfLastMatch = end;
            if ((re_flags & bt.LRE_FLAG_GLOBAL) == 0) {
                if (re_flags & bt.LRE_FLAG_STICKY != 0) {
                    p = objPtr(argv[0]);
                    rt.objectRegexp(p).last_index = end;
                }
                break;
            }
            if (end == start) {
                const cp = value.string_getcp(ctx, this_val.*, @intCast(end), c.TRUE);
                end += 1 + @as(c_int, @intFromBool(cp >= 0x10000));
            }
            last_index = end;
        }
        _ = utils.popValue(ctx, &capture_buf_ref);
    } else {
        const needle_len = value.js_string_len(ctx, argv[0]);
        var is_first = true;
        while (true) {
            const pos: c_int = if (needle_len == 0) blk: {
                @branchHint(.unlikely);
                if (is_first)
                    break :blk 0
                else if (endOfLastMatch >= input_len)
                    break :blk -1
                else
                    break :blk endOfLastMatch + 1;
            } else js_string_indexof(ctx, this_val.*, argv[0], endOfLastMatch, input_len, needle_len);
            if (pos < 0) {
                if (is_first) {
                    _ = value.string_buffer_pop(ctx, @ptrCast(&b));
                    return this_val.*;
                } else {
                    break;
                }
            }
            _ = value.string_buffer_concat_utf16(ctx, @ptrCast(&b), this_val.*, @intCast(endOfLastMatch), @intCast(pos));
            _ = js_string_concat_subst(ctx, @ptrCast(&b), this_val, &argv[1], @intCast(pos), @intCast(pos + needle_len), null, 1, &argv[0]);
            endOfLastMatch = pos + needle_len;
            is_first = false;
            if (is_replaceAll == 0)
                break;
        }
    }
    _ = value.string_buffer_concat_utf16(ctx, @ptrCast(&b), this_val.*, @intCast(endOfLastMatch), @intCast(input_len));
    return value.string_buffer_pop(ctx, @ptrCast(&b));
}

pub fn js_string_split(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    _ = argc;
    this_val.* = runtime.JS_ToString(ctx, this_val.*);
    if (vt.isExactException(this_val.*))
        return c.JS_EXCEPTION;
    var lim: u32 = undefined;
    if (vt.isUndefined(argv[1])) {
        lim = 0xffffffff;
    } else {
        if (runtime.JS_ToUint32(ctx, &lim, argv[1]) < 0)
            return c.JS_EXCEPTION;
    }
    const is_regexp = value.JS_GetClassID(ctx, argv[0]) == c.JS_CLASS_REGEXP;
    var undef_sep: bool = undefined;
    if (!is_regexp) {
        undef_sep = vt.isUndefined(argv[0]);
        argv[0] = runtime.JS_ToString(ctx, argv[0]);
        if (vt.isExactException(argv[0]))
            return c.JS_EXCEPTION;
    } else {
        undef_sep = false;
    }

    var A_ref: c.JSGCRef = undefined;
    var z_ref: c.JSGCRef = undefined;
    const A = utils.JS_PushGCRef(ctx, &A_ref);
    const z = utils.JS_PushGCRef(ctx, &z_ref);
    A.* = value.JS_NewArray(ctx, 0);
    if (vt.isExactException(A.*)) {
        _ = utils.popValue(ctx, &z_ref);
        _ = utils.popValue(ctx, &A_ref);
        return c.JS_EXCEPTION;
    }
    var lengthA: u32 = 0;
    const s_len = value.js_string_len(ctx, this_val.*);
    var p: c_int = 0;
    if (lim == 0) {
        _ = utils.popValue(ctx, &z_ref);
        return utils.popValue(ctx, &A_ref);
    }
    if (undef_sep) {
        const T = value.js_sub_string(ctx, this_val.*, p, s_len);
        if (vt.isExactException(T)) {
            _ = utils.popValue(ctx, &z_ref);
            _ = utils.popValue(ctx, &A_ref);
            return c.JS_EXCEPTION;
        }
        const ret = value.JS_SetPropertyUint32(ctx, A.*, lengthA, T);
        lengthA += 1;
        if (vt.isExactException(ret)) {
            _ = utils.popValue(ctx, &z_ref);
            _ = utils.popValue(ctx, &A_ref);
            return c.JS_EXCEPTION;
        }
        _ = utils.popValue(ctx, &z_ref);
        return utils.popValue(ctx, &A_ref);
    }

    if (is_regexp) {
        var p1 = objPtr(argv[0]);
        const bc_arr = byteArr(rt.objectRegexp(p1).byte_code);
        const re_flags = regexp.lre_get_flags(vt.byteArrayBuf(bc_arr));

        if (s_len == 0) {
            p1 = objPtr(argv[0]);
            rt.objectRegexp(p1).last_index = 0;
            z.* = regexp.js_regexp_exec(ctx, &argv[0], 1, @ptrCast(this_val), regexp.MAGIC_REGEXP_FORCE_GLOBAL);
            if (vt.isExactException(z.*)) {
                _ = utils.popValue(ctx, &z_ref);
                _ = utils.popValue(ctx, &A_ref);
                return c.JS_EXCEPTION;
            }
            if (z.* == c.JS_NULL) {
                const T = value.js_sub_string(ctx, this_val.*, p, s_len);
                if (vt.isExactException(T)) {
                    _ = utils.popValue(ctx, &z_ref);
                    _ = utils.popValue(ctx, &A_ref);
                    return c.JS_EXCEPTION;
                }
                const ret = value.JS_SetPropertyUint32(ctx, A.*, lengthA, T);
                if (vt.isExactException(ret)) {
                    _ = utils.popValue(ctx, &z_ref);
                    _ = utils.popValue(ctx, &A_ref);
                    return c.JS_EXCEPTION;
                }
            }
            _ = utils.popValue(ctx, &z_ref);
            return utils.popValue(ctx, &A_ref);
        }
        var q: c_int = 0;
        while (q < s_len) {
            p1 = objPtr(argv[0]);
            rt.objectRegexp(p1).last_index = q;
            z.* = regexp.js_regexp_exec(ctx, &argv[0], 1, @ptrCast(this_val), regexp.MAGIC_REGEXP_FORCE_GLOBAL);
            if (vt.isExactException(z.*)) {
                _ = utils.popValue(ctx, &z_ref);
                _ = utils.popValue(ctx, &A_ref);
                return c.JS_EXCEPTION;
            }
            if (z.* == c.JS_NULL) {
                if ((re_flags & bt.LRE_FLAG_STICKY) == 0) {
                    break;
                } else {
                    const cp = value.string_getcp(ctx, this_val.*, @intCast(q), c.TRUE);
                    q += 1 + @as(c_int, @intFromBool(cp >= 0x10000));
                }
            } else {
                if ((re_flags & bt.LRE_FLAG_STICKY) == 0) {
                    const res = value.JS_GetProperty(ctx, z.*, utils.js_get_atom(ctx, c.JS_ATOM_index));
                    if (vt.isExactException(res)) {
                        _ = utils.popValue(ctx, &z_ref);
                        _ = utils.popValue(ctx, &A_ref);
                        return c.JS_EXCEPTION;
                    }
                    q = vt.valueGetInt(res);
                }
                p1 = objPtr(argv[0]);
                var e = rt.objectRegexp(p1).last_index;
                if (e > s_len)
                    e = s_len;
                if (e == p) {
                    const cp = value.string_getcp(ctx, this_val.*, @intCast(q), c.TRUE);
                    q += 1 + @as(c_int, @intFromBool(cp >= 0x10000));
                } else {
                    const T = value.js_sub_string(ctx, this_val.*, p, q);
                    if (vt.isExactException(T)) {
                        _ = utils.popValue(ctx, &z_ref);
                        _ = utils.popValue(ctx, &A_ref);
                        return c.JS_EXCEPTION;
                    }
                    const ret = value.JS_SetPropertyUint32(ctx, A.*, lengthA, T);
                    lengthA += 1;
                    if (vt.isExactException(ret)) {
                        _ = utils.popValue(ctx, &z_ref);
                        _ = utils.popValue(ctx, &A_ref);
                        return c.JS_EXCEPTION;
                    }
                    if (lengthA == lim) {
                        _ = utils.popValue(ctx, &z_ref);
                        return utils.popValue(ctx, &A_ref);
                    }
                    p1 = objPtr(z.*);
                    const numberOfCaptures: c_int = @intCast(p1.u.array.len);
                    var i: c_int = 1;
                    while (i < numberOfCaptures) : (i += 1) {
                        p1 = objPtr(z.*);
                        const varr = valueArr(p1.u.array.tab);
                        const T2 = vt.valueArrayItems(varr)[@intCast(i)];
                        const ret2 = value.JS_SetPropertyUint32(ctx, A.*, lengthA, T2);
                        lengthA += 1;
                        if (vt.isExactException(ret2)) {
                            _ = utils.popValue(ctx, &z_ref);
                            _ = utils.popValue(ctx, &A_ref);
                            return c.JS_EXCEPTION;
                        }
                    }
                    p = e;
                    q = e;
                }
            }
        }
    } else {
        const r = value.js_string_len(ctx, argv[0]);
        if (s_len == 0) {
            if (r != 0) {
                const T = value.js_sub_string(ctx, this_val.*, p, s_len);
                if (vt.isExactException(T)) {
                    _ = utils.popValue(ctx, &z_ref);
                    _ = utils.popValue(ctx, &A_ref);
                    return c.JS_EXCEPTION;
                }
                const ret = value.JS_SetPropertyUint32(ctx, A.*, lengthA, T);
                if (vt.isExactException(ret)) {
                    _ = utils.popValue(ctx, &z_ref);
                    _ = utils.popValue(ctx, &A_ref);
                    return c.JS_EXCEPTION;
                }
            }
            _ = utils.popValue(ctx, &z_ref);
            return utils.popValue(ctx, &A_ref);
        }

        var q: c_int = 0;
        while (true) {
            q += @intFromBool(r == 0);
            if (q > s_len - r - @as(c_int, @intFromBool(r == 0)))
                break;
            const e = js_string_indexof(ctx, this_val.*, argv[0], q, s_len, r);
            if (e < 0)
                break;
            const T = value.js_sub_string(ctx, this_val.*, p, e);
            if (vt.isExactException(T)) {
                _ = utils.popValue(ctx, &z_ref);
                _ = utils.popValue(ctx, &A_ref);
                return c.JS_EXCEPTION;
            }
            const ret = value.JS_SetPropertyUint32(ctx, A.*, lengthA, T);
            lengthA += 1;
            if (vt.isExactException(ret)) {
                _ = utils.popValue(ctx, &z_ref);
                _ = utils.popValue(ctx, &A_ref);
                return c.JS_EXCEPTION;
            }
            if (lengthA == lim) {
                _ = utils.popValue(ctx, &z_ref);
                return utils.popValue(ctx, &A_ref);
            }
            p = e + r;
            q = p;
        }
    }

    {
        const T = value.js_sub_string(ctx, this_val.*, p, s_len);
        if (vt.isExactException(T)) {
            _ = utils.popValue(ctx, &z_ref);
            _ = utils.popValue(ctx, &A_ref);
            return c.JS_EXCEPTION;
        }
        const ret = value.JS_SetPropertyUint32(ctx, A.*, lengthA, T);
        if (vt.isExactException(ret)) {
            _ = utils.popValue(ctx, &z_ref);
            _ = utils.popValue(ctx, &A_ref);
            return c.JS_EXCEPTION;
        }
    }
    _ = utils.popValue(ctx, &z_ref);
    return utils.popValue(ctx, &A_ref);
}

pub fn js_string_match(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    _ = argc;
    var re = regexp.js_get_regexp(ctx, argv[0]) orelse return c.JS_EXCEPTION;
    const barr = byteArr(re.byte_code);
    const global = regexp.lre_get_flags(vt.byteArrayBuf(barr)) & bt.LRE_FLAG_GLOBAL;
    if (global == 0)
        return regexp.js_regexp_exec(ctx, &argv[0], 1, @ptrCast(this_val), 0);

    var p = objPtr(argv[0]);
    re = rt.objectRegexp(p);
    re.last_index = 0;

    var A_ref: c.JSGCRef = undefined;
    var result_ref: c.JSGCRef = undefined;
    const A = utils.JS_PushGCRef(ctx, &A_ref);
    const result = utils.JS_PushGCRef(ctx, &result_ref);
    A.* = c.JS_NULL;
    var n: u32 = 0;
    while (true) {
        result.* = regexp.js_regexp_exec(ctx, &argv[0], 1, @ptrCast(this_val), 0);
        if (vt.isExactException(result.*)) {
            A.* = c.JS_EXCEPTION;
            break;
        }
        if (result.* == c.JS_NULL)
            break;
        if (A.* == c.JS_NULL) {
            A.* = value.JS_NewArray(ctx, 1);
            if (vt.isExactException(A.*)) {
                A.* = c.JS_EXCEPTION;
                break;
            }
        }

        p = objPtr(result.*);
        const varr = valueArr(p.u.array.tab);
        const ret = value.JS_SetPropertyUint32(ctx, A.*, n, vt.valueArrayItems(varr)[0]);
        n += 1;
        if (vt.isExactException(ret)) {
            A.* = c.JS_EXCEPTION;
            break;
        }
    }
    _ = utils.popValue(ctx, &result_ref);
    return utils.popValue(ctx, &A_ref);
}

pub fn js_string_search(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    _ = argc;
    return regexp.js_regexp_exec(ctx, &argv[0], 1, @ptrCast(this_val), regexp.MAGIC_REGEXP_SEARCH);
}
