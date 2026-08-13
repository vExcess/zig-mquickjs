//
// Micro QuickJS engine values (C ABI exports)
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

const lib = @import("mquickjs_value_lib.zig");
const vt = @import("mquickjs_value_types.zig");
const mc = vt.mc;
const c = lib.c;

export fn js_get_short_float(v: c.JSValue) f64 {
    return lib.js_get_short_float(v);
}

export fn js_to_short_float(d: f64) c.JSValue {
    return lib.js_to_short_float(d);
}

export fn js_alloc_float64(ctx: *c.JSContext, d: f64) c.JSValue {
    return lib.js_alloc_float64(ctx, d);
}

export fn __JS_NewFloat64(ctx: *c.JSContext, d: f64) c.JSValue {
    return lib.__JS_NewFloat64(ctx, d);
}

export fn JS_NewShortInt(val: i32) c.JSValue {
    return lib.JS_NewShortInt(val);
}

export fn JS_NewFloat64(ctx: *c.JSContext, d: f64) c.JSValue {
    return lib.JS_NewFloat64(ctx, d);
}

export fn int64_is_short_int(val: i64) c.JS_BOOL {
    return lib.int64_is_short_int(val);
}

export fn JS_NewInt64(ctx: *c.JSContext, val: i64) c.JSValue {
    return lib.JS_NewInt64(ctx, val);
}

export fn JS_NewInt32(ctx: *c.JSContext, val: i32) c.JSValue {
    return lib.JS_NewInt32(ctx, val);
}

export fn JS_NewUint32(ctx: *c.JSContext, val: u32) c.JSValue {
    return lib.JS_NewUint32(ctx, val);
}

export fn JS_IsPrimitive(ctx: *c.JSContext, val: c.JSValue) c.JS_BOOL {
    return lib.JS_IsPrimitive(ctx, val);
}

export fn JS_IsObject(ctx: *c.JSContext, val: c.JSValue) c.JS_BOOL {
    return lib.JS_IsObject(ctx, val);
}

export fn JS_GetClassID(ctx: *c.JSContext, val: c.JSValue) c_int {
    return lib.JS_GetClassID(ctx, val);
}

export fn JS_SetOpaque(ctx: *c.JSContext, val: c.JSValue, opaque_val: ?*anyopaque) void {
    lib.JS_SetOpaque(ctx, val, opaque_val);
}

export fn JS_GetOpaque(ctx: *c.JSContext, val: c.JSValue) ?*anyopaque {
    return lib.JS_GetOpaque(ctx, val);
}

export fn js_get_object_class(ctx: *c.JSContext, val: c.JSValue, class_id: c_int) ?*anyopaque {
    return @ptrCast(lib.js_get_object_class(ctx, val, class_id));
}

export fn JS_IsFunction(ctx: *c.JSContext, val: c.JSValue) c.JS_BOOL {
    return lib.JS_IsFunction(ctx, val);
}

export fn JS_IsFunctionObject(ctx: *c.JSContext, val: c.JSValue) c.JS_BOOL {
    return lib.JS_IsFunctionObject(ctx, val);
}

export fn JS_IsError(ctx: *c.JSContext, val: c.JSValue) c.JS_BOOL {
    return lib.JS_IsError(ctx, val);
}

export fn JS_IsNumber(ctx: *c.JSContext, val: c.JSValue) c.JS_BOOL {
    return lib.JS_IsNumber(ctx, val);
}

export fn JS_IsString(ctx: *c.JSContext, val: c.JSValue) c.JS_BOOL {
    return lib.JS_IsString(ctx, val);
}

export fn js_alloc_string(ctx: *c.JSContext, buf_len: u32) ?*anyopaque {
    return @ptrCast(lib.js_alloc_string(ctx, buf_len));
}

export fn JS_NewStringChar(ch: u32) c.JSValue {
    return lib.JS_NewStringChar(ch);
}

export fn is_ascii_string(buf: [*c]const u8, len: usize) c.JS_BOOL {
    return lib.is_ascii_string(buf, len);
}

export fn get_string_ptr(ctx: *c.JSContext, buf: *anyopaque, val: c.JSValue) *anyopaque {
    return @ptrCast(lib.get_string_ptr(ctx, @ptrCast(@alignCast(buf)), val));
}

export fn js_sub_string_utf8(ctx: *c.JSContext, val: c.JSValue, start0: u32, end0: u32) c.JSValue {
    return lib.js_sub_string_utf8(ctx, val, start0, end0);
}

export fn JS_NewStringLen(ctx: *c.JSContext, buf: [*c]const u8, len: usize) c.JSValue {
    return lib.JS_NewStringLen(ctx, buf, len);
}

export fn JS_NewString(ctx: *c.JSContext, buf: [*:0]const u8) c.JSValue {
    return lib.JS_NewString(ctx, buf);
}

export fn js_byte_array_to_string(ctx: *c.JSContext, val: c.JSValue, len: c_int, is_ascii: c.JS_BOOL) c.JSValue {
    return lib.js_byte_array_to_string(ctx, val, len, is_ascii);
}

export fn js_string_byte_len(ctx: *c.JSContext, val: c.JSValue) c_int {
    return lib.js_string_byte_len(ctx, val);
}

export fn is_valid_len4_utf8(buf: [*c]const u8) c.JS_BOOL {
    return lib.is_valid_len4_utf8(buf);
}

export fn dump_string_pos_cache(ctx: *c.JSContext) void {
    lib.dump_string_pos_cache(ctx);
}

export fn js_string_convert_pos(ctx: *c.JSContext, val: c.JSValue, pos: u32, pos_type: c_int) u32 {
    return lib.js_string_convert_pos(ctx, val, pos, pos_type);
}

export fn js_string_utf16_to_utf8_pos(ctx: *c.JSContext, val: c.JSValue, utf16_pos: u32) u32 {
    return lib.js_string_utf16_to_utf8_pos(ctx, val, utf16_pos);
}

export fn js_string_utf8_to_utf16_pos(ctx: *c.JSContext, val: c.JSValue, utf8_pos: u32) u32 {
    return lib.js_string_utf8_to_utf16_pos(ctx, val, utf8_pos);
}

export fn is_utf8_left_surrogate(p: [*c]const u8) c.JS_BOOL {
    return lib.is_utf8_left_surrogate(p);
}

export fn is_utf8_right_surrogate(p: [*c]const u8) c.JS_BOOL {
    return lib.is_utf8_right_surrogate(p);
}

export fn string_buffer_push(ctx: *c.JSContext, s: *anyopaque, len: c_int) c_int {
    return lib.string_buffer_push(ctx, @ptrCast(@alignCast(s)), len);
}

export fn string_buffer_concat_str(ctx: *c.JSContext, s: *anyopaque, val2: c.JSValue) c_int {
    return lib.string_buffer_concat_str(ctx, @ptrCast(@alignCast(s)), val2);
}

export fn string_buffer_concat_utf8(ctx: *c.JSContext, s: *anyopaque, str: c.JSValue, start: u32, end: u32) c_int {
    return lib.string_buffer_concat_utf8(ctx, @ptrCast(@alignCast(s)), str, start, end);
}

export fn string_buffer_concat_utf16(ctx: *c.JSContext, s: *anyopaque, str: c.JSValue, start: u32, end: u32) c_int {
    return lib.string_buffer_concat_utf16(ctx, @ptrCast(@alignCast(s)), str, start, end);
}

export fn string_buffer_concat(ctx: *c.JSContext, s: *anyopaque, val2: c.JSValue) c_int {
    return lib.string_buffer_concat(ctx, @ptrCast(@alignCast(s)), val2);
}

export fn string_buffer_putc(ctx: *c.JSContext, s: *anyopaque, ch: c_int) c_int {
    return lib.string_buffer_putc(ctx, @ptrCast(@alignCast(s)), ch);
}

export fn string_buffer_puts(ctx: *c.JSContext, s: *anyopaque, str: [*:0]const u8) c_int {
    return lib.string_buffer_puts(ctx, @ptrCast(@alignCast(s)), str);
}

export fn string_buffer_pop(ctx: *c.JSContext, s: *anyopaque) c.JSValue {
    return lib.string_buffer_pop(ctx, @ptrCast(@alignCast(s)));
}

export fn JS_ConcatString(ctx: *c.JSContext, val1: c.JSValue, val2: c.JSValue) c.JSValue {
    return lib.JS_ConcatString(ctx, val1, val2);
}

export fn js_string_eq(ctx: *c.JSContext, val1: c.JSValue, val2: c.JSValue) c.JS_BOOL {
    return lib.js_string_eq(ctx, val1, val2);
}

export fn string_get_cp(p: [*c]const u8) c_int {
    return lib.string_get_cp(p);
}

export fn js_string_compare(ctx: *c.JSContext, val1: c.JSValue, val2: c.JSValue) c_int {
    return lib.js_string_compare(ctx, val1, val2);
}

export fn js_string_len(ctx: *c.JSContext, val: c.JSValue) c_int {
    return lib.js_string_len(ctx, val);
}

export fn string_getcp(ctx: *c.JSContext, str: c.JSValue, utf16_pos: u32, is_codepoint: c.JS_BOOL) c_int {
    return lib.string_getcp(ctx, str, utf16_pos, is_codepoint);
}

export fn string_getc(ctx: *c.JSContext, str: c.JSValue, utf16_pos: u32) c_int {
    return lib.string_getc(ctx, str, utf16_pos);
}

export fn js_sub_string(ctx: *c.JSContext, val: c.JSValue, start: c_int, end: c_int) c.JSValue {
    return lib.js_sub_string(ctx, val, start, end);
}

export fn is_num(ch: c_int) c_int {
    return lib.is_num(ch);
}

export fn js_is_numeric_string(ctx: *c.JSContext, val: c.JSValue) c_int {
    return lib.js_is_numeric_string(ctx, val);
}

export fn find_atom(ctx: *c.JSContext, pidx: *c_int, arr: *const anyopaque, len: c_int, val: c.JSValue) c.JSValue {
    return lib.find_atom(ctx, pidx, @ptrCast(@alignCast(arr)), len, val);
}

export fn JS_MakeUniqueString(ctx: *c.JSContext, val: c.JSValue) c.JSValue {
    return lib.JS_MakeUniqueString(ctx, val);
}

export fn JS_ToBool(ctx: *c.JSContext, val: c.JSValue) c_int {
    return lib.JS_ToBool(ctx, val);
}

export fn JS_ToCStringLen(ctx: *c.JSContext, plen: ?*usize, val: c.JSValue, buf: *c.JSCStringBuf) ?[*:0]const u8 {
    return lib.JS_ToCStringLen(ctx, plen, val, buf);
}

export fn JS_ToCString(ctx: *c.JSContext, val: c.JSValue, buf: *c.JSCStringBuf) ?[*:0]const u8 {
    return lib.JS_ToCString(ctx, val, buf);
}

export fn JS_HasException(ctx: *c.JSContext) c.JS_BOOL {
    return lib.JS_HasException(ctx);
}

export fn JS_GetException(ctx: *c.JSContext) c.JSValue {
    return lib.JS_GetException(ctx);
}

export fn JS_ToStringCheckObject(ctx: *c.JSContext, val: c.JSValue) c.JSValue {
    return lib.JS_ToStringCheckObject(ctx, val);
}

export fn JS_ThrowTypeErrorNotAnObject(ctx: *c.JSContext) c.JSValue {
    return lib.JS_ThrowTypeErrorNotAnObject(ctx);
}

export fn is_num_string(ctx: *c.JSContext, pval: *i32, val: c.JSValue) c.JS_BOOL {
    return lib.is_num_string(ctx, pval, val);
}

export fn JS_IsNumericProperty(ctx: *c.JSContext, val: c.JSValue) c.JS_BOOL {
    return lib.JS_IsNumericProperty(ctx, val);
}

export fn js_alloc_value_array(ctx: *c.JSContext, init_base: c_int, new_size: c_int) ?*anyopaque {
    return @ptrCast(lib.js_alloc_value_array(ctx, init_base, new_size));
}

export fn js_resize_value_array2(ctx: *c.JSContext, val: c.JSValue, new_size: c_int, prop_base: c_int) c.JSValue {
    return lib.js_resize_value_array2(ctx, val, new_size, prop_base);
}

export fn js_resize_value_array(ctx: *c.JSContext, val: c.JSValue, new_size: c_int) c.JSValue {
    return lib.js_resize_value_array(ctx, val, new_size);
}

export fn js_shrink_value_array(ctx: *c.JSContext, pval: *c.JSValue, new_size: c_int) void {
    lib.js_shrink_value_array(ctx, pval, new_size);
}

export fn js_alloc_byte_array(ctx: *c.JSContext, size: c_int) ?*anyopaque {
    return @ptrCast(lib.js_alloc_byte_array(ctx, size));
}

export fn js_resize_byte_array(ctx: *c.JSContext, val: c.JSValue, new_size: c_int) c.JSValue {
    return lib.js_resize_byte_array(ctx, val, new_size);
}

export fn js_shrink_byte_array(ctx: *c.JSContext, pval: *c.JSValue, new_size: c_int) void {
    lib.js_shrink_byte_array(ctx, pval, new_size);
}

export fn JS_NewObjectProtoClass1(ctx: *c.JSContext, proto: c.JSValue, class_id: c_int, extra_size: c_int) ?*anyopaque {
    return @ptrCast(lib.JS_NewObjectProtoClass1(ctx, proto, class_id, extra_size));
}

export fn JS_NewObjectProtoClass(ctx: *c.JSContext, proto: c.JSValue, class_id: c_int, extra_size: c_int) c.JSValue {
    return lib.JS_NewObjectProtoClass(ctx, proto, class_id, extra_size);
}

export fn JS_NewObjectClass(ctx: *c.JSContext, class_id: c_int, extra_size: c_int) c.JSValue {
    return lib.JS_NewObjectClass(ctx, class_id, extra_size);
}

export fn JS_NewObjectClassUser(ctx: *c.JSContext, class_id: c_int) c.JSValue {
    return lib.JS_NewObjectClassUser(ctx, class_id);
}

export fn JS_NewObject(ctx: *c.JSContext) c.JSValue {
    return lib.JS_NewObject(ctx);
}

export fn JS_NewObjectPrealloc(ctx: *c.JSContext, n: c_int) c.JSValue {
    return lib.JS_NewObjectPrealloc(ctx, n);
}

export fn JS_NewArray(ctx: *c.JSContext, initial_len: c_int) c.JSValue {
    return lib.JS_NewArray(ctx, initial_len);
}

export fn find_own_property(ctx: *c.JSContext, p: *anyopaque, prop: c.JSValue) ?*anyopaque {
    return @ptrCast(lib.find_own_property(ctx, @ptrCast(@alignCast(p)), prop));
}

export fn get_special_prop(ctx: *c.JSContext, val: c.JSValue) c.JSValue {
    return lib.get_special_prop(ctx, val);
}

export fn JS_GetPropertyInternal(ctx: *c.JSContext, obj: c.JSValue, prop: c.JSValue, allow_tail_call: c.JS_BOOL) c.JSValue {
    return lib.JS_GetPropertyInternal(ctx, obj, prop, allow_tail_call);
}

export fn JS_GetProperty(ctx: *c.JSContext, obj: c.JSValue, prop: c.JSValue) c.JSValue {
    return lib.JS_GetProperty(ctx, obj, prop);
}

export fn JS_GetPropertyStr(ctx: *c.JSContext, this_obj: c.JSValue, str: [*:0]const u8) c.JSValue {
    return lib.JS_GetPropertyStr(ctx, this_obj, str);
}

export fn JS_GetPropertyUint32(ctx: *c.JSContext, obj: c.JSValue, idx: u32) c.JSValue {
    return lib.JS_GetPropertyUint32(ctx, obj, idx);
}

export fn JS_HasProperty(ctx: *c.JSContext, obj: c.JSValue, prop: c.JSValue) c.JS_BOOL {
    return lib.JS_HasProperty(ctx, obj, prop);
}

export fn get_prop_hash_size_log2(prop_count: c_int) c_int {
    return lib.get_prop_hash_size_log2(prop_count);
}

export fn js_alloc_props(ctx: *c.JSContext, n: c_int) ?*anyopaque {
    return @ptrCast(lib.js_alloc_props(ctx, n));
}

export fn js_rehash_props(ctx: *c.JSContext, p: *anyopaque, gc_rehash: c.JS_BOOL) void {
    lib.js_rehash_props(ctx, @ptrCast(@alignCast(p)), gc_rehash);
}

export fn js_compact_props(ctx: *c.JSContext, p: *anyopaque) void {
    lib.js_compact_props(ctx, @ptrCast(@alignCast(p)));
}

export fn js_update_props(ctx: *c.JSContext, obj: c.JSValue) c_int {
    return lib.js_update_props(ctx, obj);
}

export fn get_first_free(arr: *anyopaque) c_int {
    return lib.get_first_free(@ptrCast(@alignCast(arr)));
}

export fn js_create_property(ctx: *c.JSContext, obj: c.JSValue, prop: c.JSValue) ?*anyopaque {
    return @ptrCast(lib.js_create_property(ctx, obj, prop));
}

export fn JS_DefinePropertyInternal(ctx: *c.JSContext, obj: c.JSValue, prop: c.JSValue, val: c.JSValue, setter: c.JSValue, flags: c_int) c.JSValue {
    return lib.JS_DefinePropertyInternal(ctx, obj, prop, val, setter, flags);
}

export fn JS_DefinePropertyValue(ctx: *c.JSContext, obj: c.JSValue, prop: c.JSValue, val: c.JSValue) c.JSValue {
    return lib.JS_DefinePropertyValue(ctx, obj, prop, val);
}

export fn JS_DefinePropertyGetSet(ctx: *c.JSContext, obj: c.JSValue, prop: c.JSValue, getter: c.JSValue, setter: c.JSValue, flags: c_int) c.JSValue {
    return lib.JS_DefinePropertyGetSet(ctx, obj, prop, getter, setter, flags);
}

export fn add_global_var(ctx: *c.JSContext, prop: c.JSValue, define_flag: c.JS_BOOL) c.JSValue {
    return lib.add_global_var(ctx, prop, define_flag);
}

export fn JS_SetPropertyInternal(ctx: *c.JSContext, this_obj: c.JSValue, prop: c.JSValue, val: c.JSValue, allow_tail_call: c.JS_BOOL) c.JSValue {
    return lib.JS_SetPropertyInternal(ctx, this_obj, prop, val, allow_tail_call);
}

export fn JS_SetPropertyStr(ctx: *c.JSContext, this_obj: c.JSValue, str: [*:0]const u8, val: c.JSValue) c.JSValue {
    return lib.JS_SetPropertyStr(ctx, this_obj, str, val);
}

export fn JS_SetPropertyUint32(ctx: *c.JSContext, this_obj: c.JSValue, idx: u32, val: c.JSValue) c.JSValue {
    return lib.JS_SetPropertyUint32(ctx, this_obj, idx, val);
}

export fn JS_DeleteProperty(ctx: *c.JSContext, this_obj: c.JSValue, prop: c.JSValue) c.JSValue {
    return lib.JS_DeleteProperty(ctx, this_obj, prop);
}

export fn stdlib_init_class(ctx: *c.JSContext, class_def: *const anyopaque) c.JSValue {
    return lib.stdlib_init_class(ctx, @ptrCast(@alignCast(class_def)));
}

export fn stdlib_init(ctx: *c.JSContext, arr: *const anyopaque) void {
    lib.stdlib_init(ctx, @ptrCast(@alignCast(arr)));
}
