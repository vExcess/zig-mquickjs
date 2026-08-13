//
// Micro QuickJS C API example
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

const std = @import("std");
const builtin = @import("builtin");
const posix = std.posix;

const c = @cImport({
    @cInclude("stddef.h");
    @cInclude("stdio.h");
    @cInclude("stdlib.h");
    @cInclude("string.h");
    @cInclude("sys/time.h");
    @cInclude("mquickjs.h");
});

extern "C" const js_stdlib: c.JSSTDLibraryDef;

const JS_CLASS_RECTANGLE = c.JS_CLASS_USER + 0;
const JS_CLASS_FILLED_RECTANGLE = c.JS_CLASS_USER + 1;
const JS_CFUNCTION_rectangle_closure_test = c.JS_CFUNCTION_USER + 0;

fn throwTypeError(ctx: *c.JSContext, comptime msg: [:0]const u8) c.JSValue {
    return c.JS_ThrowError(ctx, c.JS_CLASS_TYPE_ERROR, msg);
}

const RectangleData = extern struct {
    x: c_int,
    y: c_int,
};

const FilledRectangleData = extern struct {
    parent: RectangleData,
    color: c_int,
};

fn getTimeMs() i64 {
    if (builtin.os.tag == .linux or builtin.os.tag == .macos) {
        const ts = posix.clock_gettime(posix.CLOCK.MONOTONIC) catch unreachable;
        return @as(i64, @intCast(ts.sec)) * 1000 + @divTrunc(@as(i64, @intCast(ts.nsec)), 1_000_000);
    }
    var tv: c.struct_timeval = undefined;
    _ = c.gettimeofday(&tv, null);
    return @as(i64, @intCast(tv.tv_sec)) * 1000 + @divTrunc(@as(i64, @intCast(tv.tv_usec)), 1000);
}

fn getDateMs() i64 {
    var tv: c.struct_timeval = undefined;
    _ = c.gettimeofday(&tv, null);
    return @as(i64, @intCast(tv.tv_sec)) * 1000 + @divTrunc(@as(i64, @intCast(tv.tv_usec)), 1000);
}

export fn js_rectangle_constructor(
    ctx: *c.JSContext,
    this_val: *c.JSValue,
    argc: c_int,
    argv: [*]c.JSValue,
) callconv(.c) c.JSValue {
    _ = this_val;
    if ((argc & c.FRAME_CF_CTOR) == 0)
        return throwTypeError(ctx, "must be called with new");
    _ = argc & ~c.FRAME_CF_CTOR;
    const obj = c.JS_NewObjectClassUser(ctx, JS_CLASS_RECTANGLE);
    const d: *RectangleData = @ptrCast(@alignCast(c.malloc(@sizeOf(RectangleData))));
    c.JS_SetOpaque(ctx, obj, d);
    if (c.JS_ToInt32(ctx, &d.x, argv[0]) != 0)
        return c.JS_EXCEPTION;
    if (c.JS_ToInt32(ctx, &d.y, argv[1]) != 0)
        return c.JS_EXCEPTION;
    return obj;
}

export fn js_rectangle_finalizer(ctx: *c.JSContext, opaque_ptr: ?*anyopaque) callconv(.c) void {
    _ = ctx;
    const d: *RectangleData = @ptrCast(@alignCast(opaque_ptr));
    c.free(d);
}

export fn js_rectangle_get_x(
    ctx: *c.JSContext,
    this_val: *c.JSValue,
    argc: c_int,
    argv: [*]c.JSValue,
) callconv(.c) c.JSValue {
    _ = argc;
    _ = argv;
    const class_id = c.JS_GetClassID(ctx, this_val.*);
    if (class_id != JS_CLASS_RECTANGLE and class_id != JS_CLASS_FILLED_RECTANGLE)
        return throwTypeError(ctx, "expecting Rectangle class");
    const d: *RectangleData = @ptrCast(@alignCast(c.JS_GetOpaque(ctx, this_val.*)));
    return c.JS_NewInt32(ctx, d.x);
}

export fn js_rectangle_get_y(
    ctx: *c.JSContext,
    this_val: *c.JSValue,
    argc: c_int,
    argv: [*]c.JSValue,
) callconv(.c) c.JSValue {
    _ = argc;
    _ = argv;
    const class_id = c.JS_GetClassID(ctx, this_val.*);
    if (class_id != JS_CLASS_RECTANGLE and class_id != JS_CLASS_FILLED_RECTANGLE)
        return throwTypeError(ctx, "expecting Rectangle class");
    const d: *RectangleData = @ptrCast(@alignCast(c.JS_GetOpaque(ctx, this_val.*)));
    return c.JS_NewInt32(ctx, d.y);
}

export fn js_rectangle_closure_test(
    ctx: *c.JSContext,
    this_val: *c.JSValue,
    argc: c_int,
    argv: [*]c.JSValue,
    params: c.JSValue,
) callconv(.c) c.JSValue {
    _ = ctx;
    _ = this_val;
    _ = argc;
    _ = argv;
    return params;
}

export fn js_rectangle_getClosure(
    ctx: *c.JSContext,
    this_val: *c.JSValue,
    argc: c_int,
    argv: [*]c.JSValue,
) callconv(.c) c.JSValue {
    _ = this_val;
    _ = argc;
    return c.JS_NewCFunctionParams(ctx, JS_CFUNCTION_rectangle_closure_test, argv[0]);
}

export fn js_rectangle_call(
    ctx: *c.JSContext,
    this_val: *c.JSValue,
    argc: c_int,
    argv: [*]c.JSValue,
) callconv(.c) c.JSValue {
    _ = this_val;
    _ = argc;
    if (c.JS_StackCheck(ctx, 3) != 0)
        return c.JS_EXCEPTION;
    c.JS_PushArg(ctx, argv[1]);
    c.JS_PushArg(ctx, argv[0]);
    c.JS_PushArg(ctx, c.JS_NULL);
    return c.JS_Call(ctx, 1);
}

export fn js_filled_rectangle_constructor(
    ctx: *c.JSContext,
    this_val: *c.JSValue,
    argc: c_int,
    argv: [*]c.JSValue,
) callconv(.c) c.JSValue {
    _ = this_val;
    if ((argc & c.FRAME_CF_CTOR) == 0)
        return throwTypeError(ctx, "must be called with new");
    var obj_ref: c.JSGCRef = undefined;
    const obj = c.JS_PushGCRef(ctx, &obj_ref);
    _ = argc & ~c.FRAME_CF_CTOR;
    obj.* = c.JS_NewObjectClassUser(ctx, JS_CLASS_FILLED_RECTANGLE);
    const d: *FilledRectangleData = @ptrCast(@alignCast(c.malloc(@sizeOf(FilledRectangleData))));
    c.JS_SetOpaque(ctx, obj.*, d);
    if (c.JS_ToInt32(ctx, &d.parent.x, argv[0]) != 0)
        return c.JS_EXCEPTION;
    if (c.JS_ToInt32(ctx, &d.parent.y, argv[1]) != 0)
        return c.JS_EXCEPTION;
    if (c.JS_ToInt32(ctx, &d.color, argv[2]) != 0)
        return c.JS_EXCEPTION;
    _ = c.JS_PopGCRef(ctx, &obj_ref);
    return obj.*;
}

export fn js_filled_rectangle_finalizer(ctx: *c.JSContext, opaque_ptr: ?*anyopaque) callconv(.c) void {
    _ = ctx;
    const d: *FilledRectangleData = @ptrCast(@alignCast(opaque_ptr));
    c.free(d);
}

export fn js_filled_rectangle_get_color(
    ctx: *c.JSContext,
    this_val: *c.JSValue,
    argc: c_int,
    argv: [*]c.JSValue,
) callconv(.c) c.JSValue {
    _ = argc;
    _ = argv;
    if (c.JS_GetClassID(ctx, this_val.*) != JS_CLASS_FILLED_RECTANGLE)
        return throwTypeError(ctx, "expecting FilledRectangle class");
    const d: *FilledRectangleData = @ptrCast(@alignCast(c.JS_GetOpaque(ctx, this_val.*)));
    return c.JS_NewInt32(ctx, d.color);
}

export fn js_print(
    ctx: *c.JSContext,
    this_val: *c.JSValue,
    argc: c_int,
    argv: [*]c.JSValue,
) callconv(.c) c.JSValue {
    _ = this_val;
    var i: c_int = 0;
    while (i < argc) : (i += 1) {
        if (i != 0)
            _ = c.putchar(' ');
        const v = argv[@intCast(i)];
        if (c.JS_IsString(ctx, v) != 0) {
            var buf: c.JSCStringBuf = undefined;
            var len: usize = undefined;
            const str = c.JS_ToCStringLen(ctx, &len, v, &buf);
            _ = c.fwrite(str, 1, len, c.stdout);
        } else {
            c.JS_PrintValueF(ctx, argv[@intCast(i)], c.JS_DUMP_LONG);
        }
    }
    _ = c.putchar('\n');
    return c.JS_UNDEFINED;
}

export fn js_date_constructor(
    ctx: *c.JSContext,
    this_val: *c.JSValue,
    argc: c_int,
    argv: [*]c.JSValue,
) callconv(.c) c.JSValue {
    _ = this_val;
    var arg_count = argc;
    arg_count &= ~c.FRAME_CF_CTOR;
    var val: f64 = undefined;
    if (arg_count == 0) {
        val = @floatFromInt(getDateMs());
    } else if (arg_count == 1 and c.JS_IsNumber(ctx, argv[0]) != 0) {
        if (c.JS_ToNumber(ctx, &val, argv[0]) != 0)
            return c.JS_EXCEPTION;
    } else {
        return throwTypeError(ctx, "unsupported Date() parameter");
    }
    return c.JS_NewDate(ctx, val);
}

export fn js_date_now(
    ctx: *c.JSContext,
    this_val: *c.JSValue,
    argc: c_int,
    argv: [*]c.JSValue,
) callconv(.c) c.JSValue {
    _ = this_val;
    _ = argc;
    _ = argv;
    return c.JS_NewInt64(ctx, getDateMs());
}

export fn js_performance_now(
    ctx: *c.JSContext,
    this_val: *c.JSValue,
    argc: c_int,
    argv: [*]c.JSValue,
) callconv(.c) c.JSValue {
    _ = this_val;
    _ = argc;
    _ = argv;
    return c.JS_NewInt64(ctx, getTimeMs());
}

fn jsLogFunc(opaque_ptr: ?*anyopaque, buf: ?*const anyopaque, buf_len: usize) callconv(.c) void {
    _ = opaque_ptr;
    _ = c.fwrite(buf, 1, buf_len, c.stdout);
}

fn loadFile(filename: [*:0]const u8, plen: ?*c_int) [*]u8 {
    const f = c.fopen(filename, "rb");
    if (f == null) {
        _ = c.perror(filename);
        std.process.exit(1);
    }
    _ = c.fseek(f, 0, c.SEEK_END);
    const buf_len: c_int = @intCast(c.ftell(f));
    _ = c.fseek(f, 0, c.SEEK_SET);
    const buf: [*]u8 = @ptrCast(c.malloc(@intCast(buf_len + 1)));
    if (c.fread(buf, 1, @intCast(buf_len), f) != @as(usize, @intCast(buf_len))) {
        _ = c.printf("not read %d bytes\n", buf_len);
        std.process.exit(1);
    }
    buf[@intCast(buf_len)] = 0;
    _ = c.fclose(f);
    if (plen) |p| p.* = buf_len;
    return buf;
}

pub fn main() void {
    var args = std.process.argsWithAllocator(std.heap.page_allocator) catch unreachable;
    defer args.deinit();
    _ = args.skip();

    const filename_z = args.next() orelse {
        _ = c.printf("usage: example script.js\n");
        std.process.exit(1);
    };

    const mem_size: usize = 65536;
    const mem_buf: [*]u8 = @ptrCast(c.malloc(mem_size));
    const ctx = c.JS_NewContext(mem_buf, mem_size, &js_stdlib);
    c.JS_SetLogFunc(ctx, jsLogFunc);

    var buf_len: c_int = undefined;
    const buf = loadFile(filename_z.ptr, &buf_len);
    const val = c.JS_Eval(ctx, @ptrCast(buf), @intCast(buf_len), filename_z.ptr, 0);
    c.free(buf);
    if (c.JS_IsException(val) != 0) {
        const obj = c.JS_GetException(ctx);
        c.JS_PrintValueF(ctx, obj, c.JS_DUMP_LONG);
        _ = c.printf("\n");
        std.process.exit(1);
    }

    c.JS_FreeContext(ctx);
    c.free(mem_buf);
}
