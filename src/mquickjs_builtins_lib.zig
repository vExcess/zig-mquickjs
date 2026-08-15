//
// Micro QuickJS engine builtins (shared implementation)
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
pub const c = bt.c;

const JSParseState = bt.JSParseState;
const REOP = bt.REOP;
const reopcode_info = bt.reopcode_info_data;

const parser = @import("mquickjs_parser_lib.zig");
const lexer = @import("mquickjs_lexer_lib.zig");
const value = @import("mquickjs_value_lib.zig");
const runtime = @import("mquickjs_runtime_lib.zig");

const regexp = @import("mquickjs_builtins_regexp_lib.zig");
const stdlib = @import("mquickjs_builtins_std_lib.zig");

pub const re_parse_alternative = regexp.re_parse_alternative;
pub const re_parse_disjunction = regexp.re_parse_disjunction;
pub const js_parse_regexp = regexp.js_parse_regexp;
pub const js_parse_regexp_flags = regexp.js_parse_regexp_flags;
pub const dump_regexp = regexp.dump_regexp;
pub const js_regexp_get_lastIndex = regexp.js_regexp_get_lastIndex;
pub const js_regexp_get_source = regexp.js_regexp_get_source;
pub const js_regexp_set_lastIndex = regexp.js_regexp_set_lastIndex;
pub const js_regexp_get_flags = regexp.js_regexp_get_flags;
pub const js_regexp_constructor = regexp.js_regexp_constructor;
pub const js_regexp_exec = regexp.js_regexp_exec;
pub const rqsort_idx = regexp.rqsort_idx;


pub const js_fmin = stdlib.js_fmin;
pub const js_fmax = stdlib.js_fmax;
pub const js_math_min_max = stdlib.js_math_min_max;
pub const js_math_sign = stdlib.js_math_sign;
pub const js_math_fround = stdlib.js_math_fround;
pub const js_math_imul = stdlib.js_math_imul;
pub const js_math_clz32 = stdlib.js_math_clz32;
pub const js_math_atan2 = stdlib.js_math_atan2;
pub const js_math_pow = stdlib.js_math_pow;
pub const js_math_random = stdlib.js_math_random;
pub const xorshift64star = stdlib.xorshift64star;
pub const JS_ToIndex = stdlib.JS_ToIndex;
pub const js_array_buffer_alloc = stdlib.js_array_buffer_alloc;
pub const js_array_buffer_constructor = stdlib.js_array_buffer_constructor;
pub const js_array_buffer_get_byteLength = stdlib.js_array_buffer_get_byteLength;
pub const js_typed_array_base_constructor = stdlib.js_typed_array_base_constructor;
pub const js_typed_array_constructor_obj = stdlib.js_typed_array_constructor_obj;
pub const js_typed_array_constructor = stdlib.js_typed_array_constructor;
pub const get_typed_array = stdlib.get_typed_array;
pub const js_typed_array_get_length = stdlib.js_typed_array_get_length;
pub const js_typed_array_subarray = stdlib.js_typed_array_subarray;
pub const js_typed_array_set = stdlib.js_typed_array_set;
pub const JS_NewDate = stdlib.JS_NewDate;
pub const js_date_valueOf = stdlib.js_date_valueOf;
pub const js_global_eval = stdlib.js_global_eval;
pub const js_global_isNaN = stdlib.js_global_isNaN;
pub const js_global_isFinite = stdlib.js_global_isFinite;
pub const js_json_parse = stdlib.js_json_parse;
pub const js_to_quoted_string = stdlib.js_to_quoted_string;
pub const check_circular_ref = stdlib.check_circular_ref;
pub const js_json_stringify = stdlib.js_json_stringify;

const array = @import("mquickjs_builtins_array_lib.zig");

pub const js_get_array = array.js_get_array;
pub const js_array_get_length = array.js_array_get_length;
pub const js_array_resize = array.js_array_resize;
pub const js_array_set_length = array.js_array_set_length;
pub const js_array_constructor = array.js_array_constructor;
pub const js_array_push = array.js_array_push;
pub const js_array_pop = array.js_array_pop;
pub const js_array_shift = array.js_array_shift;
pub const js_array_join = array.js_array_join;
pub const js_array_toString = array.js_array_toString;
pub const JS_IsArray = array.JS_IsArray;
pub const js_array_isArray = array.js_array_isArray;
pub const js_array_reverse = array.js_array_reverse;
pub const js_array_concat = array.js_array_concat;
pub const js_array_indexOf = array.js_array_indexOf;
pub const js_array_slice = array.js_array_slice;
pub const js_array_splice = array.js_array_splice;
pub const js_array_every = array.js_array_every;
pub const js_array_reduce = array.js_array_reduce;
pub const js_array_sort_cmp = array.js_array_sort_cmp;
pub const js_array_sort_swap = array.js_array_sort_swap;
pub const js_array_sort = array.js_array_sort;

const string = @import("mquickjs_builtins_string_lib.zig");

pub const js_string_get_length = string.js_string_get_length;
pub const js_string_set_length = string.js_string_set_length;
pub const js_string_slice = string.js_string_slice;
pub const js_string_substring = string.js_string_substring;
pub const js_string_charAt = string.js_string_charAt;
pub const js_string_constructor = string.js_string_constructor;
pub const js_string_fromCharCode = string.js_string_fromCharCode;
pub const js_string_concat = string.js_string_concat;
pub const js_string_indexOf = string.js_string_indexOf;
pub const js_string_indexof = string.js_string_indexof;
pub const js_string_toLowerCase = string.js_string_toLowerCase;
pub const js_string_trim = string.js_string_trim;
pub const js_string_toString = string.js_string_toString;
pub const js_string_repeat = string.js_string_repeat;
pub const js_string_replace = string.js_string_replace;
pub const js_string_split = string.js_string_split;
pub const js_string_match = string.js_string_match;
pub const js_string_search = string.js_string_search;


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

fn newTailCall(val: c_int) c.JSValue {
    return vt.newTailCall(val);
}

fn float64AsUint64(d: f64) u64 {
    return @bitCast(d);
}

fn uint64AsFloat64(u: u64) f64 {
    return @bitCast(u);
}

fn parseCall(cur_state: c_int, func: c_int, param: c_int) c_int {
    return cur_state | (func << 8) | (param << 16);
}

fn parsePushInt(s: *JSParseState, v: c_int) void {
    parser.js_parse_push_val(s, vt.newShortInt(v));
}

fn parsePopInt(s: *JSParseState) c_int {
    return vt.valueGetInt(parser.js_parse_pop_val(s));
}

fn isDigit(ch: u8) bool {
    return ch >= '0' and ch <= '9';
}

fn minInt(a: c_int, b: c_int) c_int {
    return if (a < b) a else b;
}

fn maxInt(a: c_int, b: c_int) c_int {
    return if (a > b) a else b;
}

// Function

pub fn js_function_constructor(ctx: *c.JSContext, this_val: *c.JSValue, argc_in: c_int, argv: [*]c.JSValue) c.JSValue {
    _ = this_val;
    var argc = argc_in;
    var b: vt.StringBuffer = undefined;
    argc &= ~c.FRAME_CF_CTOR;
    _ = value.string_buffer_push(ctx, @ptrCast(&b), 0);
    _ = value.string_buffer_puts(ctx, @ptrCast(&b), "(function anonymous(");
    const n = argc - 1;
    var i: c_int = 0;
    while (i < n) : (i += 1) {
        if (i != 0) {
            _ = value.string_buffer_putc(ctx, @ptrCast(&b), ',');
        }
        if (value.string_buffer_concat(ctx, @ptrCast(&b), argv[@intCast(i)]) != 0)
            break;
    }
    _ = value.string_buffer_puts(ctx, @ptrCast(&b), "\n) {\n");
    if (n >= 0) {
        _ = value.string_buffer_concat(ctx, @ptrCast(&b), argv[@intCast(n)]);
    }
    _ = value.string_buffer_puts(ctx, @ptrCast(&b), "\n})");
    var val = value.string_buffer_pop(ctx, @ptrCast(&b));
    if (vt.isExactException(val))
        return val;
    val = parser.JS_Parse2(ctx, val, null, 0, "<input>", c.JS_EVAL_RETVAL);
    if (vt.isExactException(val))
        return val;
    return parser.JS_Run(ctx, val);
}

pub fn js_function_get_prototype(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    _ = argc;
    _ = argv;
    var obj: c.JSValue = undefined;
    var obj_ref: c.JSGCRef = undefined;
    if (!mc.isPtr(this_val.*)) {
        if (rt.valueGetSpecialTag(this_val.*) != c.JS_TAG_SHORT_FUNC)
            return throwTypeError(ctx, "not a function");
        return c.JS_UNDEFINED;
    } else {
        const p = objPtr(this_val.*);
        if (mc.mbGetMtag(p) != mc.JS_MTAG_OBJECT)
            return throwTypeError(ctx, "not a function");
        if (mc.objectClassId(p) == c.JS_CLASS_CLOSURE) {
            obj = value.JS_NewObject(ctx);
            if (vt.isExactException(obj))
                return obj;
        } else if (mc.objectClassId(p) == c.JS_CLASS_C_FUNCTION) {
            return c.JS_UNDEFINED;
        } else {
            return throwTypeError(ctx, "not a function");
        }
        utils.pushValue(ctx, &obj_ref, obj);
        _ = value.JS_DefinePropertyValue(ctx, obj, utils.js_get_atom(ctx, c.JS_ATOM_constructor), this_val.*);
        obj = utils.popValue(ctx, &obj_ref);
        utils.pushValue(ctx, &obj_ref, obj);
        _ = value.JS_DefinePropertyValue(ctx, this_val.*, utils.js_get_atom(ctx, c.JS_ATOM_prototype), obj);
        obj = utils.popValue(ctx, &obj_ref);
    }
    return obj;
}

pub fn js_function_set_prototype(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    _ = argc;
    if (value.JS_IsFunctionObject(ctx, this_val.*) == 0)
        return throwTypeError(ctx, "not a function");
    _ = value.JS_DefinePropertyValue(ctx, this_val.*, utils.js_get_atom(ctx, c.JS_ATOM_prototype), argv[0]);
    return c.JS_UNDEFINED;
}

pub fn js_function_get_length_name(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue, is_name: c_int) c.JSValue {
    _ = argc;
    _ = argv;
    var b: ?*rt.JSFunctionBytecodeExt = null;
    const ret = runtime.js_function_get_length_name1(ctx, this_val, is_name, &b);
    if (mc.isNull(ret))
        return throwTypeError(ctx, "not a function");
    return ret;
}

pub fn js_function_toString(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    var str_ref: c.JSGCRef = undefined;
    var str = js_function_get_length_name(ctx, this_val, 0, argv, 1);
    if (vt.isExactException(str))
        return str;
    utils.pushValue(ctx, &str_ref, str);
    const val = value.JS_NewString(ctx, "function ");
    str = utils.popValue(ctx, &str_ref);
    str = value.JS_ConcatString(ctx, val, str);
    utils.pushValue(ctx, &str_ref, str);
    const val2 = value.JS_NewString(ctx, "() {\n    [native code]\n}");
    str = utils.popValue(ctx, &str_ref);
    _ = argc;
    return value.JS_ConcatString(ctx, str, val2);
}

pub fn js_function_call(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    if (utils.JS_StackCheck(ctx, @intCast(argc + 1)) != 0)
        return c.JS_EXCEPTION;
    var i: c_int = 0;
    while (i < argc - 1) : (i += 1) {
        runtime.JS_PushArg(ctx, argv[@intCast(argc - 1 - i)]);
    }
    runtime.JS_PushArg(ctx, this_val.*);
    runtime.JS_PushArg(ctx, argv[0]);
    return newTailCall(argc - 1);
}

pub fn js_function_apply(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    _ = argc;
    const p0 = value.js_get_object_class(ctx, argv[1], c.JS_CLASS_ARRAY) orelse
        return throwTypeError(ctx, "not an array");
    var p: *mc.JSObjectExt = @ptrCast(@alignCast(p0));
    var arr = valueArr(p.u.array.tab);
    const len: c_int = @intCast(p.u.array.len);
    if (len > pt.JS_MAX_ARGC)
        return throwTypeError(ctx, "too many call arguments");
    if (utils.JS_StackCheck(ctx, @intCast(len + 2)) != 0)
        return c.JS_EXCEPTION;
    p = objPtr(argv[1]);
    arr = valueArr(p.u.array.tab);
    var i: c_int = 0;
    while (i < len) : (i += 1) {
        runtime.JS_PushArg(ctx, vt.valueArrayItems(arr)[@intCast(len - 1 - i)]);
    }
    runtime.JS_PushArg(ctx, this_val.*);
    runtime.JS_PushArg(ctx, argv[0]);
    return newTailCall(len);
}

pub fn js_function_bind(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    const arg_count: c_int = if (argc > 1) argc - 1 else 0;
    const arr_ptr = value.js_alloc_value_array(ctx, 0, 2 + arg_count) orelse return c.JS_EXCEPTION;
    const arr: *vt.JSValueArrayExt = @ptrCast(@alignCast(arr_ptr));
    const items = vt.valueArrayItems(arr);
    items[0] = this_val.*;
    items[1] = argv[0];
    var i: c_int = 0;
    while (i < arg_count) : (i += 1) {
        items[@intCast(2 + i)] = argv[@intCast(1 + i)];
    }
    return runtime.JS_NewCFunctionParams(ctx, c.JS_CFUNCTION_bound, mc.valueFromPtr(arr));
}

pub fn js_function_bound(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue, params: c.JSValue) c.JSValue {
    _ = this_val;
    var params_ref: c.JSGCRef = undefined;
    var arr = valueArr(params);
    const size = vt.valueArraySize(arr);
    utils.pushValue(ctx, &params_ref, params);
    const err = utils.JS_StackCheck(ctx, @intCast(size + argc));
    _ = utils.popValue(ctx, &params_ref);
    if (err != 0)
        return c.JS_EXCEPTION;
    const argc2 = size - 2 + argc;
    if (argc2 > pt.JS_MAX_ARGC)
        return throwTypeError(ctx, "too many call arguments");
    arr = valueArr(params);
    var i: c_int = argc - 1;
    while (i >= 0) : (i -= 1) {
        runtime.JS_PushArg(ctx, argv[@intCast(i)]);
    }
    i = size - 1;
    while (i >= 2) : (i -= 1) {
        runtime.JS_PushArg(ctx, vt.valueArrayItems(arr)[@intCast(i)]);
    }
    runtime.JS_PushArg(ctx, vt.valueArrayItems(arr)[0]);
    runtime.JS_PushArg(ctx, vt.valueArrayItems(arr)[1]);
    return newTailCall(argc2);
}

// Number / Boolean / String

pub fn js_number_constructor(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    _ = this_val;
    if (argc & c.FRAME_CF_CTOR != 0)
        return throwTypeError(ctx, "number constructor not supported");
    if (argc == 0) {
        return vt.newShortInt(0);
    } else {
        var d: f64 = undefined;
        if (runtime.JS_ToNumber(ctx, &d, argv[0]) != 0)
            return c.JS_EXCEPTION;
        return value.JS_NewFloat64(ctx, d);
    }
}

pub fn js_thisNumberValue(ctx: *c.JSContext, pres: *f64, val: c.JSValue) c_int {
    if (value.JS_IsNumber(ctx, val) == 0) {
        _ = throwTypeError(ctx, "not a number");
        return -1;
    }
    return runtime.JS_ToNumber(ctx, pres, val);
}

pub fn js_number_toString(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    _ = argc;
    var d: f64 = undefined;
    if (js_thisNumberValue(ctx, &d, this_val.*) != 0)
        return c.JS_EXCEPTION;
    var radix: c_int = undefined;
    if (vt.isUndefined(argv[0])) {
        radix = 10;
    } else {
        if (runtime.JS_ToInt32Sat(ctx, &radix, argv[0]) != 0)
            return c.JS_EXCEPTION;
        if (radix < 2 or radix > 36)
            return throwRangeError(ctx, "radix must be between 2 and 36");
    }
    var flags: c_int = c.JS_DTOA_FORMAT_FREE;
    if (radix != 10)
        flags |= c.JS_DTOA_EXP_DISABLED;
    return runtime.js_dtoa2(ctx, d, radix, 0, flags);
}

pub fn js_number_toFixed(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    _ = argc;
    var d: f64 = undefined;
    if (js_thisNumberValue(ctx, &d, this_val.*) != 0)
        return c.JS_EXCEPTION;
    var f: c_int = undefined;
    if (runtime.JS_ToInt32Sat(ctx, &f, argv[0]) != 0)
        return c.JS_EXCEPTION;
    if (f < 0 or f > 100)
        return throwRangeError(ctx, "invalid number of digits");
    const flags: c_int = if (@abs(d) >= 1e21) c.JS_DTOA_FORMAT_FREE else c.JS_DTOA_FORMAT_FRAC;
    return runtime.js_dtoa2(ctx, d, 10, f, flags);
}

pub fn js_number_toExponential(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    _ = argc;
    var d: f64 = undefined;
    if (js_thisNumberValue(ctx, &d, this_val.*) != 0)
        return c.JS_EXCEPTION;
    var f: c_int = undefined;
    if (runtime.JS_ToInt32Sat(ctx, &f, argv[0]) != 0)
        return c.JS_EXCEPTION;
    var flags: c_int = undefined;
    if (vt.isUndefined(argv[0]) or !std.math.isFinite(d)) {
        f = 0;
        flags = c.JS_DTOA_FORMAT_FREE;
    } else {
        if (f < 0 or f > 100)
            return throwRangeError(ctx, "invalid number of digits");
        f += 1;
        flags = c.JS_DTOA_FORMAT_FIXED;
    }
    return runtime.js_dtoa2(ctx, d, 10, f, flags | c.JS_DTOA_EXP_ENABLED);
}

pub fn js_number_toPrecision(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    _ = argc;
    var d: f64 = undefined;
    if (js_thisNumberValue(ctx, &d, this_val.*) != 0)
        return c.JS_EXCEPTION;
    var p: c_int = undefined;
    var flags: c_int = undefined;
    if (vt.isUndefined(argv[0])) {
        flags = c.JS_DTOA_FORMAT_FREE;
        p = 0;
    } else {
        if (runtime.JS_ToInt32Sat(ctx, &p, argv[0]) != 0)
            return c.JS_EXCEPTION;
        if (!std.math.isFinite(d)) {
            flags = c.JS_DTOA_FORMAT_FREE;
        } else {
            if (p < 1 or p > 100)
                return throwRangeError(ctx, "invalid number of digits");
            flags = c.JS_DTOA_FORMAT_FIXED;
        }
    }
    return runtime.js_dtoa2(ctx, d, 10, p, flags);
}

pub fn js_number_parseInt(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    _ = this_val;
    _ = argc;
    argv[0] = runtime.JS_ToString(ctx, argv[0]);
    if (vt.isExactException(argv[0]))
        return c.JS_EXCEPTION;
    var radix: c_int = undefined;
    if (runtime.JS_ToInt32(ctx, &radix, argv[1]) != 0)
        return c.JS_EXCEPTION;
    var d: f64 = undefined;
    if (radix != 0 and (radix < 2 or radix > 36)) {
        d = std.math.nan(f64);
    } else {
        if (runtime.js_atod1(ctx, &d, argv[0], radix, c.JS_ATOD_INT_ONLY) != 0)
            return c.JS_EXCEPTION;
    }
    return value.JS_NewFloat64(ctx, d);
}

pub fn js_number_parseFloat(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    _ = this_val;
    _ = argc;
    argv[0] = runtime.JS_ToString(ctx, argv[0]);
    if (vt.isExactException(argv[0]))
        return c.JS_EXCEPTION;
    var d: f64 = undefined;
    if (runtime.js_atod1(ctx, &d, argv[0], 10, 0) != 0)
        return c.JS_EXCEPTION;
    return value.JS_NewFloat64(ctx, d);
}

pub fn js_boolean_constructor(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    _ = this_val;
    if (argc & c.FRAME_CF_CTOR != 0)
        return throwTypeError(ctx, "Boolean constructor not supported");
    return newBool(value.JS_ToBool(ctx, argv[0]) != 0);
}


pub fn js_object_constructor(ctx: *c.JSContext, this_val: *c.JSValue, argc_in: c_int, argv: [*]c.JSValue) c.JSValue {
    _ = this_val;
    var argc = argc_in;
    argc &= ~c.FRAME_CF_CTOR;
    if (argc <= 0)
        return value.JS_NewObject(ctx);
    return argv[0];
}

pub fn js_object_defineProperty(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    _ = this_val;
    _ = argc;
    var val_ref: c.JSGCRef = undefined;
    var getter_ref: c.JSGCRef = undefined;

    const pobj = &argv[0];
    const pprop = &argv[1];
    const pdesc = &argv[2];

    if (value.JS_IsObject(ctx, pobj.*) == 0)
        return value.JS_ThrowTypeErrorNotAnObject(ctx);
    pprop.* = runtime.JS_ToPropertyKey(ctx, pprop.*);
    if (vt.isExactException(pprop.*))
        return c.JS_EXCEPTION;
    var val: c.JSValue = c.JS_UNDEFINED;
    var getter: c.JSValue = c.JS_UNDEFINED;
    var setter: c.JSValue = c.JS_UNDEFINED;
    var flags: c_int = 0;
    if (value.JS_HasProperty(ctx, pdesc.*, utils.js_get_atom(ctx, c.JS_ATOM_value)) != 0) {
        flags |= vt.JS_DEF_PROP_HAS_VALUE;
        val = value.JS_GetProperty(ctx, pdesc.*, utils.js_get_atom(ctx, c.JS_ATOM_value));
        if (vt.isExactException(val))
            return c.JS_EXCEPTION;
    }
    if (value.JS_HasProperty(ctx, pdesc.*, utils.js_get_atom(ctx, c.JS_ATOM_get)) != 0) {
        flags |= vt.JS_DEF_PROP_HAS_GET;
        utils.pushValue(ctx, &val_ref, val);
        getter = value.JS_GetProperty(ctx, pdesc.*, utils.js_get_atom(ctx, c.JS_ATOM_get));
        val = utils.popValue(ctx, &val_ref);
        if (vt.isExactException(getter))
            return c.JS_EXCEPTION;
        if (!vt.isUndefined(getter) and value.JS_IsFunction(ctx, getter) == 0)
            return throwTypeError(ctx, "invalid getter or setter");
    }
    if (value.JS_HasProperty(ctx, pdesc.*, utils.js_get_atom(ctx, c.JS_ATOM_set)) != 0) {
        flags |= vt.JS_DEF_PROP_HAS_SET;
        utils.pushValue(ctx, &val_ref, val);
        utils.pushValue(ctx, &getter_ref, getter);
        setter = value.JS_GetProperty(ctx, pdesc.*, utils.js_get_atom(ctx, c.JS_ATOM_set));
        getter = utils.popValue(ctx, &getter_ref);
        val = utils.popValue(ctx, &val_ref);
        if (vt.isExactException(setter))
            return c.JS_EXCEPTION;
        if (!vt.isUndefined(setter) and value.JS_IsFunction(ctx, setter) == 0)
            return throwTypeError(ctx, "invalid getter or setter");
    }
    if (flags & (vt.JS_DEF_PROP_HAS_GET | vt.JS_DEF_PROP_HAS_SET) != 0) {
        if (flags & vt.JS_DEF_PROP_HAS_VALUE != 0)
            return throwTypeError(ctx, "cannot have both value and get/set");
        val = getter;
    }
    val = value.JS_DefinePropertyInternal(ctx, pobj.*, pprop.*, val, setter, flags | vt.JS_DEF_PROP_LOOKUP);
    if (vt.isExactException(val))
        return val;
    return pobj.*;
}

pub fn js_object_getPrototypeOf(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    _ = this_val;
    _ = argc;
    if (value.JS_IsObject(ctx, argv[0]) == 0)
        return value.JS_ThrowTypeErrorNotAnObject(ctx);
    const p = objPtr(argv[0]);
    return p.proto;
}

pub fn js_set_prototype_internal(ctx: *c.JSContext, obj: c.JSValue, proto: c.JSValue) c.JSValue {
    const p = objPtr(obj);
    if (p.proto != proto) {
        if (proto != c.JS_NULL) {
            var p1 = objPtr(proto);
            while (true) {
                if (p1 == p)
                    return throwTypeError(ctx, "circular prototype chain");
                if (p1.proto == c.JS_NULL)
                    break;
                p1 = objPtr(p1.proto);
            }
        }
        p.proto = proto;
    }
    return c.JS_UNDEFINED;
}

pub fn js_object_setPrototypeOf(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    _ = this_val;
    _ = argc;
    if (value.JS_IsObject(ctx, argv[0]) == 0)
        return value.JS_ThrowTypeErrorNotAnObject(ctx);
    const proto = argv[1];
    if (proto != c.JS_NULL and value.JS_IsObject(ctx, proto) == 0)
        return throwTypeError(ctx, "not a prototype");
    if (vt.isExactException(js_set_prototype_internal(ctx, argv[0], proto)))
        return c.JS_EXCEPTION;
    return argv[0];
}

pub fn js_object_create(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    _ = this_val;
    const proto = argv[0];
    if (proto != c.JS_NULL and value.JS_IsObject(ctx, proto) == 0)
        return throwTypeError(ctx, "not a prototype");
    if (argc >= 2)
        return throwTypeError(ctx, "unsupported additional properties");
    return value.JS_NewObjectProtoClass(ctx, proto, c.JS_CLASS_OBJECT, 0);
}

pub fn js_object_keys(ctx: *c.JSContext, this_val: ?*c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    _ = this_val;
    _ = argc;
    var ret_ref: c.JSGCRef = undefined;

    if (value.JS_IsObject(ctx, argv[0]) == 0)
        return value.JS_ThrowTypeErrorNotAnObject(ctx);
    var p = objPtr(argv[0]);

    var array_len: c_int = undefined;
    if (mc.objectClassId(p) == c.JS_CLASS_ARRAY) {
        array_len = @intCast(p.u.array.len);
    } else if (mc.objectClassId(p) >= c.JS_CLASS_UINT8C_ARRAY and mc.objectClassId(p) <= c.JS_CLASS_FLOAT64_ARRAY) {
        array_len = @intCast(p.u.typed_array.len);
    } else {
        array_len = 0;
    }

    var arr = valueArr(p.props);
    const prop_count = vt.valueGetInt(vt.valueArrayItems(arr)[0]);
    const hash_mask = vt.valueGetInt(vt.valueArrayItems(arr)[1]);

    const alloc_size = array_len + prop_count;

    var ret = value.JS_NewArray(ctx, alloc_size);
    if (vt.isExactException(ret))
        return ret;

    var pos: c_int = 0;
    var i: c_int = 0;
    while (i < array_len) : (i += 1) {
        utils.pushValue(ctx, &ret_ref, ret);
        const str = runtime.JS_ToString(ctx, vt.newShortInt(i));
        ret = utils.popValue(ctx, &ret_ref);
        if (vt.isExactException(str))
            return str;
        const pret = objPtr(ret);
        const ret_arr = valueArr(pret.u.array.tab);
        vt.valueArrayItems(ret_arr)[@intCast(pos)] = str;
        pos += 1;
    }

    i = 0;
    var j: c_int = 0;
    while (j < prop_count) : (i += 1) {
        p = objPtr(argv[0]);
        arr = valueArr(p.props);
        const pr: *vt.JSPropertyExt = @ptrCast(@alignCast(&vt.valueArrayItems(arr)[@intCast(2 + hash_mask + 1 + 3 * i)]));
        if (pr.key != c.JS_UNINITIALIZED) {
            utils.pushValue(ctx, &ret_ref, ret);
            const str = runtime.JS_ToString(ctx, pr.key);
            ret = utils.popValue(ctx, &ret_ref);
            if (vt.isExactException(str))
                return str;
            const pret = objPtr(ret);
            const ret_arr = valueArr(pret.u.array.tab);
            vt.valueArrayItems(ret_arr)[@intCast(pos)] = str;
            pos += 1;
            j += 1;
        }
    }
    const pret = objPtr(ret);
    pret.u.array.len = @intCast(pos);
    return ret;
}

pub fn js_object_hasOwnProperty(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    _ = argc;
    if (mc.isNull(this_val.*) or vt.isUndefined(this_val.*))
        return throwTypeError(ctx, "cannot convert to object");
    if (value.JS_IsObject(ctx, this_val.*) == 0)
        return c.JS_FALSE;
    const prop = runtime.JS_ToPropertyKey(ctx, argv[0]);
    const p = objPtr(this_val.*);
    if (mc.objectClassId(p) == c.JS_CLASS_ARRAY) {
        const array_len: c_int = @intCast(p.u.array.len);
        if (mc.isInt(prop)) {
            const idx = vt.valueGetInt(prop);
            return newBool(idx >= 0 and idx < array_len);
        }
    } else if (mc.objectClassId(p) >= c.JS_CLASS_UINT8C_ARRAY and mc.objectClassId(p) <= c.JS_CLASS_FLOAT64_ARRAY) {
        const array_len: c_int = @intCast(p.u.typed_array.len);
        if (mc.isInt(prop)) {
            const idx = vt.valueGetInt(prop);
            return newBool(idx >= 0 and idx < array_len);
        }
    }
    return newBool(value.find_own_property(ctx, p, prop) != null);
}

pub fn js_object_toString(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    _ = argc;
    _ = argv;
    const str: [*:0]const u8 = blk: {
        if (vt.isIntOrShortFloat(this_val.*))
            break :blk "Number";
        if (!mc.isPtr(this_val.*)) {
            switch (rt.valueGetSpecialTag(this_val.*)) {
                c.JS_TAG_NULL => break :blk "Null",
                c.JS_TAG_UNDEFINED => break :blk "Undefined",
                c.JS_TAG_SHORT_FUNC => break :blk "Function",
                c.JS_TAG_BOOL => break :blk "Boolean",
                c.JS_TAG_STRING_CHAR => break :blk "String",
                else => break :blk "Object",
            }
        } else {
            const p = objPtr(this_val.*);
            switch (mc.mbGetMtag(p)) {
                mc.JS_MTAG_OBJECT => {
                    const class_id = mc.objectClassId(p);
                    if (class_id == c.JS_CLASS_ARRAY)
                        break :blk "Array";
                    if (class_id == c.JS_CLASS_ERROR)
                        break :blk "Error";
                    if (class_id == c.JS_CLASS_CLOSURE or class_id == c.JS_CLASS_C_FUNCTION)
                        break :blk "Function";
                    break :blk "Object";
                },
                mc.JS_MTAG_STRING => break :blk "String",
                mc.JS_MTAG_FLOAT64 => break :blk "Number",
                else => break :blk "Object",
            }
        }
    };
    var buf: [64]u8 = undefined;
    _ = utils.js_snprintf(@ptrCast(&buf), buf.len, "[object %s]", str);
    return value.JS_NewString(ctx, @ptrCast(&buf));
}

pub fn js_error_constructor(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue, magic: c_int) c.JSValue {
    _ = this_val;
    _ = argc & ~c.FRAME_CF_CTOR;
    var obj_ref: c.JSGCRef = undefined;

    var obj = value.JS_NewObjectProtoClass(ctx, vt.classProto(mc.ctxExt(ctx), magic).*, c.JS_CLASS_ERROR, @intCast(@sizeOf(mc.JSErrorDataExt)));
    if (vt.isExactException(obj))
        return obj;
    var p = objPtr(obj);
    rt.objectError(p).message = c.JS_NULL;
    rt.objectError(p).stack = c.JS_NULL;

    if (!vt.isUndefined(argv[0])) {
        utils.pushValue(ctx, &obj_ref, obj);
        const msg = runtime.JS_ToString(ctx, argv[0]);
        obj = utils.popValue(ctx, &obj_ref);
        if (vt.isExactException(msg))
            return msg;
        p = objPtr(obj);
        rt.objectError(p).message = msg;
    } else {
        p = objPtr(obj);
        rt.objectError(p).message = utils.js_get_atom(ctx, c.JS_ATOM_empty);
    }
    utils.pushValue(ctx, &obj_ref, obj);
    runtime.build_backtrace(ctx, obj, null, 0, 0, 1);
    obj = utils.popValue(ctx, &obj_ref);
    return obj;
}

pub fn js_error_toString(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    _ = argc;
    _ = argv;
    var b: vt.StringBuffer = undefined;

    if (value.JS_IsError(ctx, this_val.*) == 0)
        return throwTypeError(ctx, "not an Error object");
    var name = value.JS_GetProperty(ctx, this_val.*, utils.js_get_atom(ctx, c.JS_ATOM_name));
    if (vt.isExactException(name))
        return name;
    if (vt.isUndefined(name))
        name = utils.js_get_atom(ctx, c.JS_ATOM_Error)
    else
        name = runtime.JS_ToString(ctx, name);
    if (vt.isExactException(name))
        return name;
    _ = value.string_buffer_push(ctx, @ptrCast(&b), 0);
    _ = value.string_buffer_concat(ctx, @ptrCast(&b), name);
    var p = objPtr(this_val.*);
    if (rt.objectError(p).message != c.JS_NULL) {
        _ = value.string_buffer_puts(ctx, @ptrCast(&b), ": ");
        p = objPtr(this_val.*);
        _ = value.string_buffer_concat(ctx, @ptrCast(&b), rt.objectError(p).message);
    }
    return value.string_buffer_pop(ctx, @ptrCast(&b));
}

pub fn js_error_get_message(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue, magic: c_int) c.JSValue {
    _ = argc;
    _ = argv;
    if (value.JS_IsError(ctx, this_val.*) == 0)
        return throwTypeError(ctx, "not an Error object");
    const p = objPtr(this_val.*);
    if (magic == 0)
        return rt.objectError(p).message
    else
        return rt.objectError(p).stack;
}

