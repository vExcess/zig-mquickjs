//
// Micro QuickJS engine runtime — coercion and slow paths (internal submodule)
//
// Copyright (c) 2017-2025 Fabrice Bellard
// Copyright (c) 2017-2025 Charlie Gordon
//
// Ported from C to Zig by Composer 2.5 + Grok 4.6 + Gemini 3 Pro + VExcess
//

const std = @import("std");
const dtoa = @import("dtoa_lib.zig");
const utils = @import("mquickjs_utils_lib.zig");
const gc = @import("mquickjs_gc_lib.zig");
const value = @import("mquickjs_value_lib.zig");
const builtins = @import("mquickjs_builtins_lib.zig");
const rt = @import("mquickjs_runtime_types.zig");
const vt = rt.vt;
const mc = vt.mc;
pub const c = rt.c;

const OP = rt.OP;

extern fn js_lrint(x: f64) c_long;
extern fn js_fmod(x: f64, y: f64) f64;
extern fn js_pow(x: f64, y: f64) f64;

extern fn JS_PushArg(ctx: *c.JSContext, val: c.JSValue) void;
extern fn JS_Call(ctx: *c.JSContext, call_flags_in: c_int) c.JSValue;
extern fn get_var_ref(ctx: *c.JSContext, pfirst_var_ref: *c.JSValue, pval: *c.JSValue) c.JSValue;

fn jsGetShortFloat(v: c.JSValue) f64 {
    return @call(.never_inline, value.js_get_short_float, .{v});
}

fn jsNewInt32(ctx: *c.JSContext, v: i32) c.JSValue {
    return @call(.never_inline, value.JS_NewInt32, .{ctx, v});
}

fn jsNewUint32(ctx: *c.JSContext, v: u32) c.JSValue {
    return @call(.never_inline, value.JS_NewUint32, .{ctx, v});
}

fn max_int(a: c_int, b: c_int) c_int {
    return if (a > b) a else b;
}

fn throwTypeError(ctx: *c.JSContext, msg: [*:0]const u8) c.JSValue {
    return utils.JS_ThrowError(ctx, c.JS_CLASS_TYPE_ERROR, msg);
}

fn throwInternalError(ctx: *c.JSContext, msg: [*:0]const u8) c.JSValue {
    return utils.JS_ThrowError(ctx, c.JS_CLASS_INTERNAL_ERROR, msg);
}

fn c_abort() noreturn {
    std.posix.abort();
}

pub fn JS_ToPrimitive(ctx: *c.JSContext, val_in: c.JSValue, hint: c_int) c.JSValue {
    var val = val_in;
    if (value.JS_IsPrimitive(ctx, val) != 0)
        return val;
    var i: c_int = 0;
    while (i < 2) : (i += 1) {
        const atom: c_int = if ((i ^ hint) == 0) c.JS_ATOM_toString else c.JS_ATOM_valueOf;
        var val_ref: c.JSGCRef = undefined;
        utils.pushValue(ctx, &val_ref, val);
        const method = value.JS_GetProperty(ctx, val, utils.js_get_atom(ctx, atom));
        val = utils.popValue(ctx, &val_ref);
        if (vt.isExactException(method))
            return method;
        if (value.JS_IsFunction(ctx, method) != 0) {
            var method_ref: c.JSGCRef = undefined;
            utils.pushValue(ctx, &method_ref, method);
            utils.pushValue(ctx, &val_ref, val);
            const err = utils.JS_StackCheck(ctx, 2);
            val = utils.popValue(ctx, &val_ref);
            _ = utils.popValue(ctx, &method_ref);
            if (err != 0)
                return c.JS_EXCEPTION;

            JS_PushArg(ctx, method);
            JS_PushArg(ctx, val);
            utils.pushValue(ctx, &val_ref, val);
            const ret = JS_Call(ctx, 0);
            val = utils.popValue(ctx, &val_ref);
            if (vt.isExactException(ret))
                return ret;
            if (value.JS_IsObject(ctx, ret) == 0)
                return ret;
        }
    }
    return throwTypeError(ctx, "toPrimitive");
}

pub fn js_dtoa2(ctx: *c.JSContext, d: f64, radix: c_int, n_digits: c_int, flags: c_int) c.JSValue {
    const len_max = dtoa.js_dtoa_max_len(d, radix, n_digits, flags);
    const p0 = value.js_alloc_byte_array(ctx, len_max + 1) orelse return c.JS_EXCEPTION;
    var str = mc.valueFromPtr(p0);
    var str_ref: c.JSGCRef = undefined;
    utils.pushValue(ctx, &str_ref, str);
    const tmp_arr = value.js_alloc_byte_array(ctx, @sizeOf(c.JSDTOATempMem));
    str = utils.popValue(ctx, &str_ref);
    if (tmp_arr == null)
        return c.JS_EXCEPTION;
    const p: *vt.JSByteArrayExt = @ptrCast(@alignCast(mc.valueToPtr(str)));
    const len = dtoa.js_dtoa(
        @ptrCast(vt.byteArrayBuf(p)),
        d,
        radix,
        n_digits,
        flags,
        @ptrCast(@alignCast(vt.byteArrayBuf(@ptrCast(@alignCast(tmp_arr.?))))),
    );
    utils.js_free(ctx, tmp_arr);
    return value.js_byte_array_to_string(ctx, str, len, 1);
}

pub fn JS_ToString(ctx: *c.JSContext, val_in: c.JSValue) c.JSValue {
    var val = val_in;
    var buf: [128]u8 = undefined;
    redo: while (true) {
        if (mc.isInt(val)) {
            const len = dtoa.i32toa(&buf, vt.valueGetInt(val));
            buf[len] = 0;
            return value.JS_NewString(ctx, @ptrCast(&buf));
        } else if (mc.isShortFloat(val)) {
            return js_dtoa2(ctx, jsGetShortFloat(val), 10, 0, c.JS_DTOA_FORMAT_FREE);
        } else if (mc.isPtr(val)) {
            const ptr = mc.valueToPtr(val);
            const mtag = utils.js_get_mtag(ptr);
            switch (mtag) {
                mc.JS_MTAG_OBJECT => {
                    val = JS_ToPrimitive(ctx, val, rt.HINT_STRING);
                    if (vt.isExactException(val))
                        return val;
                    continue :redo;
                },
                mc.JS_MTAG_STRING => return val,
                mc.JS_MTAG_FLOAT64 => {
                    const p: *vt.JSFloat64Ext = @ptrCast(@alignCast(ptr));
                    return js_dtoa2(ctx, p.dval, 10, 0, c.JS_DTOA_FORMAT_FREE);
                },
                else => {
                    _ = utils.js_snprintf(@ptrCast(&buf), buf.len, "[mtag %d]", mtag);
                    return value.JS_NewString(ctx, @ptrCast(&buf));
                },
            }
        } else {
            switch (rt.valueGetSpecialTag(val)) {
                c.JS_TAG_NULL => return utils.js_get_atom(ctx, c.JS_ATOM_null),
                c.JS_TAG_UNDEFINED => return utils.js_get_atom(ctx, c.JS_ATOM_undefined),
                c.JS_TAG_BOOL => {
                    const atom: c_int = if (rt.valueGetSpecialValue(val) != 0) c.JS_ATOM_true else c.JS_ATOM_false;
                    return utils.js_get_atom(ctx, atom);
                },
                c.JS_TAG_STRING_CHAR => return val,
                c.JS_TAG_SHORT_FUNC => {
                    val = JS_ToPrimitive(ctx, val, rt.HINT_STRING);
                    if (vt.isExactException(val))
                        return val;
                    continue :redo;
                },
                else => return value.JS_NewString(ctx, "?"),
            }
        }
    }
}

pub fn JS_ToPropertyKey(ctx: *c.JSContext, val_in: c.JSValue) c.JSValue {
    if (mc.isInt(val_in))
        return val_in;
    const val = JS_ToString(ctx, val_in);
    if (vt.isExactException(val))
        return val;
    var n: i32 = undefined;
    if (value.is_num_string(ctx, &n, val) != 0)
        return vt.newShortInt(n)
    else
        return value.JS_MakeUniqueString(ctx, val);
}

pub fn skip_spaces(p1: [*:0]const u8) c_int {
    var p = p1;
    while (true) {
        const ch = p[0];
        if (!((ch >= 0x09 and ch <= 0x0d) or ch == 0x20))
            break;
        p += 1;
    }
    return @intCast(@intFromPtr(p) - @intFromPtr(p1));
}

pub fn js_atod1(ctx: *c.JSContext, pres: *f64, val: c.JSValue, radix: c_int, flags: c_int) c_int {
    if (rt.valueGetSpecialTag(val) == c.JS_TAG_STRING_CHAR) {
        const ch = rt.valueGetSpecialValue(val);
        if (ch >= '0' and ch <= '9') {
            pres.* = @floatFromInt(ch - '0');
        } else {
            pres.* = std.math.nan(f64);
        }
        return 0;
    }

    var val_ref: c.JSGCRef = undefined;
    var val_mut = val;
    utils.pushValue(ctx, &val_ref, val_mut);
    const tmp_arr = value.js_alloc_byte_array(ctx, @sizeOf(c.JSATODTempMem));
    val_mut = utils.popValue(ctx, &val_ref);
    if (tmp_arr == null) {
        pres.* = std.math.nan(f64);
        return -1;
    }
    const p: *vt.JSStringExt = @ptrCast(@alignCast(mc.valueToPtr(val_mut)));
    var p1: [*c]const u8 = @ptrCast(vt.stringBuf(p));
    p1 += @as(usize, @intCast(skip_spaces(@ptrCast(p1))));
    var d: f64 = undefined;
    if (@intFromPtr(p1) - @intFromPtr(vt.stringBuf(p)) == vt.stringLen(p)) {
        d = if (flags & rt.JS_ATOD_TOSTRING != 0) 0 else std.math.nan(f64);
    } else {
        d = dtoa.js_atod(p1, &p1, radix, flags, @ptrCast(@alignCast(vt.byteArrayBuf(@ptrCast(@alignCast(tmp_arr.?))))));
        utils.js_free(ctx, tmp_arr);
        if (flags & rt.JS_ATOD_TOSTRING != 0) {
            p1 += @as(usize, @intCast(skip_spaces(@ptrCast(p1))));
            if (@intFromPtr(p1) - @intFromPtr(vt.stringBuf(p)) < vt.stringLen(p))
                d = std.math.nan(f64);
        }
    }
    pres.* = d;
    return 0;
}

pub fn JS_ToNumber(ctx: *c.JSContext, pres: *f64, val_in: c.JSValue) c_int {
    var val = val_in;
    redo: while (true) {
        if (mc.isInt(val)) {
            pres.* = @floatFromInt(vt.valueGetInt(val));
            return 0;
        } else if (mc.isShortFloat(val)) {
            pres.* = jsGetShortFloat(val);
            return 0;
        } else if (mc.isPtr(val)) {
            const ptr = mc.valueToPtr(val);
            switch (utils.js_get_mtag(ptr)) {
                mc.JS_MTAG_STRING => return js_atod1(ctx, pres, val, 0, c.JS_ATOD_ACCEPT_BIN_OCT | rt.JS_ATOD_TOSTRING),
                mc.JS_MTAG_FLOAT64 => {
                    const p: *vt.JSFloat64Ext = @ptrCast(@alignCast(ptr));
                    pres.* = p.dval;
                    return 0;
                },
                mc.JS_MTAG_OBJECT => {
                    val = JS_ToPrimitive(ctx, val, rt.HINT_NUMBER);
                    if (vt.isExactException(val)) {
                        pres.* = std.math.nan(f64);
                        return -1;
                    }
                    continue :redo;
                },
                else => {
                    pres.* = std.math.nan(f64);
                    return 0;
                },
            }
        } else {
            switch (rt.valueGetSpecialTag(val)) {
                c.JS_TAG_NULL, c.JS_TAG_BOOL => {
                    pres.* = @floatFromInt(rt.valueGetSpecialValue(val));
                    return 0;
                },
                c.JS_TAG_UNDEFINED => {
                    pres.* = std.math.nan(f64);
                    return 0;
                },
                c.JS_TAG_STRING_CHAR => return js_atod1(ctx, pres, val, 0, c.JS_ATOD_ACCEPT_BIN_OCT | rt.JS_ATOD_TOSTRING),
                else => {
                    pres.* = std.math.nan(f64);
                    return 0;
                },
            }
        }
    }
}

pub fn JS_ToInt32Internal(ctx: *c.JSContext, pres: *c_int, val: c.JSValue, sat_flag: c.JS_BOOL) c_int {
    var ret: i32 = undefined;
    var d: f64 = undefined;
    if (mc.isInt(val)) {
        ret = vt.valueGetInt(val);
    } else if (mc.isShortFloat(val)) {
        d = jsGetShortFloat(val);
        ret = intFromFloat(d, sat_flag);
    } else if (mc.isPtr(val)) {
        if (JS_ToNumber(ctx, &d, val) != 0) {
            pres.* = 0;
            return -1;
        }
        ret = intFromFloat(d, sat_flag);
    } else {
        switch (rt.valueGetSpecialTag(val)) {
            c.JS_TAG_BOOL, c.JS_TAG_NULL, c.JS_TAG_UNDEFINED => {
                ret = rt.valueGetSpecialValue(val);
            },
            else => {
                if (JS_ToNumber(ctx, &d, val) != 0) {
                    pres.* = 0;
                    return -1;
                }
                ret = intFromFloat(d, sat_flag);
            },
        }
    }
    pres.* = ret;
    return 0;
}

fn intFromFloat(d: f64, sat_flag: c.JS_BOOL) i32 {
    const u: u64 = @bitCast(d);
    const e: i32 = @intCast((u >> 52) & 0x7ff);
    if (e <= (1023 + 30)) {
        return @intFromFloat(d);
    } else if (sat_flag == 0) {
        if (e <= (1023 + 30 + 53)) {
            var v = (u & ((@as(u64, 1) << 52) - 1)) | (@as(u64, 1) << 52);
            v = v << @as(u6, @intCast(e - 1023 - 52 + 32));
            var ret: i32 = @bitCast(@as(u32, @truncate(v >> 32)));
            if (u >> 63 != 0)
                ret = -ret;
            return ret;
        } else {
            return 0;
        }
    } else {
        if (e == 2047 and (u & ((@as(u64, 1) << 52) - 1)) != 0) {
            return 0;
        } else {
            if (u >> 63 != 0)
                return @bitCast(@as(u32, 0x80000000))
            else
                return 0x7fffffff;
        }
    }
}

pub fn JS_ToInt32(ctx: *c.JSContext, pres: *c_int, val: c.JSValue) c_int {
    return JS_ToInt32Internal(ctx, pres, val, 0);
}

pub fn JS_ToUint32(ctx: *c.JSContext, pres: *u32, val: c.JSValue) c_int {
    var tmp: c_int = undefined;
    const res = JS_ToInt32Internal(ctx, &tmp, val, 0);
    if (res == 0)
        pres.* = @bitCast(tmp);
    return res;
}

pub fn JS_ToInt32Sat(ctx: *c.JSContext, pres: *c_int, val: c.JSValue) c_int {
    return JS_ToInt32Internal(ctx, pres, val, 1);
}

pub fn JS_ToInt32Clamp(ctx: *c.JSContext, pres: *c_int, val: c.JSValue, min_v: c_int, max_v: c_int, min_offset: c_int) c_int {
    const res = JS_ToInt32Sat(ctx, pres, val);
    if (res == 0) {
        if (pres.* < min_v) {
            pres.* += min_offset;
            if (pres.* < min_v)
                pres.* = min_v;
        } else {
            if (pres.* > max_v)
                pres.* = max_v;
        }
    }
    return res;
}

pub fn JS_ToUint8Clamp(ctx: *c.JSContext, pres: *c_int, val: c.JSValue) c_int {
    var ret: i32 = undefined;
    var d: f64 = undefined;
    if (mc.isInt(val)) {
        ret = vt.valueGetInt(val);
        if (ret < 0)
            ret = 0
        else if (ret > 255)
            ret = 255;
    } else if (mc.isShortFloat(val)) {
        d = jsGetShortFloat(val);
        ret = uint8FromFloat(d);
    } else if (mc.isPtr(val)) {
        if (JS_ToNumber(ctx, &d, val) != 0) {
            pres.* = 0;
            return -1;
        }
        ret = uint8FromFloat(d);
    } else {
        switch (rt.valueGetSpecialTag(val)) {
            c.JS_TAG_BOOL, c.JS_TAG_NULL, c.JS_TAG_UNDEFINED => {
                ret = rt.valueGetSpecialValue(val);
            },
            else => {
                if (JS_ToNumber(ctx, &d, val) != 0) {
                    pres.* = 0;
                    return -1;
                }
                ret = uint8FromFloat(d);
            },
        }
    }
    pres.* = ret;
    return 0;
}

fn uint8FromFloat(d: f64) i32 {
    if (d < 0 or std.math.isNan(d))
        return 0
    else if (d > 255)
        return 255
    else
        return @intCast(js_lrint(d));
}

pub fn js_get_length32(ctx: *c.JSContext, pres: *u32, obj: c.JSValue) c_int {
    const len_val = value.JS_GetProperty(ctx, obj, utils.js_get_atom(ctx, c.JS_ATOM_length));
    if (vt.isExactException(len_val)) {
        pres.* = 0;
        return -1;
    }
    return JS_ToUint32(ctx, pres, len_val);
}

pub fn js_add_slow(ctx: *c.JSContext) c.JSValue {
    const sp: [*]c.JSValue = @ptrCast(mc.ctxExt(ctx).sp);
    sp[1] = JS_ToPrimitive(ctx, sp[1], rt.HINT_NONE);
    if (vt.isExactException(sp[1]))
        return c.JS_EXCEPTION;
    sp[0] = JS_ToPrimitive(ctx, sp[0], rt.HINT_NONE);
    if (vt.isExactException(sp[0]))
        return c.JS_EXCEPTION;
    if (value.JS_IsString(ctx, sp[1]) != 0 or value.JS_IsString(ctx, sp[0]) != 0) {
        sp[1] = JS_ToString(ctx, sp[1]);
        if (vt.isExactException(sp[1]))
            return c.JS_EXCEPTION;
        sp[0] = JS_ToString(ctx, sp[0]);
        if (vt.isExactException(sp[0]))
            return c.JS_EXCEPTION;
        return value.JS_ConcatString(ctx, sp[1], sp[0]);
    } else {
        var d1: f64 = undefined;
        var d2: f64 = undefined;
        if (JS_ToNumber(ctx, &d1, sp[1]) != 0)
            return c.JS_EXCEPTION;
        if (JS_ToNumber(ctx, &d2, sp[0]) != 0)
            return c.JS_EXCEPTION;
        return value.JS_NewFloat64(ctx, d1 + d2);
    }
}

pub fn js_binary_arith_slow(ctx: *c.JSContext, op: c_int) c.JSValue {
    var d1: f64 = undefined;
    var d2: f64 = undefined;
    const sp: [*]c.JSValue = @ptrCast(mc.ctxExt(ctx).sp);
    if (JS_ToNumber(ctx, &d1, sp[1]) != 0)
        return c.JS_EXCEPTION;
    if (JS_ToNumber(ctx, &d2, sp[0]) != 0)
        return c.JS_EXCEPTION;
    const r: f64 = switch (op) {
        OP.sub => d1 - d2,
        OP.mul => d1 * d2,
        OP.div => d1 / d2,
        OP.mod => js_fmod(d1, d2),
        OP.pow => js_pow(d1, d2),
        else => {
            c_abort();
        },
    };
    return value.JS_NewFloat64(ctx, r);
}

pub fn js_unary_arith_slow(ctx: *c.JSContext, op: c_int) c.JSValue {
    var d: f64 = undefined;
    const sp: [*]c.JSValue = @ptrCast(mc.ctxExt(ctx).sp);
    if (JS_ToNumber(ctx, &d, sp[0]) != 0)
        return c.JS_EXCEPTION;
    switch (op) {
        OP.inc => d += 1,
        OP.dec => d -= 1,
        OP.plus => {},
        OP.neg => d = -d,
        else => c_abort(),
    }
    return value.JS_NewFloat64(ctx, d);
}

pub fn js_post_inc_slow(ctx: *c.JSContext, op: c_int) c.JSValue {
    var d: f64 = undefined;
    const sp: [*]c.JSValue = @ptrCast(mc.ctxExt(ctx).sp);
    if (JS_ToNumber(ctx, &d, sp[0]) != 0)
        return c.JS_EXCEPTION;
    const r = d + 2 * @as(f64, @floatFromInt(op - OP.post_dec)) - 1;
    const val = value.JS_NewFloat64(ctx, d);
    if (vt.isExactException(val))
        return val;
    sp[0] = val;
    return value.JS_NewFloat64(ctx, r);
}

pub fn js_binary_logic_slow(ctx: *c.JSContext, op: c_int) c.JSValue {
    var v1: u32 = undefined;
    var v2: u32 = undefined;
    const sp: [*]c.JSValue = @ptrCast(mc.ctxExt(ctx).sp);
    if (JS_ToUint32(ctx, &v1, sp[1]) != 0)
        return c.JS_EXCEPTION;
    if (JS_ToUint32(ctx, &v2, sp[0]) != 0)
        return c.JS_EXCEPTION;
    switch (op) {
        OP.shl => return jsNewInt32(ctx, @bitCast(v1 << @as(u5, @intCast(v2 & 0x1f)))),
        OP.sar => {
            const r: i32 = @as(i32, @bitCast(v1)) >> @as(u5, @intCast(v2 & 0x1f));
            return jsNewInt32(ctx, r);
        },
        OP.shr => return jsNewUint32(ctx, v1 >> @as(u5, @intCast(v2 & 0x1f))),
        OP.@"and" => return jsNewInt32(ctx, @bitCast(v1 & v2)),
        OP.@"or" => return jsNewInt32(ctx, @bitCast(v1 | v2)),
        OP.xor => return jsNewInt32(ctx, @bitCast(v1 ^ v2)),
        else => c_abort(),
    }
}

pub fn js_not_slow(ctx: *c.JSContext) c.JSValue {
    var r: u32 = undefined;
    const sp: [*]c.JSValue = @ptrCast(mc.ctxExt(ctx).sp);
    if (JS_ToUint32(ctx, &r, sp[0]) != 0)
        return c.JS_EXCEPTION;
    return jsNewInt32(ctx, @bitCast(~r));
}

pub fn js_relational_slow(ctx: *c.JSContext, op: c_int) c.JSValue {
    const sp: [*]c.JSValue = @ptrCast(mc.ctxExt(ctx).sp);
    sp[1] = JS_ToPrimitive(ctx, sp[1], rt.HINT_NUMBER);
    if (vt.isExactException(sp[1]))
        return c.JS_EXCEPTION;
    sp[0] = JS_ToPrimitive(ctx, sp[0], rt.HINT_NUMBER);
    if (vt.isExactException(sp[0]))
        return c.JS_EXCEPTION;
    var res: c_int = undefined;
    if (value.JS_IsString(ctx, sp[1]) != 0 and value.JS_IsString(ctx, sp[0]) != 0) {
        const cmp = value.js_string_compare(ctx, sp[1], sp[0]);
        res = switch (op) {
            OP.lt => @intFromBool(cmp < 0),
            OP.lte => @intFromBool(cmp <= 0),
            OP.gt => @intFromBool(cmp > 0),
            else => @intFromBool(cmp >= 0),
        };
    } else {
        var d1: f64 = undefined;
        var d2: f64 = undefined;
        if (JS_ToNumber(ctx, &d1, sp[1]) != 0)
            return c.JS_EXCEPTION;
        if (JS_ToNumber(ctx, &d2, sp[0]) != 0)
            return c.JS_EXCEPTION;
        res = switch (op) {
            OP.lt => @intFromBool(d1 < d2),
            OP.lte => @intFromBool(d1 <= d2),
            OP.gt => @intFromBool(d1 > d2),
            else => @intFromBool(d1 >= d2),
        };
    }
    return rt.newBool(res != 0);
}

pub fn js_strict_eq(ctx: *c.JSContext, op1: c.JSValue, op2: c.JSValue) c.JS_BOOL {
    if (value.JS_IsNumber(ctx, op1) != 0) {
        if (value.JS_IsNumber(ctx, op2) == 0)
            return 0;
        var d1: f64 = undefined;
        var d2: f64 = undefined;
        _ = JS_ToNumber(ctx, &d1, op1);
        _ = JS_ToNumber(ctx, &d2, op2);
        return @intFromBool(d1 == d2);
    } else if (value.JS_IsString(ctx, op1) != 0) {
        if (value.JS_IsString(ctx, op2) == 0)
            return 0;
        return value.js_string_eq(ctx, op1, op2);
    } else {
        return @intFromBool(op1 == op2);
    }
}

pub fn js_strict_eq_slow(ctx: *c.JSContext, is_neq: c.JS_BOOL) c.JSValue {
    const sp: [*]c.JSValue = @ptrCast(mc.ctxExt(ctx).sp);
    const res = js_strict_eq(ctx, sp[1], sp[0]);
    return rt.newBool((res ^ is_neq) != 0);
}

pub fn js_eq_get_type(ctx: *c.JSContext, val: c.JSValue) c_int {
    _ = ctx;
    if (vt.isIntOrShortFloat(val)) {
        return rt.JS_ETAG_NUMBER;
    } else if (mc.isPtr(val)) {
        const ptr = mc.valueToPtr(val);
        return switch (utils.js_get_mtag(ptr)) {
            mc.JS_MTAG_FLOAT64 => rt.JS_ETAG_NUMBER,
            mc.JS_MTAG_STRING => rt.JS_ETAG_STRING,
            else => rt.JS_ETAG_OBJECT,
        };
    } else {
        const tag = rt.valueGetSpecialTag(val);
        return switch (tag) {
            c.JS_TAG_STRING_CHAR => rt.JS_ETAG_STRING,
            c.JS_TAG_SHORT_FUNC => rt.JS_ETAG_OBJECT,
            else => @intCast(tag),
        };
    }
}

pub fn js_eq_slow(ctx: *c.JSContext, is_neq: c.JS_BOOL) c.JSValue {
    const sp: [*]c.JSValue = @ptrCast(mc.ctxExt(ctx).sp);
    redo: while (true) {
        const op1 = sp[1];
        const op2 = sp[0];
        const tag1 = js_eq_get_type(ctx, op1);
        const tag2 = js_eq_get_type(ctx, op2);
        var res: c.JS_BOOL = undefined;
        if (tag1 == tag2) {
            res = js_strict_eq(ctx, op1, op2);
        } else if ((tag1 == c.JS_TAG_NULL and tag2 == c.JS_TAG_UNDEFINED) or
            (tag2 == c.JS_TAG_NULL and tag1 == c.JS_TAG_UNDEFINED))
        {
            res = 1;
        } else if ((tag1 == rt.JS_ETAG_STRING and tag2 == rt.JS_ETAG_NUMBER) or
            (tag2 == rt.JS_ETAG_STRING and tag1 == rt.JS_ETAG_NUMBER))
        {
            var d1: f64 = undefined;
            var d2: f64 = undefined;
            if (JS_ToNumber(ctx, &d1, sp[1]) != 0)
                return c.JS_EXCEPTION;
            if (JS_ToNumber(ctx, &d2, sp[0]) != 0)
                return c.JS_EXCEPTION;
            res = @intFromBool(d1 == d2);
        } else if (tag1 == c.JS_TAG_BOOL) {
            sp[1] = vt.newShortInt(rt.valueGetSpecialValue(op1));
            continue :redo;
        } else if (tag2 == c.JS_TAG_BOOL) {
            sp[0] = vt.newShortInt(rt.valueGetSpecialValue(op2));
            continue :redo;
        } else if (tag1 == rt.JS_ETAG_OBJECT and
            (tag2 == rt.JS_ETAG_NUMBER or tag2 == rt.JS_ETAG_STRING))
        {
            sp[1] = JS_ToPrimitive(ctx, op1, rt.HINT_NONE);
            if (vt.isExactException(sp[1]))
                return c.JS_EXCEPTION;
            continue :redo;
        } else if (tag2 == rt.JS_ETAG_OBJECT and
            (tag1 == rt.JS_ETAG_NUMBER or tag1 == rt.JS_ETAG_STRING))
        {
            sp[0] = JS_ToPrimitive(ctx, op2, rt.HINT_NONE);
            if (vt.isExactException(sp[0]))
                return c.JS_EXCEPTION;
            continue :redo;
        } else {
            res = 0;
        }
        return rt.newBool((res ^ is_neq) != 0);
    }
}

pub fn js_operator_in(ctx: *c.JSContext) c.JSValue {
    const sp: [*]c.JSValue = @ptrCast(mc.ctxExt(ctx).sp);
    if (js_eq_get_type(ctx, sp[0]) != rt.JS_ETAG_OBJECT)
        return throwTypeError(ctx, "invalid 'in' operand");
    const prop = JS_ToPropertyKey(ctx, sp[1]);
    if (vt.isExactException(prop))
        return prop;
    const res = value.JS_HasProperty(ctx, sp[0], prop);
    return rt.newBool(res != 0);
}

pub fn js_operator_instanceof(ctx: *c.JSContext) c.JSValue {
    const sp: [*]c.JSValue = @ptrCast(mc.ctxExt(ctx).sp);
    const op1 = sp[1];
    const op2 = sp[0];
    if (value.JS_IsFunctionObject(ctx, op2) == 0)
        return throwTypeError(ctx, "invalid 'instanceof' right operand");
    const proto = value.JS_GetProperty(ctx, op2, utils.js_get_atom(ctx, c.JS_ATOM_prototype));
    if (vt.isExactException(proto))
        return proto;
    if (value.JS_IsObject(ctx, op1) == 0)
        return rt.newBool(false);
    var p: *mc.JSObjectExt = @ptrCast(@alignCast(mc.valueToPtr(op1)));
    while (true) {
        if (p.proto == c.JS_NULL)
            return rt.newBool(false);
        if (p.proto == proto)
            return rt.newBool(true);
        p = @ptrCast(@alignCast(mc.valueToPtr(p.proto)));
    }
}

pub fn js_operator_typeof(ctx: *c.JSContext, val: c.JSValue) c.JSValue {
    const tag = js_eq_get_type(ctx, val);
    const atom: c_int = switch (tag) {
        rt.JS_ETAG_NUMBER => c.JS_ATOM_number,
        rt.JS_ETAG_STRING => c.JS_ATOM_string,
        c.JS_TAG_BOOL => c.JS_ATOM_boolean,
        rt.JS_ETAG_OBJECT => if (value.JS_IsFunction(ctx, val) != 0) c.JS_ATOM_function else c.JS_ATOM_object,
        c.JS_TAG_NULL => c.JS_ATOM_object,
        else => c.JS_ATOM_undefined,
    };
    return utils.js_get_atom(ctx, atom);
}

pub fn js_reverse_val(tab: [*]c.JSValue, n: c_int) void {
    var i: c_int = 0;
    while (i < @divTrunc(n, 2)) : (i += 1) {
        const tmp = tab[@intCast(i)];
        tab[@intCast(i)] = tab[@intCast(n - 1 - i)];
        tab[@intCast(n - 1 - i)] = tmp;
    }
}

pub fn js_closure(ctx: *c.JSContext, bfunc_in: c.JSValue, fp: ?[*]c.JSValue) c.JSValue {
    var bfunc = bfunc_in;
    var b: *rt.JSFunctionBytecodeExt = @ptrCast(@alignCast(mc.valueToPtr(bfunc)));
    var ext_vars_len: c_int = 0;
    if (b.ext_vars != c.JS_NULL) {
        const ext_vars: *vt.JSValueArrayExt = @ptrCast(@alignCast(mc.valueToPtr(b.ext_vars)));
        ext_vars_len = @divTrunc(vt.valueArraySize(ext_vars), 2);
    }
    var bfunc_ref: c.JSGCRef = undefined;
    utils.pushValue(ctx, &bfunc_ref, bfunc);
    const extra: c_int = @intCast(@sizeOf(c.JSValue) + @as(usize, @intCast(ext_vars_len)) * @sizeOf(c.JSValue));
    var closure = value.JS_NewObjectProtoClass(ctx, vt.classProto(mc.ctxExt(ctx), c.JS_CLASS_CLOSURE).*, c.JS_CLASS_CLOSURE, extra);
    bfunc = utils.popValue(ctx, &bfunc_ref);
    if (vt.isExactException(closure))
        return c.JS_EXCEPTION;
    var p: *mc.JSObjectExt = @ptrCast(@alignCast(mc.valueToPtr(closure)));
    p.u.closure.func_bytecode = bfunc;

    if (ext_vars_len > 0) {
        const refs = rt.closureVarRefs(p);
        @memset(@as([*]u8, @ptrCast(refs))[0 .. @as(usize, @intCast(ext_vars_len)) * @sizeOf(c.JSValue)], 0);
        const pfirst_var_ref: ?*c.JSValue = if (fp) |f| rt.slot(f, rt.FRAME_OFFSET_FIRST_VARREF) else null;
        var i: c_int = 0;
        while (i < ext_vars_len) : (i += 1) {
            b = @ptrCast(@alignCast(mc.valueToPtr(bfunc)));
            const ext_vars: *vt.JSValueArrayExt = @ptrCast(@alignCast(mc.valueToPtr(b.ext_vars)));
            const items = vt.valueArrayItems(ext_vars);
            const decl = vt.valueGetInt(items[@intCast(2 * i + 1)]);
            const var_kind = decl >> 16;
            const var_idx = decl & 0xffff;
            var closure_ref: c.JSGCRef = undefined;
            utils.pushValue(ctx, &bfunc_ref, bfunc);
            utils.pushValue(ctx, &closure_ref, closure);
            const val: c.JSValue = switch (var_kind) {
                rt.JS_VARREF_KIND_ARG => get_var_ref(ctx, pfirst_var_ref.?, rt.slot(fp.?, rt.FRAME_OFFSET_ARG0 + var_idx)),
                rt.JS_VARREF_KIND_VAR => get_var_ref(ctx, pfirst_var_ref.?, rt.slot(fp.?, rt.FRAME_OFFSET_VAR0 - var_idx)),
                rt.JS_VARREF_KIND_VAR_REF => blk: {
                    const po: *mc.JSObjectExt = @ptrCast(@alignCast(mc.valueToPtr(rt.slot(fp.?, rt.FRAME_OFFSET_FUNC_OBJ).*)));
                    break :blk rt.closureVarRefs(po)[@intCast(var_idx)];
                },
                rt.JS_VARREF_KIND_GLOBAL => value.add_global_var(ctx, items[@intCast(2 * i)], @intFromBool(var_idx != 0)),
                else => {
                    c_abort();
                },
            };
            closure = utils.popValue(ctx, &closure_ref);
            bfunc = utils.popValue(ctx, &bfunc_ref);
            if (vt.isExactException(val))
                return val;
            p = @ptrCast(@alignCast(mc.valueToPtr(closure)));
            rt.closureVarRefs(p)[@intCast(i)] = val;
        }
    }
    return closure;
}

pub fn js_for_of_start(ctx: *c.JSContext, is_for_in: c.JS_BOOL) c.JSValue {
    const sp: [*]c.JSValue = @ptrCast(mc.ctxExt(ctx).sp);
    if (is_for_in != 0) {
        sp[0] = builtins.js_object_keys(ctx, null, 1, @ptrCast(sp));
        if (vt.isExactException(sp[0]))
            return c.JS_EXCEPTION;
    }
    if (value.js_get_object_class(ctx, sp[0], c.JS_CLASS_ARRAY) == null)
        return throwTypeError(ctx, "unsupported type in for...of");
    const arr: *vt.JSValueArrayExt = @ptrCast(@alignCast(value.js_alloc_value_array(ctx, 0, 2) orelse return c.JS_EXCEPTION));
    const items = vt.valueArrayItems(arr);
    items[0] = sp[0];
    items[1] = vt.newShortInt(0);
    return mc.valueFromPtr(arr);
}

pub fn js_for_of_next(ctx: *c.JSContext) c.JSValue {
    const sp: [*]c.JSValue = @ptrCast(mc.ctxExt(ctx).sp);
    const arr: *vt.JSValueArrayExt = @ptrCast(@alignCast(mc.valueToPtr(sp[0])));
    const items = vt.valueArrayItems(arr);
    const pos = vt.valueGetInt(items[1]);
    const p: *mc.JSObjectExt = @ptrCast(@alignCast(mc.valueToPtr(items[0])));
    if (pos >= @as(c_int, @intCast(p.u.array.len))) {
        rt.slot(sp, -2).* = c.JS_TRUE;
        rt.slot(sp, -1).* = c.JS_UNDEFINED;
    } else {
        rt.slot(sp, -2).* = c.JS_FALSE;
        const arr1: *vt.JSValueArrayExt = @ptrCast(@alignCast(mc.valueToPtr(p.u.array.tab)));
        rt.slot(sp, -1).* = vt.valueArrayItems(arr1)[@intCast(pos)];
        items[1] = vt.newShortInt(pos + 1);
    }
    return c.JS_UNDEFINED;
}

pub fn js_new_c_function_proto(ctx: *c.JSContext, func_idx: c_int, proto: c.JSValue, has_params: c.JS_BOOL, params_in: c.JSValue) c.JSValue {
    var params = params_in;
    var params_ref: c.JSGCRef = undefined;
    utils.pushValue(ctx, &params_ref, params);
    const extra: c_int = if (has_params == 0)
        @intCast(@sizeOf(mc.JSCFunctionDataExt) - @sizeOf(c.JSValue))
    else
        @intCast(@sizeOf(mc.JSCFunctionDataExt));
    const p0 = value.JS_NewObjectProtoClass1(ctx, proto, c.JS_CLASS_C_FUNCTION, extra);
    params = utils.popValue(ctx, &params_ref);
    const p: *mc.JSObjectExt = @ptrCast(@alignCast(p0 orelse return c.JS_EXCEPTION));
    p.u.cfunc.idx = @intCast(func_idx);
    if (has_params != 0)
        p.u.cfunc.params = params;
    return mc.valueFromPtr(p);
}

pub fn JS_NewCFunctionParams(ctx: *c.JSContext, func_idx: c_int, params: c.JSValue) c.JSValue {
    return js_new_c_function_proto(ctx, func_idx, vt.classProto(mc.ctxExt(ctx), c.JS_CLASS_CLOSURE).*, 1, params);
}

pub fn js_call_constructor_start(ctx: *c.JSContext, func: c.JSValue) c.JSValue {
    var proto = value.JS_GetProperty(ctx, func, utils.js_get_atom(ctx, c.JS_ATOM_prototype));
    if (vt.isExactException(proto))
        return proto;
    if (value.JS_IsObject(ctx, proto) == 0)
        proto = vt.classProto(mc.ctxExt(ctx), c.JS_CLASS_OBJECT).*;
    return value.JS_NewObjectProtoClass(ctx, proto, c.JS_CLASS_OBJECT, 0);
}

pub fn __js_poll_interrupt(ctx: *c.JSContext) c.JSValue {
    mc.ctxExt(ctx).interrupt_counter = rt.JS_INTERRUPT_COUNTER_INIT;
    if (mc.ctxExt(ctx).interrupt_handler) |h| {
        const handler: rt.JSInterruptHandler = @ptrCast(h);
        if (handler(ctx, mc.ctxExt(ctx).opaque_val) != 0) {
            _ = throwInternalError(ctx, "interrupted");
            mc.ctxExt(ctx).current_exception_is_uncatchable = 1;
            return c.JS_EXCEPTION;
        }
    }
    return c.JS_UNDEFINED;
}
