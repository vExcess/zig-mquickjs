//
// Micro QuickJS engine builtins (C ABI exports)
//
// Copyright (c) 2017-2025 Fabrice Bellard
// Copyright (c) 2017-2025 Charlie Gordon
//
// Ported from C to Zig by VExcess
//

const lib = @import("mquickjs_builtins_lib.zig");
const bt = @import("mquickjs_builtins_types.zig");
const c = lib.c;

export fn JS_IsArray(ctx: *c.JSContext, obj: c.JSValue) c.JS_BOOL {
    return lib.JS_IsArray(ctx, obj);
}

export fn JS_NewDate(ctx: *c.JSContext, epoch_ms: f64) c.JSValue {
    return lib.JS_NewDate(ctx, epoch_ms);
}

export fn dump_regexp(ctx: *c.JSContext, p: *anyopaque) void {
    lib.dump_regexp(ctx, p);
}

export fn js_parse_regexp(s: *bt.JSParseState, re_flags: c_int) c.JSValue {
    return lib.js_parse_regexp(s, re_flags);
}

export fn js_parse_regexp_flags(pre_flags: *c_int, buf: [*]const u8) usize {
    return lib.js_parse_regexp_flags(pre_flags, buf);
}

export fn re_parse_alternative(s: *bt.JSParseState, state: c_int, dummy_param: c_int) c_int {
    return lib.re_parse_alternative(s, state, dummy_param);
}

export fn re_parse_disjunction(s: *bt.JSParseState, state: c_int, dummy_param: c_int) c_int {
    return lib.re_parse_disjunction(s, state, dummy_param);
}

export fn js_object_keys(ctx: *c.JSContext, this_val: ?*c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return lib.js_object_keys(ctx, this_val, argc, argv);
}

export fn js_set_prototype_internal(ctx: *c.JSContext, obj: c.JSValue, proto: c.JSValue) c.JSValue {
    return lib.js_set_prototype_internal(ctx, obj, proto);
}

export fn js_string_charAt(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue, magic: c_int) c.JSValue {
    return lib.js_string_charAt(ctx, this_val, argc, argv, magic);
}

export fn js_function_constructor(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return lib.js_function_constructor(ctx, this_val, argc, argv);
}

export fn js_function_get_prototype(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return lib.js_function_get_prototype(ctx, this_val, argc, argv);
}

export fn js_function_set_prototype(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return lib.js_function_set_prototype(ctx, this_val, argc, argv);
}

export fn js_function_get_length_name(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue, is_name: c_int) c.JSValue {
    return lib.js_function_get_length_name(ctx, this_val, argc, argv, is_name);
}

export fn js_function_toString(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return lib.js_function_toString(ctx, this_val, argc, argv);
}

export fn js_function_call(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return lib.js_function_call(ctx, this_val, argc, argv);
}

export fn js_function_apply(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return lib.js_function_apply(ctx, this_val, argc, argv);
}

export fn js_function_bind(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return lib.js_function_bind(ctx, this_val, argc, argv);
}

export fn js_function_bound(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue, params: c.JSValue) c.JSValue {
    return lib.js_function_bound(ctx, this_val, argc, argv, params);
}

export fn js_number_constructor(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return lib.js_number_constructor(ctx, this_val, argc, argv);
}

export fn js_number_toString(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return lib.js_number_toString(ctx, this_val, argc, argv);
}

export fn js_number_toFixed(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return lib.js_number_toFixed(ctx, this_val, argc, argv);
}

export fn js_number_toExponential(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return lib.js_number_toExponential(ctx, this_val, argc, argv);
}

export fn js_number_toPrecision(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return lib.js_number_toPrecision(ctx, this_val, argc, argv);
}

export fn js_number_parseInt(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return lib.js_number_parseInt(ctx, this_val, argc, argv);
}

export fn js_number_parseFloat(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return lib.js_number_parseFloat(ctx, this_val, argc, argv);
}

export fn js_boolean_constructor(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return lib.js_boolean_constructor(ctx, this_val, argc, argv);
}

export fn js_string_get_length(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return lib.js_string_get_length(ctx, this_val, argc, argv);
}

export fn js_string_set_length(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return lib.js_string_set_length(ctx, this_val, argc, argv);
}

export fn js_string_slice(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return lib.js_string_slice(ctx, this_val, argc, argv);
}

export fn js_string_substring(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return lib.js_string_substring(ctx, this_val, argc, argv);
}

export fn js_string_constructor(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return lib.js_string_constructor(ctx, this_val, argc, argv);
}

export fn js_string_fromCharCode(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue, is_fromCodePoint: c_int) c.JSValue {
    return lib.js_string_fromCharCode(ctx, this_val, argc, argv, is_fromCodePoint);
}

export fn js_string_concat(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return lib.js_string_concat(ctx, this_val, argc, argv);
}

export fn js_string_indexOf(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue, lastIndexOf: c_int) c.JSValue {
    return lib.js_string_indexOf(ctx, this_val, argc, argv, lastIndexOf);
}

export fn js_string_toLowerCase(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue, to_lower: c_int) c.JSValue {
    return lib.js_string_toLowerCase(ctx, this_val, argc, argv, to_lower);
}

export fn js_string_trim(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue, magic: c_int) c.JSValue {
    return lib.js_string_trim(ctx, this_val, argc, argv, magic);
}

export fn js_string_toString(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return lib.js_string_toString(ctx, this_val, argc, argv);
}

export fn js_string_repeat(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return lib.js_string_repeat(ctx, this_val, argc, argv);
}

export fn js_string_match(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return lib.js_string_match(ctx, this_val, argc, argv);
}

export fn js_string_replace(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue, is_replaceAll: c_int) c.JSValue {
    return lib.js_string_replace(ctx, this_val, argc, argv, is_replaceAll);
}

export fn js_string_search(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return lib.js_string_search(ctx, this_val, argc, argv);
}

export fn js_string_split(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return lib.js_string_split(ctx, this_val, argc, argv);
}

export fn js_object_constructor(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return lib.js_object_constructor(ctx, this_val, argc, argv);
}

export fn js_object_defineProperty(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return lib.js_object_defineProperty(ctx, this_val, argc, argv);
}

export fn js_object_getPrototypeOf(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return lib.js_object_getPrototypeOf(ctx, this_val, argc, argv);
}

export fn js_object_setPrototypeOf(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return lib.js_object_setPrototypeOf(ctx, this_val, argc, argv);
}

export fn js_object_create(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return lib.js_object_create(ctx, this_val, argc, argv);
}

export fn js_object_hasOwnProperty(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return lib.js_object_hasOwnProperty(ctx, this_val, argc, argv);
}

export fn js_object_toString(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return lib.js_object_toString(ctx, this_val, argc, argv);
}

export fn js_error_constructor(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue, magic: c_int) c.JSValue {
    return lib.js_error_constructor(ctx, this_val, argc, argv, magic);
}

export fn js_error_toString(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return lib.js_error_toString(ctx, this_val, argc, argv);
}

export fn js_error_get_message(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue, magic: c_int) c.JSValue {
    return lib.js_error_get_message(ctx, this_val, argc, argv, magic);
}

export fn js_array_get_length(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return lib.js_array_get_length(ctx, this_val, argc, argv);
}

export fn js_array_set_length(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return lib.js_array_set_length(ctx, this_val, argc, argv);
}

export fn js_array_constructor(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return lib.js_array_constructor(ctx, this_val, argc, argv);
}

export fn js_array_push(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue, is_unshift: c_int) c.JSValue {
    return lib.js_array_push(ctx, this_val, argc, argv, is_unshift);
}

export fn js_array_pop(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return lib.js_array_pop(ctx, this_val, argc, argv);
}

export fn js_array_shift(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return lib.js_array_shift(ctx, this_val, argc, argv);
}

export fn js_array_join(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return lib.js_array_join(ctx, this_val, argc, argv);
}

export fn js_array_toString(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return lib.js_array_toString(ctx, this_val, argc, argv);
}

export fn js_array_isArray(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return lib.js_array_isArray(ctx, this_val, argc, argv);
}

export fn js_array_reverse(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return lib.js_array_reverse(ctx, this_val, argc, argv);
}

export fn js_array_concat(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return lib.js_array_concat(ctx, this_val, argc, argv);
}

export fn js_array_indexOf(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue, is_lastIndexOf: c_int) c.JSValue {
    return lib.js_array_indexOf(ctx, this_val, argc, argv, is_lastIndexOf);
}

export fn js_array_slice(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return lib.js_array_slice(ctx, this_val, argc, argv);
}

export fn js_array_splice(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return lib.js_array_splice(ctx, this_val, argc, argv);
}

export fn js_array_every(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue, special: c_int) c.JSValue {
    return lib.js_array_every(ctx, this_val, argc, argv, special);
}

export fn js_array_reduce(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue, special: c_int) c.JSValue {
    return lib.js_array_reduce(ctx, this_val, argc, argv, special);
}

export fn js_array_sort(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return lib.js_array_sort(ctx, this_val, argc, argv);
}

export fn js_math_min_max(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue, magic: c_int) c.JSValue {
    return lib.js_math_min_max(ctx, this_val, argc, argv, magic);
}

export fn js_math_sign(a: f64) f64 {
    return lib.js_math_sign(a);
}

export fn js_math_fround(a: f64) f64 {
    return lib.js_math_fround(a);
}

export fn js_math_imul(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return lib.js_math_imul(ctx, this_val, argc, argv);
}

export fn js_math_clz32(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return lib.js_math_clz32(ctx, this_val, argc, argv);
}

export fn js_math_atan2(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return lib.js_math_atan2(ctx, this_val, argc, argv);
}

export fn js_math_pow(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return lib.js_math_pow(ctx, this_val, argc, argv);
}

export fn js_math_random(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return lib.js_math_random(ctx, this_val, argc, argv);
}

export fn js_array_buffer_constructor(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return lib.js_array_buffer_constructor(ctx, this_val, argc, argv);
}

export fn js_array_buffer_get_byteLength(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return lib.js_array_buffer_get_byteLength(ctx, this_val, argc, argv);
}

export fn js_typed_array_base_constructor(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return lib.js_typed_array_base_constructor(ctx, this_val, argc, argv);
}

export fn js_typed_array_constructor(ctx: *c.JSContext, this_val: ?*c.JSValue, argc: c_int, argv: [*]c.JSValue, magic: c_int) c.JSValue {
    return lib.js_typed_array_constructor(ctx, this_val, argc, argv, magic);
}

export fn js_typed_array_get_length(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue, magic: c_int) c.JSValue {
    return lib.js_typed_array_get_length(ctx, this_val, argc, argv, magic);
}

export fn js_typed_array_subarray(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return lib.js_typed_array_subarray(ctx, this_val, argc, argv);
}

export fn js_typed_array_set(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return lib.js_typed_array_set(ctx, this_val, argc, argv);
}

export fn js_date_valueOf(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return lib.js_date_valueOf(ctx, this_val, argc, argv);
}

export fn js_global_eval(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return lib.js_global_eval(ctx, this_val, argc, argv);
}

export fn js_global_isNaN(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return lib.js_global_isNaN(ctx, this_val, argc, argv);
}

export fn js_global_isFinite(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return lib.js_global_isFinite(ctx, this_val, argc, argv);
}

export fn js_json_parse(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return lib.js_json_parse(ctx, this_val, argc, argv);
}

export fn js_json_stringify(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return lib.js_json_stringify(ctx, this_val, argc, argv);
}

export fn js_regexp_get_lastIndex(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return lib.js_regexp_get_lastIndex(ctx, this_val, argc, argv);
}

export fn js_regexp_get_source(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return lib.js_regexp_get_source(ctx, this_val, argc, argv);
}

export fn js_regexp_set_lastIndex(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return lib.js_regexp_set_lastIndex(ctx, this_val, argc, argv);
}

export fn js_regexp_get_flags(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return lib.js_regexp_get_flags(ctx, this_val, argc, argv);
}

export fn js_regexp_constructor(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return lib.js_regexp_constructor(ctx, this_val, argc, argv);
}

export fn js_regexp_exec(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue, magic: c_int) c.JSValue {
    return lib.js_regexp_exec(ctx, this_val, argc, argv, magic);
}
