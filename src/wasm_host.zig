//
// Micro QuickJS WebAssembly host (browser playground)
//

const std = @import("std");
const stdlib_data = @import("mqjs_stdlib_data");

const c = @cImport({
    @cInclude("stddef.h");
    @cInclude("mquickjs.h");
});

extern "env" fn console_write(ptr: [*]const u8, len: usize) void;
extern "env" fn performance_now() f64;

const HEAP_SIZE = 2 * 1024 * 1024;
const RESULT_BUF_SIZE = 65536;
const EVAL_SRC_BUF_SIZE = 262144;

var mem_buf: [HEAP_SIZE]u8 align(8) = undefined;
var eval_src_buf: [EVAL_SRC_BUF_SIZE]u8 = undefined;
var js_ctx: ?*c.JSContext = null;

var result_buf: [RESULT_BUF_SIZE]u8 = undefined;
var result_len: usize = 0;
var js_log_err_flag: c_int = 0;

fn throwTypeError(ctx: *c.JSContext, comptime msg: [:0]const u8) c.JSValue {
    return c.JS_ThrowError(ctx, c.JS_CLASS_TYPE_ERROR, msg);
}

fn getTimeMs() i64 {
    return @intFromFloat(performance_now());
}

fn getDateMs() i64 {
    return getTimeMs();
}

fn appendOutput(buf: ?*const anyopaque, buf_len: usize) void {
    if (buf_len == 0) return;
    const src: [*]const u8 = @ptrCast(buf.?);
    const space = result_buf.len - result_len;
    const n = @min(buf_len, space);
    if (n > 0) {
        @memcpy(result_buf[result_len..][0..n], src[0..n]);
        result_len += n;
    }
    console_write(src, buf_len);
}

fn writeByte(ch: u8) void {
    appendOutput(&ch, 1);
}

fn jsLogFunc(opaque_ptr: ?*anyopaque, buf: ?*const anyopaque, buf_len: usize) callconv(.c) void {
    _ = opaque_ptr;
    appendOutput(buf, buf_len);
}

export fn mqjs_init() c_int {
    stdlib_data.relocate();
    js_ctx = c.JS_NewContext(&mem_buf, HEAP_SIZE, @ptrCast(&stdlib_data.js_stdlib));
    if (js_ctx == null) return -1;
    c.JS_SetLogFunc(js_ctx.?, jsLogFunc);
    return 0;
}

export fn mqjs_free() void {
    if (js_ctx) |ctx| {
        c.JS_FreeContext(ctx);
        js_ctx = null;
    }
}

export fn mqjs_eval(src_len: u32) c_int {
    result_len = 0;
    const ctx = js_ctx orelse return -1;
    if (src_len >= eval_src_buf.len) return -1;
    eval_src_buf[src_len] = 0;
    const val = c.JS_Eval(ctx, @ptrCast(&eval_src_buf), @intCast(src_len), "<input>", 0);
    if (c.JS_IsException(val) != 0) {
        const obj = c.JS_GetException(ctx);
        js_log_err_flag += 1;
        c.JS_PrintValueF(ctx, obj, c.JS_DUMP_LONG);
        js_log_err_flag -= 1;
        writeByte('\n');
        return 1;
    }
    return 0;
}

export fn mqjs_result_len() c_int {
    return @intCast(result_len);
}

export fn mqjs_result_ptr() [*]const u8 {
    return &result_buf;
}

export fn mqjs_src_ptr() [*]u8 {
    return &eval_src_buf;
}

export fn mqjs_src_max_len() u32 {
    return EVAL_SRC_BUF_SIZE;
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
            writeByte(' ');
        const v = argv[@intCast(i)];
        if (c.JS_IsString(ctx, v) != 0) {
            var buf: c.JSCStringBuf = undefined;
            var len: usize = undefined;
            const str = c.JS_ToCStringLen(ctx, &len, v, &buf);
            appendOutput(str, len);
        } else {
            c.JS_PrintValueF(ctx, argv[@intCast(i)], c.JS_DUMP_LONG);
        }
    }
    writeByte('\n');
    return c.JS_UNDEFINED;
}

export fn js_gc(
    ctx: *c.JSContext,
    this_val: *c.JSValue,
    argc: c_int,
    argv: [*]c.JSValue,
) callconv(.c) c.JSValue {
    _ = this_val;
    _ = argc;
    _ = argv;
    c.JS_GC(ctx);
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

export fn js_load(
    ctx: *c.JSContext,
    this_val: *c.JSValue,
    argc: c_int,
    argv: [*]c.JSValue,
) callconv(.c) c.JSValue {
    _ = this_val;
    _ = argc;
    _ = argv;
    return throwTypeError(ctx, "load is not supported in WebAssembly");
}

export fn js_setTimeout(
    ctx: *c.JSContext,
    this_val: *c.JSValue,
    argc: c_int,
    argv: [*]c.JSValue,
) callconv(.c) c.JSValue {
    _ = this_val;
    _ = argc;
    _ = argv;
    return c.JS_NewInt32(ctx, 0);
}

export fn js_clearTimeout(
    ctx: *c.JSContext,
    this_val: *c.JSValue,
    argc: c_int,
    argv: [*]c.JSValue,
) callconv(.c) c.JSValue {
    _ = ctx;
    _ = this_val;
    _ = argc;
    _ = argv;
    return c.JS_UNDEFINED;
}
