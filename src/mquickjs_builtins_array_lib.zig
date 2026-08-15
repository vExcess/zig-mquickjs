//
// Micro QuickJS engine builtins — Array (internal submodule)
//
// Copyright (c) 2017-2025 Fabrice Bellard
// Copyright (c) 2017-2025 Charlie Gordon
//
// Ported from C to Zig by Composer 2.5 + Grok 4.6 + Gemini 3 Pro + VExcess
//

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

fn newBool(v: bool) c.JSValue {
    return rt.newBool(v);
}

fn minInt(a: c_int, b: c_int) c_int {
    return if (a < b) a else b;
}

fn maxInt(a: c_int, b: c_int) c_int {
    return if (a > b) a else b;
}

fn memmoveValues(dest: [*]c.JSValue, src: [*]c.JSValue, n: usize) void {
    if (n == 0 or @intFromPtr(dest) == @intFromPtr(src)) return;
    @memmove(dest[0..n], src[0..n]);
}

pub fn js_get_array(ctx: *c.JSContext, obj: c.JSValue) ?*mc.JSObjectExt {
    const p0 = value.js_get_object_class(ctx, obj, c.JS_CLASS_ARRAY) orelse {
        _ = throwTypeError(ctx, "not an array");
        return null;
    };
    return @ptrCast(@alignCast(p0));
}

pub fn js_array_get_length(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    _ = argc;
    _ = argv;
    const p = js_get_array(ctx, this_val.*) orelse return c.JS_EXCEPTION;
    return vt.newShortInt(@intCast(p.u.array.len));
}

pub fn js_array_resize(ctx: *c.JSContext, this_val: *c.JSValue, new_len: c_int) c_int {
    if (new_len < 0 or new_len > vt.JS_SHORTINT_MAX) {
        _ = throwTypeError(ctx, "invalid array length");
        return -1;
    }
    var p = objPtr(this_val.*);
    if (new_len < p.u.array.len) {
        const arr = valueArr(p.u.array.tab);
        if (new_len < @divTrunc(vt.valueArraySize(arr), 2) and vt.valueArraySize(arr) >= 4) {
            value.js_shrink_value_array(ctx, &p.u.array.tab, new_len);
            p = objPtr(this_val.*);
        } else {
            var i = new_len;
            while (i < @as(c_int, @intCast(p.u.array.len))) : (i += 1)
                vt.valueArrayItems(arr)[@intCast(i)] = c.JS_UNDEFINED;
        }
    } else if (new_len > p.u.array.len) {
        const new_tab = value.js_resize_value_array(ctx, p.u.array.tab, new_len);
        if (vt.isExactException(new_tab))
            return -1;
        p = objPtr(this_val.*);
        p.u.array.tab = new_tab;
        const arr = valueArr(p.u.array.tab);
        var i: c_int = @intCast(p.u.array.len);
        while (i < new_len) : (i += 1)
            vt.valueArrayItems(arr)[@intCast(i)] = c.JS_UNDEFINED;
    }
    p.u.array.len = @intCast(new_len);
    return 0;
}

pub fn js_array_set_length(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    _ = argc;
    if (js_get_array(ctx, this_val.*) == null)
        return c.JS_EXCEPTION;
    var new_len: c_int = undefined;
    if (runtime.JS_ToInt32(ctx, &new_len, argv[0]) != 0)
        return c.JS_EXCEPTION;
    if (js_array_resize(ctx, this_val, new_len) != 0)
        return c.JS_EXCEPTION;
    return c.JS_UNDEFINED;
}

pub fn js_array_constructor(ctx: *c.JSContext, this_val: *c.JSValue, argc_in: c_int, argv: [*]c.JSValue) c.JSValue {
    _ = this_val;
    var argc = argc_in;
    argc &= ~c.FRAME_CF_CTOR;

    var len: c_int = undefined;
    var has_init: bool = undefined;
    if (argc == 1 and value.JS_IsNumber(ctx, argv[0]) != 0) {
        if (runtime.JS_ToInt32(ctx, &len, argv[0]) != 0)
            return c.JS_EXCEPTION;
        has_init = false;
    } else {
        len = argc;
        has_init = true;
    }

    if (len < 0 or len > vt.JS_SHORTINT_MAX)
        return throwRangeError(ctx, "invalid array length");
    const obj = value.JS_NewArray(ctx, len);
    if (vt.isExactException(obj))
        return obj;
    const p = objPtr(obj);
    p.u.array.len = @intCast(len);

    if (has_init) {
        const arr = valueArr(p.u.array.tab);
        var i: c_int = 0;
        while (i < argc) : (i += 1) {
            vt.valueArrayItems(arr)[@intCast(i)] = argv[@intCast(i)];
        }
    }
    return obj;
}

pub fn js_array_push(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue, is_unshift: c_int) c.JSValue {
    var p = js_get_array(ctx, this_val.*) orelse return c.JS_EXCEPTION;
    var from: c_int = @intCast(p.u.array.len);
    const new_len = from + argc;
    if (new_len > vt.JS_SHORTINT_MAX)
        return throwRangeError(ctx, "invalid array length");
    const new_tab = value.js_resize_value_array(ctx, p.u.array.tab, new_len);
    if (vt.isExactException(new_tab))
        return c.JS_EXCEPTION;
    p = objPtr(this_val.*);
    p.u.array.tab = new_tab;
    p.u.array.len = @intCast(new_len);
    const arr = valueArr(p.u.array.tab);
    if (is_unshift != 0 and argc > 0) {
        memmoveValues(vt.valueArrayItems(arr) + @as(usize, @intCast(argc)), vt.valueArrayItems(arr), @intCast(from));
        from = 0;
    }
    var i: c_int = 0;
    while (i < argc) : (i += 1) {
        vt.valueArrayItems(arr)[@intCast(from + i)] = argv[@intCast(i)];
    }
    return vt.newShortInt(new_len);
}

pub fn js_array_pop(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    _ = argc;
    _ = argv;
    const p = js_get_array(ctx, this_val.*) orelse return c.JS_EXCEPTION;
    if (p.u.array.len > 0) {
        const arr = valueArr(p.u.array.tab);
        p.u.array.len -= 1;
        return vt.valueArrayItems(arr)[@intCast(p.u.array.len)];
    }
    return c.JS_UNDEFINED;
}

pub fn js_array_shift(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    _ = argc;
    _ = argv;
    const p = js_get_array(ctx, this_val.*) orelse return c.JS_EXCEPTION;
    if (p.u.array.len > 0) {
        const arr = valueArr(p.u.array.tab);
        const ret = vt.valueArrayItems(arr)[0];
        p.u.array.len -= 1;
        memmoveValues(vt.valueArrayItems(arr), vt.valueArrayItems(arr) + 1, @intCast(p.u.array.len));
        return ret;
    }
    return c.JS_UNDEFINED;
}

pub fn js_array_join(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    var sep_ref: c.JSGCRef = undefined;
    var b: vt.StringBuffer = undefined;

    if (value.JS_IsObject(ctx, this_val.*) == 0)
        return value.JS_ThrowTypeErrorNotAnObject(ctx);
    var p = objPtr(this_val.*);
    const is_array = mc.objectClassId(p) == c.JS_CLASS_ARRAY;
    var len: u32 = undefined;
    if (is_array) {
        len = p.u.array.len;
    } else {
        if (runtime.js_get_length32(ctx, &len, this_val.*) != 0)
            return c.JS_EXCEPTION;
    }

    var sep: c.JSValue = undefined;
    if (argc > 0 and !vt.isUndefined(argv[0])) {
        sep = runtime.JS_ToString(ctx, argv[0]);
        if (vt.isExactException(sep))
            return sep;
    } else {
        sep = value.JS_NewStringChar(',');
    }
    utils.pushValue(ctx, &sep_ref, sep);

    _ = value.string_buffer_push(ctx, @ptrCast(&b), 0);
    var failed = false;
    var i: u32 = 0;
    while (i < len) : (i += 1) {
        if (i > 0) {
            if (value.string_buffer_concat(ctx, @ptrCast(&b), sep_ref.val) != 0) {
                failed = true;
                break;
            }
        }
        var val: c.JSValue = undefined;
        if (is_array) {
            p = objPtr(this_val.*);
            const arr = valueArr(p.u.array.tab);
            if (i < p.u.array.len)
                val = vt.valueArrayItems(arr)[@intCast(i)]
            else
                val = c.JS_UNDEFINED;
        } else {
            val = value.JS_GetPropertyUint32(ctx, this_val.*, i);
            if (vt.isExactException(val)) {
                failed = true;
                break;
            }
        }
        if (!vt.isUndefined(val) and !mc.isNull(val)) {
            if (value.string_buffer_concat(ctx, @ptrCast(&b), val) != 0) {
                failed = true;
                break;
            }
        }
    }
    if (failed) {
        _ = value.string_buffer_pop(ctx, @ptrCast(&b));
        _ = utils.popValue(ctx, &sep_ref);
        return c.JS_EXCEPTION;
    }
    const val = value.string_buffer_pop(ctx, @ptrCast(&b));
    _ = utils.popValue(ctx, &sep_ref);
    return val;
}

pub fn js_array_toString(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    _ = argc;
    _ = argv;
    var dummy: [1]c.JSValue = undefined;
    return js_array_join(ctx, this_val, 0, &dummy);
}

pub fn JS_IsArray(ctx: *c.JSContext, obj: c.JSValue) c.JS_BOOL {
    const p = value.js_get_object_class(ctx, obj, c.JS_CLASS_ARRAY);
    return @as(c.JS_BOOL, @intFromBool(p != null));
}

pub fn js_array_isArray(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    _ = this_val;
    _ = argc;
    return newBool(JS_IsArray(ctx, argv[0]) != 0);
}

pub fn js_array_reverse(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    _ = argc;
    _ = argv;
    const p = js_get_array(ctx, this_val.*) orelse return c.JS_EXCEPTION;
    const len: c_int = @intCast(p.u.array.len);
    const arr = valueArr(p.u.array.tab);
    runtime.js_reverse_val(vt.valueArrayItems(arr), len);
    return this_val.*;
}

pub fn js_array_concat(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    var p = js_get_array(ctx, this_val.*) orelse return c.JS_EXCEPTION;
    var len64: i64 = @intCast(p.u.array.len);
    var i: c_int = 0;
    while (i < argc) : (i += 1) {
        if (value.js_get_object_class(ctx, argv[@intCast(i)], c.JS_CLASS_ARRAY)) |p0| {
            p = @ptrCast(@alignCast(p0));
            len64 += @as(i64, @intCast(p.u.array.len));
        } else {
            len64 += 1;
        }
    }
    if (len64 > vt.JS_SHORTINT_MAX)
        return throwTypeError(ctx, "Array loo long");
    const len: c_int = @intCast(len64);

    const obj = value.JS_NewArray(ctx, len);
    if (vt.isExactException(obj))
        return obj;
    p = objPtr(obj);
    const arr = valueArr(p.u.array.tab);

    var pos: c_int = 0;
    i = -1;
    while (i < argc) : (i += 1) {
        const val = if (i == -1) this_val.* else argv[@intCast(i)];
        if (value.js_get_object_class(ctx, val, c.JS_CLASS_ARRAY)) |p0| {
            p = @ptrCast(@alignCast(p0));
            const arr1 = valueArr(p.u.array.tab);
            var j: c_int = 0;
            while (j < @as(c_int, @intCast(p.u.array.len))) : (j += 1)
                vt.valueArrayItems(arr)[@intCast(pos + j)] = vt.valueArrayItems(arr1)[@intCast(j)];
            pos += @intCast(p.u.array.len);
        } else {
            vt.valueArrayItems(arr)[@intCast(pos)] = val;
            pos += 1;
        }
    }
    return obj;
}

pub fn js_array_indexOf(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue, is_lastIndexOf: c_int) c.JSValue {
    var p = js_get_array(ctx, this_val.*) orelse return c.JS_EXCEPTION;
    var len: c_int = @intCast(p.u.array.len);
    var n: c_int = if (is_lastIndexOf != 0) len - 1 else 0;
    if (argc > 1) {
        if (runtime.JS_ToInt32Clamp(ctx, &n, argv[1], -is_lastIndexOf, len - is_lastIndexOf, len) != 0)
            return c.JS_EXCEPTION;
    }
    p = objPtr(this_val.*);
    len = @intCast(p.u.array.len);
    const arr = valueArr(p.u.array.tab);
    var res: c_int = -1;
    if (is_lastIndexOf != 0) {
        n = minInt(n, len - 1);
        while (n >= 0) : (n -= 1) {
            if (runtime.js_strict_eq(ctx, argv[0], vt.valueArrayItems(arr)[@intCast(n)]) != 0) {
                res = n;
                break;
            }
        }
    } else {
        while (n < len) : (n += 1) {
            if (runtime.js_strict_eq(ctx, argv[0], vt.valueArrayItems(arr)[@intCast(n)]) != 0) {
                res = n;
                break;
            }
        }
    }
    return vt.newShortInt(res);
}

pub fn js_array_slice(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    _ = argc;
    var p = js_get_array(ctx, this_val.*) orelse return c.JS_EXCEPTION;
    var len: c_int = @intCast(p.u.array.len);

    var start: c_int = undefined;
    if (runtime.JS_ToInt32Clamp(ctx, &start, argv[0], 0, len, len) != 0)
        return c.JS_EXCEPTION;
    var final = len;
    if (!vt.isUndefined(argv[1])) {
        if (runtime.JS_ToInt32Clamp(ctx, &final, argv[1], 0, len, len) != 0)
            return c.JS_EXCEPTION;
    }
    p = objPtr(this_val.*);
    len = @intCast(p.u.array.len);
    final = minInt(final, len);

    const obj = value.JS_NewArray(ctx, maxInt(final - start, 0));
    if (vt.isExactException(obj))
        return obj;
    p = objPtr(this_val.*);
    const arr = valueArr(p.u.array.tab);
    const p1 = objPtr(obj);
    const arr1 = valueArr(p1.u.array.tab);
    var k = start;
    while (k < final) : (k += 1) {
        vt.valueArrayItems(arr1)[@intCast(k - start)] = vt.valueArrayItems(arr)[@intCast(k)];
    }
    return obj;
}

pub fn js_array_splice(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    var obj_ref: c.JSGCRef = undefined;

    var p = js_get_array(ctx, this_val.*) orelse return c.JS_EXCEPTION;
    const len: c_int = @intCast(p.u.array.len);

    var start: c_int = undefined;
    if (runtime.JS_ToInt32Clamp(ctx, &start, argv[0], 0, len, len) != 0)
        return c.JS_EXCEPTION;

    var item_count: c_int = undefined;
    var del_count: c_int = undefined;
    if (argc == 0) {
        item_count = 0;
        del_count = 0;
    } else if (argc == 1) {
        item_count = 0;
        del_count = len - start;
    } else {
        item_count = argc - 2;
        if (runtime.JS_ToInt32Clamp(ctx, &del_count, argv[1], 0, len - start, 0) != 0)
            return c.JS_EXCEPTION;
    }
    const new_len = len + item_count - del_count;

    var obj = value.JS_NewArray(ctx, del_count);
    if (vt.isExactException(obj))
        return obj;
    p = objPtr(this_val.*);
    if (p.u.array.len != @as(c_uint, @intCast(len)))
        return throwTypeError(ctx, "array length was modified");
    var arr = valueArr(p.u.array.tab);
    const p1 = objPtr(obj);
    const arr1 = valueArr(p1.u.array.tab);

    var i: c_int = 0;
    while (i < del_count) : (i += 1) {
        vt.valueArrayItems(arr1)[@intCast(i)] = vt.valueArrayItems(arr)[@intCast(start + i)];
    }

    if (item_count != del_count) {
        if (del_count > item_count) {
            memmoveValues(
                vt.valueArrayItems(arr) + @as(usize, @intCast(start + item_count)),
                vt.valueArrayItems(arr) + @as(usize, @intCast(start + del_count)),
                @intCast(len - (start + del_count)),
            );
        }
        utils.pushValue(ctx, &obj_ref, obj);
        const ret = js_array_resize(ctx, this_val, new_len);
        obj = utils.popValue(ctx, &obj_ref);
        if (ret != 0)
            return c.JS_EXCEPTION;
        p = objPtr(this_val.*);
        arr = valueArr(p.u.array.tab);
        if (del_count < item_count) {
            memmoveValues(
                vt.valueArrayItems(arr) + @as(usize, @intCast(start + item_count)),
                vt.valueArrayItems(arr) + @as(usize, @intCast(start + del_count)),
                @intCast(len - (start + del_count)),
            );
        }
    }

    i = 0;
    while (i < item_count) : (i += 1)
        vt.valueArrayItems(arr)[@intCast(start + i)] = argv[@intCast(2 + i)];

    return obj;
}

pub fn js_array_every(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue, special: c_int) c.JSValue {
    var val_ref: c.JSGCRef = undefined;
    var ret_ref: c.JSGCRef = undefined;

    const p0 = js_get_array(ctx, this_val.*) orelse return c.JS_EXCEPTION;
    const len: c_int = @intCast(p0.u.array.len);

    const pfunc = &argv[0];
    var pthis_arg: ?*c.JSValue = null;
    if (argc > 1)
        pthis_arg = &argv[1];

    if (value.JS_IsFunction(ctx, pfunc.*) == 0)
        return throwTypeError(ctx, "not a function");

    var ret: c.JSValue = switch (special) {
        bt.js_special_every => c.JS_TRUE,
        bt.js_special_some => c.JS_FALSE,
        bt.js_special_map => blk: {
            const mapped = value.JS_NewArray(ctx, len);
            if (vt.isExactException(mapped))
                return c.JS_EXCEPTION;
            break :blk mapped;
        },
        bt.js_special_filter => blk: {
            const filtered = value.JS_NewArray(ctx, 0);
            if (vt.isExactException(filtered))
                return c.JS_EXCEPTION;
            break :blk filtered;
        },
        else => c.JS_UNDEFINED,
    };
    var n: c_int = 0;

    utils.pushValue(ctx, &ret_ref, ret);
    var k: c_int = 0;
    while (k < len) : (k += 1) {
        if (utils.JS_StackCheck(ctx, 5) != 0) {
            ret_ref.val = c.JS_EXCEPTION;
            break;
        }

        const p = objPtr(this_val.*);
        const arr = valueArr(p.u.array.tab);
        if (k >= @as(c_int, @intCast(p.u.array.len)))
            break;
        var val = vt.valueArrayItems(arr)[@intCast(k)];

        runtime.JS_PushArg(ctx, this_val.*);
        runtime.JS_PushArg(ctx, vt.newShortInt(k));
        runtime.JS_PushArg(ctx, val);
        runtime.JS_PushArg(ctx, pfunc.*);
        runtime.JS_PushArg(ctx, if (pthis_arg) |pa| pa.* else c.JS_UNDEFINED);
        utils.pushValue(ctx, &val_ref, val);
        var res = runtime.JS_Call(ctx, 3);
        val = utils.popValue(ctx, &val_ref);
        if (vt.isExactException(res)) {
            ret_ref.val = c.JS_EXCEPTION;
            break;
        }

        switch (special) {
            bt.js_special_every => {
                if (value.JS_ToBool(ctx, res) == 0) {
                    ret_ref.val = c.JS_FALSE;
                    break;
                }
            },
            bt.js_special_some => {
                if (value.JS_ToBool(ctx, res) != 0) {
                    ret_ref.val = c.JS_TRUE;
                    break;
                }
            },
            bt.js_special_map => {
                res = value.JS_SetPropertyUint32(ctx, ret_ref.val, @intCast(k), res);
                if (vt.isExactException(res)) {
                    ret_ref.val = c.JS_EXCEPTION;
                    break;
                }
            },
            bt.js_special_filter => {
                if (value.JS_ToBool(ctx, res) != 0) {
                    res = value.JS_SetPropertyUint32(ctx, ret_ref.val, @intCast(n), val);
                    n += 1;
                    if (vt.isExactException(res)) {
                        ret_ref.val = c.JS_EXCEPTION;
                        break;
                    }
                }
            },
            else => {},
        }
    }
    ret = utils.popValue(ctx, &ret_ref);
    return ret;
}

pub fn js_array_reduce(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue, special: c_int) c.JSValue {
    var acc_ref: c.JSGCRef = undefined;

    var p = js_get_array(ctx, this_val.*) orelse return c.JS_EXCEPTION;
    const len: c_int = @intCast(p.u.array.len);
    const pfunc = &argv[0];

    if (value.JS_IsFunction(ctx, pfunc.*) == 0)
        return throwTypeError(ctx, "not a function");

    var k: c_int = 0;
    var acc: c.JSValue = undefined;
    if (argc > 1) {
        acc = argv[1];
    } else {
        if (len == 0)
            return throwTypeError(ctx, "empty array");
        const k1: c_int = if (special == bt.js_special_reduceRight) len - k - 1 else k;
        const arr = valueArr(p.u.array.tab);
        acc = vt.valueArrayItems(arr)[@intCast(k1)];
        k += 1;
    }
    while (k < len) : (k += 1) {
        utils.pushValue(ctx, &acc_ref, acc);
        const ret = utils.JS_StackCheck(ctx, 6);
        acc = utils.popValue(ctx, &acc_ref);
        if (ret != 0)
            return c.JS_EXCEPTION;

        const k1: c_int = if (special == bt.js_special_reduceRight) len - k - 1 else k;
        p = objPtr(this_val.*);
        const arr = valueArr(p.u.array.tab);
        if (k1 >= @as(c_int, @intCast(p.u.array.len)))
            break;

        runtime.JS_PushArg(ctx, this_val.*);
        runtime.JS_PushArg(ctx, vt.newShortInt(k1));
        runtime.JS_PushArg(ctx, vt.valueArrayItems(arr)[@intCast(k1)]);
        runtime.JS_PushArg(ctx, acc);
        runtime.JS_PushArg(ctx, pfunc.*);
        runtime.JS_PushArg(ctx, c.JS_UNDEFINED);
        acc = runtime.JS_Call(ctx, 4);
        if (vt.isExactException(acc))
            return c.JS_EXCEPTION;
    }
    return acc;
}


pub fn js_array_sort_cmp(idx1: usize, idx2: usize, opaque_ptr: *anyopaque) c_int {
    const s: *bt.JSArraySortContext = @ptrCast(@alignCast(opaque_ptr));
    const ctx = s.ctx;

    if (s.exception != 0)
        return 0;

    var arr = valueArr(s.parr.*);
    const cmp: c_int = blk: {
        if (s.pfunc) |pfunc| {
            const items = vt.valueArrayItems(arr);
            if (items[2 * idx1] == items[2 * idx2])
                break :blk 0;
            if (utils.JS_StackCheck(ctx, 4) != 0) {
                s.exception = 1;
                return 0;
            }
            arr = valueArr(s.parr.*);

            runtime.JS_PushArg(ctx, vt.valueArrayItems(arr)[2 * idx2]);
            runtime.JS_PushArg(ctx, vt.valueArrayItems(arr)[2 * idx1]);
            runtime.JS_PushArg(ctx, pfunc.*);
            runtime.JS_PushArg(ctx, c.JS_UNDEFINED);
            const res = runtime.JS_Call(ctx, 2);
            if (vt.isExactException(res))
                return @truncate(c.JS_EXCEPTION);
            if (mc.isInt(res)) {
                const val = vt.valueGetInt(res);
                break :blk @as(c_int, @intFromBool(val > 0)) - @as(c_int, @intFromBool(val < 0));
            } else {
                var val: f64 = undefined;
                if (runtime.JS_ToNumber(ctx, &val, res) != 0) {
                    s.exception = 1;
                    return 0;
                }
                break :blk @as(c_int, @intFromBool(val > 0)) - @as(c_int, @intFromBool(val < 0));
            }
        } else {
            var str1_ref: c.JSGCRef = undefined;
            var str1 = vt.valueArrayItems(arr)[2 * idx1];
            if (value.JS_IsString(ctx, str1) == 0) {
                str1 = runtime.JS_ToString(ctx, str1);
                if (vt.isExactException(str1)) {
                    s.exception = 1;
                    return 0;
                }
                arr = valueArr(s.parr.*);
            }
            var str2 = vt.valueArrayItems(arr)[2 * idx2];
            if (value.JS_IsString(ctx, str2) == 0) {
                utils.pushValue(ctx, &str1_ref, str1);
                str2 = runtime.JS_ToString(ctx, str2);
                str1 = utils.popValue(ctx, &str1_ref);
                if (vt.isExactException(str2)) {
                    s.exception = 1;
                    return 0;
                }
            }
            break :blk value.js_string_compare(ctx, str1, str2);
        }
    };
    if (cmp != 0)
        return cmp;
    arr = valueArr(s.parr.*);
    const j1 = vt.valueGetInt(vt.valueArrayItems(arr)[2 * idx1 + 1]);
    const j2 = vt.valueGetInt(vt.valueArrayItems(arr)[2 * idx2 + 1]);
    return @as(c_int, @intFromBool(j1 > j2)) - @as(c_int, @intFromBool(j1 < j2));
}

pub fn js_array_sort_swap(idx1: usize, idx2: usize, opaque_ptr: *anyopaque) void {
    const s: *bt.JSArraySortContext = @ptrCast(@alignCast(opaque_ptr));
    const arr = valueArr(s.parr.*);
    const tab = vt.valueArrayItems(arr);
    var tmp = tab[2 * idx1];
    tab[2 * idx1] = tab[2 * idx2];
    tab[2 * idx2] = tmp;

    tmp = tab[2 * idx1 + 1];
    tab[2 * idx1 + 1] = tab[2 * idx2 + 1];
    tab[2 * idx2 + 1] = tmp;
}

pub fn js_array_sort(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    _ = argc;
    var pfunc: ?*c.JSValue = &argv[0];
    var tab_val_ref: c.JSGCRef = undefined;
    var ss: bt.JSArraySortContext = undefined;
    const s = &ss;

    if (!vt.isUndefined(pfunc.?.*)) {
        if (value.JS_IsFunction(ctx, pfunc.?.*) == 0)
            return throwTypeError(ctx, "not a function");
    } else {
        pfunc = null;
    }
    var p = js_get_array(ctx, this_val.*) orelse return c.JS_EXCEPTION;

    var len: c_int = @intCast(p.u.array.len);
    const tab0 = value.js_alloc_value_array(ctx, 0, len * 2) orelse return c.JS_EXCEPTION;
    var tab: *vt.JSValueArrayExt = @ptrCast(@alignCast(tab0));

    p = objPtr(this_val.*);
    var arr = valueArr(p.u.array.tab);
    var n: c_int = 0;
    var i: c_int = 0;
    while (i < len) : (i += 1) {
        if (!vt.isUndefined(vt.valueArrayItems(arr)[@intCast(i)])) {
            vt.valueArrayItems(tab)[@intCast(2 * n)] = vt.valueArrayItems(arr)[@intCast(i)];
            vt.valueArrayItems(tab)[@intCast(2 * n + 1)] = vt.newShortInt(i);
            n += 1;
        }
    }
    var tab_val = mc.valueFromPtr(tab);

    utils.pushValue(ctx, &tab_val_ref, tab_val);
    s.ctx = ctx;
    s.exception = 0;
    s.parr = &tab_val_ref.val;
    s.pfunc = pfunc;
    regexp.rqsort_idx(@intCast(n), js_array_sort_cmp, js_array_sort_swap, @ptrCast(s));
    tab_val = utils.popValue(ctx, &tab_val_ref);
    tab = valueArr(tab_val);
    if (s.exception != 0) {
        utils.js_free(ctx, tab);
        return c.JS_EXCEPTION;
    }

    p = objPtr(this_val.*);
    arr = valueArr(p.u.array.tab);
    len = minInt(len, @intCast(p.u.array.len));
    i = 0;
    while (i < len) : (i += 1) {
        vt.valueArrayItems(arr)[@intCast(i)] = vt.valueArrayItems(tab)[@intCast(2 * i)];
    }
    utils.js_free(ctx, tab);
    return this_val.*;
}
