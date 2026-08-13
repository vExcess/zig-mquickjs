//
// Micro QuickJS REPL library tables
//
// Ported from mqjs_stdlib.c
//

const std = @import("std");
const bt = @import("mquickjs_build_types.zig");

pub const Config = struct {
    class_example: bool = false,
    rectangle_class: ?*const bt.ClassDef = null,
    filled_rectangle_class: ?*const bt.ClassDef = null,
};

const js_object_proto = [_]bt.PropDef{
    bt.cfuncDef("hasOwnProperty", 1, "js_object_hasOwnProperty"),
    bt.cfuncDef("toString", 0, "js_object_toString"),
    bt.propEnd(),
};

const js_object = [_]bt.PropDef{
    bt.cfuncDef("defineProperty", 3, "js_object_defineProperty"),
    bt.cfuncDef("getPrototypeOf", 1, "js_object_getPrototypeOf"),
    bt.cfuncDef("setPrototypeOf", 2, "js_object_setPrototypeOf"),
    bt.cfuncDef("create", 2, "js_object_create"),
    bt.cfuncDef("keys", 1, "js_object_keys"),
    bt.propEnd(),
};

pub const js_object_class: bt.ClassDef = bt.classDef(
    "Object",
    1,
    "js_object_constructor",
    "JS_CLASS_OBJECT",
    &js_object,
    &js_object_proto,
    null,
    "NULL",
);

const js_function_proto = [_]bt.PropDef{
    bt.cgetsetDef("prototype", "js_function_get_prototype", "js_function_set_prototype"),
    bt.cfuncDef("call", 1, "js_function_call"),
    bt.cfuncDef("apply", 2, "js_function_apply"),
    bt.cfuncDef("bind", 1, "js_function_bind"),
    bt.cfuncDef("toString", 0, "js_function_toString"),
    bt.cgetsetMagicDef("length", "js_function_get_length_name", "NULL", "0"),
    bt.cgetsetMagicDef("name", "js_function_get_length_name", "NULL", "1"),
    bt.propEnd(),
};

pub const js_function_class: bt.ClassDef = bt.classDef(
    "Function",
    1,
    "js_function_constructor",
    "JS_CLASS_CLOSURE",
    null,
    &js_function_proto,
    null,
    "NULL",
);

const js_number_proto = [_]bt.PropDef{
    bt.cfuncDef("toExponential", 1, "js_number_toExponential"),
    bt.cfuncDef("toFixed", 1, "js_number_toFixed"),
    bt.cfuncDef("toPrecision", 1, "js_number_toPrecision"),
    bt.cfuncDef("toString", 1, "js_number_toString"),
    bt.propEnd(),
};

const js_number = [_]bt.PropDef{
    bt.cfuncDef("parseInt", 2, "js_number_parseInt"),
    bt.cfuncDef("parseFloat", 1, "js_number_parseFloat"),
    bt.propDoubleDef("MAX_VALUE", 1.7976931348623157e+308),
    bt.propDoubleDef("MIN_VALUE", 5e-324),
    bt.propDoubleDef("NaN", std.math.nan(f64)),
    bt.propDoubleDef("NEGATIVE_INFINITY", -std.math.inf(f64)),
    bt.propDoubleDef("POSITIVE_INFINITY", std.math.inf(f64)),
    bt.propDoubleDef("EPSILON", 2.220446049250313e-16),
    bt.propDoubleDef("MAX_SAFE_INTEGER", 9007199254740991.0),
    bt.propDoubleDef("MIN_SAFE_INTEGER", -9007199254740991.0),
    bt.propEnd(),
};

pub const js_number_class: bt.ClassDef = bt.classDef(
    "Number",
    1,
    "js_number_constructor",
    "JS_CLASS_NUMBER",
    &js_number,
    &js_number_proto,
    null,
    "NULL",
);

pub const js_boolean_class: bt.ClassDef = bt.classDef(
    "Boolean",
    1,
    "js_boolean_constructor",
    "JS_CLASS_BOOLEAN",
    null,
    null,
    null,
    "NULL",
);

const js_string_proto = [_]bt.PropDef{
    bt.cgetsetDef("length", "js_string_get_length", "js_string_set_length"),
    bt.cfuncMagicDef("charAt", 1, "js_string_charAt", "magic_charAt"),
    bt.cfuncMagicDef("charCodeAt", 1, "js_string_charAt", "magic_charCodeAt"),
    bt.cfuncMagicDef("codePointAt", 1, "js_string_charAt", "magic_codePointAt"),
    bt.cfuncDef("slice", 2, "js_string_slice"),
    bt.cfuncDef("substring", 2, "js_string_substring"),
    bt.cfuncDef("concat", 1, "js_string_concat"),
    bt.cfuncMagicDef("indexOf", 1, "js_string_indexOf", "0"),
    bt.cfuncMagicDef("lastIndexOf", 1, "js_string_indexOf", "1"),
    bt.cfuncDef("match", 1, "js_string_match"),
    bt.cfuncMagicDef("replace", 2, "js_string_replace", "0"),
    bt.cfuncMagicDef("replaceAll", 2, "js_string_replace", "1"),
    bt.cfuncDef("search", 1, "js_string_search"),
    bt.cfuncDef("split", 2, "js_string_split"),
    bt.cfuncMagicDef("toLowerCase", 0, "js_string_toLowerCase", "1"),
    bt.cfuncMagicDef("toUpperCase", 0, "js_string_toLowerCase", "0"),
    bt.cfuncMagicDef("trim", 0, "js_string_trim", "3"),
    bt.cfuncMagicDef("trimEnd", 0, "js_string_trim", "2"),
    bt.cfuncMagicDef("trimStart", 0, "js_string_trim", "1"),
    bt.cfuncDef("toString", 0, "js_string_toString"),
    bt.cfuncDef("repeat", 1, "js_string_repeat"),
    bt.propEnd(),
};

const js_string = [_]bt.PropDef{
    bt.cfuncMagicDef("fromCharCode", 1, "js_string_fromCharCode", "0"),
    bt.cfuncMagicDef("fromCodePoint", 1, "js_string_fromCharCode", "1"),
    bt.propEnd(),
};

pub const js_string_class: bt.ClassDef = bt.classDef(
    "String",
    1,
    "js_string_constructor",
    "JS_CLASS_STRING",
    &js_string,
    &js_string_proto,
    null,
    "NULL",
);

const js_array_proto = [_]bt.PropDef{
    bt.cfuncDef("concat", 1, "js_array_concat"),
    bt.cgetsetDef("length", "js_array_get_length", "js_array_set_length"),
    bt.cfuncMagicDef("push", 1, "js_array_push", "0"),
    bt.cfuncDef("pop", 0, "js_array_pop"),
    bt.cfuncDef("join", 1, "js_array_join"),
    bt.cfuncDef("toString", 0, "js_array_toString"),
    bt.cfuncDef("reverse", 0, "js_array_reverse"),
    bt.cfuncDef("shift", 0, "js_array_shift"),
    bt.cfuncDef("slice", 2, "js_array_slice"),
    bt.cfuncDef("splice", 2, "js_array_splice"),
    bt.cfuncMagicDef("unshift", 1, "js_array_push", "1"),
    bt.cfuncMagicDef("indexOf", 1, "js_array_indexOf", "0"),
    bt.cfuncMagicDef("lastIndexOf", 1, "js_array_indexOf", "1"),
    bt.cfuncMagicDef("every", 1, "js_array_every", "js_special_every"),
    bt.cfuncMagicDef("some", 1, "js_array_every", "js_special_some"),
    bt.cfuncMagicDef("forEach", 1, "js_array_every", "js_special_forEach"),
    bt.cfuncMagicDef("map", 1, "js_array_every", "js_special_map"),
    bt.cfuncMagicDef("filter", 1, "js_array_every", "js_special_filter"),
    bt.cfuncMagicDef("reduce", 1, "js_array_reduce", "js_special_reduce"),
    bt.cfuncMagicDef("reduceRight", 1, "js_array_reduce", "js_special_reduceRight"),
    bt.cfuncMagicDef("reduce", 1, "js_array_reduce", "js_special_reduce"),
    bt.cfuncDef("sort", 1, "js_array_sort"),
    bt.propEnd(),
};

const js_array = [_]bt.PropDef{
    bt.cfuncDef("isArray", 1, "js_array_isArray"),
    bt.propEnd(),
};

pub const js_array_class: bt.ClassDef = bt.classDef(
    "Array",
    1,
    "js_array_constructor",
    "JS_CLASS_ARRAY",
    &js_array,
    &js_array_proto,
    null,
    "NULL",
);

const js_error_proto = [_]bt.PropDef{
    bt.cfuncDef("toString", 0, "js_error_toString"),
    bt.propStringDef("name", "Error"),
    bt.cgetsetMagicDef("message", "js_error_get_message", "NULL", "0"),
    bt.cgetsetMagicDef("stack", "js_error_get_message", "NULL", "1"),
    bt.propEnd(),
};

pub const js_error_class: bt.ClassDef = bt.classMagicDef(
    "Error",
    1,
    "js_error_constructor",
    "JS_CLASS_ERROR",
    null,
    &js_error_proto,
    null,
    "NULL",
);

const js_eval_error_proto = [_]bt.PropDef{
    bt.propStringDef("name", "EvalError"),
    bt.propEnd(),
};
pub const js_eval_error_class: bt.ClassDef = bt.classMagicDef(
    "EvalError",
    1,
    "js_error_constructor",
    "JS_CLASS_EVAL_ERROR",
    null,
    &js_eval_error_proto,
    &js_error_class,
    "NULL",
);

const js_range_error_proto = [_]bt.PropDef{
    bt.propStringDef("name", "RangeError"),
    bt.propEnd(),
};
pub const js_range_error_class: bt.ClassDef = bt.classMagicDef(
    "RangeError",
    1,
    "js_error_constructor",
    "JS_CLASS_RANGE_ERROR",
    null,
    &js_range_error_proto,
    &js_error_class,
    "NULL",
);

const js_reference_error_proto = [_]bt.PropDef{
    bt.propStringDef("name", "ReferenceError"),
    bt.propEnd(),
};
pub const js_reference_error_class: bt.ClassDef = bt.classMagicDef(
    "ReferenceError",
    1,
    "js_error_constructor",
    "JS_CLASS_REFERENCE_ERROR",
    null,
    &js_reference_error_proto,
    &js_error_class,
    "NULL",
);

const js_syntax_error_proto = [_]bt.PropDef{
    bt.propStringDef("name", "SyntaxError"),
    bt.propEnd(),
};
pub const js_syntax_error_class: bt.ClassDef = bt.classMagicDef(
    "SyntaxError",
    1,
    "js_error_constructor",
    "JS_CLASS_SYNTAX_ERROR",
    null,
    &js_syntax_error_proto,
    &js_error_class,
    "NULL",
);

const js_type_error_proto = [_]bt.PropDef{
    bt.propStringDef("name", "TypeError"),
    bt.propEnd(),
};
pub const js_type_error_class: bt.ClassDef = bt.classMagicDef(
    "TypeError",
    1,
    "js_error_constructor",
    "JS_CLASS_TYPE_ERROR",
    null,
    &js_type_error_proto,
    &js_error_class,
    "NULL",
);

const js_uri_error_proto = [_]bt.PropDef{
    bt.propStringDef("name", "URIError"),
    bt.propEnd(),
};
pub const js_uri_error_class: bt.ClassDef = bt.classMagicDef(
    "URIError",
    1,
    "js_error_constructor",
    "JS_CLASS_URI_ERROR",
    null,
    &js_uri_error_proto,
    &js_error_class,
    "NULL",
);

const js_internal_error_proto = [_]bt.PropDef{
    bt.propStringDef("name", "InternalError"),
    bt.propEnd(),
};
pub const js_internal_error_class: bt.ClassDef = bt.classMagicDef(
    "InternalError",
    1,
    "js_error_constructor",
    "JS_CLASS_INTERNAL_ERROR",
    null,
    &js_internal_error_proto,
    &js_error_class,
    "NULL",
);

const js_math = [_]bt.PropDef{
    bt.cfuncMagicDef("min", 2, "js_math_min_max", "0"),
    bt.cfuncMagicDef("max", 2, "js_math_min_max", "1"),
    bt.cfuncSpecialDef("sign", 1, "f_f", "js_math_sign"),
    bt.cfuncSpecialDef("abs", 1, "f_f", "js_fabs"),
    bt.cfuncSpecialDef("floor", 1, "f_f", "js_floor"),
    bt.cfuncSpecialDef("ceil", 1, "f_f", "js_ceil"),
    bt.cfuncSpecialDef("round", 1, "f_f", "js_round_inf"),
    bt.cfuncSpecialDef("sqrt", 1, "f_f", "js_sqrt"),
    bt.propDoubleDef("E", 2.718281828459045),
    bt.propDoubleDef("LN10", 2.302585092994046),
    bt.propDoubleDef("LN2", 0.6931471805599453),
    bt.propDoubleDef("LOG2E", 1.4426950408889634),
    bt.propDoubleDef("LOG10E", 0.4342944819032518),
    bt.propDoubleDef("PI", 3.141592653589793),
    bt.propDoubleDef("SQRT1_2", 0.7071067811865476),
    bt.propDoubleDef("SQRT2", 1.4142135623730951),
    bt.cfuncSpecialDef("sin", 1, "f_f", "js_sin"),
    bt.cfuncSpecialDef("cos", 1, "f_f", "js_cos"),
    bt.cfuncSpecialDef("tan", 1, "f_f", "js_tan"),
    bt.cfuncSpecialDef("asin", 1, "f_f", "js_asin"),
    bt.cfuncSpecialDef("acos", 1, "f_f", "js_acos"),
    bt.cfuncSpecialDef("atan", 1, "f_f", "js_atan"),
    bt.cfuncDef("atan2", 2, "js_math_atan2"),
    bt.cfuncSpecialDef("exp", 1, "f_f", "js_exp"),
    bt.cfuncSpecialDef("log", 1, "f_f", "js_log"),
    bt.cfuncDef("pow", 2, "js_math_pow"),
    bt.cfuncDef("random", 0, "js_math_random"),
    bt.cfuncDef("imul", 2, "js_math_imul"),
    bt.cfuncDef("clz32", 1, "js_math_clz32"),
    bt.cfuncSpecialDef("fround", 1, "f_f", "js_math_fround"),
    bt.cfuncSpecialDef("trunc", 1, "f_f", "js_trunc"),
    bt.cfuncSpecialDef("log2", 1, "f_f", "js_log2"),
    bt.cfuncSpecialDef("log10", 1, "f_f", "js_log10"),
    bt.propEnd(),
};

pub const js_math_obj: bt.ClassDef = bt.objectDef("Math", &js_math);

const js_json = [_]bt.PropDef{
    bt.cfuncDef("parse", 2, "js_json_parse"),
    bt.cfuncDef("stringify", 3, "js_json_stringify"),
    bt.propEnd(),
};

pub const js_json_obj: bt.ClassDef = bt.objectDef("JSON", &js_json);

const js_array_buffer_proto = [_]bt.PropDef{
    bt.cgetsetDef("byteLength", "js_array_buffer_get_byteLength", "NULL"),
    bt.propEnd(),
};

pub const js_array_buffer_class: bt.ClassDef = bt.classDef(
    "ArrayBuffer",
    1,
    "js_array_buffer_constructor",
    "JS_CLASS_ARRAY_BUFFER",
    null,
    &js_array_buffer_proto,
    null,
    "NULL",
);

const js_typed_array_base_proto = [_]bt.PropDef{
    bt.cgetsetMagicDef("length", "js_typed_array_get_length", "NULL", "0"),
    bt.cgetsetMagicDef("byteLength", "js_typed_array_get_length", "NULL", "1"),
    bt.cgetsetMagicDef("byteOffset", "js_typed_array_get_length", "NULL", "2"),
    bt.cgetsetMagicDef("buffer", "js_typed_array_get_length", "NULL", "3"),
    bt.cfuncDef("join", 1, "js_array_join"),
    bt.cfuncDef("toString", 0, "js_array_toString"),
    bt.cfuncDef("subarray", 2, "js_typed_array_subarray"),
    bt.cfuncDef("set", 1, "js_typed_array_set"),
    bt.propEnd(),
};

pub const js_typed_array_base_class: bt.ClassDef = bt.classDef(
    "TypedArray",
    0,
    "js_typed_array_base_constructor",
    "JS_CLASS_TYPED_ARRAY",
    null,
    &js_typed_array_base_proto,
    null,
    "NULL",
);

fn typedArrayProps(comptime bpe: f64) [2]bt.PropDef {
    return .{
        bt.propDoubleDef("BYTES_PER_ELEMENT", bpe),
        bt.propEnd(),
    };
}

const js_Uint8ClampedArray = typedArrayProps(1);
const js_Uint8ClampedArray_proto = typedArrayProps(1);
pub const js_Uint8ClampedArray_class: bt.ClassDef = bt.classMagicDef(
    "Uint8ClampedArray",
    3,
    "js_typed_array_constructor",
    "JS_CLASS_UINT8C_ARRAY",
    &js_Uint8ClampedArray,
    &js_Uint8ClampedArray_proto,
    &js_typed_array_base_class,
    "NULL",
);

const js_Int8Array = typedArrayProps(1);
const js_Int8Array_proto = typedArrayProps(1);
pub const js_Int8Array_class: bt.ClassDef = bt.classMagicDef(
    "Int8Array",
    3,
    "js_typed_array_constructor",
    "JS_CLASS_INT8_ARRAY",
    &js_Int8Array,
    &js_Int8Array_proto,
    &js_typed_array_base_class,
    "NULL",
);

const js_Uint8Array = typedArrayProps(1);
const js_Uint8Array_proto = typedArrayProps(1);
pub const js_Uint8Array_class: bt.ClassDef = bt.classMagicDef(
    "Uint8Array",
    3,
    "js_typed_array_constructor",
    "JS_CLASS_UINT8_ARRAY",
    &js_Uint8Array,
    &js_Uint8Array_proto,
    &js_typed_array_base_class,
    "NULL",
);

const js_Int16Array = typedArrayProps(2);
const js_Int16Array_proto = typedArrayProps(2);
pub const js_Int16Array_class: bt.ClassDef = bt.classMagicDef(
    "Int16Array",
    3,
    "js_typed_array_constructor",
    "JS_CLASS_INT16_ARRAY",
    &js_Int16Array,
    &js_Int16Array_proto,
    &js_typed_array_base_class,
    "NULL",
);

const js_Uint16Array = typedArrayProps(2);
const js_Uint16Array_proto = typedArrayProps(2);
pub const js_Uint16Array_class: bt.ClassDef = bt.classMagicDef(
    "Uint16Array",
    3,
    "js_typed_array_constructor",
    "JS_CLASS_UINT16_ARRAY",
    &js_Uint16Array,
    &js_Uint16Array_proto,
    &js_typed_array_base_class,
    "NULL",
);

const js_Int32Array = typedArrayProps(4);
const js_Int32Array_proto = typedArrayProps(4);
pub const js_Int32Array_class: bt.ClassDef = bt.classMagicDef(
    "Int32Array",
    3,
    "js_typed_array_constructor",
    "JS_CLASS_INT32_ARRAY",
    &js_Int32Array,
    &js_Int32Array_proto,
    &js_typed_array_base_class,
    "NULL",
);

const js_Uint32Array = typedArrayProps(4);
const js_Uint32Array_proto = typedArrayProps(4);
pub const js_Uint32Array_class: bt.ClassDef = bt.classMagicDef(
    "Uint32Array",
    3,
    "js_typed_array_constructor",
    "JS_CLASS_UINT32_ARRAY",
    &js_Uint32Array,
    &js_Uint32Array_proto,
    &js_typed_array_base_class,
    "NULL",
);

const js_Float32Array = typedArrayProps(4);
const js_Float32Array_proto = typedArrayProps(4);
pub const js_Float32Array_class: bt.ClassDef = bt.classMagicDef(
    "Float32Array",
    3,
    "js_typed_array_constructor",
    "JS_CLASS_FLOAT32_ARRAY",
    &js_Float32Array,
    &js_Float32Array_proto,
    &js_typed_array_base_class,
    "NULL",
);

const js_Float64Array = typedArrayProps(8);
const js_Float64Array_proto = typedArrayProps(8);
pub const js_Float64Array_class: bt.ClassDef = bt.classMagicDef(
    "Float64Array",
    3,
    "js_typed_array_constructor",
    "JS_CLASS_FLOAT64_ARRAY",
    &js_Float64Array,
    &js_Float64Array_proto,
    &js_typed_array_base_class,
    "NULL",
);

const js_regexp_proto = [_]bt.PropDef{
    bt.cgetsetDef("lastIndex", "js_regexp_get_lastIndex", "js_regexp_set_lastIndex"),
    bt.cgetsetDef("source", "js_regexp_get_source", "NULL"),
    bt.cgetsetDef("flags", "js_regexp_get_flags", "NULL"),
    bt.cfuncMagicDef("exec", 1, "js_regexp_exec", "0"),
    bt.cfuncMagicDef("test", 1, "js_regexp_exec", "1"),
    bt.propEnd(),
};

pub const js_regexp_class: bt.ClassDef = bt.classDef(
    "RegExp",
    2,
    "js_regexp_constructor",
    "JS_CLASS_REGEXP",
    null,
    &js_regexp_proto,
    null,
    "NULL",
);

const js_date = [_]bt.PropDef{
    bt.cfuncDef("now", 0, "js_date_now"),
    bt.propEnd(),
};

const js_date_proto = [_]bt.PropDef{
    bt.cfuncDef("valueOf", 0, "js_date_valueOf"),
    bt.propEnd(),
};

pub const js_date_class: bt.ClassDef = bt.classDef(
    "Date",
    7,
    "js_date_constructor",
    "JS_CLASS_DATE",
    &js_date,
    &js_date_proto,
    null,
    "NULL",
);

const js_console = [_]bt.PropDef{
    bt.cfuncDef("log", 1, "js_print"),
    bt.propEnd(),
};

pub const js_console_obj: bt.ClassDef = bt.objectDef("Console", &js_console);

const js_performance = [_]bt.PropDef{
    bt.cfuncDef("now", 0, "js_performance_now"),
    bt.propEnd(),
};

pub const js_performance_obj: bt.ClassDef = bt.objectDef("Performance", &js_performance);

const global_head = [_]bt.PropDef{
    bt.propClassDef("Object", &js_object_class),
    bt.propClassDef("Function", &js_function_class),
    bt.propClassDef("Number", &js_number_class),
    bt.propClassDef("Boolean", &js_boolean_class),
    bt.propClassDef("String", &js_string_class),
    bt.propClassDef("Array", &js_array_class),
    bt.propClassDef("Math", &js_math_obj),
    bt.propClassDef("Date", &js_date_class),
    bt.propClassDef("JSON", &js_json_obj),
    bt.propClassDef("RegExp", &js_regexp_class),
    bt.propClassDef("Error", &js_error_class),
    bt.propClassDef("EvalError", &js_eval_error_class),
    bt.propClassDef("RangeError", &js_range_error_class),
    bt.propClassDef("ReferenceError", &js_reference_error_class),
    bt.propClassDef("SyntaxError", &js_syntax_error_class),
    bt.propClassDef("TypeError", &js_type_error_class),
    bt.propClassDef("URIError", &js_uri_error_class),
    bt.propClassDef("InternalError", &js_internal_error_class),
    bt.propClassDef("ArrayBuffer", &js_array_buffer_class),
    bt.propClassDef("Uint8ClampedArray", &js_Uint8ClampedArray_class),
    bt.propClassDef("Int8Array", &js_Int8Array_class),
    bt.propClassDef("Uint8Array", &js_Uint8Array_class),
    bt.propClassDef("Int16Array", &js_Int16Array_class),
    bt.propClassDef("Uint16Array", &js_Uint16Array_class),
    bt.propClassDef("Int32Array", &js_Int32Array_class),
    bt.propClassDef("Uint32Array", &js_Uint32Array_class),
    bt.propClassDef("Float32Array", &js_Float32Array_class),
    bt.propClassDef("Float64Array", &js_Float64Array_class),
    bt.cfuncDef("parseInt", 2, "js_number_parseInt"),
    bt.cfuncDef("parseFloat", 1, "js_number_parseFloat"),
    bt.cfuncDef("eval", 1, "js_global_eval"),
    bt.cfuncDef("isNaN", 1, "js_global_isNaN"),
    bt.cfuncDef("isFinite", 1, "js_global_isFinite"),
    bt.propDoubleDef("Infinity", std.math.inf(f64)),
    bt.propDoubleDef("NaN", std.math.nan(f64)),
    bt.propUndefinedDef("undefined"),
    bt.propNullDef("globalThis"),
    bt.propClassDef("console", &js_console_obj),
    bt.propClassDef("performance", &js_performance_obj),
    bt.cfuncDef("print", 1, "js_print"),
};

pub fn globalProps(comptime cfg: Config) []const bt.PropDef {
    const S = struct {
        const tail = if (cfg.class_example) [_]bt.PropDef{
            bt.propClassDef("Rectangle", cfg.rectangle_class.?),
            bt.propClassDef("FilledRectangle", cfg.filled_rectangle_class.?),
            bt.propEnd(),
        } else [_]bt.PropDef{
            bt.cfuncDef("gc", 0, "js_gc"),
            bt.cfuncDef("load", 1, "js_load"),
            bt.cfuncDef("setTimeout", 2, "js_setTimeout"),
            bt.cfuncDef("clearTimeout", 1, "js_clearTimeout"),
            bt.propEnd(),
        };
        const props = global_head ++ tail;
    };
    return &S.props;
}

pub fn cFunctionDeclProps(comptime cfg: Config) []const bt.PropDef {
    const S = struct {
        const props = if (cfg.class_example) [_]bt.PropDef{
            bt.cfuncSpecialDef("bound", 0, "generic_params", "js_function_bound"),
            bt.cfuncSpecialDef("rectangle_closure_test", 0, "generic_params", "js_rectangle_closure_test"),
            bt.propEnd(),
        } else [_]bt.PropDef{
            bt.cfuncSpecialDef("bound", 0, "generic_params", "js_function_bound"),
            bt.propEnd(),
        };
    };
    return &S.props;
}
