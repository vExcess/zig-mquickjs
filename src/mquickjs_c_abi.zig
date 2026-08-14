//
// Micro QuickJS engine C ABI (consolidated export fn symbols)
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
// Step 5: single-engine-unit C ABI layer (merged from per-module export roots)

const std = @import("std");

const utils = @import("mquickjs_utils_lib.zig");
const value = @import("mquickjs_value_lib.zig");
const runtime = @import("mquickjs_runtime_lib.zig");
const lexer = @import("mquickjs_lexer_lib.zig");
const parser = @import("mquickjs_parser_lib.zig");
const gc = @import("mquickjs_gc_lib.zig");
const builtins = @import("mquickjs_builtins_lib.zig");

const mc = @import("mquickjs_utils_types.zig");
const rt = @import("mquickjs_runtime_types.zig");
const lt = @import("mquickjs_lexer_types.zig");
const pt = @import("mquickjs_parser_types.zig");
const gt = @import("mquickjs_gc_types.zig");
const bt = @import("mquickjs_builtins_types.zig");
const c = mc.c;

fn abiCall(comptime f: anytype, args: std.meta.ArgsTuple(@TypeOf(f))) @typeInfo(@TypeOf(f)).@"fn".return_type.? {
    // Keep C ABI wrappers as optimization barriers. Same-CU extern+export
    // would otherwise inline across old object boundaries and change codegen
    // of tagged-pointer JSValues.
    return @call(.never_inline, f, args);
}


// --- mquickjs_utils ---

export const js_mtag_name = utils.js_mtag_name;

export fn JS_PushGCRef(ctx: *c.JSContext, ref: *c.JSGCRef) *c.JSValue {
    return abiCall(utils.JS_PushGCRef, .{ ctx, ref });
}

export fn JS_PopGCRef(ctx: *c.JSContext, ref: *c.JSGCRef) c.JSValue {
    return abiCall(utils.JS_PopGCRef, .{ ctx, ref });
}

export fn JS_AddGCRef(ctx: *c.JSContext, ref: *c.JSGCRef) *c.JSValue {
    return abiCall(utils.JS_AddGCRef, .{ ctx, ref });
}

export fn JS_DeleteGCRef(ctx: *c.JSContext, ref: *c.JSGCRef) void {
    abiCall(utils.JS_DeleteGCRef, .{ ctx, ref });
}

export fn js_get_atom(ctx: *c.JSContext, a: c_int) c.JSValue {
    return abiCall(utils.js_get_atom, .{ ctx, a });
}

export fn JS_IsExceptionOrTailCall(v: c.JSValue) c.JS_BOOL {
    return abiCall(utils.JS_IsExceptionOrTailCall, .{ v });
}

export fn js_get_mtag(ptr: *anyopaque) c_int {
    return abiCall(utils.js_get_mtag, .{ ptr });
}

export fn JS_StackCheck(ctx: *c.JSContext, len: c_uint) c_int {
    return abiCall(utils.JS_StackCheck, .{ ctx, len });
}

export fn js_malloc(ctx: *c.JSContext, size: c_uint, mtag: c_int) ?*anyopaque {
    return abiCall(utils.js_malloc, .{ ctx, size, mtag });
}

export fn js_mallocz(ctx: *c.JSContext, size: c_uint, mtag: c_int) ?*anyopaque {
    return abiCall(utils.js_mallocz, .{ ctx, size, mtag });
}

export fn js_free(ctx: *c.JSContext, ptr: ?*anyopaque) void {
    abiCall(utils.js_free, .{ ctx, ptr });
}

export fn set_free_block(ptr: *anyopaque, size: c_uint) void {
    abiCall(utils.set_free_block, .{ ptr, size });
}

export fn js_shrink(ctx: *c.JSContext, ptr: ?*anyopaque, new_size: c_uint) ?*anyopaque {
    return abiCall(utils.js_shrink, .{ ctx, ptr, new_size });
}

export fn JS_Throw(ctx: *c.JSContext, obj: c.JSValue) c.JSValue {
    return abiCall(utils.JS_Throw, .{ ctx, obj });
}

export fn get_short_string(buf: [*c]u8, val: c.JSValue) c_int {
    return abiCall(utils.get_short_string, .{ buf, val });
}

export fn is_digit(ch: c_int) c.JS_BOOL {
    return abiCall(utils.is_digit, .{ ch });
}

export fn is_ident_next(ch: c_int) c_int {
    return abiCall(utils.is_ident_next, .{ ch });
}

export fn js_vprintf(write_func: mc.JSWriteFn, opaque_val: ?*anyopaque, fmt: [*:0]const u8, ap: *anyopaque) callconv(.c) void {
    abiCall(utils.js_vprintf, .{ write_func, opaque_val, fmt, ap });
}

export fn js_vsnprintf(buf: [*c]u8, buf_size: usize, fmt: [*:0]const u8, ap: *anyopaque) callconv(.c) c_int {
    return abiCall(utils.js_vsnprintf, .{ buf, buf_size, fmt, ap });
}

export fn js_snprintf(buf: [*c]u8, buf_size: usize, fmt: [*:0]const u8, ...) callconv(.c) c_int {
    var ap = @cVaStart();
    defer @cVaEnd(&ap);
    return abiCall(utils.js_vsnprintf, .{ buf, buf_size, fmt, @ptrCast(&ap) });
}

export fn js_printf(ctx: *c.JSContext, fmt: [*:0]const u8, ...) callconv(.c) void {
    var ap = @cVaStart();
    defer @cVaEnd(&ap);
    const x = mc.ctxExt(ctx);
    abiCall(utils.js_vprintf, .{ x.write_func.?, x.opaque_val, fmt, @ptrCast(&ap) });
}

export fn js_putchar(ctx: *c.JSContext, ch: u8) void {
    abiCall(utils.js_putchar, .{ ctx, ch });
}

export fn JS_ThrowError(ctx: *c.JSContext, error_num: c.JSObjectClassEnum, fmt: [*:0]const u8, ...) callconv(.c) c.JSValue {
    var ap = @cVaStart();
    defer @cVaEnd(&ap);
    return abiCall(utils.jsThrowErrorVa, .{ ctx, error_num, fmt, @ptrCast(&ap) });
}

export fn JS_ThrowOutOfMemory(ctx: *c.JSContext) c.JSValue {
    return abiCall(utils.JS_ThrowOutOfMemory, .{ ctx });
}

export fn JS_PrintValueF(ctx: *c.JSContext, val: c.JSValue, flags: c_int) void {
    abiCall(utils.JS_PrintValueF, .{ ctx, val, flags });
}

export fn JS_PrintValue(ctx: *c.JSContext, val: c.JSValue) void {
    abiCall(utils.JS_PrintValue, .{ ctx, val });
}

export fn JS_DumpMemory(ctx: *c.JSContext, is_long: c.JS_BOOL) void {
    abiCall(utils.JS_DumpMemory, .{ ctx, is_long });
}

export fn JS_DumpValueF(ctx: *c.JSContext, str: [*:0]const u8, val: c.JSValue, flags: c_int) void {
    abiCall(utils.JS_DumpValueF, .{ ctx, str, val, flags });
}

export fn JS_DumpValue(ctx: *c.JSContext, str: [*:0]const u8, val: c.JSValue) void {
    abiCall(utils.JS_DumpValue, .{ ctx, str, val });
}

// --- mquickjs_value ---

export fn js_get_short_float(v: c.JSValue) f64 {
    return abiCall(value.js_get_short_float, .{ v });
}

export fn js_to_short_float(d: f64) c.JSValue {
    return abiCall(value.js_to_short_float, .{ d });
}

export fn js_alloc_float64(ctx: *c.JSContext, d: f64) c.JSValue {
    return abiCall(value.js_alloc_float64, .{ ctx, d });
}

export fn __JS_NewFloat64(ctx: *c.JSContext, d: f64) c.JSValue {
    return abiCall(value.__JS_NewFloat64, .{ ctx, d });
}

export fn JS_NewShortInt(val: i32) c.JSValue {
    return abiCall(value.JS_NewShortInt, .{ val });
}

export fn JS_NewFloat64(ctx: *c.JSContext, d: f64) c.JSValue {
    return abiCall(value.JS_NewFloat64, .{ ctx, d });
}

export fn int64_is_short_int(val: i64) c.JS_BOOL {
    return abiCall(value.int64_is_short_int, .{ val });
}

export fn JS_NewInt64(ctx: *c.JSContext, val: i64) c.JSValue {
    return abiCall(value.JS_NewInt64, .{ ctx, val });
}

export fn JS_NewInt32(ctx: *c.JSContext, val: i32) c.JSValue {
    return abiCall(value.JS_NewInt32, .{ ctx, val });
}

export fn JS_NewUint32(ctx: *c.JSContext, val: u32) c.JSValue {
    return abiCall(value.JS_NewUint32, .{ ctx, val });
}

export fn JS_IsPrimitive(ctx: *c.JSContext, val: c.JSValue) c.JS_BOOL {
    return abiCall(value.JS_IsPrimitive, .{ ctx, val });
}

export fn JS_IsObject(ctx: *c.JSContext, val: c.JSValue) c.JS_BOOL {
    return abiCall(value.JS_IsObject, .{ ctx, val });
}

export fn JS_GetClassID(ctx: *c.JSContext, val: c.JSValue) c_int {
    return abiCall(value.JS_GetClassID, .{ ctx, val });
}

export fn JS_SetOpaque(ctx: *c.JSContext, val: c.JSValue, opaque_val: ?*anyopaque) void {
    abiCall(value.JS_SetOpaque, .{ ctx, val, opaque_val });
}

export fn JS_GetOpaque(ctx: *c.JSContext, val: c.JSValue) ?*anyopaque {
    return abiCall(value.JS_GetOpaque, .{ ctx, val });
}

export fn js_get_object_class(ctx: *c.JSContext, val: c.JSValue, class_id: c_int) ?*anyopaque {
    return @ptrCast(abiCall(value.js_get_object_class, .{ ctx, val, class_id }));
}

export fn JS_IsFunction(ctx: *c.JSContext, val: c.JSValue) c.JS_BOOL {
    return abiCall(value.JS_IsFunction, .{ ctx, val });
}

export fn JS_IsFunctionObject(ctx: *c.JSContext, val: c.JSValue) c.JS_BOOL {
    return abiCall(value.JS_IsFunctionObject, .{ ctx, val });
}

export fn JS_IsError(ctx: *c.JSContext, val: c.JSValue) c.JS_BOOL {
    return abiCall(value.JS_IsError, .{ ctx, val });
}

export fn JS_IsNumber(ctx: *c.JSContext, val: c.JSValue) c.JS_BOOL {
    return abiCall(value.JS_IsNumber, .{ ctx, val });
}

export fn JS_IsString(ctx: *c.JSContext, val: c.JSValue) c.JS_BOOL {
    return abiCall(value.JS_IsString, .{ ctx, val });
}

export fn js_alloc_string(ctx: *c.JSContext, buf_len: u32) ?*anyopaque {
    return @ptrCast(abiCall(value.js_alloc_string, .{ ctx, buf_len }));
}

export fn JS_NewStringChar(ch: u32) c.JSValue {
    return abiCall(value.JS_NewStringChar, .{ ch });
}

export fn is_ascii_string(buf: [*c]const u8, len: usize) c.JS_BOOL {
    return abiCall(value.is_ascii_string, .{ buf, len });
}

export fn get_string_ptr(ctx: *c.JSContext, buf: *anyopaque, val: c.JSValue) *anyopaque {
    return @ptrCast(abiCall(value.get_string_ptr, .{ ctx, @ptrCast(@alignCast(buf)), val }));
}

export fn js_sub_string_utf8(ctx: *c.JSContext, val: c.JSValue, start0: u32, end0: u32) c.JSValue {
    return abiCall(value.js_sub_string_utf8, .{ ctx, val, start0, end0 });
}

export fn JS_NewStringLen(ctx: *c.JSContext, buf: [*c]const u8, len: usize) c.JSValue {
    return abiCall(value.JS_NewStringLen, .{ ctx, buf, len });
}

export fn JS_NewString(ctx: *c.JSContext, buf: [*:0]const u8) c.JSValue {
    return abiCall(value.JS_NewString, .{ ctx, buf });
}

export fn js_byte_array_to_string(ctx: *c.JSContext, val: c.JSValue, len: c_int, is_ascii: c.JS_BOOL) c.JSValue {
    return abiCall(value.js_byte_array_to_string, .{ ctx, val, len, is_ascii });
}

export fn js_string_byte_len(ctx: *c.JSContext, val: c.JSValue) c_int {
    return abiCall(value.js_string_byte_len, .{ ctx, val });
}

export fn is_valid_len4_utf8(buf: [*c]const u8) c.JS_BOOL {
    return abiCall(value.is_valid_len4_utf8, .{ buf });
}

export fn dump_string_pos_cache(ctx: *c.JSContext) void {
    abiCall(value.dump_string_pos_cache, .{ ctx });
}

export fn js_string_convert_pos(ctx: *c.JSContext, val: c.JSValue, pos: u32, pos_type: c_int) u32 {
    return abiCall(value.js_string_convert_pos, .{ ctx, val, pos, pos_type });
}

export fn js_string_utf16_to_utf8_pos(ctx: *c.JSContext, val: c.JSValue, utf16_pos: u32) u32 {
    return abiCall(value.js_string_utf16_to_utf8_pos, .{ ctx, val, utf16_pos });
}

export fn js_string_utf8_to_utf16_pos(ctx: *c.JSContext, val: c.JSValue, utf8_pos: u32) u32 {
    return abiCall(value.js_string_utf8_to_utf16_pos, .{ ctx, val, utf8_pos });
}

export fn is_utf8_left_surrogate(p: [*c]const u8) c.JS_BOOL {
    return abiCall(value.is_utf8_left_surrogate, .{ p });
}

export fn is_utf8_right_surrogate(p: [*c]const u8) c.JS_BOOL {
    return abiCall(value.is_utf8_right_surrogate, .{ p });
}

export fn string_buffer_push(ctx: *c.JSContext, s: *anyopaque, len: c_int) c_int {
    return abiCall(value.string_buffer_push, .{ ctx, @ptrCast(@alignCast(s)), len });
}

export fn string_buffer_concat_str(ctx: *c.JSContext, s: *anyopaque, val2: c.JSValue) c_int {
    return abiCall(value.string_buffer_concat_str, .{ ctx, @ptrCast(@alignCast(s)), val2 });
}

export fn string_buffer_concat_utf8(ctx: *c.JSContext, s: *anyopaque, str: c.JSValue, start: u32, end: u32) c_int {
    return abiCall(value.string_buffer_concat_utf8, .{ ctx, @ptrCast(@alignCast(s)), str, start, end });
}

export fn string_buffer_concat_utf16(ctx: *c.JSContext, s: *anyopaque, str: c.JSValue, start: u32, end: u32) c_int {
    return abiCall(value.string_buffer_concat_utf16, .{ ctx, @ptrCast(@alignCast(s)), str, start, end });
}

export fn string_buffer_concat(ctx: *c.JSContext, s: *anyopaque, val2: c.JSValue) c_int {
    return abiCall(value.string_buffer_concat, .{ ctx, @ptrCast(@alignCast(s)), val2 });
}

export fn string_buffer_putc(ctx: *c.JSContext, s: *anyopaque, ch: c_int) c_int {
    return abiCall(value.string_buffer_putc, .{ ctx, @ptrCast(@alignCast(s)), ch });
}

export fn string_buffer_puts(ctx: *c.JSContext, s: *anyopaque, str: [*:0]const u8) c_int {
    return abiCall(value.string_buffer_puts, .{ ctx, @ptrCast(@alignCast(s)), str });
}

export fn string_buffer_pop(ctx: *c.JSContext, s: *anyopaque) c.JSValue {
    return abiCall(value.string_buffer_pop, .{ ctx, @ptrCast(@alignCast(s)) });
}

export fn JS_ConcatString(ctx: *c.JSContext, val1: c.JSValue, val2: c.JSValue) c.JSValue {
    return abiCall(value.JS_ConcatString, .{ ctx, val1, val2 });
}

export fn js_string_eq(ctx: *c.JSContext, val1: c.JSValue, val2: c.JSValue) c.JS_BOOL {
    return abiCall(value.js_string_eq, .{ ctx, val1, val2 });
}

export fn string_get_cp(p: [*c]const u8) c_int {
    return abiCall(value.string_get_cp, .{ p });
}

export fn js_string_compare(ctx: *c.JSContext, val1: c.JSValue, val2: c.JSValue) c_int {
    return abiCall(value.js_string_compare, .{ ctx, val1, val2 });
}

export fn js_string_len(ctx: *c.JSContext, val: c.JSValue) c_int {
    return abiCall(value.js_string_len, .{ ctx, val });
}

export fn string_getcp(ctx: *c.JSContext, str: c.JSValue, utf16_pos: u32, is_codepoint: c.JS_BOOL) c_int {
    return abiCall(value.string_getcp, .{ ctx, str, utf16_pos, is_codepoint });
}

export fn string_getc(ctx: *c.JSContext, str: c.JSValue, utf16_pos: u32) c_int {
    return abiCall(value.string_getc, .{ ctx, str, utf16_pos });
}

export fn js_sub_string(ctx: *c.JSContext, val: c.JSValue, start: c_int, end: c_int) c.JSValue {
    return abiCall(value.js_sub_string, .{ ctx, val, start, end });
}

export fn is_num(ch: c_int) c_int {
    return abiCall(value.is_num, .{ ch });
}

export fn js_is_numeric_string(ctx: *c.JSContext, val: c.JSValue) c_int {
    return abiCall(value.js_is_numeric_string, .{ ctx, val });
}

export fn find_atom(ctx: *c.JSContext, pidx: *c_int, arr: *const anyopaque, len: c_int, val: c.JSValue) c.JSValue {
    return abiCall(value.find_atom, .{ ctx, pidx, @ptrCast(@alignCast(arr)), len, val });
}

export fn JS_MakeUniqueString(ctx: *c.JSContext, val: c.JSValue) c.JSValue {
    return abiCall(value.JS_MakeUniqueString, .{ ctx, val });
}

export fn JS_ToBool(ctx: *c.JSContext, val: c.JSValue) c_int {
    return abiCall(value.JS_ToBool, .{ ctx, val });
}

export fn JS_ToCStringLen(ctx: *c.JSContext, plen: ?*usize, val: c.JSValue, buf: *c.JSCStringBuf) ?[*:0]const u8 {
    return abiCall(value.JS_ToCStringLen, .{ ctx, plen, val, buf });
}

export fn JS_ToCString(ctx: *c.JSContext, val: c.JSValue, buf: *c.JSCStringBuf) ?[*:0]const u8 {
    return abiCall(value.JS_ToCString, .{ ctx, val, buf });
}

export fn JS_HasException(ctx: *c.JSContext) c.JS_BOOL {
    return abiCall(value.JS_HasException, .{ ctx });
}

export fn JS_GetException(ctx: *c.JSContext) c.JSValue {
    return abiCall(value.JS_GetException, .{ ctx });
}

export fn JS_ToStringCheckObject(ctx: *c.JSContext, val: c.JSValue) c.JSValue {
    return abiCall(value.JS_ToStringCheckObject, .{ ctx, val });
}

export fn JS_ThrowTypeErrorNotAnObject(ctx: *c.JSContext) c.JSValue {
    return abiCall(value.JS_ThrowTypeErrorNotAnObject, .{ ctx });
}

export fn is_num_string(ctx: *c.JSContext, pval: *i32, val: c.JSValue) c.JS_BOOL {
    return abiCall(value.is_num_string, .{ ctx, pval, val });
}

export fn JS_IsNumericProperty(ctx: *c.JSContext, val: c.JSValue) c.JS_BOOL {
    return abiCall(value.JS_IsNumericProperty, .{ ctx, val });
}

export fn js_alloc_value_array(ctx: *c.JSContext, init_base: c_int, new_size: c_int) ?*anyopaque {
    return @ptrCast(abiCall(value.js_alloc_value_array, .{ ctx, init_base, new_size }));
}

export fn js_resize_value_array2(ctx: *c.JSContext, val: c.JSValue, new_size: c_int, prop_base: c_int) c.JSValue {
    return abiCall(value.js_resize_value_array2, .{ ctx, val, new_size, prop_base });
}

export fn js_resize_value_array(ctx: *c.JSContext, val: c.JSValue, new_size: c_int) c.JSValue {
    return abiCall(value.js_resize_value_array, .{ ctx, val, new_size });
}

export fn js_shrink_value_array(ctx: *c.JSContext, pval: *c.JSValue, new_size: c_int) void {
    abiCall(value.js_shrink_value_array, .{ ctx, pval, new_size });
}

export fn js_alloc_byte_array(ctx: *c.JSContext, size: c_int) ?*anyopaque {
    return @ptrCast(abiCall(value.js_alloc_byte_array, .{ ctx, size }));
}

export fn js_resize_byte_array(ctx: *c.JSContext, val: c.JSValue, new_size: c_int) c.JSValue {
    return abiCall(value.js_resize_byte_array, .{ ctx, val, new_size });
}

export fn js_shrink_byte_array(ctx: *c.JSContext, pval: *c.JSValue, new_size: c_int) void {
    abiCall(value.js_shrink_byte_array, .{ ctx, pval, new_size });
}

export fn JS_NewObjectProtoClass1(ctx: *c.JSContext, proto: c.JSValue, class_id: c_int, extra_size: c_int) ?*anyopaque {
    return @ptrCast(abiCall(value.JS_NewObjectProtoClass1, .{ ctx, proto, class_id, extra_size }));
}

export fn JS_NewObjectProtoClass(ctx: *c.JSContext, proto: c.JSValue, class_id: c_int, extra_size: c_int) c.JSValue {
    return abiCall(value.JS_NewObjectProtoClass, .{ ctx, proto, class_id, extra_size });
}

export fn JS_NewObjectClass(ctx: *c.JSContext, class_id: c_int, extra_size: c_int) c.JSValue {
    return abiCall(value.JS_NewObjectClass, .{ ctx, class_id, extra_size });
}

export fn JS_NewObjectClassUser(ctx: *c.JSContext, class_id: c_int) c.JSValue {
    return abiCall(value.JS_NewObjectClassUser, .{ ctx, class_id });
}

export fn JS_NewObject(ctx: *c.JSContext) c.JSValue {
    return abiCall(value.JS_NewObject, .{ ctx });
}

export fn JS_NewObjectPrealloc(ctx: *c.JSContext, n: c_int) c.JSValue {
    return abiCall(value.JS_NewObjectPrealloc, .{ ctx, n });
}

export fn JS_NewArray(ctx: *c.JSContext, initial_len: c_int) c.JSValue {
    return abiCall(value.JS_NewArray, .{ ctx, initial_len });
}

export fn find_own_property(ctx: *c.JSContext, p: *anyopaque, prop: c.JSValue) ?*anyopaque {
    return @ptrCast(abiCall(value.find_own_property, .{ ctx, @ptrCast(@alignCast(p)), prop }));
}

export fn get_special_prop(ctx: *c.JSContext, val: c.JSValue) c.JSValue {
    return abiCall(value.get_special_prop, .{ ctx, val });
}

export fn JS_GetPropertyInternal(ctx: *c.JSContext, obj: c.JSValue, prop: c.JSValue, allow_tail_call: c.JS_BOOL) c.JSValue {
    return abiCall(value.JS_GetPropertyInternal, .{ ctx, obj, prop, allow_tail_call });
}

export fn JS_GetProperty(ctx: *c.JSContext, obj: c.JSValue, prop: c.JSValue) c.JSValue {
    return abiCall(value.JS_GetProperty, .{ ctx, obj, prop });
}

export fn JS_GetPropertyStr(ctx: *c.JSContext, this_obj: c.JSValue, str: [*:0]const u8) c.JSValue {
    return abiCall(value.JS_GetPropertyStr, .{ ctx, this_obj, str });
}

export fn JS_GetPropertyUint32(ctx: *c.JSContext, obj: c.JSValue, idx: u32) c.JSValue {
    return abiCall(value.JS_GetPropertyUint32, .{ ctx, obj, idx });
}

export fn JS_HasProperty(ctx: *c.JSContext, obj: c.JSValue, prop: c.JSValue) c.JS_BOOL {
    return abiCall(value.JS_HasProperty, .{ ctx, obj, prop });
}

export fn get_prop_hash_size_log2(prop_count: c_int) c_int {
    return abiCall(value.get_prop_hash_size_log2, .{ prop_count });
}

export fn js_alloc_props(ctx: *c.JSContext, n: c_int) ?*anyopaque {
    return @ptrCast(abiCall(value.js_alloc_props, .{ ctx, n }));
}

export fn js_rehash_props(ctx: *c.JSContext, p: *anyopaque, gc_rehash: c.JS_BOOL) void {
    abiCall(value.js_rehash_props, .{ ctx, @ptrCast(@alignCast(p)), gc_rehash });
}

export fn js_compact_props(ctx: *c.JSContext, p: *anyopaque) void {
    abiCall(value.js_compact_props, .{ ctx, @ptrCast(@alignCast(p)) });
}

export fn js_update_props(ctx: *c.JSContext, obj: c.JSValue) c_int {
    return abiCall(value.js_update_props, .{ ctx, obj });
}

export fn get_first_free(arr: *anyopaque) c_int {
    return abiCall(value.get_first_free, .{ @ptrCast(@alignCast(arr)) });
}

export fn js_create_property(ctx: *c.JSContext, obj: c.JSValue, prop: c.JSValue) ?*anyopaque {
    return @ptrCast(abiCall(value.js_create_property, .{ ctx, obj, prop }));
}

export fn JS_DefinePropertyInternal(ctx: *c.JSContext, obj: c.JSValue, prop: c.JSValue, val: c.JSValue, setter: c.JSValue, flags: c_int) c.JSValue {
    return abiCall(value.JS_DefinePropertyInternal, .{ ctx, obj, prop, val, setter, flags });
}

export fn JS_DefinePropertyValue(ctx: *c.JSContext, obj: c.JSValue, prop: c.JSValue, val: c.JSValue) c.JSValue {
    return abiCall(value.JS_DefinePropertyValue, .{ ctx, obj, prop, val });
}

export fn JS_DefinePropertyGetSet(ctx: *c.JSContext, obj: c.JSValue, prop: c.JSValue, getter: c.JSValue, setter: c.JSValue, flags: c_int) c.JSValue {
    return abiCall(value.JS_DefinePropertyGetSet, .{ ctx, obj, prop, getter, setter, flags });
}

export fn add_global_var(ctx: *c.JSContext, prop: c.JSValue, define_flag: c.JS_BOOL) c.JSValue {
    return abiCall(value.add_global_var, .{ ctx, prop, define_flag });
}

export fn JS_SetPropertyInternal(ctx: *c.JSContext, this_obj: c.JSValue, prop: c.JSValue, val: c.JSValue, allow_tail_call: c.JS_BOOL) c.JSValue {
    return abiCall(value.JS_SetPropertyInternal, .{ ctx, this_obj, prop, val, allow_tail_call });
}

export fn JS_SetPropertyStr(ctx: *c.JSContext, this_obj: c.JSValue, str: [*:0]const u8, val: c.JSValue) c.JSValue {
    return abiCall(value.JS_SetPropertyStr, .{ ctx, this_obj, str, val });
}

export fn JS_SetPropertyUint32(ctx: *c.JSContext, this_obj: c.JSValue, idx: u32, val: c.JSValue) c.JSValue {
    return abiCall(value.JS_SetPropertyUint32, .{ ctx, this_obj, idx, val });
}

export fn JS_DeleteProperty(ctx: *c.JSContext, this_obj: c.JSValue, prop: c.JSValue) c.JSValue {
    return abiCall(value.JS_DeleteProperty, .{ ctx, this_obj, prop });
}

export fn stdlib_init_class(ctx: *c.JSContext, class_def: *const anyopaque) c.JSValue {
    return abiCall(value.stdlib_init_class, .{ ctx, @ptrCast(@alignCast(class_def)) });
}

export fn stdlib_init(ctx: *c.JSContext, arr: *const anyopaque) void {
    abiCall(value.stdlib_init, .{ ctx, @ptrCast(@alignCast(arr)) });
}

// --- mquickjs_runtime ---

export const opcode_info: [rt.OP.COUNT]rt.JSOpCodeExt = rt.opcode_info_data;

export fn dummy_write_func(opaque_val: ?*anyopaque, buf: ?*const anyopaque, buf_len: usize) void {
    abiCall(runtime.dummy_write_func, .{ opaque_val, buf, buf_len });
}

export fn JS_NewContext2(mem_start: *anyopaque, mem_size: usize, stdlib_def: *const c.JSSTDLibraryDef, prepare_compilation: c.JS_BOOL) *c.JSContext {
    return abiCall(runtime.JS_NewContext2, .{ mem_start, mem_size, stdlib_def, prepare_compilation });
}

export fn JS_NewContext(mem_start: *anyopaque, mem_size: usize, stdlib_def: *const c.JSSTDLibraryDef) *c.JSContext {
    return abiCall(runtime.JS_NewContext, .{ mem_start, mem_size, stdlib_def });
}

export fn JS_FreeContext(ctx: *c.JSContext) void {
    abiCall(runtime.JS_FreeContext, .{ ctx });
}

export fn JS_SetContextOpaque(ctx: *c.JSContext, opaque_val: ?*anyopaque) void {
    abiCall(runtime.JS_SetContextOpaque, .{ ctx, opaque_val });
}

export fn JS_GetContextOpaque(ctx: *c.JSContext) ?*anyopaque {
    return abiCall(runtime.JS_GetContextOpaque, .{ ctx });
}

export fn JS_SetInterruptHandler(ctx: *c.JSContext, interrupt_handler: ?*anyopaque) void {
    abiCall(runtime.JS_SetInterruptHandler, .{ ctx, interrupt_handler });
}

export fn JS_SetLogFunc(ctx: *c.JSContext, write_func: ?rt.mc.JSWriteFn) void {
    abiCall(runtime.JS_SetLogFunc, .{ ctx, write_func });
}

export fn JS_SetRandomSeed(ctx: *c.JSContext, seed: u64) void {
    abiCall(runtime.JS_SetRandomSeed, .{ ctx, seed });
}

export fn JS_GetGlobalObject(ctx: *c.JSContext) c.JSValue {
    return abiCall(runtime.JS_GetGlobalObject, .{ ctx });
}

export fn get_var_ref(ctx: *c.JSContext, pfirst_var_ref: *c.JSValue, pval: *c.JSValue) c.JSValue {
    return abiCall(runtime.get_var_ref, .{ ctx, pfirst_var_ref, pval });
}

export fn reloc_c_func_name(ctx: *c.JSContext, val: c.JSValue) c.JSValue {
    return abiCall(runtime.reloc_c_func_name, .{ ctx, val });
}

export fn js_function_get_length_name1(ctx: *c.JSContext, this_val: *c.JSValue, is_name: c_int, pb: *?*anyopaque) c.JSValue {
    return abiCall(runtime.js_function_get_length_name1, .{ ctx, this_val, is_name, @ptrCast(@alignCast(pb)) });
}

export fn get_bit(buf: [*]const u8, index: u32) u32 {
    return abiCall(runtime.get_bit, .{ buf, index });
}

export fn get_bits_slow(buf: [*]const u8, index: u32, n: c_int) u32 {
    return abiCall(runtime.get_bits_slow, .{ buf, index, n });
}

export fn get_bits(buf: [*]const u8, buf_len: u32, index: u32, n: c_int) u32 {
    return abiCall(runtime.get_bits, .{ buf, buf_len, index, n });
}

export fn get_ugolomb(buf: [*]const u8, buf_len: u32, pindex: *u32) u32 {
    return abiCall(runtime.get_ugolomb, .{ buf, buf_len, pindex });
}

export fn get_sgolomb(buf: [*]const u8, buf_len: u32, pindex: *u32) i32 {
    return abiCall(runtime.get_sgolomb, .{ buf, buf_len, pindex });
}

export fn get_pc2line_hoisted_code_len(buf: [*]const u8, buf_len: usize) c_int {
    return abiCall(runtime.get_pc2line_hoisted_code_len, .{ buf, buf_len });
}

export fn get_pc2line(pline_num: *c_int, pcol_num: *c_int, buf: [*]const u8, buf_len: u32, pindex: *u32, has_column: c.JS_BOOL) void {
    abiCall(runtime.get_pc2line, .{ pline_num, pcol_num, buf, buf_len, pindex, has_column });
}

export fn find_line_col(pcol_num: *c_int, b: *anyopaque, pc_in: u32) c_int {
    return abiCall(runtime.find_line_col, .{ pcol_num, @ptrCast(@alignCast(b)), pc_in });
}

export fn get_func_name(ctx: *c.JSContext, func_obj: c.JSValue, str_buf: *c.JSCStringBuf, pb: *?*anyopaque) ?[*:0]const u8 {
    return abiCall(runtime.get_func_name, .{ ctx, func_obj, str_buf, @ptrCast(@alignCast(pb)) });
}

export fn build_backtrace(ctx: *c.JSContext, error_obj: c.JSValue, filename: ?[*:0]const u8, line_num: c_int, col_num: c_int, skip_level: c_int) void {
    abiCall(runtime.build_backtrace, .{ ctx, error_obj, filename, line_num, col_num, skip_level });
}

export fn JS_ToPrimitive(ctx: *c.JSContext, val: c.JSValue, hint: c_int) c.JSValue {
    return abiCall(runtime.JS_ToPrimitive, .{ ctx, val, hint });
}

export fn js_dtoa2(ctx: *c.JSContext, d: f64, radix: c_int, n_digits: c_int, flags: c_int) c.JSValue {
    return abiCall(runtime.js_dtoa2, .{ ctx, d, radix, n_digits, flags });
}

export fn JS_ToString(ctx: *c.JSContext, val: c.JSValue) c.JSValue {
    return abiCall(runtime.JS_ToString, .{ ctx, val });
}

export fn JS_ToPropertyKey(ctx: *c.JSContext, val: c.JSValue) c.JSValue {
    return abiCall(runtime.JS_ToPropertyKey, .{ ctx, val });
}

export fn skip_spaces(p1: [*:0]const u8) c_int {
    return abiCall(runtime.skip_spaces, .{ p1 });
}

export fn js_atod1(ctx: *c.JSContext, pres: *f64, val: c.JSValue, radix: c_int, flags: c_int) c_int {
    return abiCall(runtime.js_atod1, .{ ctx, pres, val, radix, flags });
}

export fn JS_ToNumber(ctx: *c.JSContext, pres: *f64, val: c.JSValue) c_int {
    return abiCall(runtime.JS_ToNumber, .{ ctx, pres, val });
}

export fn JS_ToInt32Internal(ctx: *c.JSContext, pres: *c_int, val: c.JSValue, sat_flag: c.JS_BOOL) c_int {
    return abiCall(runtime.JS_ToInt32Internal, .{ ctx, pres, val, sat_flag });
}

export fn JS_ToInt32(ctx: *c.JSContext, pres: *c_int, val: c.JSValue) c_int {
    return abiCall(runtime.JS_ToInt32, .{ ctx, pres, val });
}

export fn JS_ToUint32(ctx: *c.JSContext, pres: *u32, val: c.JSValue) c_int {
    return abiCall(runtime.JS_ToUint32, .{ ctx, pres, val });
}

export fn JS_ToInt32Sat(ctx: *c.JSContext, pres: *c_int, val: c.JSValue) c_int {
    return abiCall(runtime.JS_ToInt32Sat, .{ ctx, pres, val });
}

export fn JS_ToInt32Clamp(ctx: *c.JSContext, pres: *c_int, val: c.JSValue, min_v: c_int, max_v: c_int, min_offset: c_int) c_int {
    return abiCall(runtime.JS_ToInt32Clamp, .{ ctx, pres, val, min_v, max_v, min_offset });
}

export fn JS_ToUint8Clamp(ctx: *c.JSContext, pres: *c_int, val: c.JSValue) c_int {
    return abiCall(runtime.JS_ToUint8Clamp, .{ ctx, pres, val });
}

export fn js_get_length32(ctx: *c.JSContext, pres: *u32, obj: c.JSValue) c_int {
    return abiCall(runtime.js_get_length32, .{ ctx, pres, obj });
}

export fn js_add_slow(ctx: *c.JSContext) c.JSValue {
    return abiCall(runtime.js_add_slow, .{ ctx });
}

export fn js_binary_arith_slow(ctx: *c.JSContext, op: c_int) c.JSValue {
    return abiCall(runtime.js_binary_arith_slow, .{ ctx, op });
}

export fn js_unary_arith_slow(ctx: *c.JSContext, op: c_int) c.JSValue {
    return abiCall(runtime.js_unary_arith_slow, .{ ctx, op });
}

export fn js_post_inc_slow(ctx: *c.JSContext, op: c_int) c.JSValue {
    return abiCall(runtime.js_post_inc_slow, .{ ctx, op });
}

export fn js_binary_logic_slow(ctx: *c.JSContext, op: c_int) c.JSValue {
    return abiCall(runtime.js_binary_logic_slow, .{ ctx, op });
}

export fn js_not_slow(ctx: *c.JSContext) c.JSValue {
    return abiCall(runtime.js_not_slow, .{ ctx });
}

export fn js_relational_slow(ctx: *c.JSContext, op: c_int) c.JSValue {
    return abiCall(runtime.js_relational_slow, .{ ctx, op });
}

export fn js_strict_eq(ctx: *c.JSContext, op1: c.JSValue, op2: c.JSValue) c.JS_BOOL {
    return abiCall(runtime.js_strict_eq, .{ ctx, op1, op2 });
}

export fn js_strict_eq_slow(ctx: *c.JSContext, is_neq: c.JS_BOOL) c.JSValue {
    return abiCall(runtime.js_strict_eq_slow, .{ ctx, is_neq });
}

export fn js_eq_get_type(ctx: *c.JSContext, val: c.JSValue) c_int {
    return abiCall(runtime.js_eq_get_type, .{ ctx, val });
}

export fn js_eq_slow(ctx: *c.JSContext, is_neq: c.JS_BOOL) c.JSValue {
    return abiCall(runtime.js_eq_slow, .{ ctx, is_neq });
}

export fn js_operator_in(ctx: *c.JSContext) c.JSValue {
    return abiCall(runtime.js_operator_in, .{ ctx });
}

export fn js_operator_instanceof(ctx: *c.JSContext) c.JSValue {
    return abiCall(runtime.js_operator_instanceof, .{ ctx });
}

export fn js_operator_typeof(ctx: *c.JSContext, val: c.JSValue) c.JSValue {
    return abiCall(runtime.js_operator_typeof, .{ ctx, val });
}

export fn js_reverse_val(tab: [*]c.JSValue, n: c_int) void {
    abiCall(runtime.js_reverse_val, .{ tab, n });
}

export fn js_closure(ctx: *c.JSContext, bfunc: c.JSValue, fp: [*c]c.JSValue) c.JSValue {
    const fp_opt: ?[*]c.JSValue = if (fp) |p| @ptrCast(p) else null;
    return abiCall(runtime.js_closure, .{ ctx, bfunc, fp_opt });
}

export fn js_for_of_start(ctx: *c.JSContext, is_for_in: c.JS_BOOL) c.JSValue {
    return abiCall(runtime.js_for_of_start, .{ ctx, is_for_in });
}

export fn js_for_of_next(ctx: *c.JSContext) c.JSValue {
    return abiCall(runtime.js_for_of_next, .{ ctx });
}

export fn js_new_c_function_proto(ctx: *c.JSContext, func_idx: c_int, proto: c.JSValue, has_params: c.JS_BOOL, params: c.JSValue) c.JSValue {
    return abiCall(runtime.js_new_c_function_proto, .{ ctx, func_idx, proto, has_params, params });
}

export fn JS_NewCFunctionParams(ctx: *c.JSContext, func_idx: c_int, params: c.JSValue) c.JSValue {
    return abiCall(runtime.JS_NewCFunctionParams, .{ ctx, func_idx, params });
}

export fn js_call_constructor_start(ctx: *c.JSContext, func: c.JSValue) c.JSValue {
    return abiCall(runtime.js_call_constructor_start, .{ ctx, func });
}

export fn __js_poll_interrupt(ctx: *c.JSContext) c.JSValue {
    return abiCall(runtime.__js_poll_interrupt, .{ ctx });
}

export fn JS_PushArg(ctx: *c.JSContext, val: c.JSValue) void {
    abiCall(runtime.JS_PushArg, .{ ctx, val });
}

export fn JS_Call(ctx: *c.JSContext, call_flags: c_int) c.JSValue {
    return abiCall(runtime.JS_Call, .{ ctx, call_flags });
}

// --- mquickjs_lexer ---

export fn get_line_col(pcol_num: *c_int, buf: [*]const u8, len: usize) c_int {
    return abiCall(lexer.get_line_col, .{ pcol_num, buf, len });
}

export fn js_parse_error(s: *lt.JSParseState, fmt: [*:0]const u8, ...) callconv(.c) noreturn {
    var ap = @cVaStart();
    defer @cVaEnd(&ap);
    abiCall(lexer.js_parse_error_va, .{ s, fmt, @ptrCast(&ap) });
}

export fn js_parse_error_mem(s: *lt.JSParseState) void {
    abiCall(lexer.js_parse_error_mem, .{ s });
}

export fn js_parse_error_stack_overflow(s: *lt.JSParseState) void {
    abiCall(lexer.js_parse_error_stack_overflow, .{ s });
}

export fn js_parse_expect1(s: *lt.JSParseState, ch: c_int) void {
    abiCall(lexer.js_parse_expect1, .{ s, ch });
}

export fn js_parse_expect(s: *lt.JSParseState, ch: c_int) void {
    abiCall(lexer.js_parse_expect, .{ s, ch });
}

export fn js_parse_expect_semi(s: *lt.JSParseState) void {
    abiCall(lexer.js_parse_expect_semi, .{ s });
}

export fn js_skip_parens(s: *lt.JSParseState, pfunc_name: ?*c.JSValue) c_int {
    return abiCall(lexer.js_skip_parens, .{ s, pfunc_name });
}

export fn js_skip_expr(s: *lt.JSParseState) void {
    abiCall(lexer.js_skip_expr, .{ s });
}

export fn is_regexp_allowed(tok: c_int) c.JS_BOOL {
    return abiCall(lexer.is_regexp_allowed, .{ tok });
}

export fn js_parse_get_pos(s: *lt.JSParseState, sp: *lt.JSParsePos) void {
    abiCall(lexer.js_parse_get_pos, .{ s, sp });
}

export fn js_parse_seek_token(s: *lt.JSParseState, sp: *const lt.JSParsePos) void {
    abiCall(lexer.js_parse_seek_token, .{ s, sp });
}

export fn js_parse_skip_parens_token(s: *lt.JSParseState) c_int {
    return abiCall(lexer.js_parse_skip_parens_token, .{ s });
}

export fn js_parse_escape(buf: [*]const u8, plen: *usize) c_int {
    return abiCall(lexer.js_parse_escape, .{ buf, plen });
}

export fn js_parse_string(s: *lt.JSParseState, ppos: *u32, sep: c_int) c.JSValue {
    return abiCall(lexer.js_parse_string, .{ s, ppos, sep });
}

export fn js_parse_ident(s: *lt.JSParseState, token: *lt.JSToken, ppos: *u32, first_c: c_int) void {
    abiCall(lexer.js_parse_ident, .{ s, token, ppos, first_c });
}

export fn js_parse_regexp_token(s: *lt.JSParseState, ppos: *u32) void {
    abiCall(lexer.js_parse_regexp_token, .{ s, ppos });
}

export fn next_token(s: *lt.JSParseState) void {
    abiCall(lexer.next_token, .{ s });
}

// --- mquickjs_parser ---

export fn get_line_col_delta(pcol_num: *c_int, buf: [*]const u8, pos1: c_int, pos2: c_int) c_int {
    return abiCall(parser.get_line_col_delta, .{ pcol_num, buf, pos1, pos2 });
}

export fn emit_u8(s: *pt.JSParseState, val: u8) void {
    abiCall(parser.emit_u8, .{ s, val });
}

export fn emit_u16(s: *pt.JSParseState, val: u16) void {
    abiCall(parser.emit_u16, .{ s, val });
}

export fn emit_u32(s: *pt.JSParseState, val: u32) void {
    abiCall(parser.emit_u32, .{ s, val });
}

export fn emit_insert(s: *pt.JSParseState, pos: c_int, n: c_int) void {
    abiCall(parser.emit_insert, .{ s, pos, n });
}

export fn js_parse_push_val(s: *pt.JSParseState, val: c.JSValue) void {
    abiCall(parser.js_parse_push_val, .{ s, val });
}

export fn js_parse_pop_val(s: *pt.JSParseState) c.JSValue {
    return abiCall(parser.js_parse_pop_val, .{ s });
}

export fn js_parse_call(s: *pt.JSParseState, func_idx: c_int, param: c_int) void {
    abiCall(parser.js_parse_call, .{ s, func_idx, param });
}

export fn JS_Parse2(ctx: *c.JSContext, source_str: c.JSValue, input: ?[*:0]const u8, input_len: usize, filename: [*:0]const u8, eval_flags: c_int) c.JSValue {
    return abiCall(parser.JS_Parse2, .{ ctx, source_str, input, input_len, filename, eval_flags });
}

export fn JS_Parse(ctx: *c.JSContext, input: [*:0]const u8, input_len: usize, filename: [*:0]const u8, eval_flags: c_int) c.JSValue {
    return abiCall(parser.JS_Parse, .{ ctx, input, input_len, filename, eval_flags });
}

export fn JS_Run(ctx: *c.JSContext, val: c.JSValue) c.JSValue {
    return abiCall(parser.JS_Run, .{ ctx, val });
}

export fn JS_Eval(ctx: *c.JSContext, input: [*:0]const u8, input_len: usize, filename: [*:0]const u8, eval_flags: c_int) c.JSValue {
    return abiCall(parser.JS_Eval, .{ ctx, input, input_len, filename, eval_flags });
}

// --- mquickjs_gc ---

export fn get_mblock_size(ptr: *const anyopaque) c_int {
    return abiCall(gc.get_mblock_size, .{ ptr });
}

export fn JS_GC(ctx: *c.JSContext) void {
    abiCall(gc.JS_GC, .{ ctx });
}

export fn JS_GC2(ctx: *c.JSContext, keep_atoms: c.JS_BOOL) void {
    abiCall(gc.JS_GC2, .{ ctx, keep_atoms });
}

export fn JS_LoadBytecode(ctx: *c.JSContext, buf: [*]const u8) c.JSValue {
    return abiCall(gc.JS_LoadBytecode, .{ ctx, buf });
}

export fn JS_IsBytecode(buf: [*]const u8, buf_len: usize) c.JS_BOOL {
    return abiCall(gc.JS_IsBytecode, .{ buf, buf_len });
}

export fn JS_RelocateBytecode(ctx: *c.JSContext, buf: [*]u8, buf_len: u32) c_int {
    return abiCall(gc.JS_RelocateBytecode, .{ ctx, buf, buf_len });
}

export fn JS_RelocateBytecode2(
    ctx: *c.JSContext,
    hdr: *gt.JSBytecodeHeader,
    buf: [*]u8,
    buf_len: u32,
    new_base_addr: usize,
    update_atoms: c.JS_BOOL,
) c_int {
    return abiCall(gc.JS_RelocateBytecode2, .{ ctx, hdr, buf, buf_len, new_base_addr, update_atoms });
}

export fn JS_PrepareBytecode(
    ctx: *c.JSContext,
    hdr: *gt.JSBytecodeHeader,
    pdata_buf: *[*]const u8,
    pdata_len: *u32,
    eval_code: c.JSValue,
) void {
    abiCall(gc.JS_PrepareBytecode, .{ ctx, hdr, pdata_buf, pdata_len, eval_code });
}

export fn JS_PrepareBytecode64to32(
    ctx: *c.JSContext,
    hdr: *gt.JSBytecodeHeader32,
    pdata_buf: *[*]const u8,
    pdata_len: *u32,
    eval_code: c.JSValue,
) c_int {
    return abiCall(gc.JS_PrepareBytecode64to32, .{ ctx, hdr, pdata_buf, pdata_len, eval_code });
}

// --- mquickjs_builtins ---

export fn JS_IsArray(ctx: *c.JSContext, obj: c.JSValue) c.JS_BOOL {
    return abiCall(builtins.JS_IsArray, .{ ctx, obj });
}

export fn JS_NewDate(ctx: *c.JSContext, epoch_ms: f64) c.JSValue {
    return abiCall(builtins.JS_NewDate, .{ ctx, epoch_ms });
}

export fn dump_regexp(ctx: *c.JSContext, p: *anyopaque) void {
    abiCall(builtins.dump_regexp, .{ ctx, p });
}

export fn js_parse_regexp(s: *bt.JSParseState, re_flags: c_int) c.JSValue {
    return abiCall(builtins.js_parse_regexp, .{ s, re_flags });
}

export fn js_parse_regexp_flags(pre_flags: *c_int, buf: [*]const u8) usize {
    return abiCall(builtins.js_parse_regexp_flags, .{ pre_flags, buf });
}

export fn re_parse_alternative(s: *bt.JSParseState, state: c_int, dummy_param: c_int) c_int {
    return abiCall(builtins.re_parse_alternative, .{ s, state, dummy_param });
}

export fn re_parse_disjunction(s: *bt.JSParseState, state: c_int, dummy_param: c_int) c_int {
    return abiCall(builtins.re_parse_disjunction, .{ s, state, dummy_param });
}

export fn js_object_keys(ctx: *c.JSContext, this_val: ?*c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return abiCall(builtins.js_object_keys, .{ ctx, this_val, argc, argv });
}

export fn js_set_prototype_internal(ctx: *c.JSContext, obj: c.JSValue, proto: c.JSValue) c.JSValue {
    return abiCall(builtins.js_set_prototype_internal, .{ ctx, obj, proto });
}

export fn js_string_charAt(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue, magic: c_int) c.JSValue {
    return abiCall(builtins.js_string_charAt, .{ ctx, this_val, argc, argv, magic });
}

export fn js_function_constructor(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return abiCall(builtins.js_function_constructor, .{ ctx, this_val, argc, argv });
}

export fn js_function_get_prototype(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return abiCall(builtins.js_function_get_prototype, .{ ctx, this_val, argc, argv });
}

export fn js_function_set_prototype(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return abiCall(builtins.js_function_set_prototype, .{ ctx, this_val, argc, argv });
}

export fn js_function_get_length_name(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue, is_name: c_int) c.JSValue {
    return abiCall(builtins.js_function_get_length_name, .{ ctx, this_val, argc, argv, is_name });
}

export fn js_function_toString(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return abiCall(builtins.js_function_toString, .{ ctx, this_val, argc, argv });
}

export fn js_function_call(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return abiCall(builtins.js_function_call, .{ ctx, this_val, argc, argv });
}

export fn js_function_apply(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return abiCall(builtins.js_function_apply, .{ ctx, this_val, argc, argv });
}

export fn js_function_bind(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return abiCall(builtins.js_function_bind, .{ ctx, this_val, argc, argv });
}

export fn js_function_bound(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue, params: c.JSValue) c.JSValue {
    return abiCall(builtins.js_function_bound, .{ ctx, this_val, argc, argv, params });
}

export fn js_number_constructor(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return abiCall(builtins.js_number_constructor, .{ ctx, this_val, argc, argv });
}

export fn js_number_toString(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return abiCall(builtins.js_number_toString, .{ ctx, this_val, argc, argv });
}

export fn js_number_toFixed(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return abiCall(builtins.js_number_toFixed, .{ ctx, this_val, argc, argv });
}

export fn js_number_toExponential(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return abiCall(builtins.js_number_toExponential, .{ ctx, this_val, argc, argv });
}

export fn js_number_toPrecision(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return abiCall(builtins.js_number_toPrecision, .{ ctx, this_val, argc, argv });
}

export fn js_number_parseInt(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return abiCall(builtins.js_number_parseInt, .{ ctx, this_val, argc, argv });
}

export fn js_number_parseFloat(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return abiCall(builtins.js_number_parseFloat, .{ ctx, this_val, argc, argv });
}

export fn js_boolean_constructor(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return abiCall(builtins.js_boolean_constructor, .{ ctx, this_val, argc, argv });
}

export fn js_string_get_length(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return abiCall(builtins.js_string_get_length, .{ ctx, this_val, argc, argv });
}

export fn js_string_set_length(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return abiCall(builtins.js_string_set_length, .{ ctx, this_val, argc, argv });
}

export fn js_string_slice(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return abiCall(builtins.js_string_slice, .{ ctx, this_val, argc, argv });
}

export fn js_string_substring(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return abiCall(builtins.js_string_substring, .{ ctx, this_val, argc, argv });
}

export fn js_string_constructor(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return abiCall(builtins.js_string_constructor, .{ ctx, this_val, argc, argv });
}

export fn js_string_fromCharCode(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue, is_fromCodePoint: c_int) c.JSValue {
    return abiCall(builtins.js_string_fromCharCode, .{ ctx, this_val, argc, argv, is_fromCodePoint });
}

export fn js_string_concat(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return abiCall(builtins.js_string_concat, .{ ctx, this_val, argc, argv });
}

export fn js_string_indexOf(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue, lastIndexOf: c_int) c.JSValue {
    return abiCall(builtins.js_string_indexOf, .{ ctx, this_val, argc, argv, lastIndexOf });
}

export fn js_string_toLowerCase(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue, to_lower: c_int) c.JSValue {
    return abiCall(builtins.js_string_toLowerCase, .{ ctx, this_val, argc, argv, to_lower });
}

export fn js_string_trim(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue, magic: c_int) c.JSValue {
    return abiCall(builtins.js_string_trim, .{ ctx, this_val, argc, argv, magic });
}

export fn js_string_toString(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return abiCall(builtins.js_string_toString, .{ ctx, this_val, argc, argv });
}

export fn js_string_repeat(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return abiCall(builtins.js_string_repeat, .{ ctx, this_val, argc, argv });
}

export fn js_string_match(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return abiCall(builtins.js_string_match, .{ ctx, this_val, argc, argv });
}

export fn js_string_replace(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue, is_replaceAll: c_int) c.JSValue {
    return abiCall(builtins.js_string_replace, .{ ctx, this_val, argc, argv, is_replaceAll });
}

export fn js_string_search(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return abiCall(builtins.js_string_search, .{ ctx, this_val, argc, argv });
}

export fn js_string_split(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return abiCall(builtins.js_string_split, .{ ctx, this_val, argc, argv });
}

export fn js_object_constructor(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return abiCall(builtins.js_object_constructor, .{ ctx, this_val, argc, argv });
}

export fn js_object_defineProperty(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return abiCall(builtins.js_object_defineProperty, .{ ctx, this_val, argc, argv });
}

export fn js_object_getPrototypeOf(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return abiCall(builtins.js_object_getPrototypeOf, .{ ctx, this_val, argc, argv });
}

export fn js_object_setPrototypeOf(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return abiCall(builtins.js_object_setPrototypeOf, .{ ctx, this_val, argc, argv });
}

export fn js_object_create(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return abiCall(builtins.js_object_create, .{ ctx, this_val, argc, argv });
}

export fn js_object_hasOwnProperty(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return abiCall(builtins.js_object_hasOwnProperty, .{ ctx, this_val, argc, argv });
}

export fn js_object_toString(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return abiCall(builtins.js_object_toString, .{ ctx, this_val, argc, argv });
}

export fn js_error_constructor(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue, magic: c_int) c.JSValue {
    return abiCall(builtins.js_error_constructor, .{ ctx, this_val, argc, argv, magic });
}

export fn js_error_toString(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return abiCall(builtins.js_error_toString, .{ ctx, this_val, argc, argv });
}

export fn js_error_get_message(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue, magic: c_int) c.JSValue {
    return abiCall(builtins.js_error_get_message, .{ ctx, this_val, argc, argv, magic });
}

export fn js_array_get_length(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return abiCall(builtins.js_array_get_length, .{ ctx, this_val, argc, argv });
}

export fn js_array_set_length(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return abiCall(builtins.js_array_set_length, .{ ctx, this_val, argc, argv });
}

export fn js_array_constructor(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return abiCall(builtins.js_array_constructor, .{ ctx, this_val, argc, argv });
}

export fn js_array_push(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue, is_unshift: c_int) c.JSValue {
    return abiCall(builtins.js_array_push, .{ ctx, this_val, argc, argv, is_unshift });
}

export fn js_array_pop(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return abiCall(builtins.js_array_pop, .{ ctx, this_val, argc, argv });
}

export fn js_array_shift(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return abiCall(builtins.js_array_shift, .{ ctx, this_val, argc, argv });
}

export fn js_array_join(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return abiCall(builtins.js_array_join, .{ ctx, this_val, argc, argv });
}

export fn js_array_toString(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return abiCall(builtins.js_array_toString, .{ ctx, this_val, argc, argv });
}

export fn js_array_isArray(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return abiCall(builtins.js_array_isArray, .{ ctx, this_val, argc, argv });
}

export fn js_array_reverse(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return abiCall(builtins.js_array_reverse, .{ ctx, this_val, argc, argv });
}

export fn js_array_concat(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return abiCall(builtins.js_array_concat, .{ ctx, this_val, argc, argv });
}

export fn js_array_indexOf(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue, is_lastIndexOf: c_int) c.JSValue {
    return abiCall(builtins.js_array_indexOf, .{ ctx, this_val, argc, argv, is_lastIndexOf });
}

export fn js_array_slice(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return abiCall(builtins.js_array_slice, .{ ctx, this_val, argc, argv });
}

export fn js_array_splice(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return abiCall(builtins.js_array_splice, .{ ctx, this_val, argc, argv });
}

export fn js_array_every(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue, special: c_int) c.JSValue {
    return abiCall(builtins.js_array_every, .{ ctx, this_val, argc, argv, special });
}

export fn js_array_reduce(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue, special: c_int) c.JSValue {
    return abiCall(builtins.js_array_reduce, .{ ctx, this_val, argc, argv, special });
}

export fn js_array_sort(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return abiCall(builtins.js_array_sort, .{ ctx, this_val, argc, argv });
}

export fn js_math_min_max(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue, magic: c_int) c.JSValue {
    return abiCall(builtins.js_math_min_max, .{ ctx, this_val, argc, argv, magic });
}

export fn js_math_sign(a: f64) f64 {
    return abiCall(builtins.js_math_sign, .{ a });
}

export fn js_math_fround(a: f64) f64 {
    return abiCall(builtins.js_math_fround, .{ a });
}

export fn js_math_imul(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return abiCall(builtins.js_math_imul, .{ ctx, this_val, argc, argv });
}

export fn js_math_clz32(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return abiCall(builtins.js_math_clz32, .{ ctx, this_val, argc, argv });
}

export fn js_math_atan2(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return abiCall(builtins.js_math_atan2, .{ ctx, this_val, argc, argv });
}

export fn js_math_pow(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return abiCall(builtins.js_math_pow, .{ ctx, this_val, argc, argv });
}

export fn js_math_random(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return abiCall(builtins.js_math_random, .{ ctx, this_val, argc, argv });
}

export fn js_array_buffer_constructor(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return abiCall(builtins.js_array_buffer_constructor, .{ ctx, this_val, argc, argv });
}

export fn js_array_buffer_get_byteLength(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return abiCall(builtins.js_array_buffer_get_byteLength, .{ ctx, this_val, argc, argv });
}

export fn js_typed_array_base_constructor(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return abiCall(builtins.js_typed_array_base_constructor, .{ ctx, this_val, argc, argv });
}

export fn js_typed_array_constructor(ctx: *c.JSContext, this_val: ?*c.JSValue, argc: c_int, argv: [*]c.JSValue, magic: c_int) c.JSValue {
    return abiCall(builtins.js_typed_array_constructor, .{ ctx, this_val, argc, argv, magic });
}

export fn js_typed_array_get_length(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue, magic: c_int) c.JSValue {
    return abiCall(builtins.js_typed_array_get_length, .{ ctx, this_val, argc, argv, magic });
}

export fn js_typed_array_subarray(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return abiCall(builtins.js_typed_array_subarray, .{ ctx, this_val, argc, argv });
}

export fn js_typed_array_set(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return abiCall(builtins.js_typed_array_set, .{ ctx, this_val, argc, argv });
}

export fn js_date_valueOf(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return abiCall(builtins.js_date_valueOf, .{ ctx, this_val, argc, argv });
}

export fn js_global_eval(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return abiCall(builtins.js_global_eval, .{ ctx, this_val, argc, argv });
}

export fn js_global_isNaN(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return abiCall(builtins.js_global_isNaN, .{ ctx, this_val, argc, argv });
}

export fn js_global_isFinite(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return abiCall(builtins.js_global_isFinite, .{ ctx, this_val, argc, argv });
}

export fn js_json_parse(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return abiCall(builtins.js_json_parse, .{ ctx, this_val, argc, argv });
}

export fn js_json_stringify(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return abiCall(builtins.js_json_stringify, .{ ctx, this_val, argc, argv });
}

export fn js_regexp_get_lastIndex(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return abiCall(builtins.js_regexp_get_lastIndex, .{ ctx, this_val, argc, argv });
}

export fn js_regexp_get_source(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return abiCall(builtins.js_regexp_get_source, .{ ctx, this_val, argc, argv });
}

export fn js_regexp_set_lastIndex(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return abiCall(builtins.js_regexp_set_lastIndex, .{ ctx, this_val, argc, argv });
}

export fn js_regexp_get_flags(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return abiCall(builtins.js_regexp_get_flags, .{ ctx, this_val, argc, argv });
}

export fn js_regexp_constructor(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue) c.JSValue {
    return abiCall(builtins.js_regexp_constructor, .{ ctx, this_val, argc, argv });
}

export fn js_regexp_exec(ctx: *c.JSContext, this_val: *c.JSValue, argc: c_int, argv: [*]c.JSValue, magic: c_int) c.JSValue {
    return abiCall(builtins.js_regexp_exec, .{ ctx, this_val, argc, argv, magic });
}

