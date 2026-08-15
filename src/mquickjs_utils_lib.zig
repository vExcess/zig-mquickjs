//
// Micro QuickJS engine utilities (shared implementation)
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

const std = @import("std");
const cutils = @import("cutils_lib.zig");
const dtoa = @import("dtoa_lib.zig");
const gc = @import("mquickjs_gc_lib.zig");
const value = @import("mquickjs_value_lib.zig");
const runtime = @import("mquickjs_runtime_lib.zig");
const builtins = @import("mquickjs_builtins_lib.zig");
const mc = @import("mquickjs_utils_types.zig");

pub const c = mc.c;

const min_int = cutils.min_int;
const unicode_to_utf8 = cutils.unicode_to_utf8;
const utf8_get = cutils.utf8_get;

extern fn js_lrint(x: f64) c_long;

const PF_ZERO_PAD: c_int = 1 << 0;
const PF_ALT_FORM: c_int = 1 << 1;
const PF_MARK_POS: c_int = 1 << 2;
const PF_LEFT_ADJ: c_int = 1 << 3;
const PF_PAD_POS: c_int = 1 << 4;
const PF_INT64: c_int = 1 << 5;

fn min_size_t(a: usize, b: usize) usize {
    return if (a < b) a else b;
}

fn cstr(s: [*:0]const u8) [*c]u8 {
    return @ptrCast(@constCast(s));
}

fn max_size_t(a: usize, b: usize) usize {
    return if (a > b) a else b;
}

pub const js_mtag_name = [_][*:0]const u8{
    "free",          "object",      "float64",    "string",
    "func_bytecode", "value_array", "byte_array", "varref",
};

pub fn JS_PushGCRef(ctx: *c.JSContext, ref: *c.JSGCRef) *c.JSValue {
    const x = mc.ctxExt(ctx);
    ref.prev = @ptrCast(x.top_gc_ref);
    x.top_gc_ref = @ptrCast(@alignCast(ref));
    ref.val = c.JS_UNDEFINED;
    return &ref.val;
}

pub fn JS_PopGCRef(ctx: *c.JSContext, ref: *c.JSGCRef) c.JSValue {
    mc.ctxExt(ctx).top_gc_ref = @ptrCast(ref.prev);
    return ref.val;
}

pub fn pushValue(ctx: *c.JSContext, ref: *c.JSGCRef, val: c.JSValue) void {
    _ = JS_PushGCRef(ctx, ref);
    ref.val = val;
}

pub fn popValue(ctx: *c.JSContext, ref: *c.JSGCRef) c.JSValue {
    return JS_PopGCRef(ctx, ref);
}

pub fn JS_AddGCRef(ctx: *c.JSContext, ref: *c.JSGCRef) *c.JSValue {
    const x = mc.ctxExt(ctx);
    ref.prev = @ptrCast(x.last_gc_ref);
    x.last_gc_ref = @ptrCast(@alignCast(ref));
    ref.val = c.JS_UNDEFINED;
    return &ref.val;
}

pub fn JS_DeleteGCRef(ctx: *c.JSContext, ref: *c.JSGCRef) void {
    const x = mc.ctxExt(ctx);
    var pref: *?*c.JSGCRef = @ptrCast(&x.last_gc_ref);
    while (true) {
        const ref1 = pref.* orelse {
            std.process.abort();
        };
        if (ref1 == ref) {
            pref.* = ref1.prev;
            break;
        }
        pref = &ref1.prev;
    }
}

fn jsPushValue(ctx: *c.JSContext, ref: *c.JSGCRef, val: c.JSValue) void {
    const x = mc.ctxExt(ctx);
    ref.prev = @ptrCast(x.top_gc_ref);
    x.top_gc_ref = @ptrCast(@alignCast(ref));
    ref.val = val;
}

fn jsPopValue(ctx: *c.JSContext, ref: *c.JSGCRef) c.JSValue {
    const val = ref.val;
    mc.ctxExt(ctx).top_gc_ref = @ptrCast(ref.prev);
    return val;
}

pub fn js_get_atom(ctx: *c.JSContext, a: c_int) c.JSValue {
    const table = mc.ctxExt(ctx).atom_table;
    return mc.valueFromPtr(@ptrCast(@constCast(&table[@intCast(a)])));
}

pub fn JS_IsExceptionOrTailCall(v: c.JSValue) c.JS_BOOL {
    return @intFromBool(mc.valueGetSpecialTag(v) == c.JS_TAG_EXCEPTION);
}

pub fn js_get_mtag(ptr: *anyopaque) c_int {
    return mc.mbGetMtag(ptr);
}

fn check_free_mem(ctx: *c.JSContext, stack_bottom: *c.JSValue, size: c_uint) c_int {
    const x = mc.ctxExt(ctx);
    const stack_ptr: [*c]u8 = @ptrCast(stack_bottom);
    const remaining = @as(isize, @bitCast(@intFromPtr(stack_ptr))) - @as(isize, @bitCast(@intFromPtr(x.heap_free)));
    const need: isize = @as(isize, @intCast(size)) + @as(isize, @intCast(x.min_free_size));
    if (remaining < need) {
        gc.JS_GC(ctx);
        const remaining2 = @as(isize, @bitCast(@intFromPtr(stack_ptr))) - @as(isize, @bitCast(@intFromPtr(x.heap_free)));
        if (remaining2 < need) {
            _ = JS_ThrowOutOfMemory(ctx);
            return -1;
        }
    }
    return 0;
}

pub fn JS_StackCheck(ctx: *c.JSContext, len: c_uint) c_int {
    const x = mc.ctxExt(ctx);
    const new_len: usize = @intCast(len + mc.JS_STACK_SLACK);
    const sp: [*]c.JSValue = @ptrCast(x.sp);
    const new_stack_bottom: *c.JSValue = @ptrCast(sp - new_len);
    if (check_free_mem(ctx, new_stack_bottom, @intCast(new_len * @sizeOf(c.JSValue))) != 0)
        return -1;
    x.stack_bottom = new_stack_bottom;
    return 0;
}

pub fn js_malloc(ctx: *c.JSContext, size: c_uint, mtag: c_int) ?*anyopaque {
    if (size == 0)
        return null;

    const aligned_size = mc.alignUp(size, c.JSW);
    const x = mc.ctxExt(ctx);
    if (check_free_mem(ctx, x.stack_bottom, aligned_size) != 0)
        return null;

    const p = x.heap_free;
    x.heap_free += aligned_size;
    mc.mbInit(p, mtag);
    return p;
}

pub fn js_mallocz(ctx: *c.JSContext, size: c_uint, mtag: c_int) ?*anyopaque {
    const ptr = js_malloc(ctx, size, mtag) orelse return null;
    if (size > @sizeOf(u32)) {
        const p: [*c]u8 = @ptrCast(ptr);
        @memset(p[@sizeOf(u32)..size], 0);
    }
    return ptr;
}

pub fn js_free(ctx: *c.JSContext, ptr: ?*anyopaque) void {
    if (ptr == null) return;
    const x = mc.ctxExt(ctx);
    var ptr1: [*c]u8 = @ptrCast(ptr);
    ptr1 += @intCast(gc.get_mblock_size(ptr1));
    if (ptr1 == x.heap_free)
        x.heap_free = @ptrCast(ptr);
}

pub fn set_free_block(ptr: *anyopaque, size: c_uint) void {
    mc.mbSetFreeBlock(ptr, size);
}

pub fn js_shrink(ctx: *c.JSContext, ptr: ?*anyopaque, new_size: c_uint) ?*anyopaque {
    const aligned_new = mc.alignUp(new_size, c.JSW);

    if (aligned_new == 0) {
        js_free(ctx, ptr);
        return null;
    }
    const old_size: c_uint = @intCast(gc.get_mblock_size(ptr.?));
    std.debug.assert(aligned_new <= old_size);
    const diff = old_size - aligned_new;
    if (diff == 0)
        return ptr;
    const tail: [*c]u8 = @ptrCast(ptr.?);
    set_free_block(tail + aligned_new, diff);
    return ptr;
}

pub fn JS_Throw(ctx: *c.JSContext, obj: c.JSValue) c.JSValue {
    const x = mc.ctxExt(ctx);
    x.current_exception = obj;
    x.current_exception_is_uncatchable = c.FALSE;
    return c.JS_EXCEPTION;
}

pub fn get_short_string(buf: [*c]u8, val: c.JSValue) c_int {
    const len: c_int = @intCast(unicode_to_utf8(buf, @as(u32, @intCast(mc.valueGetSpecialValue(val)))));
    buf[@intCast(len)] = 0;
    return len;
}

pub fn is_digit(ch: c_int) c.JS_BOOL {
    return @intFromBool(ch >= '0' and ch <= '9');
}

fn pad(write_func: mc.JSWriteFn, opaque_val: ?*anyopaque, ch: u8, width: c_int, len: usize) void {
    var buf: [16]u8 = undefined;
    if (@as(c_int, @intCast(len)) >= width) return;
    var w = width - @as(c_int, @intCast(len));
    const fill = min_int(@sizeOf(@TypeOf(buf)), @intCast(w));
    @memset(buf[0..@intCast(fill)], ch);
    while (w != 0) {
        const l = min_int(w, @sizeOf(@TypeOf(buf)));
        write_func(opaque_val, &buf, @intCast(l));
        w -= l;
    }
}

pub fn js_vprintf(write_func: mc.JSWriteFn, opaque_val: ?*anyopaque, fmt: [*:0]const u8, ap: *anyopaque) void {
    const vap: *std.builtin.VaListX86_64 = @ptrCast(@alignCast(ap));
    var fmt_ptr: [*c]const u8 = fmt;
    var tmp_buf: [32]u8 = undefined;

    while (fmt_ptr[0] != 0) {
        const p = fmt_ptr;
        while (fmt_ptr[0] != '%' and fmt_ptr[0] != 0)
            fmt_ptr += 1;
        if (fmt_ptr > p)
            write_func(opaque_val, p, @intFromPtr(fmt_ptr) - @intFromPtr(p));
        if (fmt_ptr[0] == 0)
            break;
        fmt_ptr += 1;

        var flags: c_int = 0;
        while (true) {
            const ch = fmt_ptr[0];
            if (ch == '0') {
                flags |= PF_ZERO_PAD;
            } else if (ch == '#') {
                flags |= PF_ALT_FORM;
            } else if (ch == '+') {
                flags |= PF_MARK_POS;
            } else if (ch == '-') {
                flags |= PF_LEFT_ADJ;
            } else if (ch == ' ') {
                flags |= PF_PAD_POS;
            } else {
                break;
            }
            fmt_ptr += 1;
        }

        var width: c_int = 0;
        if (fmt_ptr[0] == '*') {
            width = @cVaArg(vap, c_int);
            fmt_ptr += 1;
        } else {
            while (is_digit(fmt_ptr[0]) != 0) {
                width = width * 10 + fmt_ptr[0] - '0';
                fmt_ptr += 1;
            }
        }

        var prec: c_int = 0;
        if (fmt_ptr[0] == '.') {
            fmt_ptr += 1;
            if (fmt_ptr[0] == '*') {
                prec = @cVaArg(vap, c_int);
                fmt_ptr += 1;
            } else {
                while (is_digit(fmt_ptr[0]) != 0) {
                    prec = prec * 10 + fmt_ptr[0] - '0';
                    fmt_ptr += 1;
                }
            }
        }

        while (true) {
            const ch = fmt_ptr[0];
            if (ch == 'l') {
                if (@sizeOf(c_long) == @sizeOf(i64) or fmt_ptr[-1] == 'l')
                    flags |= PF_INT64;
            } else if (ch == 'z' or ch == 't') {
                if (@sizeOf(usize) == @sizeOf(u64))
                    flags |= PF_INT64;
            } else {
                break;
            }
            fmt_ptr += 1;
        }

        const spec = fmt_ptr[0];
        fmt_ptr += 1;

        var buf: [*c]u8 = &tmp_buf;
        var len: usize = 0;

        switch (spec) {
            '%' => {
                write_func(opaque_val, fmt_ptr - 1, 1);
                continue;
            },
            'c' => {
                tmp_buf[0] = @intCast(@cVaArg(vap, c_int));
                len = 1;
                flags &= ~PF_ZERO_PAD;
            },
            's' => {
                buf = @cVaArg(vap, [*c]u8);
                if (buf == null)
                    buf = cstr("null");
                len = std.mem.len(@as([*:0]const u8, buf));
                flags &= ~PF_ZERO_PAD;
            },
            'd' => {
                if (flags & PF_INT64 != 0) {
                    len = dtoa.i64toa(buf, @cVaArg(vap, c_longlong));
                } else {
                    len = dtoa.i32toa(buf, @cVaArg(vap, c_int));
                }
            },
            'u' => {
                if (flags & PF_INT64 != 0) {
                    len = dtoa.u64toa(buf, @cVaArg(vap, c_ulonglong));
                } else {
                    len = dtoa.u32toa(buf, @cVaArg(vap, c_uint));
                }
            },
            'x' => {
                if (flags & PF_INT64 != 0) {
                    len = dtoa.u64toa_radix(buf, @cVaArg(vap, c_ulonglong), 16);
                } else {
                    len = dtoa.u64toa_radix(buf, @cVaArg(vap, c_uint), 16);
                }
            },
            'p' => {
                tmp_buf[0] = '0';
                tmp_buf[1] = 'x';
                len = dtoa.u64toa_radix(tmp_buf[2..].ptr, @cVaArg(vap, usize), 16);
                len += 2;
                buf = &tmp_buf;
            },
            'o' => {
                const val: c.JSValue = if (flags & PF_INT64 != 0)
                    @cVaArg(vap, c_ulonglong)
                else
                    @cVaArg(vap, c_uint);

                if (mc.isInt(val)) {
                    len = dtoa.i32toa(buf, mc.valueGetInt(val));
                } else if (mc.isShortFloat(val)) {
                    buf = cstr("[short_float]");
                    len = 13;
                } else if (!mc.isPtr(val)) {
                    switch (mc.valueGetSpecialTag(val)) {
                        c.JS_TAG_NULL => {
                            buf = cstr("null");
                            len = 4;
                        },
                        c.JS_TAG_UNDEFINED => {
                            buf = cstr("undefined");
                            len = 9;
                        },
                        c.JS_TAG_UNINITIALIZED => {
                            buf = cstr("uninitialized");
                            len = 13;
                        },
                        c.JS_TAG_BOOL => {
                            if (mc.valueGetSpecialValue(val) != 0) {
                                buf = cstr("true");
                                len = 4;
                            } else {
                                buf = cstr("false");
                                len = 5;
                            }
                        },
                        c.JS_TAG_STRING_CHAR => {
                            len = @intCast(get_short_string(buf, val));
                        },
                        else => {
                            buf = cstr("[tag]");
                            len = 5;
                        },
                    }
                } else {
                    const ptr = mc.valueToPtr(val);
                    const mtag = js_get_mtag(ptr);
                    switch (mtag) {
                        mc.JS_MTAG_STRING => {
                            const sp: *mc.JSStringExt = @ptrCast(@alignCast(ptr));
                            buf = mc.stringBuf(sp);
                            len = mc.stringLen(sp);
                        },
                        else => {
                            buf = cstr("[mtag]");
                            len = 5;
                        },
                    }
                }
                if (flags & PF_ALT_FORM != 0 and len > 0 and buf[len - 1] == '\n')
                    len -= 1;
                flags &= ~PF_ZERO_PAD;
            },
            else => return,
        }

        if (flags & PF_ZERO_PAD != 0) {
            pad(write_func, opaque_val, '0', width, len);
        } else if (flags & PF_LEFT_ADJ == 0) {
            pad(write_func, opaque_val, ' ', width, len);
        }
        write_func(opaque_val, buf, len);
        if (flags & PF_LEFT_ADJ != 0)
            pad(write_func, opaque_val, ' ', width, len);
    }
}

pub fn js_printf(ctx: *c.JSContext, fmt: [*:0]const u8, ...) callconv(.c) void {
    var ap = @cVaStart();
    defer @cVaEnd(&ap);
    const x = mc.ctxExt(ctx);
    js_vprintf(x.write_func.?, x.opaque_val, fmt, @ptrCast(&ap));
}

pub fn js_putchar(ctx: *c.JSContext, ch: u8) void {
    const x = mc.ctxExt(ctx);
    x.write_func.?(x.opaque_val, &ch, 1);
}

const SNPrintfState = extern struct {
    ptr: [*c]u8,
    buf_end: [*c]u8,
    len: c_int,
};

fn snprintf_write_func(opaque_val: ?*anyopaque, buf: ?*const anyopaque, buf_len: usize) callconv(.c) void {
    const s: *SNPrintfState = @ptrCast(@alignCast(opaque_val));
    s.len += @intCast(buf_len);
    const l = min_size_t(buf_len, @intFromPtr(s.buf_end) - @intFromPtr(s.ptr));
    if (l != 0) {
        const src: [*]const u8 = @ptrCast(buf.?);
        @memcpy(s.ptr[0..l], src[0..l]);
        s.ptr += l;
    }
}

pub fn js_vsnprintf(buf: [*c]u8, buf_size: usize, fmt: [*:0]const u8, ap: *anyopaque) c_int {
    var ss: SNPrintfState = undefined;
    const s = &ss;
    s.ptr = buf;
    s.buf_end = buf + max_size_t(buf_size, 1) - 1;
    s.len = 0;
    js_vprintf(snprintf_write_func, s, fmt, ap);
    if (buf_size > 0)
        s.ptr[0] = 0;
    return s.len;
}

pub fn js_snprintf(buf: [*c]u8, buf_size: usize, fmt: [*:0]const u8, ...) callconv(.c) c_int {
    var ap = @cVaStart();
    defer @cVaEnd(&ap);
    return js_vsnprintf(buf, buf_size, fmt, @ptrCast(&ap));
}

pub fn jsThrowErrorVa(ctx: *c.JSContext, error_num: c.JSObjectClassEnum, fmt: [*:0]const u8, ap: *anyopaque) c.JSValue {
    var buf: [128]u8 = undefined;
    _ = js_vsnprintf(&buf, buf.len, fmt, ap);

    const msg = value.JS_NewString(ctx, @ptrCast(&buf));
    var msg_ref: c.JSGCRef = undefined;
    jsPushValue(ctx, &msg_ref, msg);

    const x = mc.ctxExt(ctx);
    const class_proto: [*]c.JSValue = @ptrCast(@alignCast(&x.class_proto));
    const error_obj = value.JS_NewObjectProtoClass(ctx, class_proto[@intCast(error_num)], c.JS_CLASS_ERROR, @sizeOf(mc.JSErrorDataExt));
    const msg_val = jsPopValue(ctx, &msg_ref);
    if (mc.isException(error_obj))
        return error_obj;

    const p: *mc.JSObjectExt = @ptrCast(@alignCast(mc.valueToPtr(error_obj)));
    p.u.err.message = msg_val;
    p.u.err.stack = c.JS_NULL;

    if (error_num != c.JS_CLASS_SYNTAX_ERROR) {
        var error_obj_ref: c.JSGCRef = undefined;
        jsPushValue(ctx, &error_obj_ref, error_obj);
        runtime.build_backtrace(ctx, error_obj, null, 0, 0, 0);
        _ = jsPopValue(ctx, &error_obj_ref);
    }

    return JS_Throw(ctx, error_obj);
}

pub fn JS_ThrowError(ctx: *c.JSContext, error_num: c.JSObjectClassEnum, fmt: [*:0]const u8, ...) callconv(.c) c.JSValue {
    var ap = @cVaStart();
    defer @cVaEnd(&ap);
    return jsThrowErrorVa(ctx, error_num, fmt, @ptrCast(&ap));
}

pub fn JS_ThrowOutOfMemory(ctx: *c.JSContext) c.JSValue {
    const x = mc.ctxExt(ctx);
    if (x.in_out_of_memory != 0)
        return JS_Throw(ctx, c.JS_NULL);
    x.in_out_of_memory = c.TRUE;
    x.min_free_size = mc.JS_MIN_CRITICAL_FREE_SIZE;
    const val = JS_ThrowError(ctx, c.JS_CLASS_INTERNAL_ERROR, "out of memory");
    x.in_out_of_memory = c.FALSE;
    x.min_free_size = mc.JS_MIN_FREE_SIZE;
    return val;
}

fn is_ident_first(ch: c_int) c_int {
    return @intFromBool((ch >= 'a' and ch <= 'z') or
        (ch >= 'A' and ch <= 'Z') or
        ch == '_' or ch == '$');
}

pub fn is_ident_next(ch: c_int) c_int {
    return @intFromBool(is_ident_first(ch) != 0 or value.is_num(ch) != 0);
}

// JS_DUMP is always defined in mquickjs_priv.h for this project.

fn js_dump_array(ctx: *c.JSContext, arr: *mc.JSValueArrayExt, len: c_int) void {
    const arr_ptr = mc.valueArrayItems(arr);
    js_printf(ctx, "[ ");
    var i: c_int = 0;
    while (i < len) : (i += 1) {
        if (i != 0)
            js_printf(ctx, ", ");
        JS_PrintValue(ctx, arr_ptr[@intCast(i)]);
    }
    js_printf(ctx, " ]");
}

fn js_find_class_name(ctx: *c.JSContext, class_id: c_int) c.JSValue {
    var fd = mc.ctxExt(ctx).c_function_table;
    while ((fd.*.def_type != c.JS_CFUNC_constructor_magic and fd.*.def_type != c.JS_CFUNC_constructor) or
        fd.*.magic != class_id)
    {
        fd += 1;
    }
    return runtime.reloc_c_func_name(ctx, fd.*.name);
}

fn js_dump_float64(ctx: *c.JSContext, d: f64) void {
    var buf: [32]u8 = undefined;
    var tmp_mem: dtoa.JSDTOATempMem = undefined;
    _ = dtoa.js_dtoa(&buf, d, 10, 0, c.JS_DTOA_FORMAT_FREE | c.JS_DTOA_MINUS_ZERO, &tmp_mem);
    js_printf(ctx, "%s", @as([*c]u8, @ptrCast(&buf)));
}

fn js_dump_error(ctx: *c.JSContext, p: *mc.JSObjectExt) void {
    var p1 = p;
    if (p.proto != c.JS_NULL)
        p1 = @ptrCast(@alignCast(mc.valueToPtr(p.proto)));

    const pr = value.find_own_property(ctx, p1, js_get_atom(ctx, c.JS_ATOM_name));
    const name: c.JSValue = if (pr == null or c.JS_IsString(ctx, pr.?.value) == 0)
        js_get_atom(ctx, c.JS_ATOM_Error)
    else
        pr.?.value;

    js_printf(ctx, "%" ++ mc.JSValue_PRI, name);
    if (p.u.err.message != c.JS_NULL)
        js_printf(ctx, ": %" ++ mc.JSValue_PRI, p.u.err.message);
    if (p.u.err.stack != c.JS_NULL)
        js_printf(ctx, "\n%#" ++ mc.JSValue_PRI, p.u.err.stack);
}

fn js_dump_object(ctx: *c.JSContext, p: *mc.JSObjectExt, flags: c_int) void {
    const class_id = mc.objectClassId(p);
    if (flags & c.JS_DUMP_LONG != 0) {
        switch (class_id) {
            c.JS_CLASS_CLOSURE => {
                const b: *mc.JSFunctionBytecodeExt = @ptrCast(@alignCast(mc.valueToPtr(p.u.closure.func_bytecode)));
                js_printf(ctx, "function ");
                JS_PrintValueF(ctx, b.func_name, c.JS_DUMP_NOQUOTE);
                js_printf(ctx, "()");
            },
            c.JS_CLASS_C_FUNCTION => {
                js_printf(ctx, "function ");
                JS_PrintValueF(ctx, runtime.reloc_c_func_name(ctx, mc.ctxExt(ctx).c_function_table[@intCast(p.u.cfunc.idx)].name), c.JS_DUMP_NOQUOTE);
                js_printf(ctx, "()");
            },
            c.JS_CLASS_ERROR => js_dump_error(ctx, p),
            c.JS_CLASS_REGEXP => builtins.dump_regexp(ctx, p),
            c.JS_CLASS_ARRAY, c.JS_CLASS_OBJECT => {
                if (class_id >= c.JS_CLASS_UINT8C_ARRAY and class_id <= c.JS_CLASS_FLOAT64_ARRAY) {
                    var i: c_int = 0;
                    JS_PrintValueF(ctx, js_find_class_name(ctx, class_id), c.JS_DUMP_NOQUOTE);
                    js_printf(ctx, "([ ");
                    const pbuffer: *mc.JSObjectExt = @ptrCast(@alignCast(mc.valueToPtr(p.u.typed_array.buffer)));
                    const arr: *mc.JSByteArrayExt = @ptrCast(@alignCast(mc.valueToPtr(pbuffer.u.array_buffer.byte_buffer)));
                    const byte_buf = mc.byteArrayBuf(arr);
                    while (i < @as(c_int, @intCast(p.u.typed_array.len))) : (i += 1) {
                        if (i != 0)
                            js_printf(ctx, ", ");
                        const idx = i + @as(c_int, @intCast(p.u.typed_array.offset));
                        switch (class_id) {
                            c.JS_CLASS_UINT8C_ARRAY, c.JS_CLASS_UINT8_ARRAY => {
                                const v = byte_buf[@intCast(idx)];
                                js_printf(ctx, "%d", v);
                            },
                            c.JS_CLASS_INT8_ARRAY => {
                                const v: *const i8 = @ptrCast(&byte_buf[@intCast(idx)]);
                                js_printf(ctx, "%d", v.*);
                            },
                            c.JS_CLASS_INT16_ARRAY => {
                                const v: *const i16 = @ptrCast(@alignCast(&byte_buf[@intCast(idx)]));
                                js_printf(ctx, "%d", v.*);
                            },
                            c.JS_CLASS_UINT16_ARRAY => {
                                const v: *const u16 = @ptrCast(@alignCast(&byte_buf[@intCast(idx)]));
                                js_printf(ctx, "%d", v.*);
                            },
                            c.JS_CLASS_INT32_ARRAY => {
                                const v: *const i32 = @ptrCast(@alignCast(&byte_buf[@intCast(idx)]));
                                js_printf(ctx, "%d", v.*);
                            },
                            c.JS_CLASS_UINT32_ARRAY => {
                                const v: *const u32 = @ptrCast(@alignCast(&byte_buf[@intCast(idx)]));
                                js_printf(ctx, "%u", v.*);
                            },
                            c.JS_CLASS_FLOAT32_ARRAY => {
                                const v: *const f32 = @ptrCast(@alignCast(&byte_buf[@intCast(idx)]));
                                js_dump_float64(ctx, v.*);
                            },
                            c.JS_CLASS_FLOAT64_ARRAY => {
                                const v: *const f64 = @ptrCast(@alignCast(&byte_buf[@intCast(idx)]));
                                js_dump_float64(ctx, v.*);
                            },
                            else => {},
                        }
                    }
                    js_printf(ctx, " ])");
                } else {
                    const arr: *mc.JSValueArrayExt = @ptrCast(@alignCast(mc.valueToPtr(p.props)));
                    const arr_items = mc.valueArrayItems(arr);
                    const prop_count = mc.valueGetInt(arr_items[0]);
                    const hash_mask = mc.valueGetInt(arr_items[1]);
                    var is_first: c.JS_BOOL = c.TRUE;
                    var i: c_int = 0;
                    var j: c_int = 0;

                    if (class_id == c.JS_CLASS_ARRAY) {
                        const tab: *mc.JSValueArrayExt = @ptrCast(@alignCast(mc.valueToPtr(p.u.array.tab)));
                        const tab_items = mc.valueArrayItems(tab);
                        js_printf(ctx, "[ ");
                        i = 0;
                        while (i < @as(c_int, @intCast(p.u.array.len))) : (i += 1) {
                            if (is_first == 0)
                                js_printf(ctx, ", ");
                            JS_PrintValue(ctx, tab_items[@intCast(i)]);
                            is_first = c.FALSE;
                        }
                    } else {
                        if (class_id != c.JS_CLASS_OBJECT) {
                            const class_name = js_find_class_name(ctx, class_id);
                            if (!mc.isNull(class_name))
                                JS_PrintValueF(ctx, class_name, c.JS_DUMP_NOQUOTE);
                            js_putchar(ctx, ' ');
                        }
                        js_printf(ctx, "{ ");
                    }

                    i = 0;
                    j = 0;
                    while (j < prop_count) : (i += 1) {
                        const base = 2 + (hash_mask + 1) + 3 * i;
                        const pr: *mc.JSPropertyExt = @ptrCast(@alignCast(&arr_items[@intCast(base)]));
                        if (pr.key != c.JS_UNINITIALIZED) {
                            if (is_first == 0)
                                js_printf(ctx, ", ");
                            JS_PrintValueF(ctx, pr.key, c.JS_DUMP_NOQUOTE);
                            js_printf(ctx, ": ");
                            if (flags & c.JS_DUMP_RAW == 0 and mc.propType(pr) == mc.JS_PROP_SPECIAL)
                                JS_PrintValue(ctx, value.get_special_prop(ctx, pr.value))
                            else
                                JS_PrintValue(ctx, pr.value);
                            is_first = c.FALSE;
                            j += 1;
                        }
                    }
                    const end_ch: u8 = if (class_id == c.JS_CLASS_ARRAY) ']' else '}';
                    js_printf(ctx, " %c", end_ch);
                }
            },
            else => {},
        }
    } else {
        const str: [*:0]const u8 = if (class_id == c.JS_CLASS_ARRAY)
            "Array"
        else if (class_id == c.JS_CLASS_ERROR)
            "Error"
        else if (class_id == c.JS_CLASS_CLOSURE or class_id == c.JS_CLASS_C_FUNCTION)
            "Function"
        else
            "Object";
        js_printf(ctx, "[object %s]", str);
    }
}

fn dump_string(ctx: *c.JSContext, sep: c_int, buf: [*c]const u8, len: usize, flags: c_int) void {
    var use_quote: c.JS_BOOL = c.TRUE;
    var sep_ch: c_int = sep;

    if (flags & c.JS_DUMP_NOQUOTE != 0) {
        if (len >= 1 and is_ident_first(buf[0]) != 0) {
            var i: usize = 1;
            while (i < len) : (i += 1) {
                if (is_ident_next(buf[@intCast(i)]) == 0)
                    break;
            }
            if (i == len)
                use_quote = c.FALSE;
        }
    }

    if (flags & c.JS_DUMP_RAW == 0)
        sep_ch = '"';
    if (use_quote != 0)
        js_putchar(ctx, @intCast(sep_ch));

    var p: [*c]const u8 = buf;
    const p_end = buf + len;
    while (@intFromPtr(p) < @intFromPtr(p_end)) {
        var clen: usize = 0;
        const ch = utf8_get(p, @ptrCast(&clen));
        switch (ch) {
            '\t' => {
                js_putchar(ctx, '\\');
                js_putchar(ctx, 't');
            },
            '\r' => {
                js_putchar(ctx, '\\');
                js_putchar(ctx, 'r');
            },
            '\n' => {
                js_putchar(ctx, '\\');
                js_putchar(ctx, 'n');
            },
            '\x08' => {
                js_putchar(ctx, '\\');
                js_putchar(ctx, 'b');
            },
            '\x0c' => {
                js_putchar(ctx, '\\');
                js_putchar(ctx, 'f');
            },
            '"', '\\' => {
                js_putchar(ctx, '\\');
                js_putchar(ctx, @intCast(ch));
            },
            else => {
                if (ch < 32 or (ch >= 0xd800 and ch < 0xe000)) {
                    js_printf(ctx, "\\u%04x", @as(c_uint, @intCast(ch)));
                } else {
                    const x = mc.ctxExt(ctx);
                    x.write_func.?(x.opaque_val, p, clen);
                }
            },
        }
        p += clen;
    }
    if (use_quote != 0)
        js_putchar(ctx, @intCast(sep_ch));
}

pub fn JS_PrintValueF(ctx: *c.JSContext, val: c.JSValue, flags: c_int) void {
    if (mc.isInt(val)) {
        js_printf(ctx, "%d", mc.valueGetInt(val));
    } else if (mc.isShortFloat(val)) {
        js_dump_float64(ctx, value.js_get_short_float(val));
    } else if (!mc.isPtr(val)) {
        switch (mc.valueGetSpecialTag(val)) {
            c.JS_TAG_NULL, c.JS_TAG_UNDEFINED, c.JS_TAG_UNINITIALIZED, c.JS_TAG_BOOL => js_printf(ctx, "%" ++ mc.JSValue_PRI, val),
            c.JS_TAG_EXCEPTION => js_printf(ctx, "[exception %d]", mc.valueGetSpecialValue(val)),
            c.JS_TAG_CATCH_OFFSET => js_printf(ctx, "[catch_offset %d]", mc.valueGetSpecialValue(val)),
            c.JS_TAG_SHORT_FUNC => {
                const idx = mc.valueGetSpecialValue(val);
                js_printf(ctx, "function ");
                JS_PrintValueF(ctx, runtime.reloc_c_func_name(ctx, mc.ctxExt(ctx).c_function_table[@intCast(idx)].name), c.JS_DUMP_NOQUOTE);
                js_printf(ctx, "()");
            },
            c.JS_TAG_STRING_CHAR => {
                var buf: [cutils.UTF8_CHAR_LEN_MAX + 1]u8 = undefined;
                const len = get_short_string(&buf, val);
                dump_string(ctx, '`', &buf, @intCast(len), flags);
            },
            else => js_printf(ctx, "[tag %d]", @as(c_int, @intCast(mc.valueGetSpecialTag(val)))),
        }
    } else {
        const ptr = mc.valueToPtr(val);
        const mtag = js_get_mtag(ptr);
        switch (mtag) {
            mc.JS_MTAG_FLOAT64 => {
                js_dump_float64(ctx, mc.float64Value(ptr));
            },
            mc.JS_MTAG_OBJECT => {
                const op: *mc.JSObjectExt = @ptrCast(@alignCast(ptr));
                js_dump_object(ctx, op, flags);
            },
            mc.JS_MTAG_STRING => {
                const sp: *mc.JSStringExt = @ptrCast(@alignCast(ptr));
                const sep: c_int = if (mc.stringIsUnique(sp)) '\'' else '"';
                dump_string(ctx, sep, mc.stringBuf(sp), mc.stringLen(sp), flags);
            },
            mc.JS_MTAG_VALUE_ARRAY => {
                const arr: *mc.JSValueArrayExt = @ptrCast(@alignCast(ptr));
                js_dump_array(ctx, arr, mc.valueArraySize(arr));
            },
            mc.JS_MTAG_BYTE_ARRAY => {
                const arr: *mc.JSByteArrayExt = @ptrCast(@alignCast(ptr));
                js_printf(ctx, "byte_array(%llu)", @as(c_ulonglong, @intCast(mc.byteArraySize(arr))));
            },
            mc.JS_MTAG_FUNCTION_BYTECODE => {
                const b: *mc.JSFunctionBytecodeExt = @ptrCast(@alignCast(ptr));
                js_printf(ctx, "bytecode_function ");
                JS_PrintValueF(ctx, b.func_name, c.JS_DUMP_NOQUOTE);
                js_printf(ctx, "()");
            },
            mc.JS_MTAG_VARREF => {
                const pv: *mc.JSVarRefExt = @ptrCast(@alignCast(ptr));
                js_printf(ctx, "var_ref(");
                if (mc.varRefIsDetached(pv))
                    JS_PrintValue(ctx, pv.u.value)
                else
                    JS_PrintValue(ctx, pv.u.live.pvalue.*);
                js_printf(ctx, ")");
            },
            else => js_printf(ctx, "[mtag %d]", mtag),
        }
    }
}

pub fn JS_PrintValue(ctx: *c.JSContext, val: c.JSValue) void {
    JS_PrintValueF(ctx, val, 0);
}

fn get_mtag_name(mtag: c_uint) [*:0]const u8 {
    if (mtag >= js_mtag_name.len)
        return "?";
    return js_mtag_name[@intCast(mtag)];
}

fn val_to_offset(ctx: *c.JSContext, val: c.JSValue) c_uint {
    if (!mc.isPtr(val))
        return 0;
    return @intCast(@intFromPtr(mc.valueToPtr(val)) - @intFromPtr(mc.ctxExt(ctx).heap_base));
}

pub fn JS_DumpMemory(ctx: *c.JSContext, is_long: c.JS_BOOL) void {
    const x = mc.ctxExt(ctx);
    var mtag_mem_size: [mc.JS_MTAG_COUNT]c_uint = undefined;
    var mtag_count: [mc.JS_MTAG_COUNT]c_uint = undefined;
    var tot_size: c_uint = 0;

    if (is_long != 0)
        js_printf(ctx, "%10s %s %8s %15s %10s %10s %s\n", "OFFSET", "M", "SIZE", "TAG", "PROTO", "PROPS", "EXTRA");

    for (&mtag_mem_size, &mtag_count) |*ms, *mcnt| {
        ms.* = 0;
        mcnt.* = 0;
    }

    var ptr: [*c]u8 = x.heap_base;
    while (@intFromPtr(ptr) < @intFromPtr(x.heap_free)) {
        const w: c.JSWord = @as(*const c.JSWord, @ptrCast(@alignCast(ptr))).*;
        const mtag = mc.mbGetMtag(ptr);
        const gc_mark = w & 1;
        const size: c_int = gc.get_mblock_size(ptr);
        mtag_mem_size[@intCast(mtag)] += @intCast(size);
        mtag_count[@intCast(mtag)] += 1;
        tot_size += @intCast(size);

        if (is_long != 0) {
            js_printf(ctx, "0x%08x %c %8u %15s", @as(c_uint, @intCast(@intFromPtr(ptr) - @intFromPtr(x.heap_base))), if (gc_mark != 0) @as(u8, '*') else @as(u8, ' '), @as(c_uint, @intCast(size)), get_mtag_name(@intCast(mtag)));
            if (mtag != mc.JS_MTAG_FREE) {
                if (mtag == mc.JS_MTAG_OBJECT) {
                    const op: *mc.JSObjectExt = @ptrCast(@alignCast(ptr));
                    js_printf(ctx, " 0x%08x 0x%08x", val_to_offset(ctx, op.proto), val_to_offset(ctx, op.props));
                } else {
                    js_printf(ctx, " %10s %10s", "", "");
                }
                js_printf(ctx, " ");
                JS_PrintValueF(ctx, mc.valueFromPtr(ptr), c.JS_DUMP_RAW);
            }
            js_printf(ctx, "\n");
        }
        ptr += @intCast(size);
    }

    js_printf(ctx, "%15s %8s %8s %8s %8s\n", "TAG", "COUNT", "AVG_SIZE", "SIZE", "RATIO");
    var i: c_uint = 0;
    while (i < mc.JS_MTAG_COUNT) : (i += 1) {
        if (mtag_count[@intCast(i)] != 0) {
            const avg_size = @as(c_int, @intCast(js_lrint(
                @as(f64, @floatFromInt(mtag_mem_size[@intCast(i)])) / @as(f64, @floatFromInt(mtag_count[@intCast(i)])),
            )));
            const ratio = @as(c_int, @intCast(js_lrint(
                @as(f64, @floatFromInt(mtag_mem_size[@intCast(i)])) / @as(f64, @floatFromInt(tot_size)) * 100.0,
            )));
            js_printf(ctx, "%15s %8u %8d %8u %7d%%", get_mtag_name(i), mtag_count[@intCast(i)], avg_size, mtag_mem_size[@intCast(i)], ratio);
        }
    }
    js_printf(ctx, "heap size=%u/%u stack_size=%u\n", @as(c_uint, @intCast(@intFromPtr(x.heap_free) - @intFromPtr(x.heap_base))), @as(c_uint, @intCast(@intFromPtr(x.stack_top) - @intFromPtr(x.heap_base))), @as(c_uint, @intCast(@intFromPtr(x.stack_top) - @intFromPtr(x.sp))));
}

pub fn JS_DumpUniqueStrings(ctx: *c.JSContext) void {
    const x = mc.ctxExt(ctx);
    const arr: *mc.JSValueArrayExt = @ptrCast(@alignCast(mc.valueToPtr(x.unique_strings)));
    const arr_items = mc.valueArrayItems(arr);
    js_printf(ctx, "%5s %s\n", "N", "UNIQUE_STRING");
    var i: c_int = 0;
    while (i < x.unique_strings_len) : (i += 1) {
        js_printf(ctx, "%5d ", i);
        JS_PrintValue(ctx, arr_items[@intCast(i)]);
        js_printf(ctx, "\n");
    }
}

pub fn JS_DumpValueF(ctx: *c.JSContext, str: [*:0]const u8, val: c.JSValue, flags: c_int) void {
    js_printf(ctx, "%s=", str);
    JS_PrintValueF(ctx, val, flags);
    js_printf(ctx, "\n");
}

pub fn JS_DumpValue(ctx: *c.JSContext, str: [*:0]const u8, val: c.JSValue) void {
    JS_DumpValueF(ctx, str, val, 0);
}
