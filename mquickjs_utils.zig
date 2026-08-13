//
// Micro QuickJS engine utilities (C ABI exports)
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

// Ported from C to Zig by VExcess

const lib = @import("mquickjs_utils_lib.zig");
const mc = @import("mquickjs_utils_types.zig");
const c = lib.c;

export const js_mtag_name = lib.js_mtag_name;

export fn JS_PushGCRef(ctx: *c.JSContext, ref: *c.JSGCRef) *c.JSValue {
    return lib.JS_PushGCRef(ctx, ref);
}

export fn JS_PopGCRef(ctx: *c.JSContext, ref: *c.JSGCRef) c.JSValue {
    return lib.JS_PopGCRef(ctx, ref);
}

export fn JS_AddGCRef(ctx: *c.JSContext, ref: *c.JSGCRef) *c.JSValue {
    return lib.JS_AddGCRef(ctx, ref);
}

export fn JS_DeleteGCRef(ctx: *c.JSContext, ref: *c.JSGCRef) void {
    lib.JS_DeleteGCRef(ctx, ref);
}

export fn js_get_atom(ctx: *c.JSContext, a: c_int) c.JSValue {
    return lib.js_get_atom(ctx, a);
}

export fn JS_IsExceptionOrTailCall(v: c.JSValue) c.JS_BOOL {
    return lib.JS_IsExceptionOrTailCall(v);
}

export fn js_get_mtag(ptr: *anyopaque) c_int {
    return lib.js_get_mtag(ptr);
}

export fn JS_StackCheck(ctx: *c.JSContext, len: c_uint) c_int {
    return lib.JS_StackCheck(ctx, len);
}

export fn js_malloc(ctx: *c.JSContext, size: c_uint, mtag: c_int) ?*anyopaque {
    return lib.js_malloc(ctx, size, mtag);
}

export fn js_mallocz(ctx: *c.JSContext, size: c_uint, mtag: c_int) ?*anyopaque {
    return lib.js_mallocz(ctx, size, mtag);
}

export fn js_free(ctx: *c.JSContext, ptr: ?*anyopaque) void {
    lib.js_free(ctx, ptr);
}

export fn set_free_block(ptr: *anyopaque, size: c_uint) void {
    lib.set_free_block(ptr, size);
}

export fn js_shrink(ctx: *c.JSContext, ptr: ?*anyopaque, new_size: c_uint) ?*anyopaque {
    return lib.js_shrink(ctx, ptr, new_size);
}

export fn JS_Throw(ctx: *c.JSContext, obj: c.JSValue) c.JSValue {
    return lib.JS_Throw(ctx, obj);
}

export fn get_short_string(buf: [*c]u8, val: c.JSValue) c_int {
    return lib.get_short_string(buf, val);
}

export fn is_digit(ch: c_int) c.JS_BOOL {
    return lib.is_digit(ch);
}

export fn is_ident_next(ch: c_int) c_int {
    return lib.is_ident_next(ch);
}

export fn js_vprintf(write_func: mc.JSWriteFn, opaque_val: ?*anyopaque, fmt: [*:0]const u8, ap: *anyopaque) callconv(.c) void {
    lib.js_vprintf(write_func, opaque_val, fmt, ap);
}

export fn js_vsnprintf(buf: [*c]u8, buf_size: usize, fmt: [*:0]const u8, ap: *anyopaque) callconv(.c) c_int {
    return lib.js_vsnprintf(buf, buf_size, fmt, ap);
}

export fn js_snprintf(buf: [*c]u8, buf_size: usize, fmt: [*:0]const u8, ...) callconv(.c) c_int {
    var ap = @cVaStart();
    defer @cVaEnd(&ap);
    return lib.js_vsnprintf(buf, buf_size, fmt, @ptrCast(&ap));
}

export fn js_printf(ctx: *c.JSContext, fmt: [*:0]const u8, ...) callconv(.c) void {
    var ap = @cVaStart();
    defer @cVaEnd(&ap);
    const x = mc.ctxExt(ctx);
    lib.js_vprintf(x.write_func.?, x.opaque_val, fmt, @ptrCast(&ap));
}

export fn js_putchar(ctx: *c.JSContext, ch: u8) void {
    lib.js_putchar(ctx, ch);
}

export fn JS_ThrowError(ctx: *c.JSContext, error_num: c.JSObjectClassEnum, fmt: [*:0]const u8, ...) callconv(.c) c.JSValue {
    var ap = @cVaStart();
    defer @cVaEnd(&ap);
    return lib.jsThrowErrorVa(ctx, error_num, fmt, @ptrCast(&ap));
}

export fn JS_ThrowOutOfMemory(ctx: *c.JSContext) c.JSValue {
    return lib.JS_ThrowOutOfMemory(ctx);
}

export fn JS_PrintValueF(ctx: *c.JSContext, val: c.JSValue, flags: c_int) void {
    lib.JS_PrintValueF(ctx, val, flags);
}

export fn JS_PrintValue(ctx: *c.JSContext, val: c.JSValue) void {
    lib.JS_PrintValue(ctx, val);
}

export fn JS_DumpMemory(ctx: *c.JSContext, is_long: c.JS_BOOL) void {
    lib.JS_DumpMemory(ctx, is_long);
}

export fn JS_DumpValueF(ctx: *c.JSContext, str: [*:0]const u8, val: c.JSValue, flags: c_int) void {
    lib.JS_DumpValueF(ctx, str, val, flags);
}

export fn JS_DumpValue(ctx: *c.JSContext, str: [*:0]const u8, val: c.JSValue) void {
    lib.JS_DumpValue(ctx, str, val);
}
