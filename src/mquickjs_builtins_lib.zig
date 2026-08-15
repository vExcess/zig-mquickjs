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

fn newTailCall(val: c_int) c.JSValue {
    return vt.newTailCall(val);
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

// Object / Error / Array

pub fn js_object_constructor(ctx: *c.JSContext, this_val: *c.JSValue, argc_in: c_int, argv: [*]c.JSValue) c.JSValue {
    _ = this_val;
    var argc = argc_in;
    argc &= ~c.FRAME_CF_CTOR;
    if (argc <= 0)
        return value.JS_NewObject(ctx);
    return argv[0];
}

fn memmoveValues(dest: [*]c.JSValue, src: [*]c.JSValue, n: usize) void {
    if (n == 0 or @intFromPtr(dest) == @intFromPtr(src)) return;
    @memmove(dest[0..n], src[0..n]);
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
                    sp[2] = js_object_keys(ctx, &dummy_this, 1, sp);
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
                    _ = utils.popValue(ctx, &val_ref);
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
