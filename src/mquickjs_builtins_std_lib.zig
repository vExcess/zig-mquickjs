//
// Micro QuickJS engine builtins — Math/TypedArray/Date/Global/JSON (internal submodule)
//
// Copyright (c) 2017-2025 Fabrice Bellard
// Copyright (c) 2017-2025 Charlie Gordon
//
// Ported from C to Zig by Composer 2.5 + Grok 4.6 + Gemini 3 Pro + VExcess
//

const std = @import("std");
const cutils = @import("cutils_lib.zig");
const utils = @import("mquickjs_utils_lib.zig");
const bt = @import("mquickjs_builtins_types.zig");
const lt = bt.lt;
const pt = bt.pt;
const rt = bt.rt;
const vt = bt.vt;
const mc = bt.mc;
const c = bt.c;

const parser = @import("mquickjs_parser_lib.zig");
const value = @import("mquickjs_value_lib.zig");
const runtime = @import("mquickjs_runtime_lib.zig");

const builtins_main = @import("mquickjs_builtins_lib.zig");

extern fn js_pow(x: f64, y: f64) f64;
extern fn js_atan2(y: f64, x: f64) f64;

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

fn newBool(v: bool) c.JSValue {
    return rt.newBool(v);
}

fn float64AsUint64(d: f64) u64 {
    return @bitCast(d);
}

fn uint64AsFloat64(u: u64) f64 {
    return @bitCast(u);
}

fn minInt(a: c_int, b: c_int) c_int {
    return if (a < b) a else b;
}

fn maxInt(a: c_int, b: c_int) c_int {
    return if (a > b) a else b;
}

// Math / TypedArray / Date / Global / JSON

pub fn js_fmin(a: f64, b: f64) f64 {
    if (a == 0 and b == 0) {
        return uint64AsFloat64(float64AsUint64(a) | float64AsUint64(b));
    } else if (a <= b) {
        return a;
    } else {
        return b;
    }
}

// precondition: a and b are not NaN
pub fn js_fmax(a: f64, b: f64) f64 {
    if (a == 0 and b == 0) {
        return uint64AsFloat64(float64AsUint64(a) & float64AsUint64(b));
    } else if (a >= b) {
        return a;
    } else {
        return b;
    }
}

pub fn js_math_min_max(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue, magic: c_int) c.JSValue {
    _ = this_val;
    const is_max = magic != 0;
    var r: f64 = undefined;
    var a: f64 = undefined;
    var i: c_int = undefined;

    if (argc == 0) {
        return value.__JS_NewFloat64(ctx, if (is_max) -std.math.inf(f64) else std.math.inf(f64));
    }

    if (mc.isInt(argv[0])) {
        var a1: c_int = undefined;
        var r1 = vt.valueGetInt(argv[0]);
        i = 1;
        while (i < argc) : (i += 1) {
            if (!mc.isInt(argv[@intCast(i)])) {
                r = @floatFromInt(r1);
                break;
            }
            a1 = vt.valueGetInt(argv[@intCast(i)]);
            if (is_max)
                r1 = maxInt(r1, a1)
            else
                r1 = minInt(r1, a1);
        } else {
            return vt.newShortInt(r1);
        }
    } else {
        if (runtime.JS_ToNumber(ctx, &r, argv[0]) != 0)
            return c.JS_EXCEPTION;
        i = 1;
    }
    while (i < argc) : (i += 1) {
        if (runtime.JS_ToNumber(ctx, &a, argv[@intCast(i)]) != 0)
            return c.JS_EXCEPTION;
        if (!std.math.isNan(r)) {
            if (std.math.isNan(a)) {
                r = a;
            } else {
                if (is_max)
                    r = js_fmax(r, a)
                else
                    r = js_fmin(r, a);
            }
        }
    }
    return value.JS_NewFloat64(ctx, r);
}

pub fn js_math_sign(a: f64) f64 {
    if (std.math.isNan(a) or a == 0.0)
        return a;
    if (a < 0)
        return -1;
    return 1;
}

pub fn js_math_fround(a: f64) f64 {
    const f: f32 = @floatCast(a);
    return @floatCast(f);
}

pub fn js_math_imul(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    _ = this_val;
    _ = argc;
    var a: c_int = undefined;
    var b: c_int = undefined;

    if (runtime.JS_ToInt32(ctx, &a, argv[0]) != 0)
        return c.JS_EXCEPTION;
    if (runtime.JS_ToInt32(ctx, &b, argv[1]) != 0)
        return c.JS_EXCEPTION;
    // purposely ignoring overflow
    const prod: u32 = @as(u32, @bitCast(a)) *% @as(u32, @bitCast(b));
    return value.JS_NewInt32(ctx, @bitCast(prod));
}

pub fn js_math_clz32(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    _ = this_val;
    _ = argc;
    var a: u32 = undefined;
    var r: u32 = undefined;

    if (runtime.JS_ToUint32(ctx, &a, argv[0]) != 0)
        return c.JS_EXCEPTION;
    if (a == 0)
        r = 32
    else
        r = @intCast(@clz(a));
    return value.JS_NewInt32(ctx, @intCast(r));
}

pub fn js_math_atan2(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    _ = this_val;
    _ = argc;
    var y: f64 = undefined;
    var x: f64 = undefined;

    if (runtime.JS_ToNumber(ctx, &y, argv[0]) != 0)
        return c.JS_EXCEPTION;
    if (runtime.JS_ToNumber(ctx, &x, argv[1]) != 0)
        return c.JS_EXCEPTION;
    return value.JS_NewFloat64(ctx, js_atan2(y, x));
}

pub fn js_math_pow(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    _ = this_val;
    _ = argc;
    var y: f64 = undefined;
    var x: f64 = undefined;

    if (runtime.JS_ToNumber(ctx, &x, argv[0]) != 0)
        return c.JS_EXCEPTION;
    if (runtime.JS_ToNumber(ctx, &y, argv[1]) != 0)
        return c.JS_EXCEPTION;
    return value.JS_NewFloat64(ctx, js_pow(x, y));
}

// xorshift* random number generator by Marsaglia
pub fn xorshift64star(pstate: *u64) u64 {
    var x = pstate.*;
    x ^= x >> 12;
    x ^= x << 25;
    x ^= x >> 27;
    pstate.* = x;
    return x *% 0x2545F4914F6CDD1D;
}

pub fn js_math_random(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    _ = this_val;
    _ = argc;
    _ = argv;
    const v = xorshift64star(&mc.ctxExt(ctx).random_state);
    // 1.0 <= u.d < 2
    const d = uint64AsFloat64((@as(u64, 0x3ff) << 52) | (v >> 12));
    return value.__JS_NewFloat64(ctx, d - 1.0);
}

// typed array

pub fn JS_ToIndex(ctx: *c.JSContext, plen: *u64, val: c.JSValue) c_int {
    var v: c_int = undefined;
    // XXX: should support 53 bit inteers
    if (runtime.JS_ToInt32Sat(ctx, &v, val) != 0)
        return -1;
    if (v < 0 or v > vt.JS_SHORTINT_MAX) {
        _ = throwRangeError(ctx, "invalid array index");
        return -1;
    }
    plen.* = @intCast(v);
    return 0;
}

pub fn js_array_buffer_alloc(ctx: *c.JSContext, len: u64) c.JSValue {
    if (len > @as(u64, @intCast(vt.JS_SHORTINT_MAX)))
        return throwRangeError(ctx, "invalid array buffer length");
    const arr_ptr = value.js_alloc_byte_array(ctx, @intCast(len)) orelse return c.JS_EXCEPTION;
    const arr: *vt.JSByteArrayExt = @ptrCast(@alignCast(arr_ptr));
    @memset(vt.byteArrayBuf(arr)[0..@intCast(len)], 0);
    var buffer = mc.valueFromPtr(arr);
    var buffer_ref: c.JSGCRef = undefined;
    utils.pushValue(ctx, &buffer_ref, buffer);
    const obj = value.JS_NewObjectClass(ctx, c.JS_CLASS_ARRAY_BUFFER, @intCast(@sizeOf(mc.JSArrayBufferExt)));
    buffer = utils.popValue(ctx, &buffer_ref);
    if (vt.isExactException(obj))
        return obj;
    const p = objPtr(obj);
    p.u.array_buffer.byte_buffer = buffer;
    return obj;
}

pub fn js_array_buffer_constructor(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    _ = this_val;
    var len: u64 = undefined;
    if (argc & c.FRAME_CF_CTOR == 0)
        return throwTypeError(ctx, "must be called with new");
    if (JS_ToIndex(ctx, &len, argv[0]) != 0)
        return c.JS_EXCEPTION;
    return js_array_buffer_alloc(ctx, len);
}

pub fn js_array_buffer_get_byteLength(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    _ = argc;
    _ = argv;
    const p0 = value.js_get_object_class(ctx, this_val.*, c.JS_CLASS_ARRAY_BUFFER) orelse
        return throwTypeError(ctx, "expected an ArrayBuffer");
    const p: *mc.JSObjectExt = @ptrCast(@alignCast(p0));
    const arr = byteArr(p.u.array_buffer.byte_buffer);
    return vt.newShortInt(vt.byteArraySize(arr));
}

pub fn js_typed_array_base_constructor(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    _ = this_val;
    _ = argc;
    _ = argv;
    return throwTypeError(ctx, "cannot be called");
}

pub fn js_typed_array_constructor_obj(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue, magic: c_int) c.JSValue {
    _ = this_val;
    _ = argc;
    var i: c_int = undefined;
    var len: c_int = undefined;
    var val: c.JSValue = undefined;
    var obj: c.JSValue = undefined;
    var obj_ref: c.JSGCRef = undefined;
    var p: *mc.JSObjectExt = undefined;

    p = objPtr(argv[0]);
    if (mc.objectClassId(p) == c.JS_CLASS_ARRAY) {
        len = @intCast(p.u.array.len);
    } else if (mc.objectClassId(p) >= c.JS_CLASS_UINT8C_ARRAY and
        mc.objectClassId(p) <= c.JS_CLASS_FLOAT64_ARRAY)
    {
        len = @intCast(p.u.typed_array.len);
    } else {
        return throwTypeError(ctx, "unsupported object class");
    }
    val = vt.newShortInt(len);
    obj = js_typed_array_constructor(ctx, null, 1 | c.FRAME_CF_CTOR, @ptrCast(&val), magic);
    if (vt.isExactException(obj))
        return obj;

    i = 0;
    while (i < len) : (i += 1) {
        utils.pushValue(ctx, &obj_ref, obj);
        val = value.JS_GetProperty(ctx, argv[0], vt.newShortInt(i));
        obj = utils.popValue(ctx, &obj_ref);
        if (vt.isExactException(val))
            return val;
        utils.pushValue(ctx, &obj_ref, obj);
        val = value.JS_SetPropertyInternal(ctx, obj, vt.newShortInt(i), val, 0);
        obj = utils.popValue(ctx, &obj_ref);
        if (vt.isExactException(val))
            return val;
    }
    return obj;
}

pub fn js_typed_array_constructor(ctx: *c.JSContext, this_val: ?*c.JSValue, argc: c_int, argv: [*]c.JSValue, magic: c_int) c.JSValue {
    var size_log2: c_int = undefined;
    var len: u64 = undefined;
    var offset: u64 = undefined;
    var byte_length: u64 = undefined;
    var p: *mc.JSObjectExt = undefined;
    var arr: *vt.JSByteArrayExt = undefined;
    var buffer: c.JSValue = undefined;
    var obj: c.JSValue = undefined;
    var buffer_ref: c.JSGCRef = undefined;

    if (argc & c.FRAME_CF_CTOR == 0)
        return throwTypeError(ctx, "must be called with new");
    size_log2 = bt.typed_array_size_log2[@intCast(magic - c.JS_CLASS_UINT8C_ARRAY)];
    if (value.JS_IsObject(ctx, argv[0]) == 0) {
        if (JS_ToIndex(ctx, &len, argv[0]) != 0)
            return c.JS_EXCEPTION;
        buffer = js_array_buffer_alloc(ctx, len << @as(u6, @intCast(size_log2)));
        if (vt.isExactException(buffer))
            return c.JS_EXCEPTION;
        offset = 0;
    } else {
        p = objPtr(argv[0]);
        if (mc.objectClassId(p) == c.JS_CLASS_ARRAY_BUFFER) {
            arr = byteArr(p.u.array_buffer.byte_buffer);
            byte_length = @intCast(vt.byteArraySize(arr));
            if (JS_ToIndex(ctx, &offset, argv[1]) != 0)
                return c.JS_EXCEPTION;
            const align_mask = (@as(u64, 1) << @as(u6, @intCast(size_log2))) - 1;
            if ((offset & align_mask) != 0 or offset > byte_length)
                return throwRangeError(ctx, "invalid offset");
            if (vt.isUndefined(argv[2])) {
                if ((byte_length & align_mask) != 0)
                    return throwRangeError(ctx, "invalid length");
                len = (byte_length - offset) >> @as(u6, @intCast(size_log2));
            } else {
                if (JS_ToIndex(ctx, &len, argv[2]) != 0)
                    return c.JS_EXCEPTION;
                if ((offset + (len << @as(u6, @intCast(size_log2)))) > byte_length)
                    return throwRangeError(ctx, "invalid length");
            }
            buffer = argv[0];
            offset >>= @as(u6, @intCast(size_log2));
        } else {
            var dummy: c.JSValue = undefined;
            return js_typed_array_constructor_obj(ctx, this_val orelse &dummy, argc, argv, magic);
        }
    }

    utils.pushValue(ctx, &buffer_ref, buffer);
    obj = value.JS_NewObjectClass(ctx, magic, @intCast(@sizeOf(mc.JSTypedArrayExt)));
    buffer = utils.popValue(ctx, &buffer_ref);
    if (vt.isExactException(obj))
        return obj;
    p = objPtr(obj);
    p.u.typed_array.buffer = buffer;
    p.u.typed_array.offset = @intCast(offset);
    p.u.typed_array.len = @intCast(len);
    return obj;
}

pub fn get_typed_array(ctx: *c.JSContext, val: c.JSValue) ?*mc.JSObjectExt {
    if (value.JS_IsObject(ctx, val) != 0) {
        const p = objPtr(val);
        if (mc.objectClassId(p) >= c.JS_CLASS_UINT8C_ARRAY and mc.objectClassId(p) <= c.JS_CLASS_FLOAT64_ARRAY)
            return p;
    }
    _ = throwTypeError(ctx, "not a TypedArray");
    return null;
}

pub fn js_typed_array_get_length(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue, magic: c_int) c.JSValue {
    _ = argc;
    _ = argv;
    const p = get_typed_array(ctx, this_val.*) orelse return c.JS_EXCEPTION;
    const size_log2: c_int = bt.typed_array_size_log2[@intCast(mc.objectClassId(p) - c.JS_CLASS_UINT8C_ARRAY)];
    switch (magic) {
        1 => return vt.newShortInt(@intCast(p.u.typed_array.len << @as(u5, @intCast(size_log2)))),
        2 => return vt.newShortInt(@intCast(p.u.typed_array.offset << @as(u5, @intCast(size_log2)))),
        3 => return p.u.typed_array.buffer,
        else => return vt.newShortInt(@intCast(p.u.typed_array.len)),
    }
}

pub fn js_typed_array_subarray(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    _ = argc;
    var p = get_typed_array(ctx, this_val.*) orelse return c.JS_EXCEPTION;
    var start: c_int = undefined;
    var final: c_int = undefined;
    const len: c_int = @intCast(p.u.typed_array.len);
    if (runtime.JS_ToInt32Clamp(ctx, &start, argv[0], 0, len, len) != 0)
        return c.JS_EXCEPTION;
    if (vt.isUndefined(argv[1])) {
        final = len;
    } else {
        if (runtime.JS_ToInt32Clamp(ctx, &final, argv[1], 0, len, len) != 0)
            return c.JS_EXCEPTION;
    }
    p = objPtr(this_val.*);
    const offset: u32 = p.u.typed_array.offset + @as(u32, @intCast(start));
    const count: u32 = @intCast(maxInt(final - start, 0));

    // check offset and count
    const p1_buf = objPtr(p.u.typed_array.buffer);
    const arr = byteArr(p1_buf.u.array_buffer.byte_buffer);
    if (@as(u64, offset +% count) > @as(u64, @intCast(vt.byteArraySize(arr))))
        return throwRangeError(ctx, "invalid length");

    const obj = value.JS_NewObjectClass(ctx, mc.objectClassId(p), @intCast(@sizeOf(mc.JSTypedArrayExt)));
    if (vt.isExactException(obj))
        return c.JS_EXCEPTION;
    p = objPtr(this_val.*);
    const p1 = objPtr(obj);
    p1.u.typed_array.buffer = p.u.typed_array.buffer;
    p1.u.typed_array.offset = offset;
    p1.u.typed_array.len = count;
    return obj;
}

pub fn js_typed_array_set(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    var p = get_typed_array(ctx, this_val.*) orelse return c.JS_EXCEPTION;
    var src_len: u32 = undefined;
    var offset: c_int = undefined;

    if (argc > 1) {
        if (runtime.JS_ToInt32Sat(ctx, &offset, argv[1]) != 0)
            return c.JS_EXCEPTION;
    } else {
        offset = 0;
    }
    if (offset < 0)
        return throwRangeError(ctx, "invalid array length");
    if (value.JS_IsObject(ctx, argv[0]) == 0)
        return value.JS_ThrowTypeErrorNotAnObject(ctx);
    p = objPtr(this_val.*);
    const dst_len: u32 = p.u.typed_array.len;
    const p1 = objPtr(argv[0]);
    if (mc.objectClassId(p1) >= c.JS_CLASS_UINT8C_ARRAY and
        mc.objectClassId(p1) <= c.JS_CLASS_FLOAT64_ARRAY)
    {
        src_len = p1.u.typed_array.len;
        if (src_len > dst_len or @as(u32, @intCast(offset)) > dst_len - src_len)
            return throwRangeError(ctx, "invalid array length");
        if (mc.objectClassId(p1) == mc.objectClassId(p)) {
            const shift: u5 = @intCast(bt.typed_array_size_log2[@intCast(mc.objectClassId(p) - c.JS_CLASS_UINT8C_ARRAY)]);
            const dst_buffer = objPtr(p.u.typed_array.buffer);
            const dst_arr = byteArr(dst_buffer.u.array_buffer.byte_buffer);
            const src_buffer = objPtr(p1.u.typed_array.buffer);
            const src_arr = byteArr(src_buffer.u.array_buffer.byte_buffer);
            // same type: must copy to preserve float bits
            const dst_off: usize = @as(usize, (p.u.typed_array.offset + @as(u32, @intCast(offset))) << shift);
            const src_off: usize = @as(usize, p1.u.typed_array.offset << shift);
            const n: usize = @as(usize, src_len) << shift;
            const dst_p = vt.byteArrayBuf(dst_arr) + dst_off;
            const src_p = vt.byteArrayBuf(src_arr) + src_off;
            const dst_s = dst_p[0..n];
            const src_s = src_p[0..n];
            if (@intFromPtr(dst_p) <= @intFromPtr(src_p)) {
                std.mem.copyForwards(u8, dst_s, src_s);
            } else {
                std.mem.copyBackwards(u8, dst_s, src_s);
            }
            return c.JS_UNDEFINED;
        }
    } else {
        if (runtime.js_get_length32(ctx, &src_len, argv[0]) != 0)
            return c.JS_EXCEPTION;
        if (src_len > dst_len or @as(u32, @intCast(offset)) > dst_len - src_len)
            return throwRangeError(ctx, "invalid array length");
    }
    var i: u32 = 0;
    while (i < src_len) : (i += 1) {
        var val = value.JS_GetPropertyUint32(ctx, argv[0], i);
        if (vt.isExactException(val))
            return c.JS_EXCEPTION;
        val = value.JS_SetPropertyUint32(ctx, this_val.*, @as(u32, @intCast(offset)) + i, val);
        if (vt.isExactException(val))
            return c.JS_EXCEPTION;
    }
    return c.JS_UNDEFINED;
}

// Date

pub fn JS_NewDate(ctx: *c.JSContext, epoch_ms: f64) c.JSValue {
    const obj = value.JS_NewObjectClass(ctx, c.JS_CLASS_DATE, @intCast(@sizeOf(bt.JSDateExt)));
    if (vt.isExactException(obj))
        return obj;
    const p = objPtr(obj);
    bt.objectDate(p).dval = epoch_ms;
    return obj;
}

pub fn js_date_valueOf(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    _ = argc;
    _ = argv;
    const p0 = value.js_get_object_class(ctx, this_val.*, c.JS_CLASS_DATE);
    if (p0 == null) {
        _ = throwTypeError(ctx, "not a Date object");
        return c.JS_EXCEPTION;
    }
    const p: *mc.JSObjectExt = @ptrCast(@alignCast(p0.?));
    return value.__JS_NewFloat64(ctx, bt.objectDate(p).dval);
}

// global

pub fn js_global_eval(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    _ = this_val;
    _ = argc;
    if (value.JS_IsString(ctx, argv[0]) == 0)
        return argv[0];
    const val = parser.JS_Parse2(ctx, argv[0], null, 0, "<input>", c.JS_EVAL_RETVAL);
    if (vt.isExactException(val))
        return val;
    return parser.JS_Run(ctx, val);
}

pub fn js_global_isNaN(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    _ = this_val;
    _ = argc;
    var d: f64 = undefined;
    if (runtime.JS_ToNumber(ctx, &d, argv[0]) != 0)
        return c.JS_EXCEPTION;
    return newBool(std.math.isNan(d));
}

pub fn js_global_isFinite(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    _ = this_val;
    _ = argc;
    var d: f64 = undefined;
    if (runtime.JS_ToNumber(ctx, &d, argv[0]) != 0)
        return c.JS_EXCEPTION;
    return newBool(std.math.isFinite(d));
}

// JSON

pub fn js_json_parse(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    _ = this_val;
    _ = argc;
    const val = runtime.JS_ToString(ctx, argv[0]);
    if (vt.isExactException(val))
        return val;
    return parser.JS_Parse2(ctx, val, null, 0, "<input>", c.JS_EVAL_JSON);
}

pub fn js_to_quoted_string(ctx: *c.JSContext, b: *vt.StringBuffer, str: c.JSValue) c_int {
    var i: c_int = 0;
    var char_buf: vt.JSStringCharBufExt = undefined;
    var str_ref: c.JSGCRef = undefined;
    var clen: usize = undefined;

    utils.pushValue(ctx, &str_ref, str);
    _ = value.string_buffer_putc(ctx, @ptrCast(b), '"');

    while (true) {
        // XXX: inefficient
        const p: *vt.JSStringExt = @ptrCast(@alignCast(value.get_string_ptr(ctx, @ptrCast(&char_buf), str_ref.val)));
        if (i >= @as(c_int, @intCast(vt.stringLen(p))))
            break;
        var ch: c_int = cutils.utf8_get(vt.stringBuf(p) + @as(usize, @intCast(i)), &clen);
        i += @intCast(clen);

        switch (ch) {
            '\t' => {
                ch = 't';
                _ = value.string_buffer_putc(ctx, @ptrCast(b), '\\');
                _ = value.string_buffer_putc(ctx, @ptrCast(b), ch);
            },
            '\r' => {
                ch = 'r';
                _ = value.string_buffer_putc(ctx, @ptrCast(b), '\\');
                _ = value.string_buffer_putc(ctx, @ptrCast(b), ch);
            },
            '\n' => {
                ch = 'n';
                _ = value.string_buffer_putc(ctx, @ptrCast(b), '\\');
                _ = value.string_buffer_putc(ctx, @ptrCast(b), ch);
            },
            0x08 => {
                ch = 'b';
                _ = value.string_buffer_putc(ctx, @ptrCast(b), '\\');
                _ = value.string_buffer_putc(ctx, @ptrCast(b), ch);
            },
            0x0c => {
                ch = 'f';
                _ = value.string_buffer_putc(ctx, @ptrCast(b), '\\');
                _ = value.string_buffer_putc(ctx, @ptrCast(b), ch);
            },
            '"', '\\' => {
                _ = value.string_buffer_putc(ctx, @ptrCast(b), '\\');
                _ = value.string_buffer_putc(ctx, @ptrCast(b), ch);
            },
            else => {
                if (ch < 32 or (ch >= 0xd800 and ch < 0xe000)) {
                    var hex_buf: [7]u8 = undefined;
                    _ = utils.js_snprintf(@ptrCast(&hex_buf), hex_buf.len, "\\u%04x", ch);
                    _ = value.string_buffer_puts(ctx, @ptrCast(b), @ptrCast(&hex_buf));
                } else {
                    _ = value.string_buffer_putc(ctx, @ptrCast(b), ch);
                }
            },
        }
    }
    _ = value.string_buffer_putc(ctx, @ptrCast(b), '"');
    _ = utils.popValue(ctx, &str_ref);
    return 0;
}

pub fn check_circular_ref(ctx: *c.JSContext, stack_top: [*]c.JSValue, val: c.JSValue) c_int {
    var sp: [*]c.JSValue = @ptrCast(mc.ctxExt(ctx).sp);
    while (@intFromPtr(sp) < @intFromPtr(stack_top)) {
        if (sp[0] == val) {
            _ = throwTypeError(ctx, "circular reference");
            return -1;
        }
        sp += @as(usize, @intCast(bt.JSON_REC_SIZE));
    }
    return 0;
}

// XXX: no space nor replacer
pub fn js_json_stringify(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    _ = this_val;
    _ = argc;
    var b: vt.StringBuffer = undefined;
    var idx: c_int = undefined;
    var ret: c_int = undefined;

    _ = value.string_buffer_push(ctx, @ptrCast(&b), 0);
    const stack_top: [*]c.JSValue = @ptrCast(mc.ctxExt(ctx).sp);

    ret = utils.JS_StackCheck(ctx, @intCast(bt.JSON_REC_SIZE));
    if (ret != 0) {
        mc.ctxExt(ctx).sp = @ptrCast(stack_top);
        _ = value.string_buffer_pop(ctx, @ptrCast(&b));
        return c.JS_EXCEPTION;
    }
    {
        var sp: [*]c.JSValue = @ptrCast(mc.ctxExt(ctx).sp);
        sp -= 1;
        sp[0] = c.JS_NULL; // keys
        sp -= 1;
        sp[0] = vt.newShortInt(0); // prop index
        sp -= 1;
        sp[0] = argv[0]; // object
        mc.ctxExt(ctx).sp = @ptrCast(sp);
    }

    stringify: while (@intFromPtr(mc.ctxExt(ctx).sp) < @intFromPtr(stack_top)) {
        const sp0: [*]c.JSValue = @ptrCast(mc.ctxExt(ctx).sp);
        const obj = sp0[0];
        if (value.JS_IsFunction(ctx, obj) != 0) {
            _ = value.string_buffer_concat(ctx, @ptrCast(&b), utils.js_get_atom(ctx, c.JS_ATOM_null));
            mc.ctxExt(ctx).sp = @ptrCast(sp0 + @as(usize, @intCast(bt.JSON_REC_SIZE)));
        } else if (value.JS_IsObject(ctx, obj) != 0) {
            var p = objPtr(obj);
            idx = vt.valueGetInt(sp0[1]);
            if (mc.objectClassId(p) == c.JS_CLASS_ARRAY) {
                // array
                if (idx == 0)
                    _ = value.string_buffer_putc(ctx, @ptrCast(&b), '[');
                p = objPtr(@as([*]c.JSValue, @ptrCast(mc.ctxExt(ctx).sp))[0]);
                if (idx >= @as(c_int, @intCast(p.u.array.len))) {
                    // end of array
                    _ = value.string_buffer_putc(ctx, @ptrCast(&b), ']');
                    const sp: [*]c.JSValue = @ptrCast(mc.ctxExt(ctx).sp);
                    mc.ctxExt(ctx).sp = @ptrCast(sp + @as(usize, @intCast(bt.JSON_REC_SIZE)));
                } else {
                    if (idx != 0)
                        _ = value.string_buffer_putc(ctx, @ptrCast(&b), ',');
                    @as([*]c.JSValue, @ptrCast(mc.ctxExt(ctx).sp))[1] = vt.newShortInt(idx + 1);
                    ret = utils.JS_StackCheck(ctx, @intCast(bt.JSON_REC_SIZE));
                    if (ret != 0)
                        break :stringify;
                    p = objPtr(@as([*]c.JSValue, @ptrCast(mc.ctxExt(ctx).sp))[0]);
                    const arr = valueArr(p.u.array.tab);
                    const val = vt.valueArrayItems(arr)[@intCast(idx)];
                    if (check_circular_ref(ctx, stack_top, val) != 0)
                        break :stringify;
                    var sp: [*]c.JSValue = @ptrCast(mc.ctxExt(ctx).sp);
                    sp -= 1;
                    sp[0] = c.JS_NULL;
                    sp -= 1;
                    sp[0] = vt.newShortInt(0);
                    sp -= 1;
                    sp[0] = val;
                    mc.ctxExt(ctx).sp = @ptrCast(sp);
                }
            } else {
                var val: c.JSValue = undefined;
                var val_ref: c.JSGCRef = undefined;
                var saved_idx: c_int = undefined;

                // object
                if (idx == 0) {
                    _ = value.string_buffer_putc(ctx, @ptrCast(&b), '{');
                    var dummy_this: c.JSValue = undefined;
                    const sp: [*]c.JSValue = @ptrCast(mc.ctxExt(ctx).sp);
                    sp[2] = builtins_main.js_object_keys(ctx, &dummy_this, 1, sp);
                    if (vt.isExactException(sp[2]))
                        break :stringify;
                }
                saved_idx = idx;
                var found = false;
                while (true) {
                    p = objPtr(@as([*]c.JSValue, @ptrCast(mc.ctxExt(ctx).sp))[2]); // keys
                    if (idx >= @as(c_int, @intCast(p.u.array.len))) {
                        // end of object
                        _ = value.string_buffer_putc(ctx, @ptrCast(&b), '}');
                        const sp: [*]c.JSValue = @ptrCast(mc.ctxExt(ctx).sp);
                        mc.ctxExt(ctx).sp = @ptrCast(sp + @as(usize, @intCast(bt.JSON_REC_SIZE)));
                        break;
                    } else {
                        const arr = valueArr(p.u.array.tab);
                        const prop = runtime.JS_ToPropertyKey(ctx, vt.valueArrayItems(arr)[@intCast(idx)]);
                        val = value.JS_GetProperty(ctx, @as([*]c.JSValue, @ptrCast(mc.ctxExt(ctx).sp))[0], prop);
                        if (vt.isExactException(val))
                            break :stringify;
                        // skip undefined properties
                        if (!vt.isUndefined(val)) {
                            found = true;
                            break;
                        }
                        idx += 1;
                    }
                }
                if (found) {
                    utils.pushValue(ctx, &val_ref, val);
                    if (saved_idx != 0)
                        _ = value.string_buffer_putc(ctx, @ptrCast(&b), ',');
                    @as([*]c.JSValue, @ptrCast(mc.ctxExt(ctx).sp))[1] = vt.newShortInt(idx + 1);
                    p = objPtr(@as([*]c.JSValue, @ptrCast(mc.ctxExt(ctx).sp))[2]);
                    const arr = valueArr(p.u.array.tab);
                    ret = js_to_quoted_string(ctx, &b, vt.valueArrayItems(arr)[@intCast(idx)]);
                    _ = value.string_buffer_putc(ctx, @ptrCast(&b), ':');
                    ret |= utils.JS_StackCheck(ctx, @intCast(bt.JSON_REC_SIZE));
                    val = utils.popValue(ctx, &val_ref);
                    if (ret != 0)
                        break :stringify;
                    if (check_circular_ref(ctx, stack_top, val) != 0)
                        break :stringify;
                    var sp: [*]c.JSValue = @ptrCast(mc.ctxExt(ctx).sp);
                    sp -= 1;
                    sp[0] = c.JS_NULL;
                    sp -= 1;
                    sp[0] = vt.newShortInt(0);
                    sp -= 1;
                    sp[0] = val;
                    mc.ctxExt(ctx).sp = @ptrCast(sp);
                }
            }
        } else if (value.JS_IsNumber(ctx, obj) != 0) {
            var d: f64 = undefined;
            ret = runtime.JS_ToNumber(ctx, &d, obj);
            if (ret != 0)
                break :stringify;
            if (!std.math.isFinite(d)) {
                _ = value.string_buffer_concat(ctx, @ptrCast(&b), utils.js_get_atom(ctx, c.JS_ATOM_null));
                const sp: [*]c.JSValue = @ptrCast(mc.ctxExt(ctx).sp);
                mc.ctxExt(ctx).sp = @ptrCast(sp + @as(usize, @intCast(bt.JSON_REC_SIZE)));
            } else {
                if (value.string_buffer_concat(ctx, @ptrCast(&b), obj) != 0)
                    break :stringify;
                const sp: [*]c.JSValue = @ptrCast(mc.ctxExt(ctx).sp);
                mc.ctxExt(ctx).sp = @ptrCast(sp + @as(usize, @intCast(bt.JSON_REC_SIZE)));
            }
        } else if (rt.valueGetSpecialTag(obj) == c.JS_TAG_BOOL) {
            if (value.string_buffer_concat(ctx, @ptrCast(&b), obj) != 0)
                break :stringify;
            const sp: [*]c.JSValue = @ptrCast(mc.ctxExt(ctx).sp);
            mc.ctxExt(ctx).sp = @ptrCast(sp + @as(usize, @intCast(bt.JSON_REC_SIZE)));
        } else if (value.JS_IsString(ctx, obj) != 0) {
            if (js_to_quoted_string(ctx, &b, obj) != 0)
                break :stringify;
            const sp: [*]c.JSValue = @ptrCast(mc.ctxExt(ctx).sp);
            mc.ctxExt(ctx).sp = @ptrCast(sp + @as(usize, @intCast(bt.JSON_REC_SIZE)));
        } else {
            _ = value.string_buffer_concat(ctx, @ptrCast(&b), utils.js_get_atom(ctx, c.JS_ATOM_null));
            const sp: [*]c.JSValue = @ptrCast(mc.ctxExt(ctx).sp);
            mc.ctxExt(ctx).sp = @ptrCast(sp + @as(usize, @intCast(bt.JSON_REC_SIZE)));
        }
    } else {
        return value.string_buffer_pop(ctx, @ptrCast(&b));
    }

    mc.ctxExt(ctx).sp = @ptrCast(stack_top);
    _ = value.string_buffer_pop(ctx, @ptrCast(&b));
    return c.JS_EXCEPTION;
}
